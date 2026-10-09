// Distances in kilometres. A small single-scattering approximation shared by
// the sky and terrain so their horizons meet without a separate rim.
uniform vec3 sun_direction = vec3(-0.475, 0.443, 0.759);
uniform vec3 camera_planet_km = vec3(0.0, 600.01, 0.0);
uniform float atmosphere_density_scale = 1.0;
uniform float atmosphere_scattering_exposure = 1.0;
uniform float BODY_RADIUS = 600.0;
uniform float AIR_RADIUS = 617.5;
const vec3 BETA_R = vec3(0.014, 0.035, 0.085);
const vec3 BETA_M = vec3(0.009);
const int VIEW_SAMPLES = 64;
uniform int atmosphere_view_samples = 64;
uniform int atmosphere_light_samples = 6;

// A restrained distant limb shared by sky and surface, so the opaque disk
// does not cut a hard black hole into a broad, bright background halo.
vec3 distant_limb_glow(vec3 observer, vec3 direction) {
	float distance_to_body = length(observer);
	if (distance_to_body <= BODY_RADIUS) { return vec3(0.0); }
	float radius = asin(clamp(BODY_RADIUS / distance_to_body, 0.0, 1.0));
	float unresolved = 1.0-smoothstep(0.018,0.040,radius);
	float angle = length(normalize(direction)+observer/distance_to_body);
	float width = max(radius*0.22,0.00015);
	float limb = exp(-pow((angle-radius)/width,2.0));
	float daylight = 0.22+0.78*smoothstep(-0.25,0.45,dot(observer/distance_to_body,sun_direction));
	return vec3(0.018,0.045,0.085)*limb*unresolved*daylight*clamp(atmosphere_density_scale,0.0,1.0);
}

vec2 sphere_interval(vec3 origin, vec3 direction, float radius) {
	float b = dot(origin, direction);
	float discriminant = b*b - dot(origin, origin) + radius*radius;
	if (discriminant < 0.0) { return vec2(1.0, -1.0); }
	float root = sqrt(discriminant);
	return vec2(-b-root, -b+root);
}

vec2 air_density_for(float height, float density_scale, float atmosphere_height) {
	height = max(height, 0.0);
	float thickness = max(atmosphere_height,0.001);
	float edge = 1.0-smoothstep(thickness*0.7,thickness,height);
	return vec2(exp(-height/(thickness*0.32)), exp(-height/(thickness*0.09)))*edge*density_scale;
}

