extends SceneTree
## Bakes the parachute's landing collapse from the real cloth simulation.
## Run: tools/run.sh --headless --script res://tools/bake_chute_collapse.gd
const Bake = preload("res://scripts/chute_collapse_bake.gd")
const OUTPUT := "res://assets/models/parachute_1/collapse_bake.res"
const DESCENT_SPEED := 6.0
const FLOOR := -2.6592
const STEPS_PER_FRAME := 2

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var module = load("res://scenes/parachute_1.tscn").instantiate()
	module.fade_after_landing = false
	root.add_child(module)
	# Steady descent: the canopy hangs in the relative airflow.
	module.set_air_forces(Vector3.ZERO, Vector3(0, DESCENT_SPEED, 0), 1.225)
	module.set_ground(Vector3.UP, FLOOR)
	module.advance(true, module.DURATION)
	for frame in range(60 * 6): module.advance(true, 1.0 / 60.0)
	# Touchdown: gravity takes the unpressurized fabric down around the hull.
	module.set_air_forces(Vector3(0, -9.81, 0), Vector3.ZERO, 1.225)
	var bake := Bake.new()
	bake.frame_seconds = STEPS_PER_FRAME / 60.0
	var frames := int(ceil(module.FADE_SECONDS * 60.0 / STEPS_PER_FRAME))
	for frame in range(frames + 1):
		bake.canopy_frames.append(module.canopy.points.duplicate())
		bake.rope_frames.append(module.rope.points.duplicate())
		for step in range(STEPS_PER_FRAME): module.advance(true, 1.0 / 60.0, true)
	var error := ResourceSaver.save(bake, OUTPUT)
	print("Baked %d frames over %.2f s to %s: %s" % [bake.canopy_frames.size(), bake.duration(), OUTPUT, error_string(error)])
	quit(0 if error == OK else 1)
