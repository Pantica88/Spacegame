extends RefCounted
const Physics = preload("res://scripts/physics_math.gd")

## Compare against the actual triangle plane. A float32 centroid constructed
## at 600 km can be a whole coordinate step off the plane before a query runs.
static func plane_radius(a: Vector3, b: Vector3, c: Vector3, radial: Vector3, rotation: Basis) -> float:
	var normal := (b - a).cross(c - a).normalized()
	var direction := (rotation.transposed() * radial).normalized()
	return Physics.dot_double(normal, a) / Physics.dot_double(normal, direction) * sqrt(Physics.dot_double(direction, direction))

static func plane_fraction(a: Vector3, b: Vector3, c: Vector3, start: Vector3, finish: Vector3) -> float:
	var normal := (b - a).cross(c - a).normalized()
	return Physics.dot_double(normal, a - start) / Physics.dot_double(normal, finish - start)
