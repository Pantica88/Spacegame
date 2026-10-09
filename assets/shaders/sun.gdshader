shader_type spatial;
render_mode unshaded, cull_back, blend_add, depth_draw_never;

void fragment() {
	// Add light to the halo instead of covering it with a darker solid disk.
	float facing = max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);
	ALBEDO = vec3(1.0, 0.96, 0.88) * 4.0;
	// A broad feather with zero slope at the silhouette avoids a visible rim.
	ALPHA = smoothstep(0.0, 0.9, facing);
}
