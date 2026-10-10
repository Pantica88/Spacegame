shader_type spatial;
// Premultiplied blending over a clear target stores color unmultiplied, which
// keeps full 8-bit precision for thin wisps.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/clouds_volume.gdshaderinc"
#include "res://assets/shaders/renderer_color.gdshaderinc"

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Temporal mode renders a target 1 / temporal_grid the size: each texel
// marches one pixel of its grid x grid block of the full target, selected by
// temporal_offset. Rays use the viewing camera's projection, since this
// target's aspect can differ slightly from the full target's.
uniform bool temporal_march = false;
uniform int temporal_grid = 2;
uniform vec2 temporal_offset = vec2(0.0);
uniform vec2 temporal_target_size = vec2(1.0);
uniform mat4 view_inv_projection;

void fragment() {
	vec2 pixel = FRAGCOORD.xy;
	vec3 ray;
	if (temporal_march) {
		pixel = floor(FRAGCOORD.xy) * float(temporal_grid) + temporal_offset + 0.5;
		ray = cloud_view_ray(pixel / temporal_target_size, view_inv_projection, INV_VIEW_MATRIX);
	} else {
		ray = cloud_view_ray(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	}
	// The same pixel coordinate keeps each pixel's stable jitter unchanged.
	vec4 result = integrate_clouds(ray, 1e20, pixel);
	if (result.a < 0.005) { discard; }
	ALBEDO = stored_output(pow(clamp(result.rgb / CLOUD_ENCODE_RANGE, 0.0, 1.0), vec3(1.0 / 2.2)));
	ALPHA = result.a;
}
