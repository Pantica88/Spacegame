extends RefCounted
## Solar dimensions in metres, in the flight simulation frame.
# The 900 km sun is 1.5 times the current 600 km home planet's radius.
const RADIUS := 900000.0
const DISTANCE := 13599840256.0
const POSITION := Vector3(0.0, -600000.0, 0.0) + Vector3(-0.4750648667, 0.443393875, 0.7601037833) * DISTANCE

static func segment_hit(start: Vector3, finish: Vector3) -> float:
	var offset := start - POSITION
	if offset.length_squared() <= RADIUS * RADIUS: return 0.0
	var travel := finish - start
	var a := travel.length_squared()
	if a < 0.000001: return -1.0
	var b := offset.dot(travel)
	var discriminant := b*b - a*(offset.length_squared()-RADIUS*RADIUS)
	if discriminant < 0.0: return -1.0
	var fraction := (-b-sqrt(discriminant))/a
	return fraction if fraction >= 0.0 and fraction <= 1.0 else -1.0

## Parent-relative moon orbit, in metres in the shared flight frame.
static func moon_offset(definition: Resource, time: float) -> Vector3:
	var radial := -(POSITION - Vector3(0.0, -600000.0, 0.0)).normalized()
	var tangent := radial.cross(Vector3.UP).normalized()
	var phase := TAU * (float(definition.orbit_phase) + time / (86400.0 * maxf(0.001, float(definition.orbit_period_days))))
	return (radial * cos(phase) + tangent * sin(phase)) * float(definition.moon_orbit_distance_km) * 1000.0
