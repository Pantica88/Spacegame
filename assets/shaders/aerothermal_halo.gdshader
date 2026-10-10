shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, world_vertex_coords;
#include "res://assets/shaders/renderer_color.gdshaderinc"
#include "res://assets/shaders/aerothermal_hull.gdshaderinc"

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float flow_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 air_direction = vec3(0.0);
uniform vec3 hull_origin = vec3(0.0);
uniform float flow_phase = 0.0;
uniform float airspeed = 0.0;
uniform float layer = 0.0;
// World to the vessel frame of the hull profile. Until a profile is shared,
// shells extrude along the mesh normals.
uniform mat4 hull_to_local;
uniform bool hull_profile_ready = false;
varying vec3 hull_normal;
varying vec3 shell_normal;
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
	// Extrude along the vessel's smooth envelope, which depends on position
	// alone. Hard-edged meshes split their vertices with one normal per face;
	// pushed along those, the shell tore apart at every edge and small parts
	// (the parachute's nose cap) showed as rings of separate dashes.
	shell_normal = hull_normal;
	if (hull_profile_ready) {
		vec3 local_normal = hull_surface((hull_to_local * vec4(VERTEX, 1.0)).xyz).xyz;
		shell_normal = normalize(transpose(mat3(hull_to_local)) * local_normal);
	}
	float front = max(dot(shell_normal, air_direction), 0.0);
	float contact = smoothstep(0.05, 0.75, front);
	vec3 drifting = hull_position * 4.0 + air_direction * flow_phase * 1.5;
	float tongues = smoothstep(0.32, 0.76, noise(drifting + vec3(layer * 3.0)));
	vec3 tangent = -air_direction + shell_normal * dot(shell_normal, air_direction);
	float ripple = sin(dot(hull_position, air_direction) * 9.0 + flow_phase * 3.0);
	VERTEX += shell_normal * (0.045 + layer * 0.11 + front * 0.07 + contact * tongues * (0.10 + layer * 0.12) + ripple * 0.012) * intensity;
	VERTEX += tangent * (0.06 + layer * 0.16 + contact * tongues * 0.14) * intensity * flow_strength;
	// Sweep the raised flame tips downstream in world space, independent of attitude.
	VERTEX -= air_direction * tongues * (0.10 + layer * 0.22) * (0.4 + contact * 0.6) * intensity * flow_strength;
}

void fragment() {
	float rim = pow(max(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0), 1.6);
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
	// Faces turned across the envelope (collar walls, rib and bolt sides)
	// would glow edge-on as thin bright rings; the plasma follows the envelope.
	float along_envelope = smoothstep(0.05, 0.45, dot(normalize(hull_normal), normalize(shell_normal)));
	ALPHA = intensity * flow_strength * brightness * mix(0.7, 0.35, layer) * (0.45 + rim * 0.55) * along_envelope;
	vec4 added = additive_output(ALBEDO, ALPHA);
	ALBEDO = added.rgb;
	ALPHA = added.a;
}
