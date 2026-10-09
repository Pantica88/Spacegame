// Smooth envelope of the heated vessel, sampled by aerothermal_wake.gd: the
// largest hull radius per height and angle in the vessel's frame (Y along
// its axis). The wake follows it, and the heat halo extrudes along it.
uniform sampler2D hull_profile : filter_linear, repeat_enable;
uniform float hull_bottom = 0.0;
uniform float hull_top = 10.0;

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
