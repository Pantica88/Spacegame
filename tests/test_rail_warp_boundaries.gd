extends SceneTree
## Work-count regressions: deterministic even on slow CI machines.
class CountedFlight extends "res://scripts/flight_model.gd":
	var steps := 0
	func _integrate(dt: float, control: Vector3) -> void:
		steps += 1
		super._integrate(dt, control)
		# Stop a regressed limiter without hanging the test runner.
		if steps >= 2000: state.throttle = 1.0

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func orbit(altitude: float) -> CountedFlight:
	var model := CountedFlight.new()
	model.state.status = "flying"
	model.state.throttle = 0.0
	var radius := model.PLANET_RADIUS + altitude
	model.state.position = model.PLANET_CENTER + Vector3.UP * radius
	model.state.velocity = Vector3.RIGHT * sqrt(model.MU / radius)
	return model

func _initialize() -> void:
	for row in [[100.0, 0.5], [1000.0, 1.0], [10000.0, 2.0], [100000.0, 5.0]]:
		var model := CountedFlight.new()
		var altitude: float = model.ATMOSPHERE_HEIGHT + model.PLANET_RADIUS * row[1]
		model = orbit(altitude + 1.0)
		var initial_fuel: float = model.state.fuel
		var started := model.simulation_time()
		var duration: float = row[0] / 60.0
		var elapsed := model.step_rails(duration, row[0])
		check(is_equal_approx(elapsed, duration), "Circular orbit completes %dx warp beside its boundary" % row[0])
		check(model.steps < 500, "Circular orbit avoids tiny boundary steps at %dx" % row[0])
		check(is_equal_approx(model.simulation_time() - started, elapsed), "Elapsed time remains on the simulation clock")
		check(model.state.fuel == initial_fuel, "Rail warp preserves fuel")
		print("BOUNDARY %dx: %d steps for %.3f simulated seconds" % [row[0], model.steps, elapsed])
	var model := CountedFlight.new()
	var boundary_altitude := model.ATMOSPHERE_HEIGHT + model.PLANET_RADIUS
	for velocity in [Vector3(0, -100, 0), Vector3.ZERO]:
		model = orbit(boundary_altitude + 1.0)
		model.state.velocity = velocity
		var elapsed := model.step_rails(10.0, 1000.0)
		check(elapsed < 2.0 and model.warp_limit() < 1000.0, "Inward motion or gravity stops warp at the boundary")
		check(model.steps < 20, "Boundary stop uses bounded work")
		check(float(model.state.altitude) > boundary_altitude - 1.0, "Boundary stop does not overshoot by a large distance")
	model = orbit(boundary_altitude + 1.0)
	model.state.velocity = Vector3(0, 1000, 0)
	check(is_equal_approx(model.step_rails(10.0, 1000.0), 10.0) and model.steps < 20, "Outward flight does not stall alongside the boundary")
	model = orbit(4000000.0)
	model._separate_core()
	var debris: Dictionary = model.state.detached[0]
	debris.thrust = 0.0
	debris.fuel = 0.0
	debris.position = model.state.position + Vector3(0, 0, 10000)
	debris.velocity = model.state.velocity + Vector3(1500, 0, 0)
	check(is_equal_approx(model.step_rails(1000.0 / 60.0, 1000.0), 1000.0 / 60.0), "Distant fast debris permits the complete warp tick")
	check(model.steps < 20, "Distant fast debris does not force thousands of contact steps")
	if failures.is_empty():
		print("PASS: warp-boundary work, inward stops, outward flight, and distant debris")
		quit()
	else:
		for message in failures: push_error(message)
		quit(1)
