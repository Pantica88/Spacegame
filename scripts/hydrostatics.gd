extends RefCounted
## Floating rigid-body hydrostatics for a splashed-down vessel.
## The hull is a cloud of volume samples. Each carries buoyancy and water drag
## at its own position, so draft, heel, righting moment and capsize all follow
## from the vessel's mass distribution rather than a fixed waterline.

const RecoveryHull = preload("res://scripts/recovery_hull.gd")
const WATER_DENSITY := 1025.0
const DRAG_COEFFICIENT := 1.0
## Wave-radiation damping per second, scaled by displaced mass. Quadratic drag
## vanishes at low speed; this lets small bobbing and rocking die out.
const RADIATION_DAMPING := 1.5
## Water a hull must push aside to rise or sink, as a share of displaced mass,
## and the extra wave-making damping of that vertical motion. Without them a
## splashed-down capsule sprang clean out of the water and bobbed for seconds.
const HEAVE_ADDED_MASS := 1.0
const HEAVE_DAMPING := 7.0
const SLICE_LENGTH := 0.75
const MAX_SUBSTEP := 1.0 / 60.0
const MIN_SUBSTEP := 1.0 / 4000.0
# A centre sample (1/4 of the slice) plus four ring samples at sqrt(2/3) r
# reproduce each slice's volume and its waterplane second moment, which sets
# the metacentric height and therefore whether the vessel rights or capsizes.
const RING_RADIUS := 0.8164966
const RING_COUNT := 4


## shapes: {bottom, top, radius, lateral?, profile?} cylinders along local +Y.
## profile uses the recovery capsule's lathed outline from its base upward.
static func hull(shapes: Array) -> Dictionary:
	var points := PackedVector3Array()
	var volumes := PackedFloat32Array()
	var faces := PackedFloat32Array()
	var sides := PackedFloat32Array()
	var extents := PackedVector2Array()
	for shape in shapes:
		var bottom: float = shape.bottom
		var length: float = float(shape.top) - bottom
		if length <= 0.0: continue
		var count := clampi(ceili(length / SLICE_LENGTH), 2, 24)
		var thickness := length / count
		var lateral: Vector3 = shape.get("lateral", Vector3.ZERO)
		for k in range(count):
			var y := bottom + (k + 0.5) * thickness
			var radius: float = RecoveryHull.radius_at(y - bottom + RecoveryHull.BOTTOM) if shape.get("profile", false) else float(shape.radius)
			var disk := PI * radius * radius
			# Only the end slices present a face to flow along the axis.
			var face := disk if k == 0 or k == count - 1 else 0.0
			for j in range(RING_COUNT + 1):
				var weight := 0.25 if j == 0 else 0.75 / RING_COUNT
				var angle := TAU * (j - 1) / RING_COUNT
				var offset := Vector3.ZERO if j == 0 else Vector3(cos(angle), 0.0, sin(angle)) * radius * RING_RADIUS
				points.append(lateral + Vector3(0.0, y, 0.0) + offset)
				volumes.append(disk * thickness * weight)
				faces.append(face * weight)
				sides.append(2.0 * radius * thickness * weight)
				extents.append(Vector2(thickness, radius))
	return {"points": points, "volumes": volumes, "faces": faces, "sides": sides, "extents": extents}


static func volume(hull_samples: Dictionary) -> float:
	var total := 0.0
	for value in hull_samples.volumes: total += value
	return total


