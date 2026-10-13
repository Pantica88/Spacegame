extends SceneTree
const Flight = preload("res://scripts/flight_model.gd")

class CountedFlight extends "res://scripts/flight_model.gd":
	var steps := 0
	func _integrate(dt: float, control: Vector3) -> void:
		steps += 1
		super._integrate(dt, control)

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	var prepared := Flight.new()
	prepared.prepare_terrain_contacts()
	for body in prepared._debris_surfaces(prepared.simulation_time()):
		check(body.terrain.mesh != null and body.terrain.collision != null, "Every home-system contact mesh is prepared before flight")
	for altitude in [2900000000.0, 3000000000.0, 3100000000.0]:
		for speed in [-3000.0, 0.0, 3000.0]:
			var model := CountedFlight.new()
			model.state.status = "flying"
			model.state.throttle = 0.0
			model.state.position = model.PLANET_CENTER + Vector3.BACK * (model.PLANET_RADIUS + altitude)
			model.state.velocity = Vector3.BACK * speed
			var reference := Flight.new()
			reference.state = model.state.duplicate(true)
			var duration := 100000.0 / 60.0
			check(is_equal_approx(model.step_rails(duration, 100000.0), duration), "Distant warp advances the full requested time")
			var remaining := duration
			while remaining > 0.0000001:
				var step := minf(remaining, 10.0)
				reference.step_rails(step, 100000.0)
				remaining -= step
			var position_error := Vector3(model.state.position).distance_to(reference.state.position)
			var velocity_error := Vector3(model.state.velocity).distance_to(reference.state.velocity)
			check(position_error < 1.0, "Distant coast agrees with ten-second integration to within one metre")
			check(velocity_error < 0.0001, "Distant coast velocity agrees with ten-second integration")
			check(model.steps <= 4, "Distant coast avoids hundreds of unnecessary substeps")
			check(model.state.fuel == reference.state.fuel and model.state.orientation.is_equal_approx(reference.state.orientation), "Distant rails preserve fuel and attitude")
			print("DISTANT %.0f km speed %.0f: %d steps, position error %.6f m, velocity error %.9f m/s" % [altitude / 1000.0, speed, model.steps, position_error, velocity_error])
	if failures.is_empty():
		print("PASS: distant warp work, coast accuracy, and prepared moon contacts")
		quit()
	else:
		for message in failures: push_error(message)
		quit(1)
