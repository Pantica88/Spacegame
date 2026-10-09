extends SceneTree
const Craft = preload("res://scripts/craft_model.gd")
const Parts = preload("res://scripts/parts.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.design = Craft.project(Craft.migrate(Parts.default_design()), Parts.default_design())
	game.radial_symmetry = 8
	var tanks: Array[String] = []
	for i in range(8):
		Craft.add_part(game.design.assembly, "separator", "tank_2")
		var mount: Dictionary = game.design.assembly.parts[-1]
		mount.rotation = i * 45.0
		Craft.add_part(game.design.assembly, "tank", mount.id)
		tanks.append(game.design.assembly.parts[-1].id)
		Craft.add_part(game.design.assembly, "tank", tanks[-1])
		Craft.add_part(game.design.assembly, "titan", game.design.assembly.parts[-1].id)
	game._refresh_design(false)
	var started := Time.get_ticks_usec()
	for i in range(10):
		assert(game._side_stack_parents(tanks[0]).size() == 8)
	print("SIDE PARENTS ms: ", (Time.get_ticks_usec()-started)/10000.0)
	var screen := Vector2.ZERO
	var found := false
	for tank in tanks:
		for step in range(16):
			var angle := TAU * step / 16.0
			var point := Craft.lateral_position(game.design,tank)+Vector3(sin(angle)*.94,Craft.tank_center(game.design,tank)+.23,cos(angle)*.94)
			var candidate: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(point))
			var snap: Dictionary = game._radial_surface_snap("separator",candidate)
			if snap.get("parents", []).size() == 8 and snap.parents[0] in tanks:
				screen = candidate
				found = true
				break
		if found: break
	assert(found, "Can snap eight separators onto the side tanks")
	started = Time.get_ticks_usec()
	for i in range(60):
		assert(game._radial_surface_snap("separator",screen).placements.size() == 8)
	var elapsed := (Time.get_ticks_usec()-started)/60000.0
	print("SNAP ms: ", elapsed)
	assert(elapsed < 16.0, "Separator snapping fits within a 60 FPS frame budget")
	var before: Dictionary = game.design.assembly.duplicate(true)
	game._finish_build_drag("separator", screen)
	await process_frame
	await process_frame
	game._ensure_snap_geometry()
	assert(game._snap_separators.size() == 16, "Adding nested separators invalidates cached geometry")
	assert(game._radial_surface_snap("separator", screen).is_empty(), "Occupied side tank positions reject duplicates")
	for tank in tanks:
		assert(game.design.assembly.parts.any(func(part): return part.kind == "separator" and part.parent == tank), "One separator is added per side tank")
	for target in [tanks[0], str(game.design.assembly.parts[-1].id)]:
		started = Time.get_ticks_usec()
		var ids: Array[String] = game._affected_part_ids(target)
		print("HOVER IDS ms: ", (Time.get_ticks_usec()-started)/1000.0)
		started = Time.get_ticks_usec()
		game.world.preview_subassembly(ids, false)
		var build_ms := (Time.get_ticks_usec()-started)/1000.0
		print("HOVER BUILD ms: ", build_ms)
		assert(build_ms < 100.0, "Hover avoids repeated full radial layout scans")
		await process_frame
	var preview: Node3D = game.world._edit_preview
	game.workshop_orbit_drag = true
	for frame in range(120):
		game.world.orbit_camera(Vector2(8, 0))
		game._process(1.0 / 60.0)
		assert(game.world._edit_preview == preview, "Camera orbit retains its outline")
	game.workshop_orbit_drag = false
	game.workshop_pan_drag = true
	game._process(1.0 / 60.0)
	assert(game.world._edit_preview == preview, "Camera pan retains its outline")
	game.workshop_pan_drag = false
	game._undo_edit()
	await process_frame
	assert(game.design.assembly == before, "Undo restores the original craft")
	assert(game._radial_surface_snap("separator",screen).placements.size() == 8, "Undo refreshes the cached clearance")
	# Rotation edits mutate the existing dictionaries instead of replacing them.
	var mount: Dictionary = game.design.assembly.parts.filter(func(part): return part.kind == "separator")[0]
	mount.rotation += 12.0
	game._ensure_snap_geometry()
	assert(game._snap_positions[tanks[0]].is_equal_approx(Craft.lateral_position(game.design,tanks[0])), "In-place rotation invalidates positions")
	game.queue_free()
	await process_frame
	print("PASS: eight-way side separator snapping, placement, overlap, undo and rotation")
	quit()
