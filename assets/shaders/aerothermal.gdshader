shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, world_vertex_coords;
#include "res://assets/shaders/renderer_color.gdshaderinc"

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 air_direction = vec3(0.0);
varying vec3 hull_normal;

void vertex() {
	hull_normal = normalize(NORMAL);
	// Avoid coplanar depth flicker against the underlying authored surface.
	VERTEX += hull_normal * 0.002;
}

void fragment() {
	// Use the actual hull geometry; leading faces heat more than sheltered faces.
	float windward = max(dot(normalize(hull_normal), air_direction), 0.0);
	float heat = intensity * (0.38 + 0.62 * pow(windward, 0.65));
	float edge = pow(max(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0), 2.0);
	vec3 color = mix(vec3(0.8, 0.025, 0.002), vec3(1.0, 0.38, 0.035), smoothstep(0.35, 1.0, heat));
	ALBEDO = color * (0.8 + 0.8 * heat);
	ALPHA = heat * (0.85 + 0.15 * edge);
	ALBEDO = material_output(ALBEDO);
}
