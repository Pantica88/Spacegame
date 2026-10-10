shader_type spatial;
// Premultiplied blending over a clear target stores color unmultiplied, which
// keeps full 8-bit precision for thin wisps.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/clouds_volume.gdshaderinc"
#include "res://assets/shaders/renderer_color.gdshaderinc"

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Temporal mode renders a half-size target: each texel marches one pixel of
// its 2x2 block of the full reduced target, selected by temporal_offset. The
// target size is even, so this camera's frustum matches the full target's.
uniform bool temporal_march = false;
uniform vec2 temporal_offset = vec2(0.0);
uniform vec2 temporal_target_size = vec2(1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = FRAGCOORD.xy;
	if (temporal_march) {
		pixel = floor(FRAGCOORD.xy) * 2.0 + temporal_offset + 0.5;
		uv = pixel / temporal_target_size;
	}
	vec3 ray = cloud_view_ray(uv, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	// The same pixel coordinate keeps each pixel's stable jitter unchanged.
	vec4 result = integrate_clouds(ray, 1e20, pixel);
	if (result.a < 0.005) { discard; }
	ALBEDO = stored_output(pow(clamp(result.rgb / CLOUD_ENCODE_RANGE, 0.0, 1.0), vec3(1.0 / 2.2)));
	ALPHA = result.a;
}
