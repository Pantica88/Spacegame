extends SceneTree
const Parts = preload("res://scripts/parts.gd")
const Flight = preload("res://scripts/flight_model.gd")

func _initialize() -> void:
	for count in [0, 2, 8]:
		var design := Parts.default_design()
		design.engine = "titan"
		var craft := Parts.Craft.migrate(design)
		for index in range(count):
			Parts.Craft.add_part(craft, "separator", "tank_2")
			var mount: Dictionary = craft.parts[-1]
			mount.rotation = 360.0 * index / count
			Parts.Craft.add_part(craft, "tank", mount.id)
			Parts.Craft.add_part(craft, "tank", craft.parts[-1].id)
			Parts.Craft.add_part(craft, "titan", craft.parts[-1].id)
		design = Parts.Craft.project(craft, design)
		var flight := Flight.new()
		flight.reset(design)
		flight.ignite()
		flight.state.active_engines.assign(Parts.Craft.engines(design).map(func(engine): return engine.id))
		flight.state.engine_on = true
		flight.state.position = Vector3(0, 30000, 0)
		flight.state.velocity = Vector3(620, 0, 0)
		flight.step(1.0 / 60.0, {"throttle": 1.0})
		var start := Time.get_ticks_usec()
		for frame in range(120):
			flight.step(1.0 / 60.0, {"throttle": 1.0})
		print("DOUBLE-TANK TITANS %d: %.3f ms/tick" % [count, float(Time.get_ticks_usec() - start) / 120000.0])
		start = Time.get_ticks_usec()
		for frame in range(30):
			flight.step(1.0 / 60.0, {"throttle": 1.0})
			flight.telemetry()
			flight.telemetry()
		print("DOUBLE-TANK TITANS %d: %.3f ms/tick including HUD telemetry" % [count, float(Time.get_ticks_usec() - start) / 30000.0])
		assert(flight.state.thrust > 0.0)
		check_mass(flight)
		flight.state.fuel *= 0.37
		check_mass(flight)
		flight.state.boosters_attached = false
		check_mass(flight)
		if count > 0:
			flight._separate_engine_stage(craft.parts.filter(func(part): return part.kind == "separator")[0].id)
			check_mass(flight)
		flight.reset(Parts.default_design())
		check_mass(flight)
	print("PASS: powered radial engine benchmark")
	quit()

func check_mass(flight: RefCounted) -> void:
	var expected := Parts.mass_properties(flight._design, flight.state.fuel, flight.state.booster_fuel, flight.state.boosters_attached, flight._radial_layout)
	flight._mass_cache.clear()
	var actual: Dictionary = flight._mass_properties()
	var retained_layout: Array = flight._mass_layout
	flight.telemetry()
	assert(is_same(retained_layout, flight._mass_layout), "HUD telemetry reuses mass geometry outside physics step")
	assert(is_equal_approx(actual.mass, expected.mass), "Cached mass matches live geometry")
	assert(actual.center.is_equal_approx(expected.center), "Cached center matches live geometry")
	assert(actual.inertia.is_equal_approx(expected.inertia), "Cached inertia matches live geometry")
