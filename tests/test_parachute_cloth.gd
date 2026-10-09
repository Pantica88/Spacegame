extends SceneTree
const Cloth = preload("res://scripts/parachute_cloth.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var coarse := Cloth.new()
	var fine := Cloth.new()
	root.add_child(coarse)
	root.add_child(fine)
	coarse.air_velocity = Vector3(3, 7, 1)
	fine.air_velocity = coarse.air_velocity
	for frame in range(30):
		coarse.advance(1.0 / 30.0, false)
		_check_taut(coarse)
	for frame in range(120): fine.advance(1.0 / 120.0, false)
	for i in range(coarse.points.size()):
		check(coarse.points[i].distance_to(fine.points[i]) < 0.001, "Fixed stepping is independent of frame rate")
		if coarse._pinned(i): check(coarse.points[i] == coarse.rest[i], "Harness anchors remain attached")
	check(coarse.points[0].x > coarse.rest[0].x + 0.05, "Canopy yields to crosswind")
	var fabric_stretch := false
	for link in coarse.links:
		if int(link.x) < Cloth.CLOTH_COUNT:
			fabric_stretch = fabric_stretch or coarse.points[int(link.x)].distance_to(coarse.points[int(link.y)]) > link.z * 1.0001
	check(fabric_stretch, "Fabric stretches elastically under load")
	var airborne: PackedVector3Array = coarse.points.duplicate()
	coarse.advance(0, true)
	check(coarse.points == airborne, "Touchdown changes constraints without teleporting the ropes")
	coarse.air_velocity = Vector3.ZERO
	coarse.ground_normal = Vector3(0.12, 1, 0).normalized()
	for frame in range(360): coarse.advance(1.0 / 60.0, true)
	for point in coarse.points:
		check(point.is_finite(), "Cloth stays finite after wind and touchdown")
		check(point.dot(coarse.ground_normal) >= coarse.ground_offset + 0.034, "Cloth respects sloped ground")
	check(coarse.visible and is_zero_approx(coarse.pressure), "Landed fabric persists without inflation pressure")
	var slack := false
	for side in range(Cloth.SIDES):
		var anchor := Cloth.CLOTH_COUNT + side * Cloth.CORD_STEPS
		var skirt := (Cloth.RINGS - 1) * Cloth.SIDES + side
		slack = slack or coarse.points[anchor].distance_to(coarse.points[skirt]) < coarse.rest[anchor].distance_to(coarse.rest[skirt]) * 0.9
	check(slack, "Suspension ropes lose tension after touchdown")
	coarse.queue_free()
	fine.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: taut inextensible ropes, touchdown slack, elastic canopy, wind, fixed stepping and sloped ground")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_taut(cloth) -> void:
	for side in range(Cloth.SIDES):
		var anchor := Cloth.CLOTH_COUNT + side * Cloth.CORD_STEPS
		var skirt := (Cloth.RINGS - 1) * Cloth.SIDES + side
		var length: float = cloth.rest[anchor].distance_to(cloth.rest[skirt])
		check(absf(cloth.points[anchor].distance_to(cloth.points[skirt]) - length) < 0.00001, "Loaded ropes retain their full fixed length under wind")
		for segment in range(1, Cloth.CORD_STEPS):
			var expected: Vector3 = cloth.points[anchor].lerp(cloth.points[skirt], float(segment) / Cloth.CORD_STEPS)
			check(cloth.points[anchor + segment].distance_to(expected) < 0.00001, "Loaded ropes stay straight without sag or spring bounce")
