extends SceneTree
## Body registry, single source of truth for planet values, and the knowledge layer.
# Definition first: preloading it after a planet .tres breaks that resource
# (pre-existing; see docs/FOUNDATION_REVIEW.md, resource loading).
const Definition = preload("res://scripts/planet_definition.gd")
const Bodies = preload("res://scripts/body_registry.gd")
const Knowledge = preload("res://scripts/body_knowledge.gd")
const Physics = preload("res://scripts/physics_math.gd")
const Flight = preload("res://scripts/flight_model.gd")
const Surface = preload("res://scripts/planet_surface.gd")
const SolarBody = preload("res://scripts/solar_body.gd")
const World = preload("res://scripts/world_view.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	_check_registry()
	_check_two_radii()
	_check_knowledge()
	if _failures.is_empty():
		print("PASS: body registry ids and lookup, planet values follow the definition at two radii, knowledge layer")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _check_registry() -> void:
	Bodies.rebuild()
	var home: RefCounted = Bodies.home()
	_check(home.id == &"verdant" and home.parent == null, "Home planet is verdant and orbits the sun")
	_check(Surface.home() == home.terrain, "PlanetSurface's terrain is the home body's terrain")
	_check(is_equal_approx(home.mu, home.surface_gravity * home.radius * home.radius), "Gravitational parameter comes from surface gravity")
	var ids := Bodies.ids()
	_check(ids.size() >= 2 and ids[0] == &"verdant" and ids[1] == &"verdant/moon-0", "Home planet and its moon come first: %s" % [ids])
	_check(ids.has(&"ochre"), "Other bundled planets are registered")
	var mun: RefCounted = Bodies.get_body(&"verdant/moon-0")
	_check(mun != null and mun.parent == home and home.moons.has(mun), "Moon links to its parent both ways")
	_check(mun != null and mun.radius < home.radius and mun.atmosphere_height == 0.0, "Moon values come from its own definition")
	_check(Bodies.get_body(&"nowhere") == null, "Unknown ids return null")
	var offset: Vector3 = mun.offset_from_parent(1000.0)
	_check(is_equal_approx(offset.length(), float(mun.definition.moon_orbit_distance_km) * 1000.0), "Moon orbits its parent at its defined distance")
	_check(home.offset_from_parent(1000.0) == Vector3.ZERO, "Planets do not move until heliocentric orbits (step 3)")

func _check_two_radii() -> void:
	for spec in [{"radius": 1200000.0, "gravity": 5.0, "atmosphere": 50000.0}, {"radius": 300000.0, "gravity": 12.0, "atmosphere": 120000.0}]:
		var settings := Definition.new()
		settings.radius = spec.radius
		settings.surface_gravity = spec.gravity
		settings.atmosphere_height = spec.atmosphere
		Bodies.rebuild(settings)
		var label := "radius %.0f m" % spec.radius
		_check(Physics.PLANET_RADIUS == spec.radius and Flight.PLANET_RADIUS == spec.radius and Surface.RADIUS == spec.radius and World.PLANET_RADIUS == spec.radius, label + ": every radius alias follows the definition")
		_check(Physics.PLANET_CENTER == Vector3(0, -spec.radius, 0) and Flight.PLANET_CENTER == Physics.PLANET_CENTER, label + ": planet centre sits one radius below the pad")
		_check(is_equal_approx(Physics.SURFACE_GRAVITY, spec.gravity) and is_equal_approx(Physics.MU, spec.gravity * spec.radius * spec.radius), label + ": gravity and mu follow the definition")
		_check(Physics.ATMOSPHERE_HEIGHT == spec.atmosphere and Flight.ATMOSPHERE_HEIGHT == spec.atmosphere, label + ": atmosphere height follows the definition")
		_check(SolarBody.POSITION.is_equal_approx(Physics.PLANET_CENTER + SolarBody.DIRECTION * SolarBody.DISTANCE), label + ": sun position is relative to the planet centre")
		_check(Surface.LAUNCH_RADIAL.is_equal_approx(Surface.LAUNCH_BASIS * Vector3.ZERO + Surface.Terrain.LAUNCH_DIRECTION * spec.radius), label + ": launch radial scales with the radius")
		# Orbital maths through default arguments: a circular orbit above the atmosphere.
		var orbit_radius: float = spec.radius + spec.atmosphere + 10000.0
		var speed := sqrt(Physics.MU / orbit_radius)
		var elements: Dictionary = Physics.orbital_elements(Vector3(orbit_radius, 0, 0), Vector3(0, 0, speed))
		var expected_period := TAU * sqrt(pow(orbit_radius, 3.0) / Physics.MU)
		_check(absf(float(elements.get("orbital_period", 0.0)) - expected_period) < expected_period * 1e-6, label + ": orbital period uses the new mu by default (%s vs %s)" % [elements.get("orbital_period"), expected_period])
	Bodies.rebuild()
	_check(Physics.PLANET_RADIUS == float(Bodies.PlanetList.load_planet(Bodies.HOME_PATH).radius), "Rebuild restores the home planet")

func _check_knowledge() -> void:
	var knowledge := Knowledge.new()
	_check(knowledge.is_known(&"ochre") and knowledge.known_ids() == Bodies.ids(), "Everything is known by default, preserving current behaviour")
	knowledge.default_level = Knowledge.Discovery.UNDISCOVERED
	knowledge.raise(&"verdant", Knowledge.Discovery.EXPLORED)
	knowledge.raise(&"ochre", Knowledge.Discovery.DETECTED)
	knowledge.raise(&"ochre", Knowledge.Discovery.UNDISCOVERED)
	_check(knowledge.level(&"ochre") == Knowledge.Discovery.DETECTED, "Knowledge never decreases")
	_check(knowledge.known_ids() == ([&"verdant", &"ochre"] as Array[StringName]), "Hidden bodies are simulated but not listed: %s" % [knowledge.known_ids()])
	var restored: RefCounted = Knowledge.from_dict(JSON.parse_string(JSON.stringify(knowledge.to_dict())))
	_check(restored.level(&"verdant") == Knowledge.Discovery.EXPLORED and restored.level(&"verdant/moon-0") == Knowledge.Discovery.UNDISCOVERED and restored.level(&"ochre") == Knowledge.Discovery.DETECTED, "Knowledge survives a JSON round trip")
