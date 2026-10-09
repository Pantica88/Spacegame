extends SceneTree
const Flight = preload("res://scripts/flight_model.gd")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _init() -> void:
	var terrain = Flight.new().terrain
	var direction := Vector3.ZERO
	for i in range(1000):
		var candidate := Vector3(sin(i * 2.4), sin(i * 0.31), cos(i * 2.4)).normalized()
		if terrain.elevation(candidate) < -200.0:
			direction = candidate
			break
	check(not direction.is_zero_approx(), "Test finds open ocean")
	for capsule in [true, false]:
		for speed in [4.0, 12.0]:
			var model := Flight.new()
			var radial: Vector3 = direction * float(terrain.contact(direction).radius)
			model.state.capsule_only = capsule
			model.state.status = "flying"
			# Hang plumb, as under a parachute, rather than in the pad's attitude.
			model.state.orientation = Basis(Quaternion(Vector3.UP, direction))
			model.state.position = Flight.PLANET_CENTER + radial + direction * 0.001
			model.state.velocity = terrain.surface_velocity(radial) - direction * speed
			model._has_lifted = true
			model.step(1.0 / 60.0, {"throttle": 0.0})
			check(model.state.get("landing_water", false), "Safe and hard splashdowns both use water physics")
			check(model.state.status == ("landed" if speed == 4.0 else "crashed"), "Water preserves impact outcome")
			var relative: Vector3 = model.state.velocity - terrain.surface_velocity(radial)
			check(relative.dot(direction) < -speed * 0.7, "Splashdown preserves entry momentum")
			var plunge := 0.0
			for frame in range(30):
				model.step(1.0 / 60.0, {"throttle": 0.0})
				plunge = maxf(plunge, float(model.state.get("water_immersion", 0.0)))
			check(plunge > 0.3, "Vessel enters below the waterline")
			for frame in range(1200): model.step(1.0 / 60.0, {"throttle": 0.0})
			var mass := float(model._mass_properties().mass)
			check(absf(float(model.state.get("water_displaced_mass", 0.0)) - mass) < mass * 0.03, "Floating draft displaces the vessel's own mass")
			check(plunge > float(model.state.water_immersion) + 0.1, "Entry momentum plunges deeper than the resting draft")
			var axis: Vector3 = Basis(model.state.landing_body_orientation).y
			if capsule:
				check(axis.dot(direction) > 0.95, "A capsule's wide heat shield keeps it floating upright")
			else:
				check(absf(axis.dot(direction)) < 0.3, "A tall stack capsizes and floats on its side")
			check(model.state.get("settled", false) and model.warp_limit() > 1.0, "Calm floating vessels permit time warp")
			var floating_at: Vector3 = model.state.landing_body_position
			check(model.step_rails(60.0, 1000.0) > 0.0 and Vector3(model.state.landing_body_position) == floating_at, "Time warp holds the floating pose")
			check(Vector3(model.state.position).is_finite(), "Water integration stays finite")
			var position: Vector3 = model.state.position
			model.step(0.0, {"throttle": 0.0})
			check(Vector3(model.state.position) == position, "Pause freezes floating motion")
	# Horizontal entry momentum is carried into the water and then damped by it.
	var drifting := Flight.new()
	var drift_radial: Vector3 = direction * float(terrain.contact(direction).radius)
	var tangent := direction.cross(Vector3.UP).normalized()
	drifting.state.capsule_only = true
	drifting.state.status = "flying"
	drifting.state.orientation = Basis(Quaternion(Vector3.UP, direction))
	drifting.state.position = Flight.PLANET_CENTER + drift_radial + direction * 0.001
	drifting.state.velocity = terrain.surface_velocity(drift_radial) - direction * 3.0 + tangent * 5.0
	drifting._has_lifted = true
	drifting.step(1.0 / 60.0, {"throttle": 0.0})
	for frame in range(600): drifting.step(1.0 / 60.0, {"throttle": 0.0})
	var travelled := Vector3(drifting.state.water_offset) - direction * Vector3(drifting.state.water_offset).dot(direction)
	check(travelled.dot(tangent) > 0.5 and travelled.length() < 25.0, "Water drag stops horizontal splashdown drift")
	check(Vector3(drifting.state.water_velocity).length() < 0.1, "Drift comes to rest")
	# The collision mesh's flat ocean faces sag metres below sea level; a
	# capsule descending from the air must still float on the drawn water.
	var descent := Flight.new()
	var sea_radius := float(terrain.definition.radius)
	check(float(terrain.contact(direction).radius) < sea_radius - 1.0, "Test spot has a sagging ocean face")
	descent.state.capsule_only = true
	descent.state.status = "flying"
	descent.state.orientation = Basis(Quaternion(Vector3.UP, direction))
	descent.state.position = Flight.PLANET_CENTER + direction * (sea_radius + 20.0)
	descent.state.velocity = terrain.surface_velocity(direction * sea_radius) - direction * 7.0
	descent._has_lifted = true
	for frame in range(60 * 20): descent.step(1.0 / 60.0, {"throttle": 0.0})
	var floating_height := (Vector3(descent.state.position) - Flight.PLANET_CENTER).length() - sea_radius
	check(descent.state.get("landing_water", false) and absf(floating_height) < 1.0, "Splashdown floats at sea level, not on the mesh below it")
	check(float(descent.state.terrain_clearance) < 0.5, "Ground readout uses the sea surface while floating")
	if failures.is_empty(): print("PASS: water entry momentum, immersion, buoyancy, stability, drift, hard splashdowns and pause")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
