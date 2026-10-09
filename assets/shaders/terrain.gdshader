shader_type spatial;
render_mode unshaded;
#include "res://assets/shaders/atmosphere.gdshaderinc"
#include "res://assets/shaders/water.gdshaderinc"
#include "res://assets/shaders/renderer_color.gdshaderinc"
varying vec3 sphere_pos;
varying vec3 surface_point;
varying vec3 world_surface_direction;
// Occluder position is relative to this body's center, in world-oriented km.
// Zero radius disables eclipses for standalone planets and editor previews.
uniform vec3 eclipse_center_km = vec3(0.0);
uniform float eclipse_radius_km = 0.0;
uniform float eclipse_sun_distance_km = 0.0;
uniform float eclipse_sun_radius_km = 0.0;
// A distant body is composited through the observer's local atmosphere. This
// keeps moons behind the bright sky glow instead of drawing over it.
uniform bool foreground_atmosphere_enabled = false;
uniform vec3 foreground_camera_planet_km = vec3(0.0);
uniform vec3 foreground_body_center_km = vec3(0.0);
uniform float foreground_body_radius_km = 600.0;
uniform float foreground_air_radius_km = 617.5;
uniform float foreground_atmosphere_density = 1.0;
uniform bool orthographic_view = false;
uniform vec3 camera_forward = vec3(0.0, 0.0, -1.0);
uniform float surface_coordinate_scale = 1.0;
// Preserve millimetre-scale separation from the launch deck. Transform small
// offsets around its datum instead of subtracting planet-sized view positions.
uniform bool launch_origin_enabled = false;
uniform vec3 launch_origin_local = vec3(0.0);
uniform vec3 launch_origin_view = vec3(0.0);
uniform vec4 ocean_color : source_color = vec4(0.082,0.275,0.396,1.0);
// Within this camera distance ocean.gdshader draws the sea at true sea level.
// Coarse coastal triangles would otherwise lift the water toward the hills,
// so water pixels there become a seabed below it instead (at least 2.5 m,
// below the tutorial's ±1 m waves; swell is calmed in shallows): the ocean shader
// reads its depth and colour for Beer's law, refraction and edge foam.
uniform float water_cutout_radius = 0.0;
uniform float seabed_fade = 0.0;
uniform float seabed_depth_m = 70.0;
uniform float seabed_shallow_m = 2.5;
uniform vec4 seabed_color : source_color = vec4(0.55,0.50,0.36,1.0);
uniform vec4 distant_body_color : source_color = vec4(0.20,0.32,0.30,1.0);
uniform bool distant_surface_smoothing_enabled = false;
uniform bool has_baked_surface = false;
uniform sampler2D baked_surface : filter_linear_mipmap, repeat_enable;
uniform bool has_baked_topography = false;
uniform sampler2D baked_topography : filter_linear_mipmap, repeat_enable;
// Editor inspection views: natural, elevation, slopes, water coverage.
uniform int surface_view = 0;
varying vec3 terrain_normal;
// Body-space material coordinates keep the ground fixed during rotation and
// work at the map's reduced model scale as well as in flight.
float filtered_terrain(vec3 p, float frequency, float footprint) {
	// Fade early: a barely resolved noise cell reads as a square blotch.
	float weight = 1.0-smoothstep(0.1,0.3,footprint*frequency);
	if (weight <= 0.0) { return 0.0; }
	return (terrain_noise(p*frequency)-0.5)*weight;
}
void vertex() {
	sphere_pos = VERTEX;
	terrain_normal = normalize(mat3(MODEL_MATRIX)*NORMAL);
	surface_point = mat3(MODEL_MATRIX)*VERTEX*0.001*surface_coordinate_scale;
	world_surface_direction = normalize(mat3(MODEL_MATRIX)*VERTEX);
	vec3 view_vertex;
	if (launch_origin_enabled) {
		view_vertex = mat3(MODELVIEW_MATRIX)*(VERTEX-launch_origin_local)+launch_origin_view;
	} else {
		view_vertex = (MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
	}
	POSITION = PROJECTION_MATRIX*vec4(view_vertex,1.0);
}
void fragment() {
	vec3 ocean_tint = authored_color(ocean_color.rgb);
	vec3 seabed_tint = authored_color(seabed_color.rgb);
	vec3 distant_tint = authored_color(distant_body_color.rgb);
	vec4 surface_color = COLOR;
	vec4 topography = vec4(0.5, 1.0, 0.5, 0.4);
	float apparent_radius = asin(clamp(BODY_RADIUS/max(length(camera_planet_km),BODY_RADIUS),0.0,1.0));
	float distant_filter = distant_surface_smoothing_enabled ? mix(7.0,1.0,smoothstep(0.02,0.07,apparent_radius)) : 1.0;
	if (has_baked_surface) {
		vec3 direction = normalize(sphere_pos);
		vec2 uv = vec2(atan(direction.x,direction.z)/6.28318530718,
			atan(length(direction.xz),direction.y)/3.14159265359);
		uv.y = clamp(uv.y,0.5/1024.0,1.0-0.5/1024.0);
		// Unwrap derivatives at the longitude seam before selecting mip levels.
		vec2 dx = dFdx(uv);
		vec2 dy = dFdy(uv);
		dx.x -= round(dx.x);
		dy.x -= round(dy.x);
		dx *= distant_filter;
		dy *= distant_filter;
		surface_color = textureGrad(baked_surface,uv,dx,dy);
		surface_color.a = sharp_coverage(baked_surface,uv,dx,dy,surface_color.a);
		if (has_baked_topography) {
			topography = textureGrad(baked_topography,uv,dx,dy);
		}
	}
	vec3 col = surface_color.rgb;
	float coast_filter = max(0.08,fwidth(surface_color.a));
	float resolved_water = smoothstep(0.5-coast_filter,0.5+coast_filter,surface_color.a);
	float distant_coverage = distant_surface_smoothing_enabled ? 1.0-smoothstep(0.03,0.08,apparent_radius) : 0.0;
	float water_mask = mix(resolved_water,clamp(surface_color.a,0.0,1.0),distant_coverage);
	float footprint = max(length(dFdx(sphere_pos)),length(dFdy(sphere_pos)))*distant_filter;
	// Wind driven ripples fade as their wavelength drops below a pixel.
	float wave, wave_a, wave_visibility;
	water_ripples(sphere_pos,footprint,wave,wave_a,wave_visibility);
	wave_visibility *= 1.0-distant_coverage;
	float broad = filtered_terrain(sphere_pos,0.00075,footprint);
	float regional = filtered_terrain(sphere_pos,0.003,footprint);
	float middle = filtered_terrain(sphere_pos,0.009,footprint);
	float detail = filtered_terrain(sphere_pos,0.025,footprint);
	float fine = filtered_terrain(sphere_pos,0.09,footprint);
	float grain = filtered_terrain(sphere_pos,0.35,footprint);
	vec3 world_normal = normalize(terrain_normal);
	vec3 radial = normalize(world_surface_direction);
	if (has_baked_topography) {
		vec3 baked_normal = normalize(mat3(MODEL_MATRIX)*(topography.rgb*2.0-1.0));
		world_normal = normalize(mix(world_normal,baked_normal,(1.0-water_mask)*(1.0-distant_coverage)));
	}
	float slope = 1.0-clamp(dot(world_normal,radial),0.0,1.0);
	// Exposed stone follows real slopes; broad mottling provides scale even
	// from altitude, while fine grain fades before it can shimmer.
	float rock = smoothstep(0.025,0.22,slope)*(1.0-water_mask);
	col = mix(col,vec3(0.24,0.22,0.18)*(1.0+regional*0.12),rock*0.75);
	// Keep biome gradients smooth. Material variation is a low-contrast
	// surface accent, not a replacement for the underlying land colors.
	col *= 1.0+(broad*0.06+regional*0.08+middle*0.06+detail*0.08+fine*0.06+grain*0.06)*(1.0-water_mask);
	// Resolve the coast per fragment instead of smearing ocean color across
	// entire inland triangles. Shallows give the shoreline a visible edge.
	// Inside the ocean patch the real water surface meets the land. Coastal
	// pixels that stay land must not carry the terrain's own water blend:
	// far away fwidth widens it into a dark band above the sea.
	if (water_cutout_radius > 0.0 && length(VERTEX) < water_cutout_radius && water_mask <= 0.5) {
		water_mask *= 1.0-smoothstep(0.9,1.0,seabed_fade);
	}
	vec3 ocean = ocean_albedo(ocean_tint,surface_color.a,sphere_pos,footprint,wave,wave_visibility,wave_a,water_mask);
	col = mix(col,ocean,water_mask);
	DEPTH = FRAGCOORD.z;
	// Pixels that are mostly water become seabed; the rest stay coast.
	if (water_cutout_radius > 0.0 && water_mask > 0.5 && length(VERTEX) < water_cutout_radius) {
		// Sand shelving into deep water, at seabed_depth_m below sea level. It
		// stays a little below the surface (more with distance, where depth
		// precision is coarser) so the water never ties with it.
		float shelf = smoothstep(0.5,0.95,surface_color.a);
		vec3 bed = mix(seabed_tint,seabed_tint*0.2,shelf);
		// While the water fades out, show the old water beneath it instead of
		// a dark seabed, so the two cross-fade without dark rims.
		float bed_visible = smoothstep(0.9,1.0,seabed_fade);
		// Beyond 15 km ocean.gdshader discards water its own coverage test
		// calls land; any seabed left uncovered there reads as a dark rim
		// along the far shore, so show the terrain's water instead.
		bed_visible *= 1.0-smoothstep(12000.0,15000.0,length(VERTEX));
		col = mix(col,bed,bed_visible);
		// Continue along the view ray from this (possibly raised) water pixel
		// down to the seabed, and write that depth. Keep the full drop while
		// the patch fades: shrinking it with seabed_fade brought this water
		// back to sea level, where it z-fought the translucent patch in
		// streaks along the patch's spokes.
		float above_sea = length(sphere_pos)-BODY_RADIUS*1000.0;
		// Rebuild the view position from this pixel's own depth: VERTEX loses
		// metres to planet-sized coordinates beside the launch-origin path.
		vec4 here = INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,FRAGCOORD.z*2.0-1.0,1.0);
		vec3 view_here = here.xyz/here.w;
		vec3 ray_dir = normalize(view_here);
		vec3 up_view = normalize(mat3(VIEW_MATRIX)*normalize(world_surface_direction));
		float descent = max(-dot(ray_dir,up_view),0.05);
		// Beyond 4 km ocean.gdshader reads its seabed analytically, not from
		// this depth, so the drop there only has to win the depth test. A few
		// metres did not: coastal shallows tied with the patch and showed
		// through it as speckle. Grow the drop with distance past 4 km, so
		// nearer shallows keep their depth-read colour.
		float view_distance = length(view_here);
		float far_drop = view_distance*0.01*smoothstep(4000.0,6000.0,view_distance);
		vec3 bed_view = view_here+ray_dir*(max(above_sea+mix(seabed_shallow_m+view_distance*0.0002,seabed_depth_m,shelf),0.0)+far_drop)/descent;
		vec4 bed_clip = PROJECTION_MATRIX*vec4(bed_view,1.0);
		DEPTH = bed_clip.z/bed_clip.w*0.5+0.5;
		water_mask = 1.0-bed_visible;
	}
	// Land and ocean patterns become unstable once they are smaller than a
	// pixel. Preserve their average body color instead of isolated bright dots.
	float distant_smoothing = distant_surface_smoothing_enabled ? 1.0-smoothstep(0.025,0.065,apparent_radius) : 0.0;
	col = mix(col,distant_tint,distant_smoothing*0.92);
	water_mask *= 1.0-distant_smoothing;
	// Smooth radial base avoids reflecting submerged terrain facets. Swells
	// remain visible farther out than ripples; each band filters independently.
	if (water_mask > 0.001) {
		vec3 gradient = water_wave_slope(sphere_pos,footprint);
		float shore_damping = mix(0.25,1.0,smoothstep(0.5,0.85,surface_color.a));
		vec3 wave_normal = normalize(radial-(mat3(MODEL_MATRIX)*gradient/max(length(MODEL_MATRIX[0].xyz),0.000001))*water_wave_strength*shore_damping*(1.0-distant_coverage));
		world_normal = normalize(mix(world_normal,wave_normal,water_mask));
	}
	vec3 ray_origin = camera_planet_km;
	vec3 ray = surface_point-ray_origin;
	if (orthographic_view) {
		// Parallel map rays need no system-scale camera coordinates. Starting
		// just outside the atmosphere avoids cancellation in sphere intervals
		// and sample positions, which otherwise shimmers as the camera rotates.
		ray = normalize(camera_forward)*(2.0*AIR_RADIUS);
		ray_origin = surface_point-ray;
	}
	vec3 transmission;
	vec3 air = scatter_air(ray_origin,normalize(ray),length(ray),transmission);
	float glint;
	vec3 reflected_surface = lit_surface(col,world_normal,radial,normalize(ray),sun_direction,ocean_tint,water_mask,glint);
	vec3 to_occluder = eclipse_center_km-surface_point;
	// Trace from this surface point to the physical sun, not parallel rays
	// from the body center. Its finite disk creates a penumbra during eclipse.
	vec3 to_sun = sun_direction*eclipse_sun_distance_km-surface_point;
	float sun_distance = max(length(to_sun),0.001);
	vec3 eclipse_direction = to_sun/sun_distance;
	float along_sun = dot(to_occluder,eclipse_direction);
	float shadow_distance = length(to_occluder-eclipse_direction*along_sun);
	float visibility = 1.0;
	if (eclipse_radius_km > 0.0 && along_sun > 0.0 && along_sun < sun_distance) {
		float penumbra = along_sun*eclipse_sun_radius_km/sun_distance;
		float edge = max(max(fwidth(shadow_distance),penumbra),0.001);
		visibility = smoothstep(eclipse_radius_km-edge,eclipse_radius_km+edge,shadow_distance);
	}
	// Suppress reflected sunlight and atmospheric glow together during eclipse.
	reflected_surface = mix(col*vec3(0.006,0.008,0.012),reflected_surface,visibility);
	glint *= visibility;
	air *= visibility;
	vec3 resolved_body = (reflected_surface+vec3(1.0,0.98,0.95)*glint*0.9)*transmission+air;
	float distant_light = 0.04+1.25*max(dot(radial,sun_direction),0.0);
	ALBEDO = mix(resolved_body,distant_tint*distant_light,distant_smoothing);
	if (distant_surface_smoothing_enabled && !orthographic_view) {
		ALBEDO += distant_limb_glow(camera_planet_km,ray);
	}
	if (foreground_atmosphere_enabled) {
		vec3 foreground_surface = surface_point-foreground_body_center_km;
		vec3 foreground_ray = foreground_surface-foreground_camera_planet_km;
		vec3 foreground_transmission;
		vec3 foreground_air = scatter_air_for(
			foreground_camera_planet_km,normalize(foreground_ray),length(foreground_ray),
			foreground_body_radius_km,foreground_air_radius_km,
			foreground_atmosphere_density,foreground_transmission);
		float foreground_sun_height = dot(normalize(foreground_camera_planet_km),sun_direction);
		float night_visibility = 1.0-smoothstep(-0.08,0.12,foreground_sun_height);
		night_visibility = mix(night_visibility,1.0,smoothstep((foreground_air_radius_km-foreground_body_radius_km)*0.2,max(foreground_air_radius_km-foreground_body_radius_km,0.001),length(foreground_camera_planet_km)-foreground_body_radius_km));
		float celestial_visibility = exp(-dot(foreground_air,vec3(0.2126,0.7152,0.0722))*18.0)*night_visibility;
		vec3 clear_sky = vec3(0.0005,0.001,0.003);
		ALBEDO = foreground_air+foreground_transmission*mix(clear_sky,ALBEDO,celestial_visibility);
	}
	if (surface_view > 0) {
		vec3 inspection = col;
		if (surface_view == 1) {
			float height = topography.a;
			vec3 land_height = mix(vec3(0.18,0.42,0.23),vec3(0.82,0.60,0.28),smoothstep(0.4,0.65,height));
			land_height = mix(land_height,vec3(0.96,0.94,0.86),smoothstep(0.65,0.95,height));
			inspection = mix(mix(vec3(0.015,0.06,0.16),vec3(0.10,0.48,0.66),smoothstep(0.0,0.4,height)),land_height,step(0.4,height));
		} else if (surface_view == 2) {
			inspection = mix(vec3(0.14,0.40,0.29),vec3(0.92,0.30,0.10),smoothstep(0.002,0.18,slope));
		} else if (surface_view == 3) {
			inspection = mix(vec3(0.48,0.39,0.22),vec3(0.06,0.35,0.64),water_mask);
		}
		ALBEDO = inspection*(0.5+0.5*max(dot(radial,sun_direction),0.0));
	}
	ALBEDO = material_output(ALBEDO);
	ROUGHNESS = 0.72;
}
