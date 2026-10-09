extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var reference := PackedVector3Array()
	for rate in [1.0,4.0,100000.0]:
		var module = load("res://scenes/parachute_1.tscn").instantiate()
		root.add_child(module)
		module.set_air_forces(Vector3(0,-9.81,0),Vector3.ZERO,1.225)
		module.set_ground(Vector3.UP,-2.32)
		module.advance(true,3.0,true,0.0)
		var start := Time.get_ticks_usec()
		for frame in range(300):
			# Rails freezes simulation-driven effects but cloth can still settle.
			module.advance(true,0.0 if rate > 4 else rate/60.0,true,1.0/60.0)
		print("VISUAL CLOCK %.0fx: %.3f ms/tick" % [rate,(Time.get_ticks_usec()-start)/300000.0])
		if reference.is_empty(): reference = module.canopy.points.duplicate()
		else: check(module.canopy.points == reference,"Warp does not multiply cloth steps or alter settled motion")
		var frozen: PackedVector3Array = module.canopy.points.duplicate()
		module.advance(true,0,true,0)
		check(module.canopy.points == frozen,"Pause freezes cosmetic physics")
		module.free()
	if failures.is_empty(): print("PASS: cosmetic physics has bounded work at physical/rail warp and respects pause")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
