// GLSL compute passes for the clouds (RenderingDevice), not Godot shader
// language: cloud_compute.gd prepends #version, the parameter buffer and the
// cloud volume (clouds_volume.gdshaderinc, uniforms mapped to buffer slots),
// then defines CLOUD_MARCH, CLOUD_REVEAL or CLOUD_RESOLVE. The passes run
// inside the frame, before the transparent pass that composites the result
// (clouds.gdshader).
//
// The march integrates one pixel of every frame_grid x frame_grid block and
// stores its cloud light (linear, unmultiplied), opacity, and the distance to
// the cloud it saw. The reveal pass marches one pixel of every 2x2 block that
// has no exact history, such as sky a pan has just brought into view. The
// resolve rebuilds every pixel: marched ones are copied, the rest reproject
// the previous result through their distance or fill from nearby samples.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Ray through the centre of a full-resolution pixel, in world axes.
vec3 frame_ray(vec2 pixel) {
	vec2 uv = (pixel + 0.5) / frame_size;
	vec4 view_ray = frame_inv_projection * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	return normalize(frame_view_basis * view_ray.xyz);
}

// Pixel position in the previous frame of a direction seen from the previous
// camera, or -1 behind it.
vec2 previous_pixel(vec3 direction) {
	vec4 clip = previous_projection * vec4(previous_view_rotation * direction, 0.0);
	return clip.w > 0.0 ? (clip.xy / clip.w * 0.5 + 0.5) * frame_size : vec2(-1.0);
}

bool on_screen(vec2 pixel) {
	return all(greaterThanEqual(pixel, vec2(0.0))) && all(lessThan(pixel, frame_size));
}

// History depth also marks pixels that were filled in rather than marched:
// those store -(distance + 1).
float history_distance(float stored) {
	return stored >= 0.0 ? stored : -stored - 1.0;
}

float stored_distance(float distance, bool exact) {
	return exact ? distance : -distance - 1.0;
}

#ifdef CLOUD_MARCH
layout(rgba16f, set = 0, binding = 4) uniform restrict writeonly image2D fresh_color;
layout(r32f, set = 0, binding = 5) uniform restrict writeonly image2D fresh_depth;

void main() {
	ivec2 cell = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(cell, imageSize(fresh_color)))) { return; }
	vec2 pixel = vec2(cell) * frame_grid + frame_offset;
	vec4 result = vec4(0.0);
	float depth = 0.0;
	if (all(lessThan(pixel, frame_size))) {
		result = integrate_clouds_depth(frame_ray(pixel), 1e20, pixel + 0.5, depth);
	}
	if (result.a < 0.005) { result = vec4(0.0); depth = 0.0; }
	imageStore(fresh_color, cell, result);
	imageStore(fresh_depth, cell, vec4(depth));
}
#endif

#ifdef CLOUD_REVEAL
layout(rgba16f, set = 0, binding = 4) uniform restrict writeonly image2D reveal_color;
layout(r32f, set = 0, binding = 5) uniform restrict writeonly image2D reveal_depth;
layout(r32f, set = 0, binding = 6) uniform restrict readonly image2D history_depth;

void main() {
	ivec2 cell = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(cell, imageSize(reveal_color)))) { return; }
	ivec2 pixel = cell * 2 + ivec2(reveal_offset);
	bool march = false;
	// After a cut every pixel lacks history; the march rebuilds those as usual
	// instead of marching a quarter of the screen here.
	if (history_valid && on_screen(vec2(pixel))) {
		ivec2 grid_cell = pixel / int(frame_grid);
		if (pixel - grid_cell * int(frame_grid) != ivec2(frame_offset)) {
			vec2 previous = previous_pixel(cloud_motion * frame_ray(vec2(pixel)));
			march = !on_screen(previous) || imageLoad(history_depth, ivec2(previous)).r < 0.0;
		}
	}
	// Alpha -1 marks a pixel this pass skipped.
	vec4 result = vec4(0.0, 0.0, 0.0, -1.0);
	float depth = 0.0;
	if (march) {
		result = integrate_clouds_depth(frame_ray(vec2(pixel)), 1e20, vec2(pixel) + 0.5, depth);
		if (result.a < 0.005) { result = vec4(0.0); depth = 0.0; }
	}
	imageStore(reveal_color, cell, result);
	imageStore(reveal_depth, cell, vec4(depth));
}
#endif

#ifdef CLOUD_RESOLVE
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D fresh_color;
layout(r32f, set = 0, binding = 2) uniform restrict readonly image2D fresh_depth;
layout(rgba16f, set = 0, binding = 3) uniform restrict readonly image2D history_color;
layout(r32f, set = 0, binding = 4) uniform restrict readonly image2D history_depth;
layout(rgba16f, set = 0, binding = 5) uniform restrict writeonly image2D out_color;
layout(r32f, set = 0, binding = 6) uniform restrict writeonly image2D out_depth;
layout(rgba16f, set = 0, binding = 7) uniform restrict readonly image2D reveal_color;
layout(r32f, set = 0, binding = 8) uniform restrict readonly image2D reveal_depth;

