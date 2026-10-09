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
