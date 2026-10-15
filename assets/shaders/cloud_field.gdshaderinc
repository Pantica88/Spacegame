// The cloud field: where cloud is, how dense, and how it is lit.
//
// Shared word for word by three consumers, so it is written in the subset of
// GLSL that both Godot's shading language and Vulkan GLSL accept:
//   - cloud_render_pass.gd prepends it to the half-resolution compute march
//     (with CLOUD_COMPUTE defined; the uniforms then live in a UBO);
//   - ocean.gdshader includes it to mirror the clouds in the water;
//   - cloud_field.gd ports it to GDScript for vessel lighting. Keep the two
//     in step: tests/test_clouds.gd compares them.
//
// Everything is in kilometres in the cloud frame: planet-centred, rotated
// with the planet and the wind drift, so the weather map and the noise are
// fixed in it. The weather map holds formation weights per direction:
// R cumulus, G stratocumulus, B stratus/overcast (light paint makes veils),
// A storms and mushroom clouds. Weights are data, never colours.

#ifndef CLOUD_COMPUTE
uniform sampler3D cloud_shape_noise : filter_linear_mipmap, repeat_enable;
uniform sampler3D cloud_detail_noise : filter_linear, repeat_enable;
uniform sampler2D cloud_weather_map : filter_linear, repeat_enable;
// Radii: ground (sea level), cloud base, top of the low formations, top of storms.
uniform vec4 cloud_radii = vec4(600.0, 601.8, 604.0, 613.5);
// Procedural coverage, density scale, 1 for a painted map, 1 if it has storms.
uniform vec4 cloud_params = vec4(0.56, 1.0, 0.0, 0.0);
// Noise offset (km) as the billows evolve; w unused.
uniform vec4 cloud_evolution = vec4(0.0);
// Sun direction in the cloud frame; w unused.
uniform vec4 cloud_sun = vec4(0.0, 1.0, 0.0, 0.0);
// Body radius, top of the air (km), air density scale, unused.
uniform vec4 cloud_air = vec4(600.0, 690.0, 1.0, 0.0);
#endif

const float CLOUD_PI = 3.14159265359;
// Repeat lengths of the noise volumes (assets/clouds, tools/build_cloud_noise.py).
const float CLOUD_SHAPE_KM = 14.0;
const float CLOUD_STORM_KM = 9.0;
const float CLOUD_DETAIL_KM = 1.8;
// Procedural weather samples the shape volume's broad channels at this scale.
const float CLOUD_WEATHER_KM = 1100.0;
// Scale of the patches that vary painted weather.
const float CLOUD_PATCH_KM = 61.0;
// Extinction per kilometre of fully dense cloud at density scale 1.
const float CLOUD_EXTINCTION = 26.0;
// Storm paint up to this weight makes no cloud (the storm rule fades in
// above it), so the faint margins of storm stamps are skipped entirely.
const float CLOUD_STORM_MIN = 0.16;

