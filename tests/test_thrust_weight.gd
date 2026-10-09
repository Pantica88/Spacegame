extends SceneTree
const Flight = preload("res://scripts/flight_model.gd")
const Parts = preload("res://scripts/parts.gd")
const Surface = preload("res://scripts/planet_surface.gd")
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _init() -> void:
	var pad = Flight.new()
	var launch_speed: float = Vector3(pad.state.velocity).length()
	var orbital_speed := sqrt(float(pad.terrain.definition.surface_gravity) * float(pad.terrain.definition.radius))
	check(launch_speed < orbital_speed, "Planet rotation must not fling an unpowered rocket into flight")
	pad.ignite()
	pad.step(5.0, {"throttle": 0.0})
	check(float(pad.state.altitude) < 0.2, "Unpowered rocket remains on the launch pad")
	for tanks in [2, 8, 16]:
		for throttle in [0.0, 0.1, 0.25]:
			var flight = Flight.new()
			flight.reset({"engine": "sparrow", "tanks": tanks, "boosters": false})
			var definition = Surface.HOME.duplicate(true)
			definition.atmosphere_density = 0.0
			definition.moons.clear()
			flight.terrain = Surface.Terrain.new(definition)
			flight.ignite()
			var up: Vector3 = Surface.LAUNCH_RADIAL.normalized()
			flight.state.position = Flight.PLANET_CENTER + up * (definition.radius + 1000.0)
			flight.state.velocity = Vector3.ZERO
			var mass: float = flight._current_mass()
			var expected_mass: float = Parts.CAPSULE_MASS + Parts.FIN_MASS + Parts.ENGINES.sparrow.mass + tanks * (Parts.TANK_DRY_MASS + Parts.TANK_FUEL_MASS)
			check(is_equal_approx(mass, expected_mass), "Every installed tank and its fuel contributes to flight mass")
			var gravity: float = definition.surface_gravity * pow(definition.radius / (definition.radius + 1000.0), 2)
			var expected_acceleration: float = Parts.ENGINES.sparrow.thrust * throttle / mass - gravity
			check(expected_acceleration < 0.0, "Test craft thrust is below weight")
			flight.step(1.0, {"throttle": throttle})
			var vertical_velocity: float = Vector3(flight.state.velocity).dot(up)
			check(vertical_velocity < 0.0, "Heavy rocket falls under low thrust")
			check(absf(vertical_velocity - expected_acceleration) < 0.02, "Acceleration follows thrust / total mass minus gravity")
			print("tanks=%d throttle=%.0f%% mass=%.0fkg thrust=%.0fN weight=%.0fN vertical_velocity=%.2fm/s" % [tanks, throttle * 100.0, mass, flight.state.thrust, mass * gravity, vertical_velocity])
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: heavy rockets fall when thrust is below weight")
	quit(0 if failures.is_empty() else 1)
