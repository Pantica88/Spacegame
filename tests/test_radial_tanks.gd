extends SceneTree
const Craft = preload("res://scripts/craft_model.gd")
const Parts = preload("res://scripts/parts.gd")
const Flight = preload("res://scripts/flight_model.gd")
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	if not value: failures.append(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for count in [1,2,4,6,8]:
		var craft := Craft.migrate(Parts.default_design())
		var mounts: Array[String] = []
		for index in range(count):
			Craft.add_part(craft,"separator","tank_2")
			craft.parts[-1].rotation = 360.0*index/count
			mounts.append(craft.parts[-1].id)
		for mount in mounts:
			Craft.add_part(craft,"tank",mount)
			var tank: String = craft.parts[-1].id
			Craft.add_part(craft,"sparrow",tank)
		check(Craft.valid(craft),"Side assembly validates at symmetry %d" % count)
		check(craft.stages.all(func(stage): return stage.size() == 1), "Each added radial activation has its own block at symmetry %d" % count)
		check(craft.parts.filter(func(part): return part.kind in Craft.ENGINE_IDS).size() == count+1,"Every side tank gets an engine at symmetry %d" % count)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.design = Craft.project(Craft.migrate(Parts.default_design()),Parts.default_design())
	game.radial_symmetry = 2
	for angle in [90.0,270.0]:
		Craft.add_part(game.design.assembly,"separator","tank_2")
		game.design.assembly.parts[-1].rotation = angle
	game._refresh_design(false)
	await process_frame
	var height := Craft.stack_top(game.design)
	var target := Vector3(2.2,Craft.tank_center(game.design,"tank_2"),0)
	var screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(target))
	check(game._update_build_drag("tank",screen),"Side tanks snap to separators")
	check(game.drag_snap_slot == "radial_tank","Side tank uses radial slot")
	check(game.radial_snap.get("placements",[]).size() == 2,"Two tank previews")
	game._finish_build_drag("tank",screen)
	await process_frame
	await process_frame
	var side_tanks: Array = game.design.assembly.parts.filter(func(part): return part.kind == "tank" and not Craft.radial_mount(game.design.assembly,part.id).is_empty())
	check(side_tanks.size() == 2,"Symmetry installs two tanks")
	var separation_blocks: Array = game.design.assembly.stages.filter(func(stage): return stage.any(func(action): return action.begins_with("separate:separator_")))
	check(separation_blocks.size() == 1 and separation_blocks[0].size() == 2, "Symmetric separators share one activation block")
	check(Craft.free_mounts(game.design.assembly).is_empty(),"Tanks occupy booster mounts")
	check(is_equal_approx(Craft.stack_top(game.design),height),"Side tanks preserve core height")
	for tank in side_tanks:
		var position: Vector3 = game.world.installed_part_position(tank.id)
		check(is_equal_approx(absf(position.x),2.2),"Tank picker follows side position")
		var candidates: Array = game._snap_candidates("sparrow").filter(func(candidate): return candidate[0] == "engine@"+tank.id)
		check(candidates.size() == 1,"Engine mount offered beneath side tank")
		if candidates.is_empty(): continue
		var engine_screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(candidates[0][1]))
		game._finish_build_drag("sparrow",engine_screen)
		await process_frame
		await process_frame
		check(game.design.assembly.parts.any(func(part): return part.kind == "sparrow" and part.parent == tank.id),"Drag installs engine on side tank")
	check(Craft.valid(game.design.assembly),"Side assembly validates")
	var engine_blocks: Array = game.design.assembly.stages.filter(func(stage): return stage.any(func(action): return action.begins_with("ignite:engine_")))
	check(engine_blocks.size() == 1 and engine_blocks[0].size() == 2, "Symmetric engines start in one activation block")
	var loaded := Craft.load_craft(game.design)
	check(loaded.parts == game.design.assembly.parts,"Side assembly survives save/load")
	check(is_equal_approx(Craft.stack_top(game.design),height),"Side engines preserve core height")
	var flight := Flight.new()
	flight.reset(game.design)
	for tank in side_tanks:
		var engines: Array = game.design.assembly.parts.filter(func(part): return part.parent == tank.id and part.kind in Craft.ENGINE_IDS)
		if engines.is_empty(): continue
		check(is_equal_approx(flight.state.engine_fuel.get(engines[0].id,0.0),Parts.TANK_FUEL_MASS),"Side engine has independent fuel")
	var fuel: float = flight.state.fuel
	if not side_tanks.is_empty():
		var mount: String = side_tanks[0].parent
		flight._separate_engine_stage(mount)
		check(flight.state.removed_parts.has(side_tanks[0].id),"Side tank detaches with separator")
		check(not flight.state.removed_parts.has("engine"),"Core engine remains attached")
		check(is_equal_approx(fuel-flight.state.fuel,Parts.TANK_FUEL_MASS),"Separation discards side fuel only")
		check(absf(flight.state.detached[-1].local_center.x) > 2.0,"Detached branch retains lateral position")
		check(is_zero_approx(flight.state.get("stack_bottom",0.0)),"Side separation preserves core base")
	# Extending an occupied tank inserts fuel above its engine on both copies.
	var first_tank: String = side_tanks[0].id
	var before_tanks: int = game.design.tanks
	await drag_to_slot(game,"tank","tank@"+first_tank)
	await process_frame
	await process_frame
	check(game.design.tanks == before_tanks+2,"Extra fuel installs on both side stacks")
	var side_engines: Array = game.design.assembly.parts.filter(func(part): return part.kind in Craft.ENGINE_IDS and not Craft.radial_mount(game.design.assembly,part.id).is_empty())
	check(side_engines.size() == 2,"Adding fuel preserves both engines")
	var first_engine: String = side_engines[0].id
	await drag_to_slot(game,"decoupler","decoupler@"+first_engine)
	await process_frame
	await process_frame
	var side_decouplers: Array = game.design.assembly.parts.filter(func(part): return part.kind == "decoupler" and not Craft.radial_mount(game.design.assembly,part.id).is_empty())
	check(side_decouplers.size() == 2,"Engine decouplers follow symmetry")
	if not side_decouplers.is_empty():
		game._attach_part("tank","tank@"+str(side_decouplers[0].id))
		await process_frame
		await process_frame
		var lower_tanks: Array = game.design.assembly.parts.filter(func(part): return part.kind == "tank" and part.parent == side_decouplers[0].id)
		check(lower_tanks.size() == 1 and game.design.tanks == before_tanks+4,"Fuel mounts beneath both engine decouplers")
		if not lower_tanks.is_empty():
			var slot := "side_decoupler@"+str(lower_tanks[0].id)
			check(game._can_attach("decoupler",slot),"Empty side tank accepts decoupler")
			await drag_to_slot(game,"decoupler",slot)
			await process_frame
			await process_frame
			var new_decouplers: Array = game.design.assembly.parts.filter(func(part): return part.kind == "decoupler" and part.parent == lower_tanks[0].id)
			check(new_decouplers.size() == 1,"Tank-mounted decoupler installed")
			if not new_decouplers.is_empty():
				game._attach_part("tank","tank@"+str(new_decouplers[0].id))
				await process_frame
				await process_frame
				var bottoms: Array = game.design.assembly.parts.filter(func(part): return part.kind == "tank" and part.parent == new_decouplers[0].id)
				if not bottoms.is_empty():
					await drag_to_slot(game,"kestrel","engine@"+str(bottoms[0].id))
					await process_frame
					await process_frame
					check(game.design.assembly.parts.filter(func(part): return part.kind == "kestrel").size() == 2,"One engine placement installs both symmetric engines")
	check(Craft.valid(game.design.assembly),"Extended symmetric stacks validate")
	check(Craft.load_craft(game.design).parts == game.design.assembly.parts,"Extended stacks survive save/load")
	var snapshot: Dictionary = game.design.assembly.duplicate(true)
	game.radial_symmetry = 4
	game._attach_part("tank","tank@"+first_tank)
	await process_frame
	check(game.design.assembly == snapshot,"Missing symmetric counterparts reject entire edit")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: radial tanks, engine drag, save/load, fuel and separation" if failures.is_empty() else "FAIL: radial tanks")
	quit(0 if failures.is_empty() else 1)

func drag_to_slot(game: Node, kind: String, slot: String) -> void:
	var candidates: Array = game._snap_candidates(kind).filter(func(candidate): return candidate[0] == slot)
	check(not candidates.is_empty(),"Drag target exists: "+slot)
	if candidates.is_empty(): return
	var screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(candidates[0][1]))
	check(game._update_build_drag(kind,screen),"Drag snaps: "+slot)
	check(game.drag_snap_slot == slot,"Drag selects expected side connection")
	check(game.world._edit_preview.get_child_count() == 2,"Preview shows both symmetric parts")
	game._finish_build_drag(kind,screen)
	await process_frame
	await process_frame
