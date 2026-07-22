shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(0.0, 0.08, UV.y) * smoothstep(0.0, 0.08, 1.0 - UV.x) * smoothstep(0.0, 0.08, 1.0 - UV.y);
	float worn_paint = step(0.19, noise(UV * vec2(22.0, 9.0))) * mix(0.58, 1.0, noise(UV * 5.0));
	float dirt = noise(UV * vec2(55.0, 17.0));
	ALBEDO = mix(vec3(0.42, 0.29, 0.035), vec3(0.72, 0.54, 0.09), dirt);
	ROUGHNESS = 0.97;
	METALLIC = 0.0;
	ALPHA = edge * worn_paint * 0.86;
}
