shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, world_vertex_coords;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float flow_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 air_direction = vec3(0.0);
uniform vec3 hull_origin = vec3(0.0);
uniform float flow_phase = 0.0;
uniform float airspeed = 0.0;
uniform float layer = 0.0;
varying vec3 hull_normal;
varying vec3 hull_position;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i+vec3(1,0,0)), f.x), mix(hash(i+vec3(0,1,0)), hash(i+vec3(1,1,0)), f.x), f.y), mix(mix(hash(i+vec3(0,0,1)), hash(i+vec3(1,0,1)), f.x), mix(hash(i+vec3(0,1,1)), hash(i+vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	hull_normal = normalize(NORMAL);
	hull_position = VERTEX - hull_origin;
	float front = max(dot(hull_normal, air_direction), 0.0);
	float contact = smoothstep(0.05, 0.75, front);
	vec3 drifting = hull_position * 4.0 + air_direction * flow_phase * 1.5;
	float tongues = smoothstep(0.32, 0.76, noise(drifting + vec3(layer * 3.0)));
	vec3 tangent = -air_direction + hull_normal * dot(hull_normal, air_direction);
	float ripple = sin(dot(hull_position, air_direction) * 9.0 + flow_phase * 3.0);
	VERTEX += hull_normal * (0.045 + layer * 0.11 + front * 0.07 + contact * tongues * (0.10 + layer * 0.12) + ripple * 0.012) * intensity;
	VERTEX += tangent * (0.06 + layer * 0.16 + contact * tongues * 0.14) * intensity * flow_strength;
	// Sweep the raised flame tips downstream in world space, independent of attitude.
	VERTEX -= air_direction * tongues * (0.10 + layer * 0.22) * (0.4 + contact * 0.6) * intensity * flow_strength;
}

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	float windward = max(dot(normalize(hull_normal), air_direction), 0.0);
	float along = dot(hull_position, air_direction);
	vec3 transverse = hull_position - air_direction * along;
	vec3 advected = transverse * 6.0 + air_direction * (along * 1.1 + flow_phase * 1.1);
	float turbulent = noise(advected) * 0.65 + noise(advected * 2.7 + vec3(layer * 7.0)) * 0.35;
	float filaments = smoothstep(0.36, 0.80, turbulent);
	float bow = pow(windward, 4.0) * 0.55;
	// Denser moving fire where air meets the hull; sheltered faces stay thin.
	float contact = smoothstep(0.05, 0.75, windward);
	float contact_fire = contact * (0.18 + filaments * 1.1);
	float brightness = bow + filaments * (0.3 + rim) + contact_fire;
	vec3 fire = mix(vec3(1.0, 0.10, 0.006), vec3(1.0, 0.65, 0.19), windward);
	fire = mix(fire, vec3(1.0, 0.9, 0.65), bow * filaments);
	ALBEDO = fire * (1.8 + brightness);
	ALPHA = intensity * flow_strength * brightness * mix(0.7, 0.35, layer) * (0.45 + rim * 0.55);
}
