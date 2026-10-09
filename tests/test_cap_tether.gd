extends SceneTree
const Rope = preload("res://scripts/cap_tether.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func make_rope():
	var rope = Rope.new()
	rope.reset(Vector3(-1.1, 0.55, 0), Vector3.LEFT, Vector3(-0.8, 0.6, 0.25))
	return rope
func _initialize() -> void:
	var rope = make_rope()
	var initial: Vector3 = rope.points[Rope.SEGMENTS]
	for frame in range(600):
		rope.advance(1.0 / 60.0, false, Vector3.ZERO, Vector3.UP)
		check(rope.points[0] == Rope.ANCHOR, "Root must remain pinned")
		for p in rope.points: check(p.is_finite(), "Physics must remain finite")
	check(rope.points[Rope.SEGMENTS].y < initial.y - 0.3, "Cap falls and hangs under gravity")
	var max_link := 0.0
	for i in range(Rope.SEGMENTS): max_link = maxf(max_link, rope.points[i].distance_to(rope.points[i+1]))
	check(max_link < Rope.LENGTH / Rope.SEGMENTS * 1.08, "Cord cannot stretch more than solver tolerance")
	check(absf(rope.points[Rope.SEGMENTS].distance_to(rope.points[Rope.SEGMENTS+1])-Rope.CAP_LENGTH)<0.015, "Cap retains its rigid length")
	var frozen: PackedVector3Array = rope.points.duplicate()
	rope.advance(0, false, Vector3.ZERO, Vector3.UP)
	check(rope.points == frozen, "Pause preserves every particle")
	var coarse = make_rope()
	var fine = make_rope()
	for i in range(120): coarse.advance(1.0/30, false, Vector3.ZERO, Vector3.UP)
	for i in range(480): fine.advance(1.0/120, false, Vector3.ZERO, Vector3.UP)
	check(coarse.points[Rope.SEGMENTS].distance_to(fine.points[Rope.SEGMENTS]) < 0.001, "Fixed-step result independent of frame rate")
	var wind = make_rope()
	wind.air_velocity = Vector3(0, 0, 12)
	for i in range(480): wind.advance(1.0/120, false, Vector3.ZERO, Vector3.UP)
	check(wind.points[Rope.SEGMENTS].z > fine.points[Rope.SEGMENTS].z + 0.2, "Crosswind displaces cap")
	wind.air_velocity = Vector3(70, -70, 70)
	wind.acceleration = Vector3(60, -90, 0)
	for i in range(120): wind.advance(1.0/30, false, Vector3.ZERO, Vector3.UP)
	check(wind.points[Rope.SEGMENTS].distance_to(Rope.ANCHOR) < Rope.LENGTH * 1.1, "Strong forces cannot detach cap")
	for p in wind.points: check(p.is_finite(), "Strong forces stay finite")
	if failures.is_empty(): print("PASS: tether gravity, constraints, cap rigidity, pause, frame-rate independence and wind")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
