extends SceneTree

const Flight = preload("res://scripts/flight_model.gd")
const Surface = preload("res://scripts/planet_surface.gd")
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _init() -> void:
	# Remove terrain/air/moons so the measured deceleration isolates gravity.
	for radius in [300000.0, 600000.0, 1200000.0]:
		for altitude in [1000.0, 100000.0]:
			var definition = Surface.HOME.duplicate(true)
			definition.radius = radius
			definition.atmosphere_density = 0.0
			definition.moons.clear()
			var flight = Flight.new()
			flight.terrain = Surface.Terrain.new(definition)
			flight.ignite()
			flight.state.position = Flight.PLANET_CENTER + Vector3.RIGHT * (radius + altitude)
			flight.state.velocity = Vector3.RIGHT * 30.0
			flight.state.orientation = Surface.LAUNCH_BASIS
			var fuel: float = flight.state.fuel
			var gravity: float = definition.surface_gravity * pow(radius / (radius + altitude), 2)
			flight.step(1.0, {"throttle": 0.0})
			check(flight.state.thrust == 0.0 and flight.state.fuel == fuel, "Cutoff stops thrust and fuel consumption")
			check(absf(flight.state.velocity.x - (30.0 - gravity)) < 0.01, "Cutoff deceleration matches edited planet gravity: radius %s altitude %s" % [radius, altitude])
			for second in range(5): flight.step(1.0, {"throttle": 0.0})
			check(flight.state.velocity.x < 0.0, "Unpowered suborbital climb turns into descent")
			flight.state.engine_on = false
			flight.step(0.1, {"throttle": 1.0})
			check(flight.state.thrust == 0.0 and flight.state.fuel == fuel, "Disabled engine cannot thrust even at full throttle")
	var landed = Flight.new()
	landed.ignite()
	landed.step(1.0, {"throttle": 1.0})
	# A gentle touchdown with a nonzero throttle must stay shut down.
	landed.state.position = Flight.PLANET_CENTER + Surface.LAUNCH_RADIAL.normalized() * (Flight.PLANET_RADIUS + 0.1)
	landed.state.position_remainder = Vector3.ZERO
	landed.state.velocity = landed.terrain.surface_velocity(Surface.LAUNCH_RADIAL) - Surface.LAUNCH_RADIAL.normalized()
	landed.step(0.2, {"throttle": 0.1})
	check(landed.state.status == "landed", "Fixture makes a soft touchdown")
	var landed_fuel: float = landed.state.fuel
	landed.step(0.1, {"throttle": 0.1})
	check(landed.state.status == "landed" and not landed.state.engine_on and landed.state.fuel == landed_fuel, "Held throttle cannot restart a shut-down engine")
	landed.step(0.1, {"throttle": 0.0})
	landed.step(0.1, {"throttle": 1.0})
	check(landed.state.engine_on and landed.state.fuel < landed_fuel, "Cut then raise throttle deliberately restarts the engine")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: engine cutoff, unpowered descent, edited-radius gravity, and deliberate restart")
	quit(0 if failures.is_empty() else 1)
