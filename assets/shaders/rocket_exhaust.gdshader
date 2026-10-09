shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform float phase = 0.0;
uniform float thrust_intensity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// U wraps around the hollow nozzle; V flows from its lip downstream.
	float t = UV.y;
	float angle = UV.x * 6.28318530718;
	float clock = TIME * 3.5 + phase + COLOR.r * 4.7;
	float tail = pow(max(1.0 - t, 0.0), 1.7) * (1.0 - smoothstep(0.8, 1.0, t));
	// Integer angular frequencies keep the circumference seamless.
	float strand = pow(max(sin(angle * 37.0 + sin(t * 9.0 - clock) * 1.6 + phase), 0.0), 9.0);
	float fine = pow(max(sin(angle * 67.0 - t * 5.0 + sin(clock + t * 13.0)), 0.0), 14.0);
	float flow = 0.65 + 0.35 * sin(t * 39.0 - clock * 9.0 + angle * 7.0);
	float core = exp(-t * 20.0);
	// A soft near-nozzle transition avoids a bright hard seam at the bell.
	float emergence = mix(0.45, 1.0, smoothstep(0.0, 0.04, t));
	float jet = tail * (0.18 + strand * 0.8 + fine * flow * 0.4);
	float outer_layer = step(0.99, COLOR.r);
	vec3 jet_color = mix(vec3(0.13, 0.85, 1.0), vec3(1.0, 0.035, 0.015), outer_layer);
	vec3 core_color = mix(vec3(0.8, 0.98, 1.0), vec3(1.0, 0.10, 0.045), outer_layer);
	vec3 glow = jet_color * jet;
	glow += vec3(1.0, 0.22, 0.16) * exp(-t * 7.0) * 0.06;
	glow += core_color * core * 2.2;
	ALBEDO = glow;
	ALPHA = COLOR.a * thrust_intensity * emergence * (1.0 - smoothstep(0.72, 1.0, t));
}
