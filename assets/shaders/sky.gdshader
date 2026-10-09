shader_type sky;
#include "res://assets/shaders/atmosphere.gdshaderinc"
uniform bool workshop = true;
uniform float reflection_strength = 1.0;
uniform float sun_glow_visibility = 0.0;
// Soft solar halo and bloom, without optical lens streaks.
vec3 sun_glow(vec3 direction) {
	float angular_distance = length(direction - sun_direction);
	float halo = exp(-pow(angular_distance/0.085,1.3))*0.65;
	float bloom = exp(-angular_distance*angular_distance/0.00065)*2.2;
	float forward = smoothstep(0.0,0.5,dot(direction,sun_direction));
	return (vec3(1.0,0.60,0.20)*halo+vec3(1.0,0.96,0.88)*bloom)*sun_glow_visibility*forward;
}
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453123); }
float hash31(vec3 p) { return fract(sin(dot(p, vec3(127.1,311.7,74.7))) * 43758.5453123); }

// Direction-space noise keeps the Milky Way continuous across the sky UV seam.
float space_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 blend = fract(p);
	blend = blend*blend*(3.0-2.0*blend);
	float low = mix(mix(hash31(cell),hash31(cell+vec3(1.0,0.0,0.0)),blend.x),
		mix(hash31(cell+vec3(0.0,1.0,0.0)),hash31(cell+vec3(1.0,1.0,0.0)),blend.x),blend.y);
	float high = mix(mix(hash31(cell+vec3(0.0,0.0,1.0)),hash31(cell+vec3(1.0,0.0,1.0)),blend.x),
		mix(hash31(cell+vec3(0.0,1.0,1.0)),hash31(cell+vec3(1.0,1.0,1.0)),blend.x),blend.y);
	return mix(low,high,blend.z);
}

vec3 milky_way(vec3 direction) {
	vec3 pole = normalize(vec3(0.27,0.84,-0.47));
	float latitude = dot(direction,pole);
	float broad = exp(-pow(latitude/0.19,2.0));
	if (broad < 0.0001) { return vec3(0.0); }
	float large = space_noise(direction*9.0);
	float detail = space_noise(direction*31.0);
	float wisps = space_noise(direction*73.0);
	float shape = smoothstep(0.23,0.79,large*0.60+detail*0.30+wisps*0.10);
	float core = exp(-pow(latitude/0.052,2.0));
	float dust = smoothstep(0.57,0.79,space_noise(direction*24.0+vec3(8.0,2.0,5.0)));
	float broken_core = core*(1.0-dust*0.82);
	vec3 blue_haze = vec3(0.014,0.028,0.066)*broad*(0.30+0.70*shape);
	vec3 luminous_band = vec3(0.075,0.085,0.115)*broken_core*(0.22+0.78*shape);
	vec3 warm_clouds = vec3(0.037,0.018,0.026)*broad*shape*shape;
	return blue_haze+luminous_band+warm_clouds;
}

// Small inclined disks with bright nuclei and faint, broken spiral arms.
vec3 distant_galaxy(vec3 direction, vec3 center, vec3 tint, float size) {
	vec3 right = normalize(cross(center,vec3(0.0,1.0,0.0)));
	vec3 up = cross(right,center);
	vec2 disk = vec2(dot(direction,right),dot(direction,up)*2.7)/size;
	float radius = length(disk);
	if (radius > 2.8 || dot(direction,center) < 0.0) { return vec3(0.0); }
	float angle = atan(disk.y,disk.x);
	float arms = 0.55+0.45*cos(angle*2.0-radius*8.0);
	float haze = exp(-radius*radius*1.35)*(0.45+0.55*arms);
	float nucleus = exp(-radius*radius*26.0);
	return tint*haze*0.085+vec3(0.17,0.16,0.15)*nucleus;
}