// Distances along a ray to the near and far crossings of a planet-centred
// sphere; (1, -1) when it misses.
vec2 cloud_sphere_hits(vec3 origin, vec3 ray, float radius) {
	float b = dot(origin, ray);
	float c = dot(origin, origin) - radius * radius;
	float h = b * b - c;
	if (h < 0.0) { return vec2(1.0, -1.0); }
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

// A smooth offset (km) that bends the noise volumes, so their repeat
// never lines up into a visible grid across a planet.
vec3 cloud_warp(vec3 p) {
	return vec3(sin(p.y * 0.083 + p.z * 0.047), sin(p.z * 0.071 + p.x * 0.059), sin(p.x * 0.067 + p.y * 0.091)) * 3.5;
}

// Formation weights above a point. Painted weights vary by up to a fifth
// over tens of kilometres, so a broad stamp still breaks into denser and
// thinner patches.
vec4 cloud_weather(vec3 p) {
	vec3 dir = normalize(p);
	if (cloud_params.z > 0.5) {
		vec2 size = vec2(textureSize(cloud_weather_map, 0));
		float u = atan(dir.z, dir.x) / (2.0 * CLOUD_PI) + 0.5;
		float v = acos(clamp(dir.y, -1.0, 1.0)) / CLOUD_PI;
		// Longitude repeats; latitude stops at the polar rows.
		v = clamp(v, 0.5 / size.y, 1.0 - 0.5 / size.y);
		float patches = textureLod(cloud_shape_noise, dir * (cloud_radii.y / CLOUD_PATCH_KM) + vec3(0.37, 0.11, 0.73), 0.0).b;
		return textureLod(cloud_weather_map, vec2(u, v), 0.0) * mix(0.78, 1.2, patches);
	}
	// Procedural weather: broad patches of cumulus and stratocumulus.
	vec4 broad = textureLod(cloud_shape_noise, dir * (cloud_radii.y / CLOUD_WEATHER_KM) + cloud_evolution.xyz * 0.002, 0.0);
	float coverage = cloud_params.x;
	float amount = smoothstep(0.80 - coverage * 0.75, 1.05 - coverage * 0.75, broad.b);
	float layered = smoothstep(0.40, 0.62, broad.a);
	return vec4(amount * (1.0 - layered) * 0.85, amount * layered * 0.8, 0.0, 0.0);
}

// Density before fine erosion (x), lighting height from the formation's base
// to its top (y), erosion strength (z) and the shape volume's lumps (w).
// r is length(p); w the weather above p. lod picks the shape volume's mip
// for a ray's footprint: far away, cells smaller than a pixel blur into
// their average and the formation edges soften to keep the same coverage.
vec4 cloud_coarse(vec3 p, float r, vec4 w, float lod) {
	float base = cloud_radii.y;
	float hs = (r - base) / (cloud_radii.w - base);
	if (hs <= 0.0 || hs >= 1.0) { return vec4(0.0); }
	float hl = (r - base) / (cloud_radii.z - base);
	bool low = hl < 1.0 && w.r + w.g + w.b > 0.0;
	bool storm = w.a > CLOUD_STORM_MIN;
	if (!low && !storm) { return vec4(0.0); }
	// The shape varies more slowly with height than across, so cells
	// stand as columns: a gap seen from above goes right through the layer.
	vec3 q = p - (p / r) * ((r - base) * 0.45);
	vec4 n = textureLod(cloud_shape_noise, (q + cloud_warp(q) + cloud_evolution.xyz) / CLOUD_SHAPE_KM, lod);
	float soft = lod * 0.06;
	float density = 0.0;
	float lit = 0.0;
	float erode = 0.0;
	if (low) {
		if (w.r > 0.0) {
			// Cumulus: separate heaps on a flat base. Each heap rises highest
			// where the noise peaks inside its footprint, so its crown is a
			// dome; the soft interior leaves erosion room to carve billows.
			float cover = pow(min(w.r, 1.0), 0.7) * 0.66;
			float excess = clamp((n.r - 1.0 + cover) / max(cover, 0.05), 0.0, 1.0);
			float top = mix(0.4, 1.0, clamp(n.b * 1.6 - 0.3, 0.0, 1.0)) * mix(0.7, 1.0, w.r);
			float crown = top * sqrt(excess);
			float d = smoothstep(0.0, 0.3 + soft, excess) * smoothstep(0.0, 0.05, hl)
				* (1.0 - smoothstep(crown * 0.6, crown, hl));
			density += d;
			lit += d * clamp(hl / max(crown, 0.05), 0.0, 1.0);
			erode += d * 0.8;
		}
		if (w.g > 0.0) {
			// Stratocumulus: a layer of joined cells, each domed to its own
			// height, with seams and holes between them.
			float top = (0.36 + 0.16 * n.b) * mix(0.6, 1.0, n.g);
			float profile = smoothstep(0.02, 0.1, hl) * (1.0 - smoothstep(top - 0.12, top, hl));
			// Even full paint leaves seams; overcast is the closed deck.
			float cover = min(w.g, 1.0) * 0.72;
			float cells = mix(n.r, n.g, 0.6);
			float d = smoothstep(1.0 - cover - soft, 1.24 - cover + soft, cells) * profile;
			density += d;
			lit += d * clamp(hl / top, 0.0, 1.0);
			erode += d * 0.65;
		}
		if (w.b > 0.0) {
			// Stratus: a continuous sheet. Light paint leaves a thin veil.
			float top = 0.3 + 0.1 * n.b;
			float profile = smoothstep(0.0, 0.08, hl) * (1.0 - smoothstep(top - 0.14, top, hl));
			float d = clamp(w.b * 1.45 - 0.12 + (n.r - 0.55) * 0.5, 0.0, 1.0) * profile;
			density += d;
			lit += d * clamp(hl / top, 0.0, 1.0);
			erode += d * 0.12;
		}
	}
	if (storm) {
		// Storms and mushroom clouds from one rule: below the cap only heavy
		// paint rises as a column; in the cap band light paint spreads too.
		// The band lies lower and reaches higher where paint is heavy, so a
		// round stamp grows a domed cap over a narrow stem.
		// Towers billow alike in every direction: their own, unstretched
		// lookup at a finer scale than the layer cells.
		vec4 b = textureLod(cloud_shape_noise, (p + cloud_warp(p) + cloud_evolution.xyz) / CLOUD_STORM_KM, lod);
		float contour = clamp((b.r - 0.5) * 0.22 + (b.g - 0.5) * 0.12, -0.08, 0.08);
		float cap_low = mix(0.70, 0.58, w.a);
		float cap_high = mix(0.80, 0.97, w.a) + (n.b - 0.5) * 0.04;
		float cap = smoothstep(cap_low - 0.05, cap_low + 0.05, hs);
		float need = mix(0.60, 0.22, cap) - contour;
		float d = smoothstep(need - 0.05, need + 0.05, w.a) * smoothstep(CLOUD_STORM_MIN, CLOUD_STORM_MIN + 0.08, w.a)
			* smoothstep(0.0, 0.02, hs) * (1.0 - smoothstep(cap_high - 0.08, cap_high, hs))
			* (0.75 + 0.45 * b.g);
		density += d;
		lit += d * clamp(hs / cap_high, 0.0, 1.0);
		erode += d * 0.5;
	}
	if (density <= 0.0) { return vec4(0.0); }
	return vec4(min(density, 1.0), lit / density, erode / density, n.g);
}

// Full density: coarse shape eroded by the detail volume. detail fades the
// erosion out (0 none, 1 full) where its billows are too small to resolve.
float cloud_density(vec3 p, vec4 w, float detail, float lod, out float light_height) {
	vec4 c = cloud_coarse(p, length(p), w, lod);
	light_height = c.y;
	if (c.x <= 0.0) { return 0.0; }
	if (detail <= 0.0) { return c.x; }
	vec4 fine = textureLod(cloud_detail_noise, (p + cloud_evolution.xyz * 2.5) / CLOUD_DETAIL_KM, 0.0);
	// A second, three times finer octave crisps the billows up close.
	float finer = textureLod(cloud_detail_noise, (p + cloud_evolution.xyz * 4.0) / (CLOUD_DETAIL_KM * 0.33), 0.0).g;
	float fbm = fine.r * 0.5 + fine.g * 0.3 + finer * 0.2;
	// Wispy, torn bases; billowing tops.
	float billow = mix(1.0 - fbm, fbm, clamp(c.y * 3.0, 0.0, 1.0));
	float e = c.z * detail * billow;
	return clamp((c.x - e) / max(1.0 - e, 0.05), 0.0, 1.0);
}

// Coarse optical depth (density x km) from p toward the sun. Taps triple in
// distance, the last a couple of kilometres up a storm tower; jitter in
// [0, 1) varies their spacing between frames.
float cloud_sun_depth(vec3 p, vec4 w, vec3 sun, float jitter, float lod) {
	float total = 0.0;
	float previous = 0.0;
	float reach = 0.07;
	for (int i = 0; i < 4; i++) {
		float t = reach * (0.75 + 0.5 * jitter);
		vec3 q = p + sun * t;
		total += cloud_coarse(q, length(q), w, lod).x * (t - previous);
		previous = t;
		reach *= 3.0;
	}
	return total;
}

// Henyey-Greenstein, scaled so an isotropic medium scatters 1.
float cloud_hg(float cosine, float g) {
	return (1.0 - g * g) / pow(max(1.0 + g * g - 2.0 * g * cosine, 1e-4), 1.5);
}

// Light scattered toward the eye per unit of extinction. Octaves of weaker,
// broader, less attenuated scattering stand in for multiple scattering, so
// thick cloud stays white inside instead of turning black.
vec3 cloud_scatter(float sun_depth, float cosine, vec3 sunlight, vec3 ambient, float light_height, float density) {
	float tau = sun_depth * CLOUD_EXTINCTION * cloud_params.y;
	float direct = 0.0;
	float a = 1.0;
	float b = 1.0;
	float g = 1.0;
	for (int i = 0; i < 3; i++) {
		float phase = mix(cloud_hg(cosine, -0.2 * g), cloud_hg(cosine, 0.7 * g), 0.55);
		direct += a * exp(-tau * b) * phase;
		a *= 0.45;
		b *= 0.45;
		g *= 0.5;
	}
	// Thin edges facing the sun scatter less back toward it (powder).
	float powder = mix(1.0, 1.0 - exp(-density * 8.0), 0.5 * (1.0 - cosine) * 0.5);
	return sunlight * direct * 0.42 * powder + ambient * mix(0.35, 1.0, light_height);
}

// Sunlight reaching p: the planet's shadow and the reddening of a long path
// through the air, relative to the noon sun at sea level.
vec3 cloud_sunlight(vec3 p) {
	vec3 sun = cloud_sun.xyz;
	float r = length(p);
	float ground = cloud_air.x;
	float horizon = -sqrt(max(0.0, 1.0 - ground * ground / (r * r)));
	float elevation = dot(p / r, sun) - horizon;
	float daylight = smoothstep(-0.012, 0.025, elevation);
	if (daylight <= 0.0) { return vec3(0.0); }
	float air_height = max(cloud_air.y - ground, 0.001);
	float path = max(cloud_sphere_hits(p, sun, cloud_air.y).y, 0.0);
	vec2 depth = vec2(0.0);
	for (int i = 0; i < 6; i++) {
		float u = (float(i) + 0.5) / 6.0;
		vec3 q = p + sun * (u * u * path);
		float h = max(length(q) - ground, 0.0);
		vec2 air = vec2(exp(-h / (air_height * 0.32)), exp(-h / (air_height * 0.09)));
		depth += air * path * (2.0 * float(i) + 1.0) / 36.0;
	}
	// A noon path from sea level is the white point.
	depth -= vec2(0.32, 0.09) * air_height;
	vec3 tau = (vec3(0.014, 0.035, 0.085) * depth.x + vec3(0.009) * depth.y) * cloud_air.z;
	// Low sun warms toward orange and rose, as the sky's own sunset does.
	float sunset = 1.0 - smoothstep(0.0, 0.25, elevation);
	vec3 tint = mix(vec3(1.0), vec3(1.3, 0.62, 0.36), sunset);
	return exp(-max(tau, vec3(0.0)) * 0.3) * tint * daylight;
}

// Skylight on a cloud, from its own sunlight: blue by day, warm at sunset,
// and a faint blue-grey at night so the deck never vanishes.
vec3 cloud_ambient(vec3 p, vec3 sunlight) {
	float elevation = dot(normalize(p), cloud_sun.xyz);
	vec3 sky = mix(vec3(0.62, 0.42, 0.36), vec3(0.36, 0.48, 0.70), smoothstep(-0.02, 0.3, elevation));
	float day = smoothstep(-0.18, 0.2, elevation);
	return vec3(0.004, 0.006, 0.011) + sky * day * 0.34 * mix(0.55, 1.0, dot(sunlight, vec3(0.333)));
}

// Cloud seen along a mirrored ray from the water, for the ocean: light
// (not premultiplied) and opacity. Four coarse samples up through the low
// formations and one at storm-cap height; light from each sample's height.
vec4 cloud_mirror(vec3 origin, vec3 ray) {
	float start = cloud_sphere_hits(origin, ray, cloud_radii.y).y;
	if (start <= 0.0) { return vec4(0.0); }
	float low_end = cloud_sphere_hits(origin, ray, cloud_radii.z).y;
	float span = min(low_end - start, 10.0);
	vec3 sunlight = cloud_sunlight(origin + ray * start);
	vec3 ambient = cloud_ambient(origin, sunlight);
	float cosine = dot(ray, cloud_sun.xyz);
	vec3 color = vec3(0.0);
	float remaining = 1.0;
	for (int i = 0; i < 5; i++) {
		vec3 q;
		float length_km;
		if (i < 4) {
			q = origin + ray * (start + span * (float(i) + 0.5) / 4.0);
			length_km = span / 4.0;
		} else {
			if (cloud_params.w < 0.5) { break; }
			float cap_radius = mix(cloud_radii.y, cloud_radii.w, 0.8);
			q = origin + ray * cloud_sphere_hits(origin, ray, cap_radius).y;
			length_km = min((cloud_radii.w - cloud_radii.y) * 0.2 / max(dot(ray, normalize(q)), 0.15), 8.0);
		}
		vec4 c = cloud_coarse(q, length(q), cloud_weather(q), 1.0);
		if (c.x <= 0.0) { continue; }
		float opacity = 1.0 - exp(-c.x * CLOUD_EXTINCTION * cloud_params.y * length_km);
		// The cloud above a sample shades it in proportion to its depth below the top.
		float above = (1.0 - c.y) * c.x * 1.2;
		color += cloud_scatter(above, cosine, sunlight, ambient, c.y, c.x) * remaining * opacity;
		remaining *= 1.0 - opacity;
	}
	float alpha = 1.0 - remaining;
	return alpha < 0.004 ? vec4(0.0) : vec4(color / alpha, alpha);
}
