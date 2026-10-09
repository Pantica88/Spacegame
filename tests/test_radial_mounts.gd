extends SceneTree
const Craft = preload("res://scripts/craft_model.gd")
const Parts = preload("res://scripts/parts.gd")
const Flight = preload("res://scripts/flight_model.gd")
var failures: Array[String] = []
func check(ok: bool, label: String):
	if not ok: failures.append(label)
func build(count: int) -> Dictionary:
	var craft := Craft.migrate(Parts.default_design())
	for i in range(count):
		Craft.add_part(craft,"separator","tank_2")
		craft.parts[-1].rotation = 17.3+360.0*i/count
		craft.parts[-1].surface_offset = .23
		Craft.add_part(craft,"boosters",craft.parts[-1].id)
	return Craft.project(craft,Parts.default_design())
func _initialize():
	for count in [1,2,4,6,8]:
		var design := build(count)
		check(Craft.valid(design.assembly),"Graph valid %d"%count)
		var saved := Craft.load_craft(design)
		var saved_design := Craft.project(saved,design)
		var before_mounts := Craft.radial_instances(design,"separator")
		var after_mounts := Craft.radial_instances(saved_design,"separator")
		for index in range(before_mounts.size()):
			check(before_mounts[index].position.distance_to(after_mounts[index].position) < .00001,"Fractional angle and height survive save %d"%count)
		var stats := Parts.stats(design)
		check(stats.booster_count == count and stats.separator_count == count,"Counts %d"%count)
		check(is_equal_approx(stats.booster_thrust,count*22000.0),"Thrust %d"%count)
		check(is_equal_approx(stats.booster_fuel_mass,count*320.0),"Fuel %d"%count)
		var properties := Parts.mass_properties(design,stats.core_fuel_mass,stats.booster_fuel_mass,true)
		check(is_equal_approx(properties.mass,stats.wet_mass),"Mass ledger %d"%count)
		check(Vector2(properties.center.x,properties.center.z).length() > .1 if count == 1 else Vector2(properties.center.x,properties.center.z).length() < .0001,"Mass balance %d"%count)
		var model := Flight.new()
		model.reset(design)
		model.state.status = "flying"
		model.state.position = Vector3(0,50000,0)
		model.state.sas = false
		model.state.engine_on = true
		model.state.boosters_on = true
		model._integrate(.01,Vector3.ZERO)
		check(model.state.angular_velocity.length() > .0001 if count == 1 else model.state.angular_velocity.length() < .0001,"Off-axis thrust torque %d"%count)
		var mass: float = model._current_mass()
		var momentum: Vector3 = model.state.velocity*mass
		model._separate_boosters()
		var after: Vector3 = model.state.velocity*model._current_mass()
		var mass_after: float = model._current_mass()
		for debris in model.state.detached:
			after += debris.velocity*debris.mass
			mass_after += debris.mass
		check(after.distance_to(momentum) < .02,"Separation momentum %d"%count)
		check(is_equal_approx(mass,mass_after),"Separation mass %d"%count)
		check(model.state.detached.size() == count,"Individual detached bodies %d"%count)
		var id: String = design.assembly.parts.filter(func(p): return p.kind == "separator")[0].id
		Craft.remove_part(design.assembly,id)
		check(Craft.valid(design.assembly),"Remove one mount graph %d"%count)
		check(Craft.radial_instances(design,"boosters").size() == count-1,"Only its child is removed %d"%count)
	for failure in failures: push_error(failure)
	print("PASS: radial counts, mass, balance, thrust torque, saves and separation" if failures.is_empty() else "FAIL: radial physics")
	quit(0 if failures.is_empty() else 1)