// Sample counts are explicit for callers needing less than the scene-wide
// atmosphere_view_samples / atmosphere_light_samples.
vec3 scatter_air_steps(vec3 origin, vec3 direction, float max_distance, float body_radius, float air_radius, float density_scale, int max_view_samples, int max_light_samples, out vec3 transmission) {
	transmission = vec3(1.0);
	if (air_radius <= body_radius || density_scale <= 0.0) { return vec3(0.0); }
	vec2 interval = sphere_interval(origin, direction, air_radius);
	float start = max(interval.x, 0.0);
	float end = min(interval.y, max_distance);
	vec2 ground = sphere_interval(origin, direction, body_radius);
	if (ground.x > 0.0 && ground.y > ground.x) { end = min(end, ground.x); }
	vec3 result = vec3(0.0);
	if (end > start) {
		// Finer midpoint integration prevents visible color bands at the limb.
		int view_count = clamp(max_view_samples,1,64);
		// Short paths (ground seen from low altitude) barely change in density;
		// cap their steps at ~3% of the air's depth. Long limb rays keep the full count.
		view_count = clamp(int(ceil((end-start)/max((air_radius-body_radius)*0.03,0.001))),2,view_count);
		int light_count = clamp(max_light_samples,1,6);
		float step_length = (end-start)/float(view_count);
		vec2 view_depth = vec2(0.0);
		float cosine = dot(direction, sun_direction);
		float rayleigh_phase = 0.75*(1.0+cosine*cosine);
		float g = 0.76;
		float mie_phase = 0.25*(1.0-g*g)/pow(max(1.0+g*g-2.0*g*cosine,0.05),1.5);
		for (int i=0; i<VIEW_SAMPLES; i++) {
			if (i >= view_count) { break; }
			vec3 sample_pos = origin+direction*(start+(float(i)+0.5)*step_length);
			vec2 density = air_density_for(length(sample_pos)-body_radius,density_scale,air_radius-body_radius);
			vec2 half_depth = view_depth+density*step_length*0.5;
			view_depth += density*step_length;
			float sample_radius = length(sample_pos);
			float horizon = -sqrt(max(0.0,1.0-body_radius*body_radius/(sample_radius*sample_radius)));
			float sun_elevation = dot(sample_pos/sample_radius,sun_direction)-horizon;
			// A broad penumbra plus weak indirect scattering keeps the halo wrapped
			// around the globe instead of slicing it at the day/night terminator.
			float direct_visibility = smoothstep(-0.10,0.12,sun_elevation);
			float illumination = mix(0.22,1.0,direct_visibility);
			if (illumination > 0.001) {
				float sun_length = max(sphere_interval(sample_pos,sun_direction,air_radius).y,0.0);
				vec2 sun_depth = vec2(0.0);
				for (int j=0; j<6; j++) {
					if (j >= light_count) { break; }
					float u = (float(j)+0.5)/float(light_count);
					vec3 sun_pos = sample_pos+sun_direction*(u*u*sun_length);
					sun_depth += air_density_for(length(sun_pos)-body_radius,density_scale,air_radius-body_radius)*sun_length*(2.0*float(j)+1.0)/float(light_count*light_count);
				}
				vec3 view_attenuation = exp(-BETA_R*half_depth.x-BETA_M*half_depth.y);
				vec3 sun_attenuation = exp(-BETA_R*(half_depth.x+sun_depth.x)-BETA_M*(half_depth.y+sun_depth.y));
				vec3 attenuation = mix(view_attenuation,sun_attenuation,direct_visibility);
				// Art-tuned warm transmission for long, low-angle sunlight paths.
				float sunset = (1.0-smoothstep(0.0,0.22,max(sun_elevation,0.0)))*direct_visibility;
				vec3 sun_tint = mix(vec3(1.0),vec3(1.6,0.55,0.22),sunset);
				result += attenuation*sun_tint*(BETA_R*density.x*rayleigh_phase+BETA_M*density.y*mie_phase)*step_length*0.52*illumination;
			}
		}
		transmission = exp(-BETA_R*view_depth.x-BETA_M*view_depth.y);
	}
	// Restore daylight brightness for observers in the lower atmosphere.
	// Fade this exposure adjustment out before orbit to retain the subtle rim.
	float observer_altitude = max(length(origin)-body_radius,0.0);
	float daylight = smoothstep(-0.06,0.25,dot(normalize(origin),sun_direction));
	float lower_air = 1.0-smoothstep(0.0,air_radius-body_radius,observer_altitude);
	return result * mix(1.0,3.0,daylight*lower_air) * atmosphere_scattering_exposure;
}

vec3 scatter_air_for(vec3 origin, vec3 direction, float max_distance, float body_radius, float air_radius, float density_scale, out vec3 transmission) {
	return scatter_air_steps(origin,direction,max_distance,body_radius,air_radius,density_scale,atmosphere_view_samples,atmosphere_light_samples,transmission);
}

vec2 air_density(float height) {
	return air_density_for(height,atmosphere_density_scale,AIR_RADIUS-BODY_RADIUS);
}

vec3 scatter_air(vec3 origin, vec3 direction, float max_distance, out vec3 transmission) {
	return scatter_air_for(origin,direction,max_distance,BODY_RADIUS,AIR_RADIUS,atmosphere_density_scale,transmission);
}
