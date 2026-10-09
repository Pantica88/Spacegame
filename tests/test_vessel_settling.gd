extends SceneTree
const Flight = preload("res://scripts/flight_model.gd")
const Parts = preload("res://scripts/parts.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _init() -> void:
	for capsule in [false, true]:
		var model := Flight.new()
		model.reset(Parts.default_design())
		model.state.capsule_only = capsule
		model.state.orientation = Basis(Vector3.FORWARD, PI / 4)
		model.state.position = Vector3(0, 0.01, 0)
		model.state.velocity = Vector3(0, -2, 0)
		model.state.status = "flying"
		model._has_lifted = true
		model.step(1.0 / 60, {"throttle": 0.0})
		check(model.state.status in ["landed", "crashed"], "Tilted vessel reaches touchdown")
		var touchdown: Basis = model.state.orientation
		check(touchdown.y.dot(Vector3.UP) < 0.8, "Touchdown does not snap vessel upright")
		var report_time: float = model.state.time
		var status: String = model.state.status
		for frame in range(600): model.step(1.0 / 60, {"throttle": 0.0})
		check(not Basis(model.state.orientation).is_equal_approx(touchdown), "Tilted vessel continues rotating after touchdown")
		check(absf(Basis(model.state.orientation).y.dot(Vector3.UP)) < 0.3, "Unstable vessel falls onto its side")
		check(model.state.status == status and model.state.time == report_time, "Settling preserves flight result and report time")
		check(Vector3(model.state.position).is_finite() and Vector3(model.state.angular_velocity).is_finite(), "Settling stays finite")
		check(model.state.get("settled", false), "Quiet vessel enters persistent rest after touchdown")
		check(Vector3(model.state.settling_velocity).is_zero_approx() and Vector3(model.state.angular_velocity).is_zero_approx(), "Rest stops residual rolling and sliding")
		var resting_position: Vector3 = model.state.landing_body_position
		var resting_orientation: Basis = model.state.landing_body_orientation
		for frame in range(120): model.step(1.0 / 60, {"throttle": 0.0})
		check(Vector3(model.state.landing_body_position).is_equal_approx(resting_position) and Basis(model.state.landing_body_orientation).is_equal_approx(resting_orientation), "Rest stays fixed relative to the rotating terrain")
		var craft: Dictionary = model._collision_bodies().back()
		var support: Vector3 = model._debris_support(craft, Vector3.UP)
		check(model.terrain.clearance(Vector3(craft.position) + support + Vector3(0, Flight.PLANET_RADIUS, 0), model.simulation_time()) > -0.02, "Settled hull remains above terrain")
		var frozen: Basis = model.state.orientation
		model.step(0, {"throttle": 0.0})
		check(Basis(model.state.orientation).is_equal_approx(frozen), "Pause freezes settling")
	var upright := Flight.new()
	upright.state.status = "flying"
	upright.state.position = Vector3(0, 0.01, 0)
	upright.state.velocity = Vector3(0, -2, 0)
	upright._has_lifted = true
	for frame in range(300): upright.step(1.0 / 60, {"throttle": 0.0})
	check(Basis(upright.state.orientation).y.dot(Vector3.UP) > 0.99, "Balanced upright landing stays upright")
	check(upright.state.get("settled", false), "Upright landing also comes to rest")
	upright.step(1.0 / 60, {"throttle": 1.0})
	check(upright.state.status == "flying" and not upright.state.get("settled", true), "Ignition wakes a settled fueled vessel")
	for capsule in [false, true]:
		for speed in [19.0, 21.0, 100.0]:
			var impact := Flight.new()
			impact.state.capsule_only = capsule
			impact.state.status = "flying"
			impact.state.position = Vector3(0, 0.01, 0)
			impact.state.velocity = impact.terrain.surface_velocity(Vector3(0, Flight.PLANET_RADIUS, 0)) + Vector3(0, -speed, 0)
			impact._has_lifted = true
			impact.step(1.0 / 60, {"throttle": 0.0})
			var destructive: bool = speed > Flight.DEBRIS_BREAKUP_SPEED
			check(impact.state.destroyed == destructive, "Craft and capsule obey the surface explosion threshold")
			check(impact.state.surface_impacts.size() == (1 if destructive else 0), "Destructive touchdown emits exactly one explosion")
			if destructive:
				check(impact._collision_bodies().is_empty(), "Destroyed craft leaves collision simulation")
				check(not impact._can_relaunch({"throttle": 1.0}), "Destroyed craft cannot relaunch")
				impact.step(0.1, {"throttle": 1.0})
				check(impact.state.surface_impacts.size() == 1, "Destroyed craft cannot explode again")
	if failures.is_empty(): print("PASS: tilted capsule and full vessel settle under gravity after touchdown")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
