shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/clouds_volume.gdshaderinc"

uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
// Reduced-resolution volume: encoded color in RGB, unmultiplied, opacity in A.
uniform sampler2D cloud_lowres : filter_nearest, repeat_disable;
uniform bool lowres_enabled = false;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Opacity-weighted bilinear upsampling: empty texels carry no color, so the
// soft cloud edges do not darken or bleed into clear sky.
vec4 upsample_clouds(vec2 uv) {
	ivec2 size = textureSize(cloud_lowres, 0);
	vec2 position = uv * vec2(size) - 0.5;
	vec2 base = floor(position);
	vec2 f = position - base;
	vec3 color = vec3(0.0);
	float alpha = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 offset = ivec2(i & 1, i >> 1);
		ivec2 texel = clamp(ivec2(base) + offset, ivec2(0), size - 1);
		vec4 encoded = texelFetch(cloud_lowres, texel, 0);
		vec2 w2 = mix(1.0 - f, f, vec2(offset));
		float weight = w2.x * w2.y * encoded.a;
		color += pow(encoded.rgb, vec3(2.2)) * weight;
		alpha += weight;
	}
	return vec4(color * CLOUD_ENCODE_RANGE / max(alpha, 1e-5), alpha);
}

// Distance to the scene for a depth sample at uv, or 1e20 where the depth
// buffer is not used. Depth is sampled in fragment(): the Compatibility
// renderer only exposes the depth texture there.
float scene_clip(float depth, vec2 uv, mat4 inv_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0);
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 scene = inv_projection * vec4(ndc, 1.0);
	float scene_distance = length(scene.xyz / scene.w) * 0.001;
	// Use the depth buffer for nearby craft and terrain only. A close vessel
	// camera needs a small near plane while the planet is millions of metres
	// away; reconstructed orbital depth then varies enough between pixels to
	// cut random holes in the cloud deck. The analytic ground intersection
	// above already clips distant clouds against the planet.
	return scene_distance < 100.0 ? scene_distance : 1e20;
}

bool clouds_beyond(vec4 segments, float clip) {
	return clip >= segments.y || (segments.w >= segments.y && clip >= segments.z);
}

vec4 shade_clouds(vec3 ray, vec4 segments, float clip, vec2 uv, vec2 frag, bool lowres_safe) {
	if (clip <= segments.x) { return vec4(0.0); }
	// The reduced pass ignores scene depth. It is exact wherever geometry lies
	// beyond every cloud segment; only pixels whose geometry sits inside the
	// shell (a craft flying through cloud) integrate here at full resolution.
	// Open-sky pixels have nothing for the reduced pass to bleed onto, so they
	// always upsample. A full-resolution march along the horizon and tower
	// silhouettes cost several milliseconds at ground level.
	if (lowres_enabled && (lowres_safe || clip >= 1e19) && clouds_beyond(segments, clip)) {
		// Opacity changes inside a cloud bank stay on the reduced-resolution
		// path. Raymarching those edges here duplicates the volume pass over
		// large orbital views; geometric silhouettes are guarded by lowres_safe.
		return upsample_clouds(uv);
	}
	return integrate_clouds(ray, clip, frag);
}

void fragment() {
	vec3 ray = cloud_view_ray(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	vec4 segments = cloud_ray_segments(ray);
	if (segments.y <= segments.x) { discard; }

	float clip = scene_clip(texture(scene_depth, SCREEN_UV).r, SCREEN_UV, INV_PROJECTION_MATRIX);
	// The depth buffer holds one sample per pixel, so a binary clip leaves
	// stair steps along terrain silhouettes that MSAA has already smoothed.
	// Where neighbours disagree on terrain versus open sky, blend the two
	// results by the share of open sky around this pixel.
	vec2 texel = 1.0 / vec2(textureSize(scene_depth, 0));
	float open = 0.0;
	float near_clip = clip < 1e19 ? clip : 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 offset = vec2(float((i & 1) * 2 - 1), float((i >> 1) * 2 - 1)) * texel;
		float neighbour = scene_clip(texture(scene_depth, SCREEN_UV + offset).r, SCREEN_UV + offset, INV_PROJECTION_MATRIX);
		if (neighbour >= 1e19) { open += 0.25; } else { near_clip = max(near_clip, neighbour); }
	}
	open = clip >= 1e19 ? 0.5 + open * 0.5 : open * 0.5;
	// The reduced pass ignores terrain, so its texels beside a pixel that does
	// integrate here carry cloud from rays that run on past the hills. Bilinear
	// upsampling would bleed that onto terrain as dashes below the horizon.
	bool lowres_safe = true;
	if (lowres_enabled) {
		vec2 lowres_texel = 1.0 / vec2(textureSize(cloud_lowres, 0));
		// Authored decks fill only the lower part of the shell, so their horizon
		// sits below the shell limb; guard that silhouette too.
		float deck_radius = cloud_bottom_km() + cloud_thickness_km * cloud_deck_fraction;
		vec2 deck = sphere_interval(camera_planet_km, ray, deck_radius);
		bool deck_hit = deck.y > deck.x && deck.y > 0.0;
		for (int i = 0; i < 4; i++) {
			vec2 offset = vec2(float((i & 1) * 2 - 1), float((i >> 1) * 2 - 1)) * lowres_texel;
			vec2 uv = SCREEN_UV + offset;
			vec3 near_ray = cloud_view_ray(uv, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
			vec2 near_deck = sphere_interval(camera_planet_km, near_ray, deck_radius);
			if ((near_deck.y > near_deck.x && near_deck.y > 0.0) != deck_hit) { lowres_safe = false; }
			vec4 near_segments = cloud_ray_segments(near_ray);
			// A neighbour past the shell limb marks the deck's silhouette against
			// space; upsampling there would show reduced-resolution stair steps.
			if (near_segments.y <= near_segments.x) { lowres_safe = false; continue; }
			float near = scene_clip(texture(scene_depth, uv).r, uv, INV_PROJECTION_MATRIX);
			if (!clouds_beyond(near_segments, near)) { lowres_safe = false; }
		}
	}
	// Silhouette pixels blend an open-sky pass (0) with a ground pass (1).
	bool blend = open > 0.0 && open < 1.0;
	vec2 clips = blend ? vec2(1e20, near_clip) : vec2(clip);
	// One call site: inlining the march twice costs every pixel, not only the
	// silhouette pixels that take this branch.
	vec4 shaded[2];
	for (int i = 0; i < 2; i++) {
		if (i == 1 && !blend) { break; }
		shaded[i] = shade_clouds(ray, segments, clips[i], SCREEN_UV, FRAGCOORD.xy, lowres_safe);
	}
	vec4 result = blend ? mix(shaded[1], shaded[0], open) : shaded[0];
	if (result.a < 0.005) { discard; }
	ALBEDO = result.rgb;
	ALPHA = result.a;
}