// The reveal pass's sample for a 2x2 cell; alpha -1 where it marched nothing.
vec4 reveal_at(ivec2 cell, out float depth) {
	if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, imageSize(reveal_color)))) {
		depth = 0.0;
		return vec4(0.0, 0.0, 0.0, -1.0);
	}
	depth = imageLoad(reveal_depth, cell).r;
	return imageLoad(reveal_color, cell);
}

// Opacity-weighted bilinear between the reveal samples around a pixel, using
// only cells the pass marched. False where it marched none of them.
bool reveal_fill(vec2 pixel_center, out vec4 color, out float depth) {
	vec2 position = (pixel_center - 0.5 - reveal_offset) / 2.0;
	vec2 base = floor(position);
	vec2 f = position - base;
	vec3 sum = vec3(0.0);
	float alpha = 0.0;
	float weight = 0.0;
	depth = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 offset = ivec2(i & 1, i >> 1);
		float near_depth;
		vec4 texel = reveal_at(ivec2(base) + offset, near_depth);
		if (texel.a < 0.0) { continue; }
		vec2 w2 = mix(1.0 - f, f, vec2(offset));
		float w = w2.x * w2.y + 1e-4;
		sum += texel.rgb * texel.a * w;
		alpha += texel.a * w;
		weight += w;
		if (near_depth > 0.0) { depth = depth > 0.0 ? min(depth, near_depth) : near_depth; }
	}
	color = vec4(sum / max(alpha, 1e-5), alpha / max(weight, 1e-5));
	return weight > 0.0;
}

vec4 fresh_at(ivec2 cell) {
	return imageLoad(fresh_color, clamp(cell, ivec2(0), imageSize(fresh_color) - 1));
}

float fresh_depth_at(ivec2 cell) {
	return imageLoad(fresh_depth, clamp(cell, ivec2(0), imageSize(fresh_depth) - 1)).r;
}

vec4 history_at(ivec2 texel) {
	return imageLoad(history_color, clamp(texel, ivec2(0), imageSize(history_color) - 1));
}

vec4 catmull_rom_weights(float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	return vec4(-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0,
		-1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2);
}

