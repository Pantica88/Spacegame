extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var ground := Node3D.new()
	root.add_child(ground)
	var module = load("res://scenes/parachute_1.tscn").instantiate()
	module.fade_after_landing = false
	root.add_child(module)
	module.advance(true, 3.0)
	var cloth = module.canopy
	var initial_cap: Vector3 = module.cap_pivot.global_position
	var initial_cloth: PackedVector3Array = cloth.points.duplicate()
	module.cut_away(ground)
	check(cloth.points == initial_cloth, "Cutting preserves fabric positions")
	check(module.cap_pivot.global_position.distance_to(initial_cap) < 0.001, "Cutting preserves cap position")
	check(cloth.weights[cloth.CLOTH_COUNT] > 0, "Cut suspension anchors become free particles")
	module.advance(false, 0.0)
	check(cloth.points == initial_cloth, "Pause freezes released fabric")
	check(module.cap_pivot.global_position.distance_to(initial_cap) < 0.001, "Pause freezes released cap")
	# The ship leaves, but its engine acceleration must not reach the discarded parts.
	module.position.y = 20
	module.set_air_forces(Vector3(0, -80, 0), Vector3(0, -50, 0), 1.225)
	for frame in range(360): module.advance(false, 1.0 / 60.0)
	var highest := -INF
	for point in cloth.points:
		check(point.is_finite(), "Released fabric stays finite")
		var height: float = point.dot(cloth.ground_normal) - cloth.ground_offset
		highest = maxf(highest, height)
		check(height >= 0.034, "Released fabric stays above ground")
	check(highest < 0.3, "Entire canopy and free suspension lines fall onto ground")
	check(module.cap_pivot.global_position.y < initial_cap.y - 0.5, "Untethered cap falls away from departing vessel")
	check(module.rope.points[0].y < module.rope.ANCHOR.y - 0.5, "Cap cord anchor falls freely too")
	for point in module.rope.points:
		check(point.is_finite() and point.dot(module.rope.ground_normal) >= module.rope.ground_offset, "Cap and tether collide with ground")
	check(cloth.visible and module.cap_pivot.is_visible_in_tree(), "Cut fabric and cap remain visible")
	module.queue_free()
	await process_frame
	await process_frame
	check(ground.get_child_count() == 0, "Leaving flight cleans up all cutaway visuals")
	ground.queue_free()
	if failures.is_empty(): print("PASS: released cloth, free cap and cord, ground contact, pause and cleanup")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
