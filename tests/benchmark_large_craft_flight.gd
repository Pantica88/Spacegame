extends SceneTree

const Parts = preload("res://scripts/parts.gd")
const Flight = preload("res://scripts/flight_model.gd")
const Fixture = preload("res://tests/large_craft_fixture.gd")


func _initialize() -> void:
	var design := Fixture.design()
	assert(design.tanks == 53 and Parts.Craft.engines(design).size() == 33)
	var model := Flight.new()
	var start := Time.get_ticks_usec()
	model.reset(design)
	print("LARGE CRAFT: reset %.3f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
	model.ignite()
	model.state.active_engines.assign(Parts.Craft.engines(design).map(func(engine): return engine.id))
	model.state.position = Vector3(0, 30000, 0)
	model.state.velocity = Vector3(620, 0, 0)
	var initial_fuel: float = model.state.fuel
	var fuel_flow := 0.0
	for engine in Parts.Craft.engines(design):
		var spec: Dictionary = Parts.ENGINES[engine.kind]
		fuel_flow += float(spec.thrust) / (float(spec.isp) * Parts.STANDARD_GRAVITY)
	model.step(1.0 / 60.0, {"throttle": 1.0})
	start = Time.get_ticks_usec()
	for frame in range(120):
		model.step(1.0 / 60.0, {"throttle": 1.0, "pitch": 0.1})
		model.telemetry()
		model.telemetry()
	print("LARGE CRAFT: 53 tanks / 33 engines physics + two telemetry reads %.3f ms/tick" % ((Time.get_ticks_usec() - start) / 120000.0))
	assert(model.state.status == "flying" and model.state.thrust > 0.0)
	assert(absf(initial_fuel - model.state.fuel - fuel_flow * 121.0 / 60.0) < 0.001, "All nested engines consume their own fuel at the unchanged rate")
	check_mass(model)
	start = Time.get_ticks_usec()
	for index in range(10): model._stack_top()
	print("LARGE CRAFT: stack height %.3f ms" % ((Time.get_ticks_usec() - start) / 10000.0))
	var mass_before: float = model._current_mass()
	start = Time.get_ticks_usec()
	model._separate_engine_stage(design.assembly.parts.filter(func(part): return part.kind == "separator")[0].id)
	print("LARGE CRAFT: nested side stage separation %.3f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
	assert(model.state.detached.size() == 1)
	var detached: Dictionary = model.state.detached[0]
	assert(absf(mass_before - model._current_mass() - detached.dry_mass - detached.fuel) < 0.001, "Nested stage release conserves mass and remaining fuel")
	start = Time.get_ticks_usec()
	model.step(1.0 / 60.0, {"throttle": 1.0})
	print("LARGE CRAFT: first physics tick after separation %.3f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
	check_mass(model)
	start = Time.get_ticks_usec()
	for frame in range(30):
		model.step(1.0 / 60.0, {"throttle": 1.0})
		model.telemetry()
	print("LARGE CRAFT: after side separation %.3f ms/tick" % ((Time.get_ticks_usec() - start) / 30000.0))
	model.reset(Parts.default_design())
	assert(model._engines.size() == 1 and model._parts_by_id.is_empty() and model._supplied_tanks.is_empty(), "Reset removes all cached nested-engine topology")
	check_mass(model)
	print("PASS: large-craft fuel burn, mass, staging, cached geometry and reset")
	quit()


func check_mass(model: RefCounted) -> void:
	var expected := Parts.mass_properties(model._design, model.state.fuel, model.state.booster_fuel, model.state.boosters_attached)
	var actual: Dictionary = model._mass_properties()
	assert(is_equal_approx(actual.mass, expected.mass))
	assert(actual.center.is_equal_approx(expected.center))
	assert(actual.inertia.is_equal_approx(expected.inertia))
	assert(is_equal_approx(model._stack_top(), Parts.Craft.stack_top(model._design)), "Fixed geometry remains valid after staging and reset")
