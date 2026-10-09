// Water colour and lighting shared by terrain.gdshader and ocean.gdshader.
// Both must produce identical pixels where the near-surface ocean patch hands
// over to the planet mesh's water, so neither may diverge from these.


// Visual sea state; metres and seconds in body space, independent of map scale.
uniform float water_wave_strength : hint_range(0.0, 2.0) = 1.0;
uniform float water_wave_speed : hint_range(0.0, 3.0) = 1.0;

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

// Derivative of smooth 3D noise: finite wave packets instead of infinitely
// repeating sine crests. The gradient keeps highlights continuous in motion.
vec3 water_noise_gradient(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	vec3 u = f*f*f*(f*(f*6.0-15.0)+10.0);
	vec3 du = 30.0*f*f*(f-1.0)*(f-1.0);
	float a = terrain_hash(cell);
	float b = terrain_hash(cell+vec3(1,0,0));
	float c = terrain_hash(cell+vec3(0,1,0));
	float d = terrain_hash(cell+vec3(1,1,0));
	float e = terrain_hash(cell+vec3(0,0,1));
	float f1 = terrain_hash(cell+vec3(1,0,1));
	float g = terrain_hash(cell+vec3(0,1,1));
	float h = terrain_hash(cell+vec3(1,1,1));
	return du*vec3(
		mix(mix(b-a,d-c,u.y),mix(f1-e,h-g,u.y),u.z),
		mix(mix(c-a,d-b,u.x),mix(g-e,h-f1,u.x),u.z),
		mix(mix(e-a,f1-b,u.x),mix(g-c,h-d,u.x),u.y));
}
vec3 ocean_wave_gradient(vec3 p, vec3 direction, float wavelength, float amplitude, float speed, float footprint) {
	float visible = 1.0-smoothstep(0.06,0.25,footprint/wavelength);
	if (visible <= 0.0) { return vec3(0.0); }
	// Rotate each band to prevent the noise lattice aligning between scales.
	vec3 across = normalize(cross(direction,vec3(0.17,0.97,0.11)));
	mat3 frame = mat3(direction,across,cross(direction,across));
	vec3 q = transpose(frame)*p/wavelength;
	q += vec3(-TIME*water_wave_speed*speed*0.12,0.0,0.0);
	return frame*water_noise_gradient(q)*(amplitude*6.28318530718/wavelength*visible);
}
// Tangential surface slope of the distant sea state, in body space.
vec3 water_wave_slope(vec3 body_pos, float footprint) {
	vec3 gradient = ocean_wave_gradient(body_pos,normalize(vec3(0.8,0.25,0.5)),48.0,0.65,1.12,footprint);
	gradient += ocean_wave_gradient(body_pos,normalize(vec3(-0.35,0.9,0.25)),19.0,0.32,1.8,footprint);
	gradient += ocean_wave_gradient(body_pos,normalize(vec3(0.4,-0.3,0.85)),7.0,0.13,2.97,footprint);
	gradient += ocean_wave_gradient(body_pos,normalize(vec3(-0.7,0.5,0.3)),2.4,0.045,5.07,footprint);
	vec3 local_radial = normalize(body_pos);
	return gradient - local_radial*dot(gradient,local_radial);
}

