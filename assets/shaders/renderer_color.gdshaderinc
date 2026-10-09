// Colour conventions of the renderer these shaders were tuned in.
//
// Godot 4.5's Compatibility renderer treats material colour as sRGB-encoded:
// it uploads source_color uniforms and samples textures without converting
// them, then turns ALBEDO, EMISSION and the sky's COLOR into linear light with
// the polynomial below, just before lighting and tonemapping
// (drivers/gles3/shaders/scene.glsl and sky.glsl). Forward+ takes those
// outputs as linear light already and decodes source_color inputs on the way
// in. Every custom shader here was tuned under Compatibility, so on other
// renderers they apply the same conversions themselves and keep that look.

// Godot's GLES3 srgb_to_linear() approximation. It is applied exactly as
// Compatibility does, to HDR values too, where it grows like a cubic.
vec3 compat_srgb_to_linear(vec3 color) {
	return color * (color * (color * 0.305306011 + 0.682171111) + 0.012522878);
}

// Exact sRGB transfer functions, matching the hardware conversion of sRGB
// render targets and the CPU conversion of source_color uniforms.
vec3 exact_linear_to_srgb(vec3 color) {
	vec3 c = max(color, vec3(0.0));
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
}

vec3 exact_srgb_to_linear(vec3 color) {
	vec3 c = max(color, vec3(0.0));
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

// A colour written to ALBEDO, EMISSION or sky COLOR.
vec3 material_output(vec3 color) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return color;
#else
	return compat_srgb_to_linear(color);
#endif
}

// A source_color uniform or texture sample, as these shaders' arithmetic
// expects it: still sRGB-encoded.
vec3 authored_color(vec3 color) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return color;
#else
	return exact_linear_to_srgb(color);
#endif
}

// Offscreen targets read back by another pass (the cloud passes) store what
// the shader wrote. Compatibility's sRGB encode cancels its decode of ALBEDO;
// Forward+ encodes linear light, so write the exact inverse.
vec3 stored_output(vec3 color) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return color;
#else
	return exact_srgb_to_linear(color);
#endif
}

// Godot's Filmic tonemapper (tonemap_inc.glsl) for a given white point.
vec3 filmic_tonemap(vec3 color, float white) {
	// A..F of the Uncharted 2 curve, with Godot's exposure bias of 2 baked in.
	const vec3 k_ab = vec3(0.22 * 4.0, 0.30 * 2.0, 0.10);
	const vec3 k_def = vec3(0.20, 0.01, 0.30);
	color = max(color, vec3(0.0));
	vec3 mapped = (color * (k_ab.x * color + k_ab.z * k_ab.y) + k_def.x * k_def.y)
		/ (color * (k_ab.x * color + k_ab.y) + k_def.x * k_def.z) - k_def.y / k_def.z;
	float mapped_white = (white * (k_ab.x * white + k_ab.z * k_ab.y) + k_def.x * k_def.y)
		/ (white * (k_ab.x * white + k_ab.y) + k_def.x * k_def.z) - k_def.y / k_def.z;
	return mapped / mapped_white;
}

// A hint_screen_texture sample as Compatibility provides it: the displayed,
// tonemapped sRGB image. Forward+ provides linear light before tonemapping,
// so encode it here. Assumes the flight Environment's tonemapping (Filmic,
// white 1.0, exposure 1.0; world_view.gd _make_environment).
vec3 displayed_screen_color(vec3 color) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return color;
#else
	return exact_linear_to_srgb(min(filmic_tonemap(color, 1.0), vec3(1.0)));
#endif
}

// Additive (blend_add) layers. Compatibility tonemaps each layer on its own,
// so one layer can add at most display white per channel, however hot its
// colour. Forward+ adds linear light: decoded HDR colours (the polynomial
// above grows like a cubic) then add without limit, overlaps overflow the
// buffer, and the red channel of fire saturates long before green, turning
// it pink. Cap each layer at linear 1.0, which Filmic with white 1.0
// displays as white, and alpha at 1 as the 8-bit target did. Set ALBEDO and
// ALPHA from the result.
vec4 additive_output(vec3 albedo, float alpha) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return vec4(albedo, alpha);
#else
	return vec4(min(compat_srgb_to_linear(albedo), vec3(1.0)), clamp(alpha, 0.0, 1.0));
#endif
}
