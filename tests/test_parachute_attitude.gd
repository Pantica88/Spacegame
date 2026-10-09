extends SceneTree
const Flight = preload("res://scripts/flight_model.gd")
const Parts = preload("res://scripts/parts.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	for capsule_only in [false, true]:
		var model := Flight.new()
		model.reset(Parts.default_design())
		model.state.capsule_only = capsule_only
		model.state.status = "flying"
		model.state.position = Vector3(0, 1500, 0)
		model.state.velocity = model.terrain.surface_velocity(model.state.position + Vector3(0, Flight.PLANET_RADIUS, 0)) + Vector3(0, -25, 0)
		var sideways := Basis(Vector3.FORWARD, PI / 2)
		model.state.orientation = sideways
		model.deploy_chute()
		check(model.state.chute_deployed, "Sideways descending vessel can deploy")
		check(Basis(model.state.orientation).is_equal_approx(sideways), "Deployment does not snap vessel attitude")
		model.step(1.0 / 60.0, {"throttle": 0.0})
		check(Basis(model.state.orientation).y.dot(Vector3.UP) < 0.05, "First inflation step does not snap upright")
		for frame in range(360): model.step(1.0 / 60.0, {"throttle": 0.0})
		check(Basis(model.state.orientation).y.dot(Vector3.UP) > 0.9, "Attachment drag gradually aligns vessel under canopy")
		check(model.state.status == "flying", "Attitude recovery happens before ground contact")
	var module = load("res://scenes/parachute_1.tscn").instantiate()
	root.add_child(module)
	module.basis = Basis(Vector3.FORWARD, PI / 2)
	var local_frame: Basis = module.basis.transposed()
	module.set_air_forces(local_frame * Vector3(0, -9.81, 0), local_frame * Vector3(0, 25, 0), 1.225)
	module.advance(true, 0.7)
	check(module.canopy.global_basis.y.normalized().dot(Vector3.UP) > 0.99, "Canopy ejects into upward airflow from horizontal vessel")
	check(absf(module.global_basis.y.dot(Vector3.UP)) < 0.01, "Canopy alignment leaves housing and vessel sideways")
	module.basis = Basis(Vector3.FORWARD, PI / 4)
	local_frame = module.basis.transposed()
	var airflow := Vector3(-12, 25, 0)
	module.set_air_forces(local_frame * Vector3(0, -9.81, 0), local_frame * airflow, 1.225)
	for frame in range(180): module.advance(true, 1.0 / 60.0)
	check(module.canopy.global_basis.y.normalized().dot(airflow.normalized()) > 0.99, "Canopy follows drag direction rather than vessel axis")
	var frozen: Transform3D = module.canopy.transform
	module.advance(true, 0)
	check(module.canopy.transform.is_equal_approx(frozen), "Pause freezes canopy alignment")
	module.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: sideways deployment, independent canopy, gradual drag torque, airflow tracking and pause")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
