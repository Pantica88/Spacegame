shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform;
#include "res://assets/shaders/renderer_color.gdshaderinc"

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float airspeed = 0.0;
uniform float flow_phase = 0.0;
uniform vec3 local_flow = vec3(0.0, -1.0, 0.0);
uniform sampler2D hull_profile : filter_linear, repeat_enable;
uniform float hull_bottom = 0.0;
uniform float hull_top = 10.0;
varying float path_distance;
varying float exposure;
varying float air_contact;

float hash(float p) { return fract(sin(p * 127.1) * 43758.5453); }
float noise(float p) {
	float i = floor(p);
	float f = fract(p);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

float hull_radius(float y, float angle) {
	float row = clamp((y - hull_bottom) / (hull_top - hull_bottom), 0.0, 1.0);
	return textureLod(hull_profile, vec2(angle / 6.2831853 + 0.5 / 24.0, (row * 47.0 + 0.5) / 48.0), 0.0).r;
}

vec4 hull_surface(vec3 p) {
	float radial = max(length(p.xz), 0.001);
	float angle = atan(p.z, p.x);
	float radius = hull_radius(p.y, angle);
	float side = radial - radius;
	float cap = max(hull_bottom - p.y, p.y - hull_top);
	if (cap > side + 0.12) return vec4(0.0, p.y < hull_bottom ? -1.0 : 1.0, 0.0, cap);
	float dy = (hull_radius(p.y + 0.06, angle) - hull_radius(p.y - 0.06, angle)) / 0.12;
	float da = (hull_radius(p.y, angle + 0.10) - hull_radius(p.y, angle - 0.10)) / 0.20;
	vec3 normal = normalize(vec3(p.x / radial + da * p.z / (radial * radial), -dy, p.z / radial - da * p.x / (radial * radial)));
	vec3 cap_normal = vec3(0.0, p.y < (hull_bottom + hull_top) * 0.5 ? -1.0 : 1.0, 0.0);
	normal = normalize(mix(normal, cap_normal, smoothstep(-0.12, 0.12, cap - side)));
	return vec4(normal, max(side, cap));
}

void vertex() {
	// The fixed vertices store seeds and step indices. Trace them against the same
	// hull texture every frame: no attitude thresholds, mesh swaps or crossfades.
	vec3 point = VERTEX;
	vec3 radial = NORMAL;
	vec4 surface = hull_surface(point);
	exposure = 1.0 - smoothstep(0.20, 0.75, dot(surface.xyz, local_flow));
	air_contact = smoothstep(0.05, 0.75, -dot(surface.xyz, local_flow));
	// Keep the fast advection, but limit the visible wake to half its former length.
	float step_length = mix(0.15, 0.31, clamp(airspeed / 1500.0, 0.0, 1.0));
	int steps = int(UV.y + 0.5);
	vec3 tangent = local_flow;
	path_distance = 0.0;
	for (int i = 0; i < 36; i++) {
		if (i >= steps) break;
		// Once safely downstream, the rest of the path is free flow.
		if (surface.w > 1.6 && dot(surface.xyz, local_flow) > 0.15) {
			float remaining = float(steps - i) * step_length;
			point += local_flow * remaining;
			path_distance += remaining;
			tangent = local_flow;
			break;
		}
		float influence = exp(-max(surface.w, 0.0) * 2.5);
		vec3 velocity = local_flow - surface.xyz * min(dot(local_flow, surface.xyz), 0.0) * influence;
		velocity += radial * 0.25 * influence;
		vec3 before = point;
		point += normalize(velocity) * step_length;
		for (int correction = 0; correction < 2; correction++) {
			surface = hull_surface(point);
			if (surface.w >= 0.07) break;
			point += surface.xyz * (0.075 - surface.w);
		}
		tangent = normalize(point - before);
		path_distance += length(point - before);
	}
	// Expand ribbons in view space so their width stays stable as the camera orbits.
	vec3 view_point = (MODELVIEW_MATRIX * vec4(point, 1.0)).xyz;
	vec3 view_tangent = normalize((MODELVIEW_MATRIX * vec4(tangent, 0.0)).xyz);
	vec3 side = cross(view_tangent, normalize(-view_point));
	side /= max(length(side), 0.001);
	float t = UV2.x;
	float root_fire = air_contact * (1.0 - smoothstep(0.05, 0.30, t));
	float width = (mix(0.055, 0.24, t) + root_fire * 0.12) * (0.65 + min(airspeed / 1000.0, 2.0) * 0.35);
	float flutter = sin(path_distance * 2.0 - flow_phase * 0.8 + UV2.y * 23.0);
	VERTEX = view_point + side * (UV.x * width + flutter * t * t * 0.32);
}

void fragment() {
	float t = UV2.x;
	float travel = path_distance - flow_phase + UV2.y * 17.0;
	float turbulence = noise(travel * 1.4) * 0.65 + noise(travel * 4.0 + UV2.y) * 0.35;
	float packets = smoothstep(0.40, 0.86, turbulence);
	float edge = exp(-UV.x * UV.x * 4.5) * (1.0 - smoothstep(0.7, 1.0, abs(UV.x)));
	float root_fire = air_contact * (1.0 - smoothstep(0.05, 0.30, t));
	float fade = mix(air_contact * 0.14, 1.0, smoothstep(0.0, 0.035, t)) * pow(max(1.0 - t, 0.0), 1.4) * (1.0 - smoothstep(0.65, 1.0, t));
	float core = pow(max(0.0, 1.0 - abs(UV.x)), 7.0) * packets;
	vec3 color = mix(vec3(1.0, 0.40, 0.07), vec3(1.0, 0.055, 0.004), smoothstep(0.0, 0.55, t));
	color = mix(color, vec3(1.0, 0.85, 0.48), core * (1.0 - t) * 0.55);
	ALBEDO = color * (1.5 + core * 2.0);
	ALPHA = exposure * strength * fade * edge * (0.08 + packets * 0.72 + root_fire * (0.20 + packets * 0.70));
	vec4 added = additive_output(ALBEDO, ALPHA);
	ALBEDO = added.rgb;
	ALPHA = added.a;
}
