import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector


MODEL_SCALE = 26.0
BODY_AXIS_HEIGHT = 0.021 * MODEL_SCALE
DECIMATE_RATIO = 0.15


def bake_to_world(obj):
    mesh = obj.data.copy()
    mesh.name = f"{obj.name}_prepared"
    mesh.transform(obj.matrix_world)
    obj.data = mesh
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)


def filtered_copy(source, name, predicate):
    mesh = source.data.copy()
    mesh.name = f"{name}_mesh"
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    rejected = [face for face in bm.faces if not predicate(face.calc_center_median())]
    if rejected:
        bmesh.ops.delete(bm, geom=rejected, context="FACES")
    loose_vertices = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose_vertices:
        bmesh.ops.delete(bm, geom=loose_vertices, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name=name, object_data=mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_world_vertices(obj):
    return [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]


def distance_to_segment(point, start, end):
    segment = end - start
    if segment.length_squared == 0.0:
        return (point - start).length
    progress = max(0.0, min(1.0, (point - start).dot(segment) / segment.length_squared))
    return (point - (start + segment * progress)).length


def analyze_leg(obj, name):
    vertices = mesh_world_vertices(obj)
    if not vertices:
        raise RuntimeError(f"Leg {name} has no vertices")

    nearest_to_body = sorted(
        vertices,
        key=lambda point: abs(point.x) + abs(point.z - BODY_AXIS_HEIGHT) * 0.45,
    )[: min(80, len(vertices))]
    hip = sum(nearest_to_body, Vector()) / len(nearest_to_body)

    farthest_from_hip = sorted(
        vertices,
        key=lambda point: (point - hip).length_squared,
        reverse=True,
    )[: min(60, len(vertices))]
    foot = sum(farthest_from_hip, Vector()) / len(farthest_from_hip)

    chord = foot - hip
    knee_candidates = []
    for point in vertices:
        progress = (point - hip).dot(chord) / chord.length_squared
        if 0.24 <= progress <= 0.76:
            knee_candidates.append((distance_to_segment(point, hip, foot), point))
    knee_candidates.sort(key=lambda item: item[0], reverse=True)
    knee_points = [item[1] for item in knee_candidates[: min(100, len(knee_candidates))]]
    knee = sum(knee_points, Vector()) / len(knee_points)
    return hip, knee, foot


def configure_segment(obj, name, start, end, side, row):
    obj.name = name
    obj.data.name = f"{name}_mesh"
    obj.data.transform(Matrix.Translation(-start))
    obj.location = start

    marker = bpy.data.objects.new(name=f"End_{name}", object_data=None)
    marker.empty_display_type = "SPHERE"
    marker.empty_display_size = 0.04
    marker.parent = obj
    marker.location = end - start
    bpy.context.scene.collection.objects.link(marker)

    obj["rest_length"] = (end - start).length
    obj["side"] = side
    obj["row"] = row


def split_leg_for_bones(obj, name):
    hip, knee, foot = analyze_leg(obj, name)
    upper_name = f"{name}_Upper"
    lower_name = f"{name}_Lower"
    upper = filtered_copy(
        obj,
        upper_name,
        lambda center: distance_to_segment(center, hip, knee) <= distance_to_segment(center, knee, foot),
    )
    lower = filtered_copy(
        obj,
        lower_name,
        lambda center: distance_to_segment(center, hip, knee) > distance_to_segment(center, knee, foot),
    )
    bpy.data.objects.remove(obj, do_unlink=True)
    side = "left" if "_L" in name else "right"
    row = int(name[-1])
    configure_segment(upper, upper_name, hip, knee, side, row)
    configure_segment(lower, lower_name, knee, foot, side, row)
    print(
        "PREPARED_LEG",
        name,
        "hip=", tuple(round(value, 4) for value in hip),
        "knee=", tuple(round(value, 4) for value in knee),
        "foot=", tuple(round(value, 4) for value in foot),
        "segments=", round((knee - hip).length, 4), round((foot - knee).length, 4),
    )


def optimize_for_realtime(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new(name="RealtimeDecimation", type="DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = DECIMATE_RATIO
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


args = sys.argv[sys.argv.index("--") + 1 :]
source_path = os.path.abspath(args[0])
output_path = os.path.abspath(args[1])
os.makedirs(os.path.dirname(output_path), exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=source_path, import_shading="NORMALS")

mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
for obj in mesh_objects:
    bake_to_world(obj)

for obj in list(bpy.context.scene.objects):
    if obj.type != "MESH":
        bpy.data.objects.remove(obj, do_unlink=True)

objects = {obj.name: obj for obj in bpy.context.scene.objects if obj.type == "MESH"}
thorax_source = objects["mesh_10"]

# The segmentation export fused the foremost leg pair to the thorax.  Split the
# two lateral/front regions at the shoulder; the animated meshes overlap the
# retained body edge so the procedural motion never exposes the cut.
front_left = filtered_copy(
    thorax_source,
    "Leg_L0",
    lambda center: center.x < -0.012 and center.y < -0.006,
)
front_right = filtered_copy(
    thorax_source,
    "Leg_R0",
    lambda center: center.x > 0.012 and center.y < -0.006,
)
body_thorax = filtered_copy(
    thorax_source,
    "BodyThorax",
    lambda center: not (abs(center.x) > 0.012 and center.y < -0.006),
)
bpy.data.objects.remove(thorax_source, do_unlink=True)

rename_map = {
    "mesh_0": "Leg_L1",
    "mesh_2": "Leg_R1",
    "mesh_7": "Leg_L2",
    "mesh_3": "Leg_R2",
    "mesh_9": "Leg_L3",
    "mesh_4": "Leg_R3",
    "mesh_1": "BodyAbdomen",
    "mesh_8": "BodyHead",
    "mesh_5": "MandibleL",
    "mesh_6": "MandibleR",
}
for old_name, new_name in rename_map.items():
    objects[old_name].name = new_name
    objects[old_name].data.name = f"{new_name}_mesh"

prepared_meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
for obj in prepared_meshes:
    obj.data.transform(Matrix.Scale(MODEL_SCALE, 4))
    optimize_for_realtime(obj)

for leg_name in [
    "Leg_L0", "Leg_L1", "Leg_L2", "Leg_L3",
    "Leg_R0", "Leg_R1", "Leg_R2", "Leg_R3",
]:
    split_leg_for_bones(bpy.data.objects[leg_name], leg_name)

for body_name in ["BodyThorax", "BodyAbdomen", "BodyHead", "MandibleL", "MandibleR"]:
    body = bpy.data.objects[body_name]
    body["arachnid_body_part"] = True

bpy.context.scene["arachnid_prepared_version"] = 2
bpy.context.scene["model_scale"] = MODEL_SCALE

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(
    filepath=output_path,
    export_format="GLB",
    export_yup=True,
    export_animations=False,
    export_skins=False,
    export_cameras=False,
    export_lights=False,
    export_extras=True,
)
print("PREPARED_EXPORT", output_path)
