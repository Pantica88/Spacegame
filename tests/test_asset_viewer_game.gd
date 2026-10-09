extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var design: Dictionary = game.design.duplicate(true)
	game._show_asset_viewer()
	assert(game.paused and game.asset_viewer.embedded)
	assert(game.asset_viewer.components.size() == 9)
	assert(root.disable_3d)
	game.asset_viewer.close_requested.emit()
	assert(game.asset_viewer == null and not game.paused)
	assert(game.design == design)
	assert(not root.disable_3d)
	game._toggle_pause()
	game._show_asset_viewer()
	assert(game.modal == null)
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	game._input(escape)
	assert(game.asset_viewer == null and not game.paused)
	await game._roll_out()
	game._show_asset_viewer()
	var time: float = game.flight.simulation_time()
	game._physics_process(1.0)
	assert(game.flight.simulation_time() == time)
	game._close_asset_viewer()
	assert(game.mode == "flight")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	print("PASS: in-game viewer opens, closes with button/Escape, preserves design and pauses flight")
	quit()
