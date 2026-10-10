shader_type spatial;
// Rebuilds the full reduced-resolution cloud target from this frame's quarter
// of fresh samples and the previous result, reprojected for the camera's
// rotation and travel. Same storage as clouds_lowres.gdshader: premultiplied
// blending over a clear target stores the encoded color unmultiplied, opacity
// in alpha.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/renderer_color.gdshaderinc"

// Half-size target: texel c holds pixel 2c + fresh_offset of the full target.
uniform sampler2D fresh_samples : filter_nearest, repeat_disable;
uniform sampler2D history : filter_nearest, repeat_disable;
uniform vec2 fresh_offset = vec2(0.0);
uniform bool history_valid = false;
// World-to-view rotation of the previous frame's camera.
uniform mat3 previous_view_rotation;
// Camera travel since the previous frame and its position (km, planet frame).
// History moves as if every cloud lay on the sphere of reprojection_radius_km,
// the middle of the low deck; seen from altitude that is close to where they
// are, so travel no longer drags history out of place.
uniform vec3 camera_motion_km = vec3(0.0);
uniform vec3 camera_planet_km = vec3(0.0, 600.01, 0.0);
uniform float reprojection_radius_km = 603.85;
// Share of history kept where a pixel is marched afresh. Far above the clouds
// a pixel covers kilometres of sub-pixel cloud, and replacing it outright
// flickers; averaging over frames settles that. 0 replaces as before.
uniform float history_blend = 0.0;
// Slack (stored units) letting history stray outside the fresh samples around
// it. Grazing rays at the planet's rim sample the deck kilometres apart, and
// their fresh values jump between frames; clamping history to them brings the
// flicker back. Only far above the clouds while the camera barely moves.
uniform float history_tolerance = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec4 catmull_rom_weights(float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	return vec4(-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0,
		-1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2);
}

// Catmull-Rom history in premultiplied space, where empty texels carry no
// color, limited to its four nearest texels: bilinear softens a moving view a
// little every frame, and an unlimited sharp filter would build up overshoot.
vec4 history_at(vec2 uv) {
	ivec2 size = textureSize(history, 0);
	vec2 position = uv * vec2(size) - 0.5;
	vec2 base = floor(position);
	vec2 f = position - base;
	vec4 wx = catmull_rom_weights(f.x);
	vec4 wy = catmull_rom_weights(f.y);
	vec4 sum = vec4(0.0);
	vec4 low = vec4(1e9);
	vec4 high = vec4(-1e9);
	for (int y = 0; y < 4; y++) {
		for (int x = 0; x < 4; x++) {
			vec4 texel = texelFetch(history, clamp(ivec2(base) + ivec2(x - 1, y - 1), ivec2(0), size - 1), 0);
			vec4 premultiplied = vec4(texel.rgb * texel.a, texel.a);
			sum += premultiplied * wx[x] * wy[y];
			if ((x == 1 || x == 2) && (y == 1 || y == 2)) {
				low = min(low, premultiplied);
				high = max(high, premultiplied);
			}
		}
	}
	sum = clamp(sum, low, high);
	return vec4(sum.rgb / max(sum.a, 1e-5), sum.a);
}

// Distance (km) along a view ray to the reprojection sphere: the near side
// from above, the far side from below. A ray passing beside it uses its
// closest approach, so the distance runs on smoothly across the planet's rim
// instead of jumping to infinity there.
float reprojection_depth(vec3 ray) {
	float r = length(camera_planet_km);
	float b = dot(camera_planet_km, ray);
	// (r - R)(r + R) keeps the precision that r * r - R * R loses near the sphere.
	float c = (r - reprojection_radius_km) * (r + reprojection_radius_km);
	float h = b * b - c;
	if (h < 0.0) { return max(-b, 0.0); }
	return max(c > 0.0 ? -b - sqrt(h) : -b + sqrt(h), 0.0);
}

// Opacity-weighted bilinear between this frame's fresh samples around a pixel,
// for pixels without usable history: soft rather than blocky.
vec4 fresh_fill(vec2 pixel_center) {
	ivec2 cells = textureSize(fresh_samples, 0);
	vec2 position = (pixel_center - 0.5 - fresh_offset) / 2.0;
	vec2 base = floor(position);
	vec2 f = position - base;
	vec3 color = vec3(0.0);
	float alpha = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 offset = ivec2(i & 1, i >> 1);
		vec4 texel = texelFetch(fresh_samples, clamp(ivec2(base) + offset, ivec2(0), cells - 1), 0);
		vec2 w2 = mix(1.0 - f, f, vec2(offset));
		float w = w2.x * w2.y;
		color += texel.rgb * texel.a * w;
		alpha += texel.a * w;
	}
	return vec4(color / max(alpha, 1e-5), alpha);
}

vec2 previous_uv_of(vec3 direction, mat4 projection) {
	vec4 clip = projection * vec4(previous_view_rotation * direction, 0.0);
	return clip.w > 0.0 ? clip.xy / clip.w * 0.5 + 0.5 : vec2(-1.0);
}

void fragment() {
	ivec2 pixel = ivec2(FRAGCOORD.xy);
	ivec2 cell = pixel / 2;
	ivec2 cells = textureSize(fresh_samples, 0);
	vec4 fresh = texelFetch(fresh_samples, clamp(cell, ivec2(0), cells - 1), 0);
	vec4 result = fresh;
	bool is_fresh = pixel - cell * 2 == ivec2(fresh_offset);
	if (!is_fresh) {
		result = fresh_fill(FRAGCOORD.xy);
	}
	if (history_valid && (!is_fresh || history_blend > 0.0)) {
		vec4 view_ray = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
		vec3 ray = normalize(mat3(INV_VIEW_MATRIX) * view_ray.xyz);
		float depth = reprojection_depth(ray);
		// Rays pointing away from the planet see only far clouds: rotation alone.
		vec3 seen = depth > 0.0 ? ray * depth + camera_motion_km : ray;
		vec2 previous_uv = previous_uv_of(normalize(seen), PROJECTION_MATRIX);
		if (all(greaterThanEqual(previous_uv, vec2(0.0))) && all(lessThanEqual(previous_uv, vec2(1.0)))) {
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
			vec4 clamped = clamp(reprojected, low - history_tolerance, high + history_tolerance);
			result = is_fresh ? mix(fresh, clamped, history_blend) : clamped;
		}
	}
	if (result.a < 0.005) { discard; }
	ALBEDO = stored_output(result.rgb);
	ALPHA = result.a;
}
