extends SceneTree
const Parts = preload("res://scripts/parts.gd")
const Craft = Parts.Craft
const Profile = preload("res://scripts/profile.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var game := preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.design = Craft.project(Craft.migrate(Parts.default_design()), Parts.default_design())
	game._refresh_design(false)
	var world = game.world
	for count in range(3, Craft.MAX_TANKS + 1):
		assert(game._part_available("tank") and game._can_attach("tank", "tank"), "Tank available throughout tall build")
		var candidates: Array = game._snap_candidates("tank")
		var target: Vector2 = world.camera.unproject_position(world._rocket.to_global(candidates[0][1]))
		game._finish_build_drag("tank", target)
		await process_frame
		await process_frame
		assert(game.design.tanks == count, "Tank drop grows connected stack")
		assert(Craft.valid(game.design.assembly), "Tall assembly remains valid")
		if count > 4:
			assert(world._rocket.position.y >= 0.99, "Tall stack clears workshop floor")
			var top: Vector2 = world.camera.unproject_position(world._rocket.to_global(Vector3(0, world._height, 0)))
			var bottom: Vector2 = world.camera.unproject_position(world._rocket.position)
			var canvas: Rect2 = game.build_drop_area.get_global_rect()
			assert(canvas.has_point(top) and canvas.has_point(bottom), "Growing stack remains inside assembly view")
	# Check each tank's world anchor, independently of authored scene names.
	var tank_parts: Array = game.design.assembly.parts.filter(func(part): return part.kind == "tank")
	assert(tank_parts.size() == Craft.MAX_TANKS)
	for index in range(1, tank_parts.size()):
		var above: Vector3 = world.installed_part_position(tank_parts[index-1].id)
		var below: Vector3 = world.installed_part_position(tank_parts[index].id)
		assert(is_equal_approx(above.y - below.y, 2.15), "Every rendered tank has a distinct connected position")
	await process_frame
	var mid_picker: Control
	for picker in game.attachment_layer.get_children():
		if picker.get("part_id") == tank_parts[7].id: mid_picker = picker
	assert(mid_picker != null and mid_picker.size.y < 50.0, "Tall-stack tank picker follows visible tank size")
	var hover := InputEventMouseMotion.new()
	hover.position = mid_picker.get_global_rect().get_center()
	root.push_input(hover, true)
	assert(root.gui_get_hovered_control() == mid_picker, "Individual middle tank remains selectable when zoomed out")
	assert(not game._part_available("tank") and not game._can_attach("tank", "tank"), "Catalogue enforces new limit")
	Craft.add_part(game.design.assembly, "tank")
	assert(game.design.assembly.parts.filter(func(part): return part.kind == "tank").size() == Craft.MAX_TANKS, "Model also enforces limit")
	var stats := Parts.stats(game.design)
	assert(is_equal_approx(stats.core_fuel_mass, Craft.MAX_TANKS * Parts.TANK_FUEL_MASS), "All tall-stack fuel contributes to stats")
	game._save_design()
	var saved := Profile.new()
	assert(saved.last_error.is_empty() and saved.data.design.tanks == Craft.MAX_TANKS, "Tall rocket survives save/reload")
	var restored: Dictionary = saved.data.design.assembly.duplicate(true)
	assert(is_equal_approx(restored.root_height,game.design.assembly.root_height), "Raised root survives JSON float round trip")
	restored.root_height = game.design.assembly.root_height
	assert(restored == game.design.assembly, "Connections and stages survive saving")
	var reopened := preload("res://scripts/world_view.gd").new()
	reopened.set_design(saved.data.design)
	root.add_child(reopened)
	assert(reopened._distance > 60.0 and reopened._rocket.position.y >= 0.99, "Opening a saved tall rocket frames it above the floor")
	reopened.queue_free()
	await process_frame
	await process_frame
	world.camera.make_current()
	game._undo_edit()
	assert(game.design.tanks == Craft.MAX_TANKS - 1, "Undo removes last tall-stack addition")
	game._redo_edit()
	assert(game.design.tanks == Craft.MAX_TANKS, "Redo restores tall stack")
	var focus: Vector3 = world._camera_focus
	world.pan_workshop_camera(Vector2(0, 100))
	assert(world._camera_focus.distance_to(focus) > 1.0, "Panning reaches other sections of rocket")
	world.fit_workshop_camera()
	assert(world._workshop_pan.is_zero_approx(), "Fit clears pan offset")
	world.workshop_camera_view("Reset")
	assert(world._distance > 60.0, "Reset frames tall rocket")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/tall-rocket.png")
	# A launchable taller design exercises the physical model and location switch.
	game.design = Parts.default_design()
	game.design.tanks = 8
	game.design.engine = "titan"
	game._refresh_design(false)
	assert(not game.launch_button.disabled, "Sufficient thrust permits taller launch")
	await game._roll_out()
	assert(game.mode == "flight" and game.flight._design.tanks == 8, "Rollout preserves tall design")
	game._stage()
	for step in range(100): game.flight.step(0.05, {"throttle": 1.0, "sas": true})
	assert(game.flight.state.altitude > 1.0, "Tall rocket lifts off")
	game._return_workshop()
	assert(world._rocket.position.y >= 0.99, "Returning tall craft has workshop floor clearance")
	print("PASS: sixteen-tank build, spacing, framing, limits, save/reload, undo/redo, pan and eight-tank launch")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	quit()