vec3 deep_space(vec3 direction) {
	vec3 backdrop = vec3(0.0008,0.0016,0.0045);
	backdrop += milky_way(direction);
	backdrop += distant_galaxy(direction,normalize(vec3(0.54,0.25,-0.80)),vec3(0.42,0.52,0.92),0.075);
	backdrop += distant_galaxy(direction,normalize(vec3(-0.76,-0.12,0.64)),vec3(0.90,0.48,0.39),0.043);
	return backdrop;
}
// Layered random positions and Gaussian star cores inspired by xcv145336's
// CC0 starfield: https://godotshaders.com/shader/2d-starfield-in-the-sky-with-scrolling-effect-ver-1-0/
vec3 starfield(vec2 sky_uv, float animation_time) {
	vec3 stars = vec3(0.0);
	for (int layer=0; layer<3; layer++) {
		float rows = 100.0 + float(layer)*80.0;
		vec2 grid = sky_uv*vec2(rows*2.0,rows);
		// Invert the local sky projection to measure star shapes in pixels.
		// UV distance alone stretches the cores near the sky's poles.
		vec2 dx = dFdx(grid);
		vec2 dy = dFdy(grid);
		float determinant = dx.x*dy.y-dx.y*dy.x;
		float safe_determinant = abs(determinant) < 0.00000001 ? 0.00000001 : determinant;
		float pixel_scale = max(max(length(dx),length(dy)),0.0001);
		vec2 cell = floor(grid);
		for (int y=-1; y<=1; y++) {
			for (int x=-1; x<=1; x++) {
				vec2 neighbor = cell+vec2(float(x),float(y));
				vec2 id = vec2(mod(neighbor.x,rows*2.0),neighbor.y);
				float seed = hash21(id+float(layer)*37.0);
				if (seed < 0.965 || id.y < 0.0 || id.y >= rows) { continue; }
				vec2 center = vec2(hash21(id+17.0),hash21(id+43.0));
				vec2 offset = grid-neighbor-center;
				float size = mix(0.035,0.10,hash21(id+71.0));
				vec2 pixel_offset = vec2(dy.y*offset.x-dy.x*offset.y,dx.x*offset.y-dx.y*offset.x)/safe_determinant;
				float radius = size/pixel_scale;
				float variance = radius*radius+0.166667;
				float distance_squared = dot(pixel_offset,pixel_offset);
				float core = exp(-distance_squared/variance)*radius*radius/variance;
				float halo_variance = radius*radius*4.0+0.166667;
				float halo = exp(-distance_squared/halo_variance)*0.12*radius*radius*4.0/halo_variance;
				vec3 tint = mix(vec3(0.65,0.8,1.0),vec3(1.0,0.88,0.7),hash21(id+91.0));
				float period = mix(12.0,20.0,hash21(id+113.0));
				float twinkle = 0.9+0.1*sin(animation_time*6.28318530718/period+seed*6.28318530718);
				stars += (core+halo)*tint*(1.8-float(layer)*0.45)*twinkle;
			}
		}
	}
	return stars;
}
void sky() {
	vec3 direction = normalize(EYEDIR);
	if (AT_CUBEMAP_PASS || workshop) {
		float elevation = clamp(direction.y*0.75+0.22,0.0,1.0);
		COLOR = mix(vec3(0.43,0.64,0.66),vec3(0.065,0.22,0.32),pow(elevation,0.55));
		if (AT_CUBEMAP_PASS && !workshop) { COLOR *= reflection_strength; }
	} else {
		vec3 transmission;
		float planet_distance = length(camera_planet_km);
		// Sky seen below the horizon only shows where terrain and ocean meshes
		// sag under the true sphere, as MSAA edge samples. Shade those with the
		// horizon colour instead of the darker through-the-ground ray.
		vec3 up = camera_planet_km/max(planet_distance,0.001);
		float horizon_sin = clamp(BODY_RADIUS/max(planet_distance,0.001),0.0,1.0);
		float horizon_dot = -sqrt(1.0-horizon_sin*horizon_sin)+0.0005;
		vec3 across = direction-up*dot(direction,up);
		if (dot(direction,up) < horizon_dot && dot(across,across) > 1e-8) {
			direction = normalize(normalize(across)*sqrt(1.0-horizon_dot*horizon_dot)+up*horizon_dot);
		}
		// Follow the ray all the way to the atmosphere. A fixed maximum made the
		// glow vanish abruptly once the camera traveled beyond that distance.
		vec3 air = scatter_air(camera_planet_km,direction,planet_distance+AIR_RADIUS,transmission);
		vec2 ground = sphere_interval(camera_planet_km,direction,BODY_RADIUS);
		float clear_view = ground.x > 0.0 && ground.y > ground.x ? 0.0 : 1.0;
		float local_sun_height = dot(normalize(camera_planet_km),sun_direction);
		float night_visibility = 1.0-smoothstep(-0.08,0.12,local_sun_height);
		night_visibility = mix(night_visibility,1.0,smoothstep((AIR_RADIUS-BODY_RADIUS)*0.2,max(AIR_RADIUS-BODY_RADIUS,0.001),length(camera_planet_km)-BODY_RADIUS));
		float star_visibility = exp(-dot(air,vec3(0.2126,0.7152,0.0722))*18.0)*night_visibility;
		vec3 space = vec3(0.0);
		if (star_visibility > 0.001) {
			space = (deep_space(direction)+starfield(SKY_COORDS,TIME))*star_visibility;
		}
		COLOR = air + transmission*clear_view*(space+sun_glow(direction));
		COLOR += distant_limb_glow(camera_planet_km,direction);
	}
}
