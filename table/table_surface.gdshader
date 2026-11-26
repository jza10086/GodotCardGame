shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.25, 0.11, 0.058, 1.0);
uniform vec4 grain_color : source_color = vec4(0.47, 0.25, 0.135, 1.0);
uniform bool felt = false;

varying vec3 table_position;

float surface_noise(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	table_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = table_position.xz;
	if (felt) {
		vec2 edge = abs(p);
		float apothem = max(max(edge.x, edge.y), (edge.x + edge.y) * 0.70710678);
		float line = 1.0 - smoothstep(0.023, 0.061, abs(apothem - 10.73));
		float trim = smoothstep(10.73, 10.91, apothem);
		float nap = surface_noise(floor(p * 85.0));
		vec3 cloth = base_color.rgb * (0.95 + 0.08 * nap - trim * 0.16);
		ALBEDO = mix(cloth, grain_color.rgb, line * 0.68);
		ROUGHNESS = 0.96;
	} else {
		float drift = sin(p.x * 0.77 + p.y * 0.38) + 0.36 * sin(p.x * 1.8 - p.y * 1.1);
		float grain_axis = p.y + 0.21 * p.x + table_position.y * 0.32 + drift * 0.15;
		float band = 0.5 + 0.5 * sin(grain_axis * 17.0);
		float pores = 0.5 + 0.5 * sin(grain_axis * 53.0 + sin(p.x * 0.88));
		float tone = 0.31 + band * 0.19 + pores * 0.10;
		ALBEDO = mix(base_color.rgb, grain_color.rgb, tone);
		ROUGHNESS = 0.43 + pores * 0.10;
	}
}
