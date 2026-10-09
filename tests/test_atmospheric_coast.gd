extends SceneTree
const Flight = preload("res://scripts/flight_model.gd")
const Physics = preload("res://scripts/physics_math.gd")
const Surface = preload("res://scripts/planet_surface.gd")
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _init() -> void:
	# Standard atmosphere density samples, kg/m³; catch excessive upper-air drag.
	for sample in [[0.0, 1.225], [11000.0, 0.3639], [20000.0, 0.08803], [32000.0, 0.01323], [47000.0, 0.001428], [71000.0, 0.00006421]]:
		check(absf(Flight.air_density_at(sample[0]) / sample[1] - 1.0) < 0.01, "Layer density matches reference at %.0f m" % sample[0])
	var previous_density := 1.225
	for altitude in range(0, 90001, 100):
		var density := Flight.air_density_at(float(altitude))
		check(density >= 0.0 and density <= previous_density + 0.000001, "Density decreases continuously with altitude")
		previous_density = density
	check(Flight.air_density_at(Flight.ATMOSPHERE_HEIGHT) == 0.0, "Atmospheric boundary is vacuum")
	check(Flight.air_density_at(-100.0) == Flight.air_density_at(0.0), "Below datum uses surface density")
	check(is_equal_approx(Flight._air_density_profile(10000.0, 2.45, 45000.0), 2.0 * Flight.air_density_at(20000.0)), "Custom density and atmosphere height scale the reference column")
	var velocity := Vector3(30, 200, 0)
	var nose_only := Physics.body_drag_acceleration(velocity, Vector3.UP, 1.225, 2000, 0.52, 0, 1.0 / 60.0)
	var long_hull := Physics.body_drag_acceleration(velocity, Vector3.UP, 1.225, 2000, 0.52, 25, 1.0 / 60.0)
	check(is_equal_approx(nose_only.y, long_hull.y), "Hull crossflow does not act as extra axial braking")
	check(long_hull.x < nose_only.x, "Broadside area resists lateral airflow")
	for dt in [1.0 / 120.0, 1.0 / 60.0, 0.25]:
		for speed in [0.0, 200.0, 3000.0]:
			var air: Vector3 = velocity.normalized() * speed
			var drag := Physics.body_drag_acceleration(air, Vector3.UP, 1.225, 400, 203.52, 25, dt)
			var after: Vector3 = air + drag * dt
			check(drag.dot(air) <= 0.0, "Aerodynamics never adds kinetic energy")
			check(after.length() <= air.length() + 0.001 and after.x >= -0.001 and after.y >= -0.001, "Strong drag cannot reverse airflow components")
	check(Physics.body_drag_acceleration(velocity, Vector3.UP, 0, 2000, 0.52, 25, 0.1) == Vector3.ZERO, "Vacuum has no aerodynamic force")
	var previous_speed := -1.0
	for step_size in [1.0 / 60.0, 1.0 / 30.0]:
		var flight = Flight.new()
		flight.reset({"engine":"sparrow", "tanks":16, "boosters":false})
		flight.ignite()
		flight.state.fuel = 0.0
		flight.state.engine_on = false
		flight.state.position = Flight.PLANET_CENTER + Vector3.BACK * (Flight.PLANET_RADIUS + 6000.0)
		flight.state.velocity = flight.terrain.surface_velocity(Vector3.BACK * (Flight.PLANET_RADIUS + 6000.0)) + Vector3(200, 0, 40)
		flight.state.orientation = Basis(Vector3.UP, Vector3.RIGHT, Vector3.FORWARD)
		var start: Vector3 = flight.state.position
		for tick in range(roundi(10.0 / step_size)):
			flight.step(step_size, {"throttle":0.0})
		check(flight.state.thrust == 0.0 and flight.state.fuel == 0.0, "Coast has no powered assistance")
		check(flight.state.air_velocity.x > 150.0, "Streamlined empty rocket retains forward momentum for ten seconds")
		check(flight.state.vertical_speed < 0.0, "Gravity bends the unpowered climb into descent")
		var surface_travel: float = flight.terrain.surface_velocity(Vector3.BACK * (Flight.PLANET_RADIUS + 6000.0)).x * 10.0
		check(flight.state.position.x - start.x - surface_travel > 1700.0, "Empty vessel travels forward instead of stopping and dropping vertically")
		if previous_speed > 0.0: check(absf(previous_speed - flight.state.speed) < 0.02, "Coasting is consistent across frame rates")
		previous_speed = flight.state.speed
		print("COAST: forward %.2f m/s, vertical %.2f m/s after 10 seconds" % [flight.state.air_velocity.x, flight.state.vertical_speed])
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: directional drag, momentum retention, gravity-driven descent, and stable integration")
	quit(0 if failures.is_empty() else 1)