// Catmull-Rom history in premultiplied space, limited to the range of its four
// nearest texels: repeated resampling while moving would otherwise build up
// overshoot into speckle.
vec4 history_bicubic(vec2 position) {
	vec2 base = floor(position - 0.5);
	vec2 f = position - 0.5 - base;
	vec4 wx = catmull_rom_weights(f.x);
	vec4 wy = catmull_rom_weights(f.y);
	vec4 sum = vec4(0.0);
	vec4 low = vec4(1e9);
	vec4 high = vec4(-1e9);
	for (int y = 0; y < 4; y++) {
		for (int x = 0; x < 4; x++) {
			vec4 texel = history_at(ivec2(base) + ivec2(x - 1, y - 1));
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

// Opacity-weighted bilinear between the fresh samples around a pixel; also
// returns the nearest cloud distance among them (0 for none).
vec4 fresh_fill(vec2 pixel_center, out float depth) {
	vec2 position = (pixel_center - 0.5 - frame_offset) / frame_grid;
	vec2 base = floor(position);
	vec2 f = position - base;
	vec3 color = vec3(0.0);
	float alpha = 0.0;
	depth = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 offset = ivec2(i & 1, i >> 1);
		vec4 texel = fresh_at(ivec2(base) + offset);
		vec2 w2 = mix(1.0 - f, f, vec2(offset));
		float w = w2.x * w2.y;
		color += texel.rgb * texel.a * w;
		alpha += texel.a * w;
		float near = fresh_depth_at(ivec2(base) + offset);
		if (near > 0.0) { depth = depth > 0.0 ? min(depth, near) : near; }
	}
	return vec4(color / max(alpha, 1e-5), alpha);
}

// The clamp works in the reduced pass's 8-bit encoding (clouds_lowres), where
// equal steps look equally large in bright and dark cloud.
vec4 encode(vec4 color) {
	return vec4(pow(clamp(color.rgb / 4.0, 0.0, 1.0), vec3(1.0 / 2.2)), color.a);
}

vec4 decode(vec4 encoded) {
	return vec4(pow(encoded.rgb, vec3(2.2)) * 4.0, encoded.a);
}

// Distance (km) along a view ray to the middle of the low deck, or 0 for a ray
// that misses it: where a pixel showing clear air would show cloud, so its
// history moves with the camera instead of staying put at infinity.
float deck_distance(vec3 ray) {
	float radius = BODY_RADIUS + cloud_height_km - cloud_thickness_km * 0.5 + cloud_thickness_km * cloud_deck_fraction * 0.5;
	float r = length(camera_planet_km);
	float b = dot(camera_planet_km, ray);
	float c = (r - radius) * (r + radius);
	float h = b * b - c;
	if (h < 0.0) { return 0.0; }
	return max(c > 0.0 ? -b - sqrt(h) : -b + sqrt(h), 0.0);
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(pixel, ivec2(frame_size)))) { return; }
	ivec2 cell = pixel / int(frame_grid);
	vec4 result;
	float depth;
	// Marched this frame, or reprojected from a pixel that was.
	bool exact = false;
	ivec2 reveal_cell = ivec2(floor(vec2(pixel - ivec2(reveal_offset)) / 2.0));
	float revealed_depth;
	vec4 revealed = reveal_at(reveal_cell, revealed_depth);
	if (pixel - cell * int(frame_grid) == ivec2(frame_offset)) {
		result = fresh_at(cell);
		depth = fresh_depth_at(cell);
		exact = true;
	} else if (reveal_cell * 2 + ivec2(reveal_offset) == pixel && revealed.a >= 0.0) {
		result = revealed;
		depth = revealed_depth;
		exact = true;
	} else {
		// Without exact history, the reveal samples (2 pixels apart) fill
		// better than the march's (frame_grid apart).
		vec4 filled;
		float filled_depth;
		bool have_reveal = reveal_fill(vec2(pixel) + 0.5, filled, filled_depth);
		result = fresh_fill(vec2(pixel) + 0.5, depth);
		if (have_reveal) {
			result = filled;
			depth = filled_depth > 0.0 ? filled_depth : depth;
		}
		if (history_valid) {
			vec3 ray = frame_ray(vec2(pixel));
			vec3 carried = cloud_motion * ray;
			// Where the cloud this pixel shows sat in the previous frame: carried
			// with the planet's spin and the wind, then seen from the previous
			// camera. Start from the nearest fresh sample's distance; clear
			// pixels use the deck's, and rays that miss it are far away.
			float reach = depth > 0.0 ? depth : deck_distance(ray);
			vec3 seen = reach > 0.0 ? carried * reach + camera_offset_km : carried;
			vec2 previous = previous_pixel(normalize(seen));
			// History there recorded the distance of the cloud it showed. The
			// clouds are translucent volumes, so it is the same cloud: refine
			// this pixel's distance from it and reproject again.
			for (int i = 0; i < 2; i++) {
				if (any(lessThan(previous, vec2(0.0))) || any(greaterThanEqual(previous, frame_size))) { break; }
				float was = history_distance(imageLoad(history_depth, ivec2(previous)).r);
				if (was <= 0.0) { break; }
				// Solve |carried * d + camera_offset_km| = was for d.
				float b = dot(carried, camera_offset_km);
				float h = b * b - dot(camera_offset_km, camera_offset_km) + was * was;
				if (h < 0.0) { break; }
				depth = max(-b + sqrt(h), 0.001);
				previous = previous_pixel(normalize(carried * depth + camera_offset_km));
			}
			bool history_exact = on_screen(previous) && imageLoad(history_depth, ivec2(previous)).r >= 0.0;
			// History that was itself filled in yields to fresher reveal samples.
			if (on_screen(previous) && (history_exact || !have_reveal)) {
				vec4 reprojected = history_bicubic(previous);
				exact = history_exact;
				// Clamp to the fresh samples around this block, so changed
				// clouds cannot leave trails. A still view keeps some slack so
				// detail finer than the fresh grid survives; moving changes haze
				// and lighting along every view ray, so motion tightens it.
				vec4 low = vec4(1e9);
				vec4 high = vec4(-1e9);
				for (int y = -1; y <= 1; y++) {
					for (int x = -1; x <= 1; x++) {
						vec4 near = encode(fresh_at(cell + ivec2(x, y)));
						low = min(low, near);
						high = max(high, near);
					}
				}
				float moving = smoothstep(0.25, 1.0, length(previous - previous_pixel(carried)));
				float slack = history_tolerance * (1.0 - moving);
				vec4 encoded = encode(reprojected);
				vec4 clamped = clamp(encoded, low - slack, high + slack);
				// While moving, history the clamp had to pull far is stale:
				// mixing it with exact fresh pixels would show the sampling
				// grid, so lean on the smooth fill of fresh samples. A still
				// camera under changing sunlight keeps the clamped history.
				float stale = smoothstep(0.03, 0.12, length(clamped - encoded)) * moving;
				result = mix(decode(clamped), result, stale);
				// Mostly filled in now: let the reveal pass march it again.
				exact = exact && stale < 0.5;
			}
		}
	}
	if (result.a < 0.005) { result = vec4(0.0); depth = 0.0; }
	imageStore(out_color, pixel, result);
	imageStore(out_depth, pixel, vec4(stored_distance(depth, exact)));
}
#endif
