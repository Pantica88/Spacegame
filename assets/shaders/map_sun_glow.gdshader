shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

void vertex() {
	// Face the map camera while retaining the sun's world position and depth.
	float model_scale = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * model_scale, INV_VIEW_MATRIX[1] * model_scale, INV_VIEW_MATRIX[2] * model_scale, MODEL_MATRIX[3]);
}

void fragment() {
	float radius = length((UV - vec2(0.5)) * 12.0);
	float halo = exp(-pow(radius / 4.25, 1.3)) * 0.65;
	float bloom = exp(-radius * radius / 1.625) * 2.2;
	ALBEDO = vec3(1.0, 0.60, 0.20) * halo + vec3(1.0, 0.96, 0.88) * bloom;
	ALPHA = 1.0 - smoothstep(3.5, 6.0, radius);
}