// Bilinear coverage from the base level. Some GL drivers point-sample the
// half-float surface map, which stair-steps every coastline by whole texels.
float coverage_bilinear(sampler2D tex, vec2 uv) {
	ivec2 size = textureSize(tex, 0);
	vec2 p = uv * vec2(size) - 0.5;
	ivec2 i = ivec2(floor(p));
	vec2 f = p - floor(p);
	int x0 = (i.x % size.x + size.x) % size.x;
	int x1 = (x0 + 1) % size.x;
	int y0 = clamp(i.y, 0, size.y - 1);
	int y1 = clamp(i.y + 1, 0, size.y - 1);
	float a = texelFetch(tex, ivec2(x0, y0), 0).a;
	float b = texelFetch(tex, ivec2(x1, y0), 0).a;
	float c = texelFetch(tex, ivec2(x0, y1), 0).a;
	float d = texelFetch(tex, ivec2(x1, y1), 0).a;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Sharp coverage while texels are magnified; the mipmapped value farther out.
float sharp_coverage(sampler2D tex, vec2 uv, vec2 dx, vec2 dy, float filtered) {
	vec2 size = vec2(textureSize(tex, 0));
	float texels = max(length(dx * size), length(dy * size));
	if (texels > 1.5) { return filtered; }
	return mix(coverage_bilinear(tex, uv), filtered, smoothstep(0.5, 1.5, texels));
}

// Ripple brightness and drifting shore foam, in body-space metres.
void water_ripples(vec3 body_pos, float footprint, out float wave, out float wave_a, out float wave_visibility) {
	wave_visibility = 1.0 - smoothstep(0.3, 3.0, footprint);
	vec3 wave_position = body_pos * 0.18;
	wave_a = terrain_noise(wave_position + vec3(TIME*water_wave_speed*0.7,0.0,TIME*water_wave_speed*0.28));
	float wave_b = terrain_noise(wave_position*2.3 + vec3(-TIME*water_wave_speed*0.42,0.0,TIME*water_wave_speed*0.61));
	wave = (wave_a-0.5)*0.7 + (wave_b-0.5)*0.3;
}

// Shallows near the coast (coverage 0.5) are lighter; open sea is darker.
vec3 ocean_body(vec3 ocean, float coverage) {
	return mix(ocean*1.3, ocean*0.65, smoothstep(0.55, 0.95, coverage));
}

// col: surface albedo (land/water mix). view_ray: camera to surface, unit.
// Returns sunlit, sky-filled and reflected colour before atmosphere.
vec3 lit_surface(vec3 col, vec3 n, vec3 radial, vec3 view_ray, vec3 sun, vec3 ocean, float water_mask, out float glint) {
	float sun_height = dot(n, sun);
	float horizon_light = smoothstep(-0.03, 0.03, dot(radial, sun));
	vec3 sky_fill = vec3(0.045,0.065,0.085)*(0.45+0.55*max(dot(n,radial),0.0))*horizon_light;
	vec3 surface_light = vec3(0.006,0.008,0.012)+sky_fill+vec3(1.0,0.98,0.95)*max(sun_height,0.0)*1.55*horizon_light;
	vec3 view_direction = -view_ray;
	vec3 half_vector = normalize(sun+view_direction);
	float fresnel = 0.08+0.92*pow(1.0-max(dot(n,view_direction),0.0),3.2);
	vec3 reflected_sun = reflect(-sun, n);
	float sun_reflection = pow(max(dot(reflected_sun, view_direction),0.0),10.0);
	float lit_water = clamp(0.35 + 0.65*max(sun_height,0.0),0.0,1.0);
	vec3 ocean_reflection_tint = mix(vec3(0.18,0.30,0.46), vec3(1.0,0.96,0.90), lit_water);
	vec3 water_reflection = mix(ocean*0.72, ocean_reflection_tint, 0.6);
	water_reflection += sky_fill*0.8;
	water_reflection += vec3(1.0,0.98,0.94)*sun_reflection*max(sun_height,0.0)*1.7;
	float ocean_reflectivity = clamp(water_mask*fresnel*0.76,0.0,1.0);
	glint = pow(max(dot(n,half_vector),0.0),120.0)*fresnel*water_mask*max(sun_height,0.0)*0.9;
	return mix(col*surface_light, water_reflection, ocean_reflectivity);
}

// Water albedo: shallows, ripple brightness and irregular drifting shore foam.
// The base colour parameter must not be named ocean_color: terrain.gdshader has
// a vec4 uniform of that name, and Forward+ resolves the name to the uniform.
vec3 ocean_albedo(vec3 base_color, float coverage, vec3 body_pos, float footprint, float wave, float wave_visibility, float wave_a, float water_mask) {
	vec3 ocean = ocean_body(base_color, coverage);
	ocean *= 1.0 + wave * 0.24 * wave_visibility * water_wave_strength;
	float shore_foam = (1.0-smoothstep(0.55,0.78,coverage)) * water_mask;
	// Do not turn the coverage mask into periodic contour lines. Broad,
	// drifting foam patches stay irregular and filter before they sparkle.
	float foam_patch = terrain_noise(body_pos*0.035+vec3(TIME*water_wave_speed*0.12,0.0,-TIME*water_wave_speed*0.08));
	float foam_break = smoothstep(0.48,0.72,foam_patch)*mix(0.65,1.0,wave_a);
	return mix(ocean,vec3(0.48,0.69,0.72),shore_foam*foam_break*0.65*(1.0-smoothstep(2.0,25.0,footprint))*water_wave_strength);
}
