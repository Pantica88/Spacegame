shader_type sky;
#include "res://assets/shaders/atmosphere.gdshaderinc"
uniform bool workshop = true;
uniform float reflection_strength = 1.0;
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453123); }
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
		vec3 stars = starfield(SKY_COORDS,TIME);
		vec3 transmission;
		vec3 air = scatter_air(camera_planet_km,direction,1000.0,transmission);
		float sun = smoothstep(0.99990,0.99996,dot(direction,sun_direction));
		vec2 ground = sphere_interval(camera_planet_km,direction,BODY_RADIUS);
		float clear_view = ground.x > 0.0 && ground.y > ground.x ? 0.0 : 1.0;
		float local_sun_height = dot(normalize(camera_planet_km),sun_direction);
		float night_visibility = 1.0-smoothstep(-0.08,0.12,local_sun_height);
		night_visibility = mix(night_visibility,1.0,smoothstep(2.0,10.0,length(camera_planet_km)-BODY_RADIUS));
		float star_visibility = exp(-dot(air,vec3(0.2126,0.7152,0.0722))*18.0)*night_visibility;
		COLOR = air + transmission*clear_view*(vec3(0.0005,0.001,0.003)+stars*star_visibility+sun*vec3(5.0,4.7,4.2));
	}
}
