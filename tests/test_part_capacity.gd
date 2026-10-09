extends SceneTree
const Craft = preload("res://scripts/craft_model.gd")
const Parts = preload("res://scripts/parts.gd")
const Profile = preload("res://scripts/profile.gd")
func _initialize() -> void:
	var craft := Craft.migrate(Parts.default_design())
	var engine_tank := ""
	for branch in range(15):
		Craft.add_part(craft,"separator","tank_1")
		var parent: String = craft.parts[-1].id
		for level in range(14):
			Craft.add_part(craft,"tank",parent)
			parent = craft.parts.filter(func(part): return part.parent == parent and part.kind == "tank")[0].id
		engine_tank = parent
		Craft.add_part(craft,"sparrow",engine_tank)
	while craft.parts.size() < Craft.MAX_PARTS: Craft.add_part(craft,"tank")
	assert(Craft.valid(craft),"Maximum-size assembly validates")
	var before: Dictionary = craft.duplicate(true)
	Craft.add_part(craft,"tank")
	assert(craft == before,"New parts cannot exceed capacity")
	Craft.add_part(craft,"titan",engine_tank)
	assert(craft.parts.size() == Craft.MAX_PARTS,"Engine replacement does not need a free slot")
	assert(craft.parts.any(func(part): return part.parent == engine_tank and part.kind == "titan"),"Existing engine can be replaced at capacity")
	assert(Craft.valid(craft),"Replacement preserves valid assembly")
	var design := Craft.project(craft,Parts.default_design())
	var saved := Profile.new("user://capacity-test.json")
	saved.data.design = design
	saved.save()
	assert(saved.last_error.is_empty(),"Maximum craft saves")
	var restored := Profile.new("user://capacity-test.json")
	assert(restored.last_error.is_empty(),"Maximum craft fits the save-size limit")
	assert(restored.data.design.assembly.parts == Craft.load_craft(design).parts,"Maximum craft survives actual profile reload")
	print("PASS: 256-part craft, capacity enforcement, engine replacement and profile reload")
	quit()
