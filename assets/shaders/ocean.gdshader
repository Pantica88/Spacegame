shader_type spatial;
// StayAtHomeDev "infinite ocean" water shader, ported to a planet:
// https://stayathomedev.com/tutorials/general-tutorials/infinite-ocean
// Uniforms, textures, wave displacement, fresnel albedo, Beer's-law depth
// colour, screen refraction, edge foam, normal maps and specular follow the
// tutorial. Planet adaptations:
//  - world_pos.xz becomes wave_pos, metres in a planet-fixed tangent frame;
//    the grid is wrapped onto the sphere and reaches past the horizon.
//  - The tutorial's per-tile seam stitching is omitted: this is one mesh.
//  - Displacement is centred on sea level (mean zero) for splashdown.
//  - Distant water receives the same atmosphere as the terrain.
//  - The terrain draws a seabed below this surface (terrain.gdshader).
render_mode blend_mix, cull_disabled, depth_draw_always;
// Includes atmosphere.gdshaderinc; cloud_layer.gd mirrors its uniforms here.
#include "res://assets/shaders/clouds_volume.gdshaderinc"
#include "res://assets/shaders/water.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.0, 0.04, 0.10);
uniform vec3 albedo2 : source_color = vec3(0.0, 0.08, 0.18);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;
uniform sampler2D wave : filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_bump : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_normal2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec2 wave_direction = vec2(0.5, -0.2);
uniform vec2 wave_direction2 = vec2(-0.5, 0.5);
uniform float time_scale : hint_range(0.0, 0.2, 0.005) = 0.1;
uniform float noise_scale = 20.0;
uniform float height_scale = 2.0;
uniform vec3 color_deep : source_color = vec3(0.005, 0.025, 0.06);
uniform vec3 color_shallow : source_color = vec3(0.0, 0.08, 0.18);
uniform float beers_law = 2.0;
uniform float depth_offset = 1.5;
uniform float edge_scale = 0.3;
uniform vec3 edge_color : source_color = vec3(1.0, 1.0, 1.0);
// The vessel hull (segment and radius, world space). The edge foam marks a
// shallow depth difference, which a floating hull also makes; without this
// it painted a pale band over the hull's submerged part.
uniform vec3 hull_a;
uniform vec3 hull_b;
uniform float hull_radius = 0.0;
uniform vec3 ocean_pos;
// Set by ocean_patch.gd so floating craft can sample the same surface.
uniform float wave_time = 0.0;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// Planet placement (ocean_patch.gd).
uniform float planet_radius = 600000.0;
uniform float patch_extent = 8000.0;
// Keep the inner grid dense as the horizon expands at altitude.
uniform float base_extent = 8000.0;
uniform float dense_radius = 250.0;
uniform vec3 anchor_world;
uniform vec3 axis_u = vec3(1.0, 0.0, 0.0);
uniform vec3 axis_v = vec3(0.0, 0.0, 1.0);
uniform vec3 planet_center_world;
// Cross-fades with the terrain's own water when climbing out of range.
uniform float fade = 1.0;
// Base ring cell size; the vertex shader accounts for outer-grid stretching.
uniform float first_cell = 0.25;
uniform float ring_growth = 0.0165;
// Swell: the tutorial's wave texture again at larger, rotated scales, so a
// 20 m texture never reads as a repeating tile. Wavelengths in metres.
uniform vec4 swell_scales = vec4(97.0, 311.0, 1130.0, 3700.0);
uniform vec4 swell_heights = vec4(0.25, 0.45, 0.65, 0.8);
// Swell uses its own smooth (non-ridged) noise, so large waves are rounded
// rather than scaled-up copies of the tutorial's ridged ripples.
uniform sampler2D swell_noise : filter_linear_mipmap, repeat_enable;
uniform float swell_size = 1024.0;
// The swell texture holds this many times more waves per side than one
// octave's scale, and one tile spans that many scales. With only a few waves
// per tile, the 97 m octave repeated as a lattice: converging lines or a grid
// of blobs, depending on the view direction.
uniform float swell_repeat = 4.0;
// Optional swell slope boost for distant views.
uniform float swell_slope_boost = 1.0;
// Sea state varies by region (km scale), so no layer repeats evenly.
uniform float sea_state_scale = 5200.0;
// Planet water coverage (0.5 coast, 1.0 open sea): swell shoals near shore.
uniform sampler2D baked_surface : filter_linear_mipmap, repeat_enable;
uniform mat3 body_from_world;
// Must match terrain.gdshader's seabed: depth below sea level by coverage.
uniform float seabed_shallow_m = 2.5;
uniform float seabed_depth_m = 70.0;
// The graded launch complex sits at sea level; keep its ground dry. The planet
// map is far coarser than the pad, so the zone is tested analytically.
uniform vec3 launch_direction_body = vec3(0.0, 0.0, 1.0);
uniform float launch_dry_radius = 0.0;
// Cloud reflections sample the cloud volume where the mirrored ray meets the
// deck base, so they hold at any view angle. cloud_layer.gd sets the volume
// uniforms and turns this off while the clouds are hidden.
uniform bool cloud_reflection_enabled = false;
uniform float cloud_reflection_strength = 1.0;
// Art controls for mirrored clouds: brightness scales their light; density
// thickens them (1 - (1 - opacity)^density), so banks read solid over sky.
uniform float cloud_reflection_brightness = 1.0;
uniform float cloud_reflection_density = 4.0;
// TEMPORARY A/B (hover preview J): mirrored cloud sun shadow.
// 0 current 0.5 km cap, 1 sky's column filled with the base density,
// 2 sky's column with one tap toward the sun (one more volume read),
// 3 sky's column, sampled through the whole deck and storm caps (mirrored_deck).
// 0 current, 1 sky column, 2 sky tap, 3 full deck (default, chosen by the owner 2026-10-09).
uniform int cloud_reflection_shading = 3;
// The real sky, mirrored behind the clouds. It stands in for the environment
// reflection, whose cubemap is a fixed gradient (sky.gdshader's cubemap pass).
uniform float sky_reflection_strength = 1.0;
uniform int sky_view_samples = 6;

