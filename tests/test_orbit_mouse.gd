extends SceneTree
## Dispatch real viewport mouse events; also runnable against an exported PCK.
const Physics = preload("res://scripts/physics_math.gd")
const Surface = preload("res://scripts/planet_surface.gd")
var game
var map
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()
func mouse(point: Vector2, pressed: bool, relative: Vector2 = Vector2.ZERO, motion: bool = false) -> void:
	if motion:
		var event := InputEventMouseMotion.new()
		event.position = point
		event.global_position = point
		event.relative = relative
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
func click(point: Vector2) -> void:
	mouse(point, false, Vector2.ZERO, true)
	mouse(point, true)
	mouse(point, false)
func run() -> void:
	var home: Resource = Surface.home().definition.duplicate(true)
	home.moons.clear()
	Surface.reset_home(home)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.design = game.Parts.default_design()
	await game._roll_out()
	game._stage()
	game._set_throttle(0.0)
	game.flight.state.throttle = 0.0
	var radial := Vector3(0.45, 0.34, 0.82).normalized() * 100000.0
	game.flight.state.position = Physics.PLANET_CENTER + radial
	game.flight.state.velocity = radial.normalized().cross(Vector3.UP).normalized() * sqrt(Physics.MU / radial.length())
	game._toggle_map()
	game._update_flight_ui()
	map = game.map_instrument
	map.yaw = 0.9
	map.pitch = 1.05
	await process_frame
	await process_frame
	var picked := false
	for index in range(10, map._coast_points.size()-1, 5):
		var world_point: Vector3 = map._coast_points[index] * 0.001
		var point: Vector2 = map.camera.unproject_position(world_point)
		if not Rect2(Vector2(240,150), map.size-Vector2(600,240)).has_point(point): continue
		if map._point_occluded(world_point) or map._craft_icon_hit(point): continue
		if map._maneuver_path_hit(point) < 1.0: continue
		var global_point: Vector2 = map.get_global_transform_with_canvas() * point
		click(global_point)
		await process_frame
		check(map.orbit_menu.visible, "Actual viewport click opens the orbit popup")
		if not map.orbit_menu.visible:
			print("CLICK DEBUG: map local=",point," global=",global_point," mouse over=",root.gui_get_hovered_control())
		picked = true
		break
	check(picked, "A visible coast point was selected")
	if map.orbit_menu.visible:
		click(map.orbit_create_button.get_global_rect().get_center())
		await process_frame
		await process_frame
		check(map.maneuver_valid and map.maneuver_gizmo.visible, "Actual popup button click creates the six-handle plan")
		if map.maneuver_gizmo.visible:
			var handle: Dictionary = map.maneuver_gizmo.handles[0]
			var start: Vector2 = map.get_global_transform_with_canvas() * Vector2(handle.point)
			var delta: Vector2 = Vector2(handle.direction) * 30.0
			mouse(start, false, Vector2.ZERO, true)
			mouse(start, true)
			mouse(start + delta, true, delta, true)
			mouse(start + delta, false)
			await process_frame
			check(map.maneuver.components.x > 20.0, "Actual viewport drag changes burn delta-v")
			check(map.maneuver_gizmo.dragging == -1, "Actual mouse release ends the drag")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("/tmp/aphelion-real-mouse.png")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: actual viewport orbit click, popup button and maneuver drag" if failures.is_empty() else "FAIL: actual orbit mouse interaction")
	quit(0 if failures.is_empty() else 1)
