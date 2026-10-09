shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform float thrust_intensity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	// UV radius 1 is the actual inner nozzle lip, not a wide billboard halo.
	float aperture = 1.0 - smoothstep(0.90, 1.0, radius);
	float hollow_center = smoothstep(0.38, 0.60, radius);
	float hot_ring = exp(-pow((radius - 0.74) / 0.18, 2.0));
	float pulse = 1.0 + sin(TIME * 43.0) * 0.035;
	ALBEDO = mix(vec3(0.18, 0.65, 1.0), vec3(0.85, 0.97, 1.0), hot_ring)
		* (0.35 + hot_ring * 1.6) * pulse;
	ALPHA = aperture * hollow_center * thrust_intensity * 0.65;
}
