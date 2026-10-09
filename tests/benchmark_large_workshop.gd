extends SceneTree
const Fixture = preload("res://tests/large_craft_fixture.gd")
const Craft = preload("res://scripts/craft_model.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var design := Fixture.design()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.design = design
	game.radial_symmetry = 8
	var start := Time.get_ticks_usec()
	game._refresh_design(false)
	print("LARGE REFRESH ms: ", (Time.get_ticks_usec()-start)/1000.0)
	var stage_rows: Array = game.stage_preview.get_children()
	for operation in ["_refresh_assembly", "_refresh_part_selection"]:
		start = Time.get_ticks_usec()
		game.call(operation)
		print("LARGE %s ms: %.2f" % [operation, (Time.get_ticks_usec()-start)/1000.0])
	assert(game.stage_preview.get_children() == stage_rows, "Unchanged stages retain their controls between workshop refreshes")
	for kind in ["decoupler", "tank", "sparrow"]:
		start = Time.get_ticks_usec()
		var candidates: Array = game._snap_candidates(kind)
		print("LARGE CANDIDATES %s ms: %.2f" % [kind,(Time.get_ticks_usec()-start)/1000.0])
		var target: Array = []
		for candidate in candidates:
			if "@" in candidate[0] and game._can_attach(kind,candidate[0]): target = candidate
		assert(not target.is_empty())
		var screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(target[1]))
		start = Time.get_ticks_usec()
		game._update_build_drag(kind,screen)
		print("LARGE FIRST DRAG %s ms: %.2f" % [kind,(Time.get_ticks_usec()-start)/1000.0])
		start = Time.get_ticks_usec()
		for frame in range(30): game._update_build_drag(kind,screen)
		var elapsed := (Time.get_ticks_usec()-start)/30000.0
		print("LARGE REPEATED DRAG %s ms: %.2f" % [kind,elapsed])
		assert(elapsed < 16.0, "Large-craft drag update fits a 60 FPS budget")
		game._clear_build_drag()
	# Exercise target changes and cancelled drags across many rendered frames.
	# No full craft copies should accumulate in the attachment-validity cache.
	for cycle in range(3):
		for kind in ["decoupler", "tank", "sparrow"]:
			for candidate in game._snap_candidates(kind):
				var screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(candidate[1]))
				game._update_build_drag(kind, screen)
				await process_frame
			game._clear_build_drag()
			await process_frame
		for value in game._drag_validity.values():
			assert(value is bool, "Validation caches decisions, not complete simulated crafts")
		assert(game._drag_validity.size() < 40, "Validation cache scales by symmetric groups")
	game.queue_free()
	await process_frame
	print("PASS: large workshop benchmark")
	quit()
