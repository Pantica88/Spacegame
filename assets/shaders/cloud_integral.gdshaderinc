// Common integration contract for the current spatial cloud shaders and a
// future RenderingDevice backend. Keep this include free of engine uniforms
// and shader-language hints so the same arithmetic can run in GLSL compute.
//
// Distances are kilometres along a normalized camera ray, not view-space Z.
// Depth describes extinction-weighted sample contributions, not an opaque
// surface. The existing march may represent several density taps by one point.
// Source light is in the current artistic, Compatibility-authored working
// space; it is not calibrated physical radiance or converted linear HDR.
#ifndef APHELION_CLOUD_INTEGRAL
#define APHELION_CLOUD_INTEGRAL

struct CloudDepthMoments {
	float weight;
	float origin_km;
	float mean_offset_km;
	float m2_km2;
	float last_distance_km;
};

struct CloudIntegral {
	vec3 light; // Accumulated source light multiplied by its extinction weight.
	float transmittance;
	float weighted_distance_km; // Original sum retained for legacy haze parity.
	float density_samples;
	bool traversed; // Distinguishes marched clear air from an early ray rejection.
	CloudDepthMoments depth;
};

CloudIntegral cloud_integral_empty() {
	CloudDepthMoments depth;
	depth.weight = 0.0;
	depth.origin_km = 0.0;
	depth.mean_offset_km = 0.0;
	depth.m2_km2 = 0.0;
	depth.last_distance_km = 0.0;
	CloudIntegral result;
	result.light = vec3(0.0);
	result.transmittance = 1.0;
	result.weighted_distance_km = 0.0;
	result.density_samples = 0.0;
	result.traversed = false;
	result.depth = depth;
	return result;
}

// Caller supplies opacity in [0, 1] and a nonnegative sample distance.
// Preserve the production light/transmittance arithmetic and its operation
// order. Depth measurement is opt-in until a renderer actually consumes it.
void cloud_integral_add(inout CloudIntegral result, vec3 source_light, float opacity, float distance_km) {
	float weight = result.transmittance * opacity;
	result.light += source_light * weight;
	result.weighted_distance_km += distance_km * weight;
#ifdef CLOUD_MEASURE_DEPTH
	if (weight > 0.0) {
		if (result.depth.weight <= 0.0) {
			result.depth.origin_km = distance_km;
		}
		// Weighted Welford around the first contributing distance avoids
		// subtracting huge squared depths for thin clouds viewed from orbit.
		float offset_km = distance_km - result.depth.origin_km;
		float total_weight = result.depth.weight + weight;
		float delta_km = offset_km - result.depth.mean_offset_km;
		result.depth.mean_offset_km += delta_km * (weight / total_weight);
		result.depth.m2_km2 += weight * delta_km * (offset_km - result.depth.mean_offset_km);
		result.depth.weight = total_weight;
		result.depth.last_distance_km = distance_km;
	}
#endif
	result.transmittance *= 1.0 - opacity;
}

bool cloud_depth_valid(CloudDepthMoments depth) {
	// A contribution at the camera (zero distance) is still valid. Very thin
	// clouds may contribute even when 1 - transmittance rounds to zero.
	return depth.weight > 0.0;
}

float cloud_depth_mean_km(CloudDepthMoments depth) {
	return cloud_depth_valid(depth) ? depth.origin_km + depth.mean_offset_km : 0.0;
}

float cloud_depth_variance_km2(CloudDepthMoments depth) {
	return cloud_depth_valid(depth) ? max(depth.m2_km2 / depth.weight, 0.0) : 0.0;
}

#endif