## Advances a floating body by dt. The water is at rest in this frame and its
## surface is the plane through the origin with normal `up`.
## body: position and velocity of the centre of mass, orientation, angular
## velocity in local axes, mass, diagonal local inertia, and local centre.
## Writes displaced_mass and draft (deepest hull point below the surface).
static func step(body: Dictionary, hull_samples: Dictionary, up: Vector3, gravity: float, dt: float) -> void:
	var remaining := dt
	var mass := maxf(float(body.mass), 1.0)
	var inertia: Vector3 = Vector3(body.inertia).max(Vector3.ONE)
	while remaining > 0.0000001:
		var load := loads(body, hull_samples, up, gravity)
		# Explicit drag must not reverse a sample's motion within one substep.
		var rate := maxf(float(load.linear_damping) / mass, float(load.angular_damping) / minf(inertia.x, minf(inertia.y, inertia.z)))
		var h := clampf(0.7 / maxf(rate, 0.000001), MIN_SUBSTEP, MAX_SUBSTEP)
		h = minf(h, remaining)
		var basis: Basis = body.orientation
		var acceleration := Vector3(load.force) / mass - up * gravity
		# Entrained water shares only the vertical acceleration.
		acceleration -= up * acceleration.dot(up) * float(load.added_mass) / (mass + float(load.added_mass))
		body.velocity = Vector3(body.velocity) + acceleration * h
		var omega: Vector3 = Vector3(body.angular_velocity) + (basis.transposed() * Vector3(load.torque)) / inertia * h
		if omega.length() > 0.000001:
			basis = (basis * Basis(omega.normalized(), omega.length() * h)).orthonormalized()
		body.orientation = basis
		body.angular_velocity = omega
		body.position = Vector3(body.position) + Vector3(body.velocity) * h
		remaining -= h
	var final := loads(body, hull_samples, up, gravity)
	body.displaced_mass = final.displaced_mass
	body.draft = final.draft


static func loads(body: Dictionary, hull_samples: Dictionary, up: Vector3, gravity: float) -> Dictionary:
	var basis: Basis = body.orientation
	var center: Vector3 = body.center
	var position: Vector3 = body.position
	var velocity: Vector3 = body.velocity
	var omega: Vector3 = basis * Vector3(body.angular_velocity)
	var axis := basis.y
	var cosine := absf(axis.dot(up))
	var sine := sqrt(maxf(0.0, 1.0 - cosine * cosine))
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	var displaced := 0.0
	var draft := -INF
	var linear_damping := 0.0
	var angular_damping := 0.0
	var points: PackedVector3Array = hull_samples.points
	var volumes: PackedFloat32Array = hull_samples.volumes
	var faces: PackedFloat32Array = hull_samples.faces
	var sides: PackedFloat32Array = hull_samples.sides
	var extents: PackedVector2Array = hull_samples.extents
	for i in range(points.size()):
		var arm := basis * (points[i] - center)
		var depth := -(position + arm).dot(up)
		# Vertical half-extent of this sample's share of the slice.
		var half := maxf(0.5 * (cosine * extents[i].x + sine * extents[i].y), 0.02)
		draft = maxf(draft, depth + half)
		if depth + half <= 0.0: continue
		var wet := minf((depth + half) / (2.0 * half), 1.0)
		var submerged := volumes[i] * wet
		displaced += WATER_DENSITY * submerged
		var sample_force := up * (WATER_DENSITY * gravity * submerged)
		var flow := velocity + omega.cross(arm)
		var speed := flow.length()
		var coefficient := RADIATION_DAMPING * WATER_DENSITY * submerged
		var heave := HEAVE_DAMPING * WATER_DENSITY * submerged
		if speed > 0.000001:
			var along := absf(axis.dot(flow) / speed)
			var area := faces[i] * along + sides[i] * sqrt(maxf(0.0, 1.0 - along * along))
			coefficient += 0.5 * WATER_DENSITY * DRAG_COEFFICIENT * area * wet * speed
		sample_force -= flow * coefficient + up * (flow.dot(up) * heave)
		linear_damping += coefficient + heave
		angular_damping += (coefficient + heave) * arm.length_squared()
		force += sample_force
		torque += arm.cross(sample_force)
	return {"force": force, "torque": torque, "displaced_mass": displaced, "added_mass": displaced * HEAVE_ADDED_MASS, "draft": maxf(draft, 0.0), "linear_damping": linear_damping, "angular_damping": angular_damping}
