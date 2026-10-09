shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never;
#include "res://assets/shaders/atmosphere.gdshaderinc"
#include "res://assets/shaders/renderer_color.gdshaderinc"
uniform vec3 camera_forward = vec3(0.0, 0.0, -1.0);
varying vec3 surface_point;

void vertex() {
	surface_point = mat3(MODEL_MATRIX)*VERTEX;
}

void fragment() {
	// Draw the far side of the shell: terrain depth hides it over the disk,
	// where the terrain shader already integrates the foreground haze.
	vec3 direction = normalize(camera_forward);
	vec3 origin = surface_point-direction*(2.0*AIR_RADIUS);
	vec3 transmission;
	ALBEDO = scatter_air(origin,direction,2.0*AIR_RADIUS,transmission);
	ALPHA = 1.0;
	vec4 added = additive_output(ALBEDO, ALPHA);
	ALBEDO = added.rgb;
	ALPHA = added.a;
}
