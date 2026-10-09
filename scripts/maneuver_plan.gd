extends RefCounted
## Render-independent, single-body impulsive maneuver prediction. SI units.
const Physics = preload("res://scripts/physics_math.gd")
const MAX_SECONDS := 21600.0
const SAMPLES := 480

var epoch := -1.0
var components := Vector3.ZERO # Prograde, normal, radial-out, evaluated at epoch.
var result: Dictionary = {}

func clear() -> void:
	epoch = -1.0
	components = Vector3.ZERO
	result.clear()

## Exact Kepler propagation for elliptical and hyperbolic non-radial coasts.
## Near-parabolic and degenerate trajectories return unavailable, never NaNs.
static func propagate(radial: Vector3, velocity: Vector3, seconds: float, mu: float, radius: float) -> Dictionary:
	if not radial.is_finite() or not velocity.is_finite() or not is_finite(seconds) or seconds < 0.0 or mu <= 0.0 or radial.length() <= radius: return {}
	var elements := Physics.orbital_elements(radial, velocity, mu, radius)
	if not elements.orbit_plane_defined or not is_finite(elements.semi_major_axis): return {}
	var e: float = elements.eccentricity
	var a: float = elements.semi_major_axis
	var axis: Vector3 = Vector3(elements.eccentricity_vector).normalized() if e > 0.00001 else radial.normalized()
	var side: Vector3 = Vector3(elements.normal).cross(axis).normalized()
	var n := sqrt(mu / pow(absf(a), 3.0))
	var p: Vector3
	var v: Vector3
	if elements.bound_orbit:
		var minor := sqrt(maxf(0.0, 1.0 - e * e))
		var initial := atan2(radial.dot(side) / (a * minor), radial.dot(axis) / a + e)
		var mean := wrapf(initial - e * sin(initial) + n * seconds, -PI, PI)
		var low := -PI
		var high := PI
		for iteration in range(48):
			var mid := (low + high) * 0.5
			if mid - e * sin(mid) < mean: low = mid
			else: high = mid
		var anomaly := (low + high) * 0.5
		p = axis * (a * (cos(anomaly) - e)) + side * (a * minor * sin(anomaly))
		var rate := n / (1.0 - e * cos(anomaly))
		v = axis * (-a * sin(anomaly) * rate) + side * (a * minor * cos(anomaly) * rate)
	else:
		var length := -a
		var minor := sqrt(e * e - 1.0)
		var initial := asinh(radial.dot(side) / (length * minor))
		var mean := e * sinh(initial) - initial + n * seconds
		var low := -50.0
		var high := 50.0
		for iteration in range(64):
			var mid := (low + high) * 0.5
			if e * sinh(mid) - mid < mean: low = mid
			else: high = mid
		var anomaly := (low + high) * 0.5
		p = axis * (length * (e - cosh(anomaly))) + side * (length * minor * sinh(anomaly))
		var rate := n / (e * cosh(anomaly) - 1.0)
		v = axis * (-length * sinh(anomaly) * rate) + side * (length * minor * cosh(anomaly) * rate)
	if not p.is_finite() or not v.is_finite(): return {}
	return {"position": p, "velocity": v}

static func horizon(radial: Vector3, velocity: Vector3, mu: float, radius: float) -> float:
	var elements := Physics.orbital_elements(radial, velocity, mu, radius)
	return minf(MAX_SECONDS, float(elements.orbital_period)) if elements.bound_orbit else minf(MAX_SECONDS, maxf(600.0, radial.length() / maxf(velocity.length(), 1.0) * 8.0))

static func timed_path(radial: Vector3, velocity: Vector3, mu: float, radius: float, duration: float = -1.0) -> Dictionary:
	var points := PackedVector3Array()
	var times := PackedFloat64Array()
	if propagate(radial, velocity, 0.0, mu, radius).is_empty(): return {"points": points, "times": times}
	var end := horizon(radial, velocity, mu, radius) if duration < 0.0 else duration
	for index in range(SAMPLES + 1):
		var time := end * float(index) / SAMPLES
		var sample := propagate(radial, velocity, time, mu, radius)
		if sample.is_empty(): break
		points.append(sample.position)
		times.append(time)
		if Vector3(sample.position).length() <= radius: break
	return {"points": points, "times": times}

