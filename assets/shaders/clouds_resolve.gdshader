shader_type spatial;
// Rebuilds the full reduced-resolution cloud target from this frame's quarter
// of fresh samples and the previous result, reprojected for camera rotation.
// Same storage as clouds_lowres.gdshader: premultiplied blending over a clear
// target stores the encoded color unmultiplied, opacity in alpha.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/renderer_color.gdshaderinc"

// Half-size target: texel c holds pixel 2c + fresh_offset of the full target.
uniform sampler2D fresh_samples : filter_nearest, repeat_disable;
uniform sampler2D history : filter_nearest, repeat_disable;
uniform vec2 fresh_offset = vec2(0.0);
uniform bool history_valid = false;
// World-to-view rotation of the previous frame's camera.
uniform mat3 previous_view_rotation;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec4 history_at(vec2 uv) {
	// Opacity-weighted bilinear: empty texels carry no color.
	ivec2 size = textureSize(history, 0);
	vec2 position = uv * vec2(size) - 0.5;
	vec2 base = floor(position);
	vec2 f = position - base;
	vec3 color = vec3(0.0);
	float alpha = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 offset = ivec2(i & 1, i >> 1);
		vec4 texel = texelFetch(history, clamp(ivec2(base) + offset, ivec2(0), size - 1), 0);
		vec2 w2 = mix(1.0 - f, f, vec2(offset));
		float w = w2.x * w2.y;
		color += texel.rgb * texel.a * w;
		alpha += texel.a * w;
	}
	return vec4(color / max(alpha, 1e-5), alpha);
}

void fragment() {
	ivec2 pixel = ivec2(FRAGCOORD.xy);
	ivec2 cell = pixel / 2;
	ivec2 cells = textureSize(fresh_samples, 0);
	vec4 fresh = texelFetch(fresh_samples, clamp(cell, ivec2(0), cells - 1), 0);
	vec4 result = fresh;
	if (history_valid && pixel - cell * 2 != ivec2(fresh_offset)) {
		vec4 view_ray = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
		vec3 ray = normalize(mat3(INV_VIEW_MATRIX) * view_ray.xyz);
		vec4 clip = PROJECTION_MATRIX * vec4(previous_view_rotation * ray, 0.0);
		vec2 previous_uv = clip.xy / clip.w * 0.5 + 0.5;
		if (clip.w > 0.0 && all(greaterThanEqual(previous_uv, vec2(0.0))) && all(lessThanEqual(previous_uv, vec2(1.0)))) {
			vec4 reprojected = history_at(previous_uv);
			// Clamp to the fresh samples around this block, so clouds that moved
			// or changed cannot leave trails.
			vec4 low = vec4(1e9);
			vec4 high = vec4(-1e9);
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					vec4 near = texelFetch(fresh_samples, clamp(cell + ivec2(x, y), ivec2(0), cells - 1), 0);
					low = min(low, near);
					high = max(high, near);
				}
			}
			result = clamp(reprojected, low, high);
		}
	}
	if (result.a < 0.005) { discard; }
	ALBEDO = stored_output(result.rgb);
	ALPHA = result.a;
}