varying float wave_height;
varying vec3 world_pos;
varying vec2 wave_pos;
varying float vertex_distance;
varying float vertex_distance_clamped;
varying float cell_size;
// Atmosphere along the view ray to this vertex. Seen from altitude, most
// ocean pixels are tens of kilometres away and take the full sample count;
// the result varies smoothly across a cell, so shade it per vertex.
varying vec3 air_light;
varying vec3 air_transmission;
// Sky light along the mirror of the swell-free surface. It changes slowly
// across the view, so it is integrated per vertex like the air above.
varying vec3 sky_light;
// Air between the water and the cloud base along the same mirror. The sky's
// clouds are seen through haze (integrate_clouds); without it their mirror
// image kept the raw cloud colour, white under a tinted sky.
varying vec3 cloud_air_light;
varying vec3 cloud_air_transmission;

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

// The tutorial linearises depth with hand-set near/far planes. This camera's
// planes span 0.5 m to over 1000 km, so use the exact inverse projection.
float linear_depth(float raw, vec2 screen_uv, mat4 inv_projection) {
	vec4 view = inv_projection * vec4(screen_uv * 2.0 - 1.0, raw * 2.0 - 1.0, 1.0);
	return -view.z / view.w;
}

mat2 rotation(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// One swell octave: the swell texture rotated, scaled and drifting.
vec2 swell_uv(vec2 p, int octave) {
	float scale = swell_scales[octave] * swell_repeat;
	vec2 dir = rotation(0.9 + float(octave) * 2.1) * normalize(wave_direction);
	return rotation(0.7 + float(octave) * 1.9) * p / scale + dir * wave_time * time_scale * (8.0 / scale);
}

// Regional strength of one layer, 0.15..1.6, from the swell texture sampled
// at kilometre scale. Each layer gets its own pattern, so calm and rough
// patches differ per wavelength and the repeat of any one layer is broken.
float sea_state(vec2 p, int layer) {
	float a = 1.3 + float(layer) * 2.4;
	float n = textureLod(swell_noise, rotation(a) * p / (sea_state_scale * swell_repeat * (1.0 + 0.37 * float(layer))) + vec2(0.31, 0.17) * float(layer), 0.0).r;
	float m = textureLod(swell_noise, rotation(-a) * p / (sea_state_scale * swell_repeat * 2.9), 0.0).r;
	return mix(0.35, 1.1, smoothstep(0.2, 0.8, n * 0.65 + m * 0.35));
}

// Swell wave_height gradient (metres per metre) by central differences, filtered
// to the pixel footprint.
vec2 swell_gradient(vec2 p, int octave, float footprint) {
	float scale = swell_scales[octave] * swell_repeat;
	float lod = log2(max(footprint * swell_size / scale, 1.0));
	vec2 uv = swell_uv(p, octave);
	float e = exp2(lod) / swell_size;
	float dx = textureLod(swell_noise, uv + vec2(e, 0.0), lod).r - textureLod(swell_noise, uv - vec2(e, 0.0), lod).r;
	float dy = textureLod(swell_noise, uv + vec2(0.0, e), lod).r - textureLod(swell_noise, uv - vec2(0.0, e), lod).r;
	vec2 grad_uv = vec2(dx, dy) / (2.0 * e) * 2.0 * swell_heights[octave];
	return rotation(-(0.7 + float(octave) * 1.9)) * grad_uv / scale;
}

// Each octave fades once it is too short for the local grid or pixel size.
float octave_weight(float scale, float resolution) {
	return smoothstep(4.0 * resolution, 10.0 * resolution, scale);
}

// The ripple textures repeat every 10-20 m and, sharing one orientation,
// line up with each other, so open water read as one copy-pasted tile. Each
// layer is turned to its own angle, and each region samples it at a random
// offset, blended across a slowly varying noise index (Quilez, "texture
// repetition", technique 3). p: wave_pos; drift: the layer's motion in tiles;
// tile: its repeat in metres; p_dx/p_dy: wave_pos derivatives, unshifted,
// because the offsets jump between regions and must not pick mips.
vec3 untiled(sampler2D tex, vec2 p, vec2 p_dx, vec2 p_dy, vec2 drift, float tile, int layer) {
	mat2 turn = rotation(float(layer) * 2.4);
	// Turning drift too keeps each layer's world-space motion unchanged.
	vec2 uv = turn * (p / tile + drift);
	vec2 uv_dx = turn * p_dx / tile;
	vec2 uv_dy = turn * p_dy / tile;
	// The swell texture's features span a tenth of it, so a region runs a
	// tile or two before its offset changes.
	float a = 0.37 + float(layer) * 1.7;
	float variation = textureLod(swell_noise, rotation(a) * p / (tile * (97.0 + 23.0 * float(layer))) + vec2(0.13, 0.41) * float(layer), 0.0).r;
	float index = variation * 8.0;
	float i = floor(index);
	vec2 seed = vec2(3.0, 7.0) + float(layer) * vec2(1.3, 0.7);
	vec3 first = textureGrad(tex, uv + sin(seed * i), uv_dx, uv_dy).rgb;
	vec3 second = textureGrad(tex, uv + sin(seed * (i + 1.0)), uv_dx, uv_dy).rgb;
	// Biasing the seam by the content hides it in the texture's own detail.
	vec3 n = mix(first, second, smoothstep(0.2, 0.8, fract(index) - 0.1 * dot(first - second, vec3(1.0)))) * 2.0 - 1.0;
	// Slopes come back in texture axes. NoiseTexture2D stores green flipped
	// against uv.y, which turns the inverse rotation back into turn itself.
	n.xy = turn * n.xy;
	return n * 0.5 + 0.5;
}

float waveheight(vec2 offset, int mode) {
	float h1 = 0.0;
	float h2 = 0.0;
	switch (mode) {
		case 0:
			return texture(wave, (wave_pos + offset) / noise_scale + (wave_time * wave_direction) * time_scale).r;
		case 1:
			return texture(wave, (wave_pos + offset) / noise_scale + (wave_time * wave_direction2) * time_scale).r;
		default:
			h1 = texture(wave, (wave_pos + offset) / noise_scale + (wave_time * wave_direction) * time_scale).r;
			h2 = texture(wave, (wave_pos + offset) / noise_scale + (wave_time * wave_direction2) * time_scale).r;
			return mix(h1, h2, 0.5);
	}
}

// Light of one mirrored cloud sample, as integrate_clouds() lights the sky's.
vec3 mirror_light(vec3 p, vec3 formation, float height, float bottom, vec3 ray) {
	float radius = length(p);
	float density = formation.x * cloud_density_scale;
	float opacity_scale = authored_weather ? 1.2 : 3.0;
	float sun_height = dot(p / radius, sun_direction);
	float horizon = -sqrt(max(0.0, 1.0 - pow(bottom / radius, 2.0)));
	float daylight = smoothstep(horizon - 0.025, horizon + 0.045, sun_height);
	float sun_shadow;
	if (cloud_reflection_shading == 0) {
		// Gaps above the base let light through; a full column of this density
		// shaded every base like a storm.
		float column = min(cloud_thickness_km * cloud_deck_fraction * 0.5 / max(sun_height, 0.2), 0.5);
		sun_shadow = exp(-density * column * cloud_density_scale * opacity_scale);
	} else {
		// The sky's sun column (sun_optical_depth): up to the formation top,
		// lengthened by a low sun.
		float top = mix(cloud_deck_fraction, 1.0, formation.z);
		float optical = cloud_reflection_shading == 2
			? sun_optical_depth(p, height, top, bottom, 0.0)
			: formation.x * min(max(top - height, 0.02) / max(sun_height, 0.2), top * 1.5) * cloud_thickness_km;
		sun_shadow = exp(-optical * cloud_density_scale * opacity_scale);
	}
	float sun_cos = dot(ray, sun_direction);
	float phase = mix(hg_phase(sun_cos, -0.2), hg_phase(sun_cos, 0.5), 0.5);
	float sunset = 1.0 - smoothstep(0.0, 0.28, max(sun_height, 0.0));
	vec3 sunlight = mix(vec3(1.0, 0.98, 0.94), vec3(1.0, 0.36, 0.12), sunset);
	float light_height = clamp(formation.y, 0.0, 1.0);
	vec3 ambient = vec3(0.002, 0.003, 0.006)
		+ vec3(0.14, 0.19, 0.27) * daylight * mix(0.5, 1.15, max(light_height, 1.0 - density))
		+ vec3(0.07, 0.06, 0.045) * daylight * max(sun_height, 0.0) * (1.0 - light_height);
	float direct = sun_shadow * (0.15 + 0.55 * phase) + 0.2 * pow(sun_shadow, 0.25);
	return ambient + sunlight * daylight * direct;
}

// TEMPORARY A/B mode 3: three samples through the low deck along the ray,
// then one at the storm cap's height, composited front to back like the sky.
// Each family has its own height band (cells and sheets start above the
// base, anvils at 76% of the shell), so a single base sample missed them.
vec4 mirrored_deck(vec3 origin, vec3 ray) {
	float bottom = cloud_bottom_km();
	float start = sphere_interval(origin, ray, bottom).y;
	if (start <= 0.0) { return vec4(0.0); }
	float opacity_scale = authored_weather ? 1.2 : 3.0;
	float deck_end = sphere_interval(origin, ray, bottom + cloud_thickness_km * cloud_deck_fraction).y;
	// Grazing rays cross tens of kilometres of deck; the near part hides the rest.
	float span = min(deck_end - start, 8.0);
	vec3 color = vec3(0.0);
	float remaining = 1.0;
	for (int i = 0; i < 4; i++) {
		vec3 p;
		float length_km;
		if (i < 3) {
			p = origin + ray * (start + span * (float(i) + 0.5) / 3.0);
			length_km = span / 3.0;
		} else {
			// Storm cap: only storms reach above the deck, and authored_density
			// returns without a volume read where none is painted.
			float cap = sphere_interval(origin, ray, bottom + cloud_thickness_km * 0.76).y;
			if (cap <= 0.0) { break; }
			p = origin + ray * cap;
			length_km = min(cloud_thickness_km * 0.2 / max(dot(ray, normalize(p)), 0.15), 8.0);
		}
		float height = (length(p) - bottom) / cloud_thickness_km;
		vec3 formation = sample_formation(p, height, 0.0, false);
		float density = formation.x * cloud_density_scale;
		if (density <= 0.0) { continue; }
		float opacity = 1.0 - exp(-density * length_km * opacity_scale);
		color += mirror_light(p, formation, height, bottom, ray) * remaining * opacity;
		remaining *= 1.0 - opacity;
	}
	float alpha = 1.0 - remaining;
	return alpha < 0.005 ? vec4(0.0) : vec4(color / alpha, alpha);
}

// Underside of the deck along a mirrored ray: unmultiplied RGB and opacity.
// One density sample ~175 m into the deck, lit as cloud_layer.gd's
// _trace_glow estimates surrounding cloud. Each sample costs about 0.5 ms of
// full-screen water at 1080p, so the base's own density stands in for the
// sun column: denser bases sit under thicker cloud.
vec4 mirrored_clouds(vec3 origin, vec3 ray) {
	float bottom = cloud_bottom_km();
	float start = sphere_interval(origin, ray, bottom).y;
	if (start <= 0.0) { return vec4(0.0); }
	vec3 base = origin + ray * start;
	// A height step, so grazing rays still reach into the deck.
	float step_km = 0.35 / max(dot(ray, normalize(base)), 0.15);
	vec3 p = base + ray * (step_km * 0.5);
	float radius = length(p);
	float height = (radius - bottom) / cloud_thickness_km;
	// Ripples blur the mirror image; the coarse billows alone (one volume
	// read) are enough, as distant clouds use.
	vec3 formation = sample_formation(p, height, 0.0, false);
	float density = formation.x * cloud_density_scale;
	if (density <= 0.0) { return vec4(0.0); }
	float opacity_scale = authored_weather ? 1.2 : 3.0;
	float opacity = 1.0 - exp(-density * step_km * opacity_scale);
	return opacity < 0.005 ? vec4(0.0) : vec4(mirror_light(p, formation, height, bottom, ray), opacity);
}

void vertex() {
	// Unit disc scaled to the current extent, wrapped exactly onto the sphere.
	vec2 flat_xz = VERTEX.xz * base_extent;
	float base_r = length(flat_xz);
	float outer = max(base_extent - dense_radius, 1.0);
	float stretch = max(patch_extent - base_extent, 0.0);
	float transition = max(base_r - dense_radius, 0.0) / outer;
	float r = base_r + stretch * transition * transition;
	float angle = r / planet_radius;
	vec2 dir_xz = r > 0.0 ? flat_xz / max(base_r, 0.0001) : vec2(0.0);
	VERTEX = vec3(dir_xz.x * planet_radius * sin(angle), planet_radius * (cos(angle) - 1.0), dir_xz.y * planet_radius * sin(angle));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 offset = world_pos - anchor_world;
	wave_pos = vec2(dot(offset, axis_u), dot(offset, axis_v));
	vec3 up = normalize(world_pos - planet_center_world);
	mat3 to_local = transpose(mat3(MODEL_MATRIX));

	vertex_distance = distance(world_pos, ocean_pos);
	vertex_distance = clamp(vertex_distance, 0.0, 85.0);
	vertex_distance_clamped = vertex_distance / 85.0;
	float height_mix = waveheight(vec2(0.0, 0.0), 2);
	wave_height = (height_mix - 0.5) * height_scale * (1.0 - smoothstep(0.0, 85.0, vertex_distance));
	cell_size = (first_cell + ring_growth * base_r) * (1.0 + 2.0 * stretch * transition / outer);
	vec3 body_dir = body_from_world * up;
	vec2 body_uv = vec2(atan(body_dir.x, body_dir.z) / 6.28318530718, atan(length(body_dir.xz), body_dir.y) / 3.14159265359);
	// Swell shoals with the seabed's depth, so troughs never near the bottom.
	float bed_depth = mix(seabed_shallow_m, seabed_depth_m, smoothstep(0.5, 0.95, textureLod(baked_surface, body_uv, 2.0).a));
	float shoal = clamp(bed_depth / seabed_depth_m, 0.0, 1.0);
	shoal *= shoal;
	for (int i = 0; i < 4; i++) {
		float w = octave_weight(swell_scales[i], cell_size) * sea_state(wave_pos, i);
		wave_height += (textureLod(swell_noise, swell_uv(wave_pos, i), 0.0).r - 0.5) * 2.0 * swell_heights[i] * w * shoal;
	}
	// Planet: distant water is seen through the same air as the terrain.
	vec3 ray = (world_pos - planet_center_world) * 0.001 - camera_planet_km;
	vec3 view_dir = normalize(world_pos - INV_VIEW_MATRIX[3].xyz);
	air_light = vec3(0.0);
	air_transmission = vec3(1.0);
	sky_light = vec3(0.0);
	cloud_air_light = vec3(0.0);
	cloud_air_transmission = vec3(1.0);
	// The patch surrounds the camera; about half of it lies behind the view.
	// Far outside any field of view, so no drawn triangle reaches these.
	if (dot(view_dir, -INV_VIEW_MATRIX[2].xyz) > -0.3) {
		vec3 transmission;
		air_light = scatter_air(camera_planet_km, normalize(ray), length(ray), transmission);
		air_transmission = transmission;
		vec3 sky_transmission;
		// The mirrored sky ray crosses the whole atmosphere, so it always took
		// the full scene sample count; its colour varies smoothly along it.
		vec3 mirror_origin = (world_pos - planet_center_world) * 0.001;
		vec3 mirror_ray = reflect(view_dir, up);
		sky_light = scatter_air_steps(mirror_origin, mirror_ray, 1.0e6, BODY_RADIUS, AIR_RADIUS, atmosphere_density_scale, sky_view_samples, 1, sky_transmission);
		float cloud_distance = sphere_interval(mirror_origin, mirror_ray, cloud_bottom_km()).y;
		if (cloud_reflection_enabled && cloud_distance > 0.0) {
			cloud_air_light = scatter_air_steps(mirror_origin, mirror_ray, cloud_distance, BODY_RADIUS, AIR_RADIUS, atmosphere_density_scale, sky_view_samples, 1, cloud_air_transmission);
		}
	}
	VERTEX += to_local * up * wave_height;

	NORMAL = to_local * up;
	TANGENT = to_local * axis_u;
	BINORMAL = to_local * axis_v;
}

void fragment() {
	float depth = linear_depth(texture(DEPTH_TEXTURE, SCREEN_UV).r, SCREEN_UV, INV_PROJECTION_MATRIX);
	// Far away the depth buffer cannot resolve metres of water and bands into
	// contours. There, use the known seabed shape along the view ray.
	vec3 up_world = normalize(world_pos - planet_center_world);
	vec3 body_dir = body_from_world * up_world;
	vec2 body_uv = vec2(atan(body_dir.x, body_dir.z) / 6.28318530718, atan(length(body_dir.xz), body_dir.y) / 3.14159265359);
	// Land per the planet map, tested as terrain.gdshader does. Low-detail
	// distant terrain (flight LODs above 8 km) sags hundreds of metres below
	// sea level along coasts; no water there. Near the camera, raised coastal
	// triangles occlude the water themselves, so the map is not consulted.
	vec2 uv_dx = dFdx(body_uv);
	vec2 uv_dy = dFdy(body_uv);
	uv_dx.x -= round(uv_dx.x);
	uv_dy.x -= round(uv_dy.x);
	float coverage = sharp_coverage(baked_surface, body_uv, uv_dx, uv_dy, textureGrad(baked_surface, body_uv, uv_dx, uv_dy).a);
	// Fade across about a pixel instead of discarding: MSAA cannot smooth a
	// discard, which left the distant shoreline stair-stepped.
	float shore = -VERTEX.z > 15000.0 ? clamp((coverage - 0.48) / max(fwidth(coverage), 1e-4) + 0.5, 0.0, 1.0) : 1.0;
	if (shore <= 0.0) { discard; }
	if (length(body_dir - launch_direction_body) * planet_radius < launch_dry_radius) { discard; }
	float shelf = smoothstep(0.5, 0.95, coverage);
	float bed = mix(seabed_shallow_m, seabed_depth_m, shelf) + wave_height;
	vec3 ray_view = normalize(VERTEX);
	vec3 up_view = normalize(mat3(VIEW_MATRIX) * up_world);
	float descent = max(-dot(ray_view, up_view), 0.02);
	float analytic = -VERTEX.z + bed / descent * -ray_view.z;
	depth = mix(depth, analytic, smoothstep(1500.0, 4000.0, -VERTEX.z));
	float depth_blend = exp((depth + VERTEX.z + depth_offset) * -beers_law);
	depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);
	float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

	vec3 screen_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, depth_blend_power * 2.5).rgb;
	vec3 depth_color = mix(color_shallow.rgb, color_deep.rgb, depth_blend_power);
	vec3 color = mix(screen_color * depth_color, depth_color * 0.25, depth_blend_power * 0.5);

	float z_depth = depth;
	float z_pos = -VERTEX.z;
	float z_dif = z_depth - z_pos;

	vec2 time = (wave_time * wave_direction) * time_scale;
	vec2 time2 = (wave_time * wave_direction2) * time_scale;

	vec2 wave_dx = dFdx(wave_pos);
	vec2 wave_dy = dFdy(wave_pos);
	vec3 normal_blend = mix(untiled(texture_normal, wave_pos, wave_dx, wave_dy, time / 10.0, 10.0, 0),
		untiled(texture_normal2, wave_pos, wave_dx, wave_dy, time2 / 10.0, 10.0, 1), 0.5);
	vec3 wave_normal_blend = mix(untiled(wave_bump, wave_pos, wave_dx, wave_dy, time, noise_scale, 2),
		untiled(wave_bump, wave_pos, wave_dx, wave_dy, time2, noise_scale, 3), 0.3);

	float fresnel = fresnel(5.0, NORMAL, VIEW);
	vec3 surface_color = mix(albedo, albedo2, fresnel);

	vec3 hull_axis = hull_b - hull_a;
	float hull_t = clamp(dot(world_pos - hull_a, hull_axis) / max(dot(hull_axis, hull_axis), 1e-6), 0.0, 1.0);
	float hull_distance = distance(world_pos, hull_a + hull_axis * hull_t);
	float foam = (1.0 - step(edge_scale, z_dif)) * (hull_radius > 0.0 ? smoothstep(hull_radius, hull_radius + 1.5, hull_distance) : 1.0);
	vec3 depth_color_adj = mix(color, edge_color, foam);
	ALBEDO = clamp(surface_color + depth_color_adj, vec3(0.0), vec3(1.0));
	METALLIC = metallic;
	ROUGHNESS = roughness;
	// InfiniteOcean's two overlapping detail layers carry the near-water look.
	// Filter each layer by its footprint rather than removing all ripples at
	// one arbitrary distance. The distant surface approaches a calm normal.
	float footprint = max(length(dFdx(wave_pos)), length(dFdy(wave_pos)));
	float fine_weight = 1.0 - smoothstep(0.4, 3.0, footprint);
	float ripple_weight = 1.0 - smoothstep(0.8, 6.0, footprint);
	vec3 flat_map = vec3(0.5, 0.5, 1.0);
	vec3 detail_map = mix(mix(flat_map, wave_normal_blend, ripple_weight),
		mix(flat_map, normal_blend, fine_weight), 0.5);
	float boost = mix(1.0, swell_slope_boost, smoothstep(300.0, 3000.0, -VERTEX.z));
	vec2 grad = vec2(0.0);
	float shoal = pow(clamp(mix(seabed_shallow_m, seabed_depth_m, shelf) / seabed_depth_m, 0.0, 1.0), 2.0);
	for (int i = 0; i < 4; i++) {
		grad += swell_gradient(wave_pos, i, footprint) * sea_state(wave_pos, i) * boost * shoal;
	}
	vec3 tangent_normal = normalize(detail_map * 2.0 - 1.0);
	tangent_normal = normalize(vec3(tangent_normal.xy - grad, max(tangent_normal.z, 0.1)));
	NORMAL_MAP = tangent_normal * 0.5 + 0.5;
	SPECULAR = mix(0.5, wave_normal_blend.r, ripple_weight);

	ALBEDO *= air_transmission;
	EMISSION = air_light;
	vec3 tangent_u = normalize(axis_u - up_world * dot(axis_u, up_world));
	vec3 tangent_v = cross(up_world, tangent_u);
	vec3 normal_world = normalize(tangent_u * tangent_normal.x + tangent_v * tangent_normal.y + up_world * tangent_normal.z);
	vec3 view_ray = normalize(world_pos - INV_VIEW_MATRIX[3].xyz);
	float reflectance = 0.02 + 0.98 * pow(1.0 - clamp(dot(normal_world, -view_ray), 0.0, 1.0), 5.0);
	// Full ripples scatter grazing rays across kilometres of cloud and
	// break the reflection into flecks; mirror a calmer surface.
	vec3 bounce = reflect(view_ray, normalize(mix(up_world, normal_world, 0.35)));
	// Steep ripples can tip the bounce below the horizon; mirror the swell-free surface then.
	if (dot(bounce, up_world) < 0.01) { bounce = reflect(view_ray, up_world); }
	vec3 origin_km = (world_pos - planet_center_world) * 0.001;
	vec3 sky = sky_light;
	// The mirrored ray starts at the water, so cloud bases stay reflected at
	// any camera height: from above the deck they show through its gaps, and
	// the cloud layer covers the rest. Like the sky, they last until the patch
	// fades (ocean_patch.gd FADE_START).
	float cloud_weight = reflectance * cloud_reflection_strength;
	vec4 cloud = vec4(0.0);
	// Steeper water reflects too little for the clouds to show.
	if (cloud_reflection_enabled && cloud_weight > 0.03) {
		cloud = cloud_reflection_shading == 3 ? mirrored_deck(origin_km, bounce) : mirrored_clouds(origin_km, bounce);
		cloud.rgb = cloud.rgb * cloud_reflection_brightness * cloud_air_transmission + cloud_air_light;
		// The deck march already has the sky's opacity; the boost thickened
		// a single base sample.
		cloud.a = 1.0 - pow(1.0 - cloud.a, cloud_reflection_shading == 3 ? 1.0 : cloud_reflection_density);
		// Ease in from the skip threshold so it leaves no edge.
		cloud.a *= cloud_reflection_strength * smoothstep(0.03, 0.06, cloud_weight);
	}
	// Cloud in front, sky behind; the mirror replaces the water's own color.
	vec3 mirrored = sky * sky_reflection_strength * (1.0 - cloud.a) + cloud.rgb * cloud.a;
	float mirror = clamp(reflectance * (sky_reflection_strength * (1.0 - cloud.a) + cloud.a), 0.0, 1.0);
	ALBEDO *= 1.0 - mirror;
	EMISSION += mirrored * reflectance * air_transmission;
	// Replaces the environment's reflection, which is one fixed gradient in
	// every direction: it kept the side facing away from a sunset bright.
	RADIANCE = vec4(0.0, 0.0, 0.0, sky_reflection_strength);
	ALPHA = fade * mix(smoothstep(0.9, 1.0, fade), 1.0, depth_blend_power) * shore;
}
