extends RefCounted
## Local-frame, fixed-step rope and two-point cap. Camera rebasing never moves particles.
const SEGMENTS := 16
const LENGTH := 1.4
const CAP_LENGTH := 0.28
const STEP := 1.0 / 120.0
const ANCHOR := Vector3(-0.194, 0.4505, 0)
var points := PackedVector3Array()
var previous := PackedVector3Array()
var accumulator := 0.0
var acceleration := Vector3(0, -9.81, 0)
var air_velocity := Vector3.ZERO
var density := 1.225
var detached := false
var ground_normal := Vector3.UP
var ground_offset := -2.565
# A resting cord sleeps until its forces or ground change; 32 constraint
# passes at 120 Hz otherwise cost ~1.5 ms every frame after landing.
var sleeping := false
var _quiet_time := 0.0
var _rest_environment: Array = []

func reset(mouth: Vector3, axis: Vector3, velocity := Vector3.ZERO) -> void:
	detached = false
	points.resize(SEGMENTS + 2)
	previous.resize(SEGMENTS + 2)
	for i in range(SEGMENTS + 1):
		var t := float(i) / SEGMENTS
		points[i] = ANCHOR.lerp(mouth, t) + Vector3(0, -0.16 * sin(t * PI), 0)
		previous[i] = points[i] - velocity * STEP * t
	points[SEGMENTS + 1] = mouth + axis.normalized() * CAP_LENGTH
	previous[SEGMENTS + 1] = points[SEGMENTS + 1] - velocity * STEP
	accumulator = 0.0
	sleeping = false
	_quiet_time = 0.0

func advance(delta: float, pinned: bool, mouth: Vector3, axis: Vector3) -> void:
	# Bound catch-up work after stalls; normal 30/60/120 Hz frames use identical steps.
	var environment := [acceleration, air_velocity, density, ground_normal, ground_offset, detached]
	if sleeping:
		if not pinned and _same_environment(environment): return
		sleeping = false
		_quiet_time = 0.0
	accumulator += clampf(delta, 0, 0.1)
	while accumulator + 0.0000001 >= STEP:
		accumulator -= STEP
		_step(pinned, mouth, axis)
		if pinned:
			_quiet_time = 0.0
			continue
		var motion := 0.0
		for i in range(points.size()):
			motion = maxf(motion, points[i].distance_squared_to(previous[i]))
		# Sleep is part of the fixed-step simulation too. Sampling only the last
		# substep of a render frame changes which motion spikes reset quiet time.
		_quiet_time = _quiet_time + STEP if motion < 0.0000016 else 0.0
		if _quiet_time >= 0.5:
			sleeping = true
			previous = points.duplicate()
			_rest_environment = environment
			accumulator = 0.0
			break

func _same_environment(environment: Array) -> bool:
	return Vector3(environment[0]).distance_squared_to(_rest_environment[0]) < 0.0025 \
		and Vector3(environment[1]).distance_squared_to(_rest_environment[1]) < 0.0025 \
		and absf(float(environment[2]) - float(_rest_environment[2])) < 0.01 \
		and Vector3(environment[3]).is_equal_approx(_rest_environment[3]) \
		and absf(float(environment[4]) - float(_rest_environment[4])) < 0.001 \
		and environment[5] == _rest_environment[5]

func _weight(index: int, pinned: bool) -> float:
	if (index == 0 and not detached) or (pinned and index >= SEGMENTS): return 0.0
	return 2.5 if index >= SEGMENTS else 80.0

func _step(pinned: bool, mouth: Vector3, axis: Vector3) -> void:
	for i in range(0 if detached else 1, points.size()):
		if pinned and i >= SEGMENTS: continue
		var velocity := (points[i] - previous[i]) / STEP
		var relative_air := (air_velocity - velocity).limit_length(80.0)
		var drag := relative_air * relative_air.length() * density * (0.025 if i >= SEGMENTS else 0.055)
		var next := points[i] + velocity * exp(-0.4 * STEP) * STEP + (acceleration + drag).limit_length(150) * STEP * STEP
		previous[i] = points[i]
		points[i] = next
	if not detached: points[0] = ANCHOR
	if pinned:
		points[SEGMENTS] = mouth
		points[SEGMENTS + 1] = mouth + axis * CAP_LENGTH
		previous[SEGMENTS] = mouth
		previous[SEGMENTS + 1] = points[SEGMENTS + 1]
	for iteration in range(32):
		for i in range(SEGMENTS + 1):
			var difference := points[i + 1] - points[i]
			var distance := difference.length()
			var rest := CAP_LENGTH if i == SEGMENTS else LENGTH / SEGMENTS
			# Cord resists stretching, but is free to bend and go slack.
			if distance < 0.000001 or (i < SEGMENTS and distance <= rest): continue
			var wa := _weight(i, pinned)
			var wb := _weight(i + 1, pinned)
			if wa + wb == 0: continue
			var correction := difference * ((distance - rest) / distance / (wa + wb))
			points[i] += correction * wa
			points[i + 1] -= correction * wb
		for i in range(0 if detached else 1, points.size()):
			if _weight(i, pinned) == 0: continue
			_collide(i)
	# A global reach constraint prevents accumulated chain error under large gusts.
	if not pinned and not detached:
		var reach := points[SEGMENTS] - ANCHOR
		if reach.length() > LENGTH:
			var correction := reach.normalized() * (reach.length() - LENGTH)
			points[SEGMENTS] -= correction
			points[SEGMENTS + 1] -= correction
	if not detached: points[0] = ANCHOR

func _collide(index: int) -> void:
	# Conservative capsule/housing envelope keeps cord and cap outside the hull.
	var p := points[index]
	var padding := 0.17 if index >= SEGMENTS else 0.008
	if detached:
		var depth := padding - (p.dot(ground_normal) - ground_offset)
		if depth > 0:
			points[index] += ground_normal * depth
			previous[index] = previous[index].lerp(points[index], 0.35)
		return
	if p.y > ANCHOR.y + padding or p.y < -2.5: return
	var radius := (0.334 - p.y * (0.61 / 1.92) if p.y >= 0 else lerpf(0.32, 0.96, clampf(-p.y / 2.3, 0, 1))) + padding
	var radial := Vector3(p.x, 0, p.z)
	if radial.length() >= radius: return
	var outward := radial.normalized() if radial.length() > 0.00001 else Vector3.LEFT
	points[index] = Vector3(outward.x * radius, p.y, outward.z * radius)
