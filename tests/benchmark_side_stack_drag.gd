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
	for kind in ["decoupler", "tank", "sparrow"]:
		var candidates: Array = game._snap_candidates(kind)
		var target: Array = []
		for candidate in candidates:
			if "@" in candidate[0] and game._can_attach(kind, candidate[0]):
				target = candidate
				break
		assert(not target.is_empty())
		var screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(target[1]))
		game._update_build_drag(kind, screen)
		var start := Time.get_ticks_usec()
		var preview: Node3D = game.world._edit_preview
		assert(preview.get_child_count() == 8, "Side-stack preview contains eight parts")
		for frame in range(30):
			assert(game._update_build_drag(kind, screen))
			assert(game.world._edit_preview == preview, "Pointer updates reuse the preview")
		var elapsed := (Time.get_ticks_usec()-start)/30000.0
		print("DRAG %s ms: %.3f" % [kind, elapsed])
		assert(elapsed < 16.0, "Side-stack drag fits in a 60 FPS frame budget")
		var slot: String = target[0]
		var expected: Dictionary = game._calculate_side_stack_edit(kind, slot)
		assert(game._side_stack_edit(kind, slot) == expected, "Cached edit matches full validation")
		var copy: Dictionary = game._side_stack_edit(kind, slot)
		copy.parts.clear()
		assert(game._side_stack_edit(kind, slot) == expected, "Callers cannot mutate the cached edit")
		game.radial_symmetry = 1
		assert(game._side_stack_edit(kind, slot) == game._calculate_side_stack_edit(kind, slot), "Symmetry invalidates edit cache")
		game.radial_symmetry = 8
		var before: Dictionary = game.design.assembly.duplicate(true)
		game.design.assembly.stages.reverse()
		assert(game._side_stack_edit(kind, slot) == game._calculate_side_stack_edit(kind, slot), "Stage reordering invalidates edit cache")
		game.design.assembly = before.duplicate(true)
		game._attach_part(kind, slot)
		await process_frame
		await process_frame
		var normalized := Craft.load_craft(Craft.project(expected, game.design))
		assert(game.design.assembly == normalized, "Placement applies the validated eight-way edit")
		game._undo_edit()
		await process_frame
		assert(game.design.assembly == before, "Undo restores the craft")
		assert(game._side_stack_edit(kind, slot) == expected, "Undo invalidates edit cache")
		game._clear_build_drag()
	game.queue_free()
	await process_frame
	print("PASS: eight-way decoupler, tank and engine drag, placement, cache invalidation and undo")
	quit()
