extends SceneTree
const Craft = preload("res://scripts/craft_model.gd")
const Parts = preload("res://scripts/parts.gd")
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	if not value: failures.append(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.design = Craft.project(Craft.migrate(Parts.default_design()),Parts.default_design())
	game.radial_symmetry = 2
	var tanks: Array[String] = []
	for angle in [90.0,270.0]:
		Craft.add_part(game.design.assembly,"separator","tank_2")
		game.design.assembly.parts[-1].rotation = angle
		var mount: String = game.design.assembly.parts[-1].id
		Craft.add_part(game.design.assembly,"tank",mount)
		tanks.append(game.design.assembly.parts[-1].id)
	game._refresh_design(false)
	await process_frame
	var center: Vector3 = game.world.installed_part_position(tanks[0])
	var direction: Vector3 = game.world._rocket.to_local(game.world.camera.global_position)-center
	direction.y = 0
	direction = direction.normalized()
	var point := center+direction*.94
	var screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(point))
	check(game._update_build_drag("separator",screen),"Separator snaps to side tank surface")
	check(game.radial_snap.get("parents",[]) == tanks,"Separators target matching side tanks")
	game._finish_build_drag("separator",screen)
	await process_frame
	await process_frame
	var nested: Array = game.design.assembly.parts.filter(func(part): return part.kind == "separator" and part.parent in tanks)
	check(nested.size() == 2,"Two nested separators installed")
	if nested.size() == 2:
		var mounts := Craft.radial_instances(game.design,"separator").filter(func(mount): return mount.id == nested[0].id)
		var mount: Dictionary = mounts[0]
		check(mount.position.distance_to(center) > 1.16 and mount.position.distance_to(center) < 1.18,"Separator offset is relative to its tank")
		var target: Vector3 = mount.position+Vector3(sin(mount.angle),0,cos(mount.angle))*(2.2-1.17)
		var tank_screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(target))
		check(game._update_build_drag("tank",tank_screen),"Tanks snap to nested separators")
		game._finish_build_drag("tank",tank_screen)
		await process_frame
		await process_frame
		var outer: Array = game.design.assembly.parts.filter(func(part): return part.kind == "tank" and part.parent == nested[0].id)
		check(outer.size() == 1 and game.design.tanks == 6,"Nested tanks install in symmetry")
		if not outer.is_empty():
			check(game.world.installed_part_position(outer[0].id).distance_to(target) < .001,"Nested tank renders at accumulated offset")
			game._attach_part("sparrow","engine@"+str(outer[0].id))
			await process_frame
			await process_frame
			check(Craft.engines(game.design).size() == 3,"Nested engine placement follows symmetry")
		check(Craft.valid(game.design.assembly),"Nested craft validates")
		check(Craft.load_craft(game.design).parts == game.design.assembly.parts,"Nested craft survives load")
		game._remove_part_to_catalogue(nested[0].id)
		await process_frame
		await process_frame
		check(game.design.tanks == 4 and Craft.engines(game.design).size() == 1,"Nested group removal preserves parent tanks")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: nested separator snapping, symmetry, tanks, engines, save/load and removal" if failures.is_empty() else "FAIL: nested separators")
	quit(0 if failures.is_empty() else 1)
