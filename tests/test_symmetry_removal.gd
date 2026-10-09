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
	game.radial_symmetry = 8
	var tanks: Array[String] = []
	for index in range(8):
		Craft.add_part(game.design.assembly,"separator","tank_2")
		var mount: Dictionary = game.design.assembly.parts[-1]
		mount.rotation = 45.0*index
		Craft.add_part(game.design.assembly,"tank",mount.id)
		tanks.append(game.design.assembly.parts[-1].id)
	game._refresh_design(false)
	await process_frame
	check(game._can_attach("tank","tank@"+tanks[0]),"Eight-way extra fuel is accepted")
	game._attach_part("tank","tank@"+tanks[0])
	await process_frame
	await process_frame
	check(game.design.tanks == 18,"Two complete rings of eight plus core tanks")
	check(Craft.valid(game.design.assembly),"18-tank craft validates")
	check(Craft.load_craft(game.design).parts == game.design.assembly.parts,"18-tank craft survives load")
	var rendered_tanks := 0
	for node in game.world._rocket.find_children("*","Node3D",true,false):
		if str(node.get_meta("part_id","")).begins_with("tank_"): rendered_tanks += 1
	check(rendered_tanks == 18,"All 18 tanks render")
	var lower: Array = game.design.assembly.parts.filter(func(part): return part.kind == "tank" and part.parent == tanks[0])
	game._attach_part("sparrow","engine@"+str(lower[0].id))
	await process_frame
	await process_frame
	check(Craft.engines(game.design).size() == 9,"Eight-way engines install below added tanks")
	var full: Dictionary = game.design.assembly.duplicate(true)
	game.radial_symmetry = 1
	game._begin_return_drag(tanks[0])
	check(game._affected_part_ids(tanks[0]).size() == 24,"Removal preview includes eight complete branches")
	game._remove_part_to_catalogue(tanks[0])
	await process_frame
	await process_frame
	check(game.design.tanks == 2 and Craft.engines(game.design).size() == 1,"Normal drag removes all matching tanks and engines")
	game._undo_edit()
	await process_frame
	check(game.design.assembly == full,"Undo restores whole group")
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.physical_keycode = KEY_SHIFT
	shift.pressed = true
	shift.shift_pressed = true
	Input.parse_input_event(shift)
	Input.flush_buffered_events()
	game._begin_return_drag(tanks[0])
	shift = InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.physical_keycode = KEY_SHIFT
	shift.pressed = false
	Input.parse_input_event(shift)
	check(game.return_drag_single,"Shift is captured at drag start")
	check(game._affected_part_ids(tanks[0]).size() == 3,"Shift preview includes one branch")
	game._remove_part_to_catalogue(tanks[0])
	await process_frame
	await process_frame
	check(game.design.tanks == 16 and Craft.engines(game.design).size() == 8,"Shift drag removes one stack only")
	game._remove_part_to_catalogue(tanks[1])
	await process_frame
	await process_frame
	check(game.design.tanks == 2,"Normal removal handles remaining seven copies")
	game._undo_edit()
	await process_frame
	game._undo_edit()
	await process_frame
	game.selected_part = tanks[0]
	var delete := InputEventKey.new()
	delete.physical_keycode = KEY_DELETE
	delete.pressed = true
	game._input(delete)
	await process_frame
	check(game.design.tanks == 2,"Delete removes group")
	check(Craft.valid(game.design.assembly),"Removal keeps staging valid")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: eight-way fuel, group removal, Shift drag, Delete and undo" if failures.is_empty() else "FAIL: symmetry removal")
	quit(0 if failures.is_empty() else 1)
