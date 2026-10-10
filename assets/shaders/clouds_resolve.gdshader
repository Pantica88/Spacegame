shader_type spatial;
// Rebuilds the full cloud target from this frame's fresh samples (one pixel of
// every grid x grid block) and the previous result, reprojected for camera
// motion. Same storage as clouds_lowres.gdshader: premultiplied blending over
// a clear target stores the encoded color unmultiplied, opacity in alpha.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/renderer_color.gdshaderinc"

// Texel c holds pixel c * grid + fresh_offset of the full target.
uniform sampler2D fresh_samples : filter_nearest, repeat_disable;
uniform sampler2D history : filter_nearest, repeat_disable;
uniform int grid = 2;
uniform vec2 fresh_offset = vec2(0.0);
uniform bool history_valid = false;
// World-to-view rotation of the previous frame's camera.
uniform mat3 previous_view_rotation;
// Full-resolution reconstruction only. Camera translation since the previous
// frame (km, planet frame) reprojects history at the low deck's depth;
// zero treats every cloud as infinitely far, as the reduced pass does.
uniform vec3 camera_motion_km = vec3(0.0);
uniform vec3 camera_planet_km = vec3(0.0, 600.01, 0.0);
// History is reprojected as if every cloud lay on this sphere (km): the
// middle of the low deck, where most cloud sits. Real cloud lies within
// reprojection_spread_km of it; parallax over that spread decides how far the
// reprojection can be trusted.
uniform float reprojection_radius_km = 603.85;
uniform float reprojection_spread_km = 0.7;
// Catmull-Rom history keeps reprojected detail sharp while the camera turns;
// bilinear softens it a little every frame.
uniform bool bicubic_history = false;
// How far reprojected history may stray outside the fresh samples around it
// when nothing moves. Parallax tightens it to the fresh range.
uniform float history_tolerance = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec4 history_bilinear(vec2 uv) {
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

vec4 catmull_rom_weights(float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	return vec4(-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0,
		-1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2);
}

vec4 history_bicubic(vec2 uv) {
	// Filtered in premultiplied space, where empty texels carry no color.
	ivec2 size = textureSize(history, 0);
	vec2 position = uv * vec2(size) - 0.5;
	vec2 base = floor(position);
	vec2 f = position - base;
	vec4 wx = catmull_rom_weights(f.x);
	vec4 wy = catmull_rom_weights(f.y);
	vec4 sum = vec4(0.0);
	for (int y = 0; y < 4; y++) {
		for (int x = 0; x < 4; x++) {
			vec4 texel = texelFetch(history, clamp(ivec2(base) + ivec2(x - 1, y - 1), ivec2(0), size - 1), 0);
			sum += vec4(texel.rgb * texel.a, texel.a) * wx[x] * wy[y];
		}
	}
	// Negative lobes can overshoot; clamp_to_fresh() bounds the rest.
	sum = max(sum, vec4(0.0));
	float alpha = min(sum.a, 1.0);
	return vec4(sum.rgb / max(sum.a, 1e-5), alpha);
}

vec4 fresh_at(ivec2 cell) {
	return texelFetch(fresh_samples, clamp(cell, ivec2(0), textureSize(fresh_samples, 0) - 1), 0);
}

// Opacity-weighted bilinear between the fresh samples around a pixel, for
// pixels with no usable history.
vec4 fresh_fill(vec2 pixel_center) {
	vec2 position = (pixel_center - 0.5 - fresh_offset) / float(grid);
	vec2 base = floor(position);
	vec2 f = position - base;
	vec3 color = vec3(0.0);
	float alpha = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 offset = ivec2(i & 1, i >> 1);
		vec4 texel = fresh_at(ivec2(base) + offset);
		vec2 w2 = mix(1.0 - f, f, vec2(offset));
		float w = w2.x * w2.y;
		color += texel.rgb * texel.a * w;
		alpha += texel.a * w;
	}
	return vec4(color / max(alpha, 1e-5), alpha);
}

// Distance (km) along a view ray to the reprojection sphere, or 0 for a ray
// that misses it: the near side from above, the far side from below.
float reprojection_depth(vec3 ray) {
	vec3 origin = camera_planet_km;
	float r = length(origin);
	float b = dot(origin, ray);
	// (r - R)(r + R) keeps the precision that r * r - R * R loses near the sphere.
	float c = (r - reprojection_radius_km) * (r + reprojection_radius_km);
	float h = b * b - c;
	if (h < 0.0) { return 0.0; }
	float root = sqrt(h);
	float depth = c > 0.0 ? -b - root : -b + root;
	return max(depth, 0.0);
}

vec2 previous_uv_of(vec3 direction, mat4 projection) {
	vec4 clip = projection * vec4(previous_view_rotation * direction, 0.0);
	return clip.w > 0.0 ? clip.xy / clip.w * 0.5 + 0.5 : vec2(-1.0);
}

void fragment() {
	ivec2 pixel = ivec2(FRAGCOORD.xy);
	ivec2 cell = pixel / grid;
	vec4 result;
	if (pixel - cell * grid == ivec2(fresh_offset)) {
		result = fresh_at(cell);
	} else {
		result = fresh_fill(FRAGCOORD.xy);
		if (history_valid) {
			vec4 view_ray = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
			vec3 ray = normalize(mat3(INV_VIEW_MATRIX) * view_ray.xyz);
			vec2 previous_uv = previous_uv_of(ray, PROJECTION_MATRIX);
			// Pixels by which the reprojection may misplace the cloud.
			float uncertainty = 0.0;
			float depth = reprojection_depth(ray);
			if (depth > 0.0 && dot(camera_motion_km, camera_motion_km) > 0.0) {
				// Where the cloud at this depth sat in the previous view, and
				// where it would have sat at the far edge of the deck.
				vec2 near_uv = previous_uv_of(normalize(ray * depth + camera_motion_km), PROJECTION_MATRIX);
				vec2 far_uv = previous_uv_of(normalize(ray * (depth + reprojection_spread_km) + camera_motion_km), PROJECTION_MATRIX);
				uncertainty = length((far_uv - near_uv) * VIEWPORT_SIZE);
				// Close to the sphere the spread spans the whole view.
				if (depth < reprojection_spread_km) { uncertainty = max(uncertainty, 4.0); }
				previous_uv = near_uv;
			}
			if (all(greaterThanEqual(previous_uv, vec2(0.0))) && all(lessThanEqual(previous_uv, vec2(1.0)))) {
				vec4 reprojected = bicubic_history ? history_bicubic(previous_uv) : history_bilinear(previous_uv);
				// Clamp to the fresh samples around this block, so clouds that
				// moved or changed cannot leave trails. A still view keeps some
				// slack: detail finer than the fresh grid lies outside their range.
				vec4 low = vec4(1e9);
				vec4 high = vec4(-1e9);
				for (int y = -1; y <= 1; y++) {
					for (int x = -1; x <= 1; x++) {
						vec4 near = fresh_at(cell + ivec2(x, y));
						low = min(low, near);
						high = max(high, near);
					}
				}
				float slack = history_tolerance * (1.0 - smoothstep(0.25, 1.0, uncertainty));
				vec4 clamped = clamp(reprojected, low - slack, high + slack);
				// Where the deck's depth spread misplaces history by pixels,
				// lean on the fresh fill instead.
				result = mix(clamped, result, smoothstep(1.0, 4.0, uncertainty));
			}
		}
	}
	if (result.a < 0.005) { discard; }
	ALBEDO = stored_output(clamp(result.rgb, 0.0, 1.0));
	ALPHA = clamp(result.a, 0.0, 1.0);
}
