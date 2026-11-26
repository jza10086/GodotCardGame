shader_type spatial;
render_mode cull_disabled;

uniform float layers = 1.0;

void fragment() {
	float line = smoothstep(0.64, 0.94, fract(UV.y * layers));
	float detail = 1.0 - smoothstep(0.35, 1.55, fwidth(UV.y * layers));
	float stripe = layers > 1.0 ? line * detail : 0.0;
	ALBEDO = mix(vec3(0.86, 0.79, 0.65), vec3(0.49, 0.38, 0.28), stripe * 0.57);
	ROUGHNESS = 0.87;
}
