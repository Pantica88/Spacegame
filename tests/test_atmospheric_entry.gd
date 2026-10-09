extends SceneTree
## Run: godot --headless --path . --script tests/test_atmospheric_entry.gd

const Flight = preload("res://scripts/flight_model.gd")

func _init() -> void:
	var flight = Flight.new()
	var surface_speed: float = flight.terrain.surface_velocity(Vector3(0, 0, Flight.PLANET_RADIUS)).length()
	var orbital_speed: float = sqrt(Flight.MU / Flight.PLANET_RADIUS)
	assert(surface_speed < orbital_speed, "The atmosphere must rotate slower than low orbit")
	flight.ignite()
	flight.state.engine_on = false
	flight.state.capsule_only = true
	flight.state.position = Vector3(0, -Flight.PLANET_RADIUS, Flight.PLANET_RADIUS + 85000)
	flight.state.velocity = Vector3(0, 0, -2200)
	var previous_altitude: float = 85000.0
	var slowest_air_speed: float = INF
	for second in range(220):
		flight.step(1.0, {"throttle": 0.0})
		if flight.state.status != "flying":
			break
		var altitude: float = float(flight.state.altitude)
		assert(altitude < previous_altitude, "Atmospheric drag must not launch the descending capsule back into space")
		previous_altitude = altitude
		slowest_air_speed = minf(slowest_air_speed, float(flight.state.speed))
	assert(slowest_air_speed > 80.0, "Entry must approach a falling terminal speed, not stop in midair")
	assert(flight.state.status != "flying", "The descending capsule should reach the surface")
	print("PASS: equatorial entry slows continuously and reaches the surface")
	quit(0)