## Full-throttle estimate for currently ignited liquid engines, with depletion
## events for separate tank feeds. Does not assume staging or booster ignition.
static func burn_estimate(mass: float, engines: Array, requested: float) -> Dictionary:
	var available := 0.0
	var elapsed := 0.0
	var needed_fuel := 0.0
	var duration := 0.0 if requested <= 0.0001 else INF
	var working := engines.duplicate(true)
	while not working.is_empty():
		var thrust := 0.0
		var flow := 0.0
		var interval := INF
		for engine in working:
			var rate: float = float(engine.thrust) / (float(engine.isp) * Physics.STANDARD_GRAVITY)
			flow += rate
			thrust += float(engine.thrust)
			interval = minf(interval, float(engine.fuel) / rate)
		if flow <= 0.0 or interval <= 0.0 or not is_finite(interval): break
		var fuel := minf(flow * interval, maxf(0.0, mass - 0.001))
		var exhaust := thrust / flow
		var delta_v := exhaust * log(mass / (mass - fuel))
		if not is_finite(duration) and requested <= available + delta_v:
			var burn_fuel := mass * (1.0 - exp(-(requested - available) / exhaust))
			duration = elapsed + burn_fuel / flow
			needed_fuel += burn_fuel
		elif not is_finite(duration): needed_fuel += fuel
		available += delta_v
		elapsed += interval
		mass -= fuel
		for engine in working:
			engine.fuel = maxf(0.0, float(engine.fuel) - interval * float(engine.thrust) / (float(engine.isp) * Physics.STANDARD_GRAVITY))
		working = working.filter(func(engine): return float(engine.fuel) > 0.0001)
	return {"available": available, "duration": duration, "fuel": needed_fuel, "sufficient": is_finite(duration)}

func evaluate(radial: Vector3, velocity: Vector3, now: float, mu: float, radius: float) -> Dictionary:
	result = {}
	if epoch < now or epoch - now > MAX_SECONDS: return result
	var at_node := propagate(radial, velocity, epoch - now, mu, radius)
	if at_node.is_empty() or Vector3(at_node.position).length() <= radius: return result
	var basis := Physics.orbital_elements(at_node.position, at_node.velocity, mu, radius)
	if not basis.orbit_plane_defined: return result
	var burn: Vector3 = Vector3(basis.prograde) * components.x + Vector3(basis.normal) * components.y + Vector3(basis.radial_out) * components.z
	var after: Vector3 = Vector3(at_node.velocity) + burn
	result = {"position": at_node.position, "velocity": at_node.velocity, "burn": burn, "after_velocity": after,
		"elements": Physics.orbital_elements(at_node.position, after, mu, radius)}
	return result

static func time_to_point(radial: Vector3, velocity: Vector3, point: Vector3, mu: float, radius: float) -> float:
	var elements := Physics.orbital_elements(radial, velocity, mu, radius)
	if not elements.orbit_plane_defined or not is_finite(elements.semi_major_axis): return -1.0
	var e: float = elements.eccentricity
	var a: float = elements.semi_major_axis
	var axis: Vector3 = Vector3(elements.eccentricity_vector).normalized() if e > 0.00001 else radial.normalized()
	var side: Vector3 = Vector3(elements.normal).cross(axis).normalized()
	var means: Array[float] = []
	for position in [radial, point]:
		var angle := atan2(position.dot(side), position.dot(axis))
		if elements.bound_orbit:
			var anomaly := atan2(sqrt(1.0 - e * e) * sin(angle), e + cos(angle))
			means.append(anomaly - e * sin(anomaly))
		else:
			var denominator := 1.0 + e * cos(angle)
			if denominator <= 0.0: return -1.0
			var anomaly := asinh(sqrt(e * e - 1.0) * sin(angle) / denominator)
			means.append(e * sinh(anomaly) - anomaly)
	var difference: float = means[1] - means[0]
	if elements.bound_orbit: difference = fposmod(difference, TAU)
	return difference / sqrt(mu / pow(absf(a), 3.0))
