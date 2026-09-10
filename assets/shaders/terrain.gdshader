shader_type spatial;
render_mode unshaded;
#include "res://assets/shaders/atmosphere.gdshaderinc"
varying vec3 sphere_pos;
varying vec3 surface_point;
varying vec3 world_surface_direction;
uniform float surface_coordinate_scale = 1.0;
uniform vec4 ocean_color : source_color = vec4(0.082,0.275,0.396,1.0);
uniform bool has_baked_surface = false;
uniform sampler2D baked_surface : filter_linear_mipmap, repeat_enable;
varying vec3 terrain_normal;
// Body-space material coordinates keep the ground fixed during rotation and
// work at the map's reduced model scale as well as in flight.
float terrain_hash(vec3 p) {
	// Hash all three axes independently: a linear cell index repeats along
	// integer diagonals and creates rows of dots on the globe.
	p = fract(p*vec3(0.1031,0.1030,0.0973));
	p += dot(p,p.yxz+33.33);
	return fract((p.x+p.y)*p.z);
}
float terrain_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f*f*(3.0-2.0*f);
	vec4 a = vec4(terrain_hash(cell),terrain_hash(cell+vec3(1,0,0)),
		terrain_hash(cell+vec3(0,1,0)),terrain_hash(cell+vec3(1,1,0)));
	vec4 b = vec4(terrain_hash(cell+vec3(0,0,1)),terrain_hash(cell+vec3(1,0,1)),
		terrain_hash(cell+vec3(0,1,1)),terrain_hash(cell+vec3(1,1,1)));
	return mix(mix(mix(a.x,a.y,f.x),mix(a.z,a.w,f.x),f.y),
		mix(mix(b.x,b.y,f.x),mix(b.z,b.w,f.x),f.y),f.z);
}
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
}
void fragment() {
	vec4 surface_color = COLOR;
	if (has_baked_surface) {
		vec3 direction = normalize(sphere_pos);
		vec2 uv = vec2(atan(direction.x,direction.z)/6.28318530718,
			acos(clamp(direction.y,-1.0,1.0))/3.14159265359);
		uv.y = clamp(uv.y,0.5/1024.0,1.0-0.5/1024.0);
		// Unwrap derivatives at the longitude seam before selecting mip levels.
		vec2 dx = dFdx(uv);
		vec2 dy = dFdy(uv);
		dx.x -= round(dx.x);
		dy.x -= round(dy.x);
		surface_color = textureGrad(baked_surface,uv,dx,dy);
	}
	vec3 col = surface_color.rgb;
	float coast_filter = max(0.08,fwidth(surface_color.a));
	float water_mask = smoothstep(0.5-coast_filter,0.5+coast_filter,surface_color.a);
	float footprint = max(length(dFdx(sphere_pos)),length(dFdy(sphere_pos)));
	float broad = filtered_terrain(sphere_pos,0.00075,footprint);
	float regional = filtered_terrain(sphere_pos,0.003,footprint);
	float middle = filtered_terrain(sphere_pos,0.009,footprint);
	float detail = filtered_terrain(sphere_pos,0.025,footprint);
	float fine = filtered_terrain(sphere_pos,0.09,footprint);
	float grain = filtered_terrain(sphere_pos,0.35,footprint);
	vec3 world_normal = normalize(terrain_normal);
	vec3 radial = normalize(world_surface_direction);
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
	vec3 ocean = mix(ocean_color.rgb*1.3,ocean_color.rgb*0.3,smoothstep(0.55,0.95,surface_color.a));
	col = mix(col,ocean,water_mask);
	float sun_height = dot(world_normal,sun_direction);
	float horizon_light = smoothstep(-0.03,0.03,dot(normalize(world_surface_direction),sun_direction));
	vec3 ray = surface_point-camera_planet_km;
	vec3 transmission;
	vec3 air = scatter_air(camera_planet_km,normalize(ray),length(ray),transmission);
	vec3 sky_fill = vec3(0.045,0.065,0.085)*(0.45+0.55*max(dot(world_normal,radial),0.0))*horizon_light;
	vec3 surface_light = vec3(0.006,0.008,0.012)+sky_fill+vec3(1.0,0.98,0.95)*max(sun_height,0.0)*1.55*horizon_light;
	vec3 view_direction = -normalize(ray);
	vec3 half_vector = normalize(sun_direction+view_direction);
	float fresnel = 0.02+0.98*pow(1.0-max(dot(world_normal,view_direction),0.0),5.0);
	float glint = pow(max(dot(world_normal,half_vector),0.0),180.0)*fresnel*water_mask*max(sun_height,0.0);
	ALBEDO = (col*surface_light+vec3(1.0,0.98,0.95)*glint*0.8)*transmission+air;
	ROUGHNESS = 0.84;
}
