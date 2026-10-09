extends RefCounted
## Representative of a workshop craft with four nested eight-way rings.
const Craft = preload("res://scripts/craft_model.gd")
const Parts = preload("res://scripts/parts.gd")

static func design() -> Dictionary:
	var base := Parts.default_design()
	base.tanks = 5
	base.engine = "titan"
	var craft := Craft.migrate(base)
	var parents: Array[String] = []
	for i in range(8): parents.append("tank_5")
	for ring in range(4):
		var next_parents: Array[String] = []
		var ignition: Array[String] = []
		var separation: Array[String] = []
		for i in range(8):
			Craft.add_part(craft, "separator", parents[i])
			var mount: Dictionary = craft.parts[-1]
			mount.rotation = i * 45.0
			separation.append("separate:" + str(mount.id))
			Craft.add_part(craft, "tank", mount.id)
			var tank_id: String = craft.parts[-1].id
			next_parents.append(tank_id)
			if ring < 2:
				Craft.add_part(craft, "tank", tank_id)
				tank_id = craft.parts[-1].id
			Craft.add_part(craft, "titan" if ring == 0 else "kestrel", tank_id)
			ignition.append("ignite:" + str(craft.parts[-1].id))
		# Group each ring as the workshop symmetry placement does.
		var actions: Array[String] = []
		actions.append_array(ignition)
		actions.append_array(separation)
		var retained: Array = []
		for stage in craft.stages:
			var remaining: Array = stage.filter(func(action): return action not in actions)
			if not remaining.is_empty(): retained.append(remaining)
		retained.append(ignition)
		retained.append(separation)
		craft.stages = retained
		parents = next_parents
	assert(Craft.valid(craft), "Large nested benchmark craft is valid")
	var result := Craft.project(craft, base)
	assert(result.tanks == 53 and Craft.engines(result).size() == 33)
	return result
