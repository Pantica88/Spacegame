extends SceneTree
const Craft = preload("res://scripts/craft_model.gd")
const Parts = preload("res://scripts/parts.gd")
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	if not value: failures.append(label)
func _initialize(): run.call_deferred()
func run():
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.design = Craft.project(Craft.migrate(Parts.default_design()),Parts.default_design())
	for index in range(3): Craft.add_part(game.design.assembly,"tank")
	game.radial_symmetry = 8
	var first := ""
	for index in range(8):
		Craft.add_part(game.design.assembly,"separator","tank_4")
		game.design.assembly.parts[-1].rotation = index*45.0
		var parent: String = game.design.assembly.parts[-1].id
		for level in range(2):
			Craft.add_part(game.design.assembly,"tank",parent)
			var tank: String = game.design.assembly.parts[-1].id
			Craft.add_part(game.design.assembly,"tank",tank)
			var engine_tank: String = game.design.assembly.parts.filter(func(part): return part.kind == "tank" and part.parent == tank)[0].id
			Craft.add_part(game.design.assembly,"sparrow",engine_tank)
			if level == 0:
				Craft.add_part(game.design.assembly,"separator",engine_tank)
				game.design.assembly.parts[-1].rotation = index*45.0
				parent = game.design.assembly.parts[-1].id
		if index == 0: first = game.design.assembly.parts[-1].id
	game._refresh_design(false)
	await process_frame
	check(game.design.assembly.parts.size() == 74,"Large nested craft starts with 74 parts")
	game._attach_part("decoupler","decoupler@"+first)
	await process_frame
	await process_frame
	var ds: Array = game.design.assembly.parts.filter(func(p): return p.parent == first)
	game._attach_part("tank","tank@"+str(ds[0].id))
	await process_frame
	await process_frame
	var ts: Array = game.design.assembly.parts.filter(func(p): return p.parent == ds[0].id)
	check(game.design.assembly.parts.size() == 90,"Decouplers and lower tanks exceed old 80-part cap")
	var slot := "engine@"+str(ts[0].id)
	check(game._can_attach("sparrow",slot),"Lower nested side tank accepts engines in eight-way symmetry")
	var candidates: Array = game._snap_candidates("sparrow").filter(func(candidate): return candidate[0] == slot)
	check(candidates.size() == 1,"Lower-stage engine mount exists")
	for c in game._snap_candidates("sparrow"):
		if c[0] == slot:
			var screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(c[1]))
			check(game.build_drop_area.get_global_rect().has_point(screen),"Engine drop target is inside the workshop canvas")
			check(game.world._rocket.to_global(c[1]).y > 0.0,"Lower engine mount clears the hangar floor")
			check(game._update_build_drag("sparrow",screen),"Engine drag snaps to lower side stage")
			game._finish_build_drag("sparrow",screen)
			await process_frame
			await process_frame
			check(Craft.engines(game.design).size() == 25,"Drag installs all eight lower-stage engines")
			check(Craft.valid(game.design.assembly),"Completed three-engine-per-branch craft validates")
			check(Craft.load_craft(game.design).parts == game.design.assembly.parts,"Lower-stage engines survive saving")
			game.world.workshop_camera_view("Reset")
			var engine_screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(game.world.installed_part_position(game.design.assembly.parts[-1].id)))
			check(game.build_drop_area.get_global_rect().has_point(engine_screen),"Reset keeps lower engines accessible")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: nested lower-stage engine drag, eight-way symmetry, floor clearance and framing" if failures.is_empty() else "FAIL: lower-stage engine")
	quit(0 if failures.is_empty() else 1)
