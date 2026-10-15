shader_type spatial;
// Lays the half-resolution clouds from cloud_render_pass.gd over the scene in
// the transparent pass: after the sun and the ocean (render priority 1),
// before nearby exhaust and heat. A screen triangle; cloud_layer.gd owns it.
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/atmosphere.gdshaderinc"
#include "res://assets/shaders/renderer_color.gdshaderinc"

// Premultiplied cloud light and transmittance (the resolved display target).
uniform sampler2D cloud_light : filter_nearest, repeat_disable;
// Per texel: first contribution, mean contribution and end of the march (km),
// and 1 where scene geometry ended it. Negative front/mean: no cloud.
uniform sampler2D cloud_depth : filter_nearest, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform bool cloud_ready = false;
// F9's cost view: the march writes sample-count colours instead of light.
uniform bool cost_view = false;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

// Cloud for a pixel whose geometry lies scene_km away (1e9 for sky), from
// the four nearest half-resolution texels: premultiplied light and
// transmittance, and in mean_km the cloud's distance. A texel counts only if
// it describes this depth: its march stopped where this pixel's geometry is,
// or all its cloud lies in front of or behind that geometry.
vec4 upsample(vec2 uv, float scene_km, float depth_step, out float mean_km) {
	// A half-resolution texel spans two pixels, so its depth may differ from
	// this pixel's by a couple of the screen's own depth steps: grazing
	// terrain at the horizon changes fast from pixel to pixel.
	float tolerance = scene_km * 0.03 + depth_step * 3.0 + 0.003;
	ivec2 size = textureSize(cloud_light, 0);
	vec2 position = uv * vec2(size) - 0.5;
	vec2 base = floor(position);
	vec2 f = position - base;
	vec4 total = vec4(0.0);
	float weight = 0.0;
	float distance_sum = 0.0;
	float distance_weight = 0.0;
	vec4 nearest = vec4(0.0, 0.0, 0.0, 1.0);
	float nearest_error = 1e20;
	float nearest_mean = -1.0;
	for (int i = 0; i < 4; i++) {
		ivec2 offset = ivec2(i & 1, i >> 1);
		ivec2 texel = clamp(ivec2(base) + offset, ivec2(0), size - 1);
		vec4 c = texelFetch(cloud_light, texel, 0);
		vec4 d = texelFetch(cloud_depth, texel, 0);
		vec2 corner = mix(1.0 - f, f, vec2(offset));
		float bilinear = corner.x * corner.y + 1e-4;
		bool clipped = d.w > 0.5;
		// The light is averaged over frames but the depths are this frame's,
		// so judge by where the march stopped, which does not flicker; the
		// front of the cloud only decides the clear-cut case of geometry well
		// in front of all of it (a craft before a distant bank).
		bool matches;
		if (scene_km < (d.x >= 0.0 ? d.x : d.z) * 0.9 - 0.002) {
			matches = true;
			c = vec4(0.0, 0.0, 0.0, 1.0);
		} else if (clipped) {
			matches = abs(scene_km - d.z) <= tolerance;
		} else {
			matches = scene_km >= d.z - tolerance;
		}
		if (matches) {
			total += c * bilinear;
			weight += bilinear;
			if (d.y > 0.0 && c.a < 1.0) {
				distance_sum += d.y * bilinear * (1.0 - c.a);
				distance_weight += bilinear * (1.0 - c.a);
			}
		} else if (clipped && abs(scene_km - d.z) < nearest_error) {
			// Geometry thinner than a texel: the closest march is the best guess.
			nearest_error = abs(scene_km - d.z);
			nearest = c;
			nearest_mean = d.y;
		}
	}
	if (weight <= 0.0) {
		mean_km = nearest_mean > 0.0 ? nearest_mean : min(scene_km, 50.0);
		return nearest;
	}
	mean_km = distance_weight > 0.0 ? distance_sum / distance_weight : min(scene_km, 50.0);
	return total / weight;
}

void fragment() {
	if (!cloud_ready) { discard; }
	vec2 uv = SCREEN_UV;
	if (cost_view) {
		ivec2 size = textureSize(cloud_light, 0);
		ALBEDO = texelFetch(cloud_light, clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1), 0).rgb;
		ALPHA = 1.0;
	} else {
		float raw_depth = texture(scene_depth, uv).r;
		vec4 surface = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
		float scene_km = raw_depth <= 0.0 ? 1e9 : length(surface.xyz / surface.w) * 0.001;
		float depth_step = raw_depth <= 0.0 ? 0.0 : min(fwidth(scene_km), scene_km);
		float mean_km;
		vec4 cloud = upsample(uv, scene_km, depth_step, mean_km);
		float alpha = clamp(1.0 - cloud.a, 0.0, 1.0);
		if (alpha < 0.002) { discard; }
		// Air between the camera and the cloud, as the sky and terrain apply
		// it: they add it in the shaders' encoded colour and decode the sum
		// (renderer_color.gdshaderinc), so distant cloud fades into the same haze.
		vec4 near_point = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
		vec3 ray = normalize(mat3(INV_VIEW_MATRIX) * (near_point.xyz / near_point.w));
		vec3 transmission;
		vec3 air = scatter_air(camera_planet_km, ray, mean_km, transmission);
		vec3 light = cloud.rgb / alpha;
		ALBEDO = compat_srgb_to_linear(air + transmission * exact_linear_to_srgb(light)) * alpha;
		ALPHA = alpha;
	}
}
