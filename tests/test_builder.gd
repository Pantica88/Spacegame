extends SceneTree
var game: Node
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count

func _fin_vertices(node: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh is ArrayMesh:
			var vertices: PackedVector3Array = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			if vertices.size() == 24:
				for vertex in vertices:
					result.append(child.to_global(vertex))
	return result

func _check_fin_geometry(expected: PackedVector3Array, message: String) -> void:
	var parent: Node3D = game.world._capsule if game.world._part_parent("fins") == "capsule" else game.world._lower_parts[0]
	var actual := _fin_vertices(parent)
	check(expected.size() == 96 and actual.size() == expected.size(), message + " has four fins")
	if actual.size() != expected.size(): return
	for index in range(actual.size()):
		if not actual[index].is_equal_approx(expected[index]):
			check(false, message + " matches installed vertices")
			return

func _has_hidden_model_branch(node: Node) -> bool:
	for child in node.get_children():
		if child is Node3D and not child.visible and _mesh_count(child) > 0:
			return true
		if _has_hidden_model_branch(child):
			return true
	return false

func _part_picker(id: String) -> Control:
	for child in game.attachment_layer.get_children():
		if child.get("part_id") == id:
			return child
	return null

func drag_part(part: String, slot: String) -> void:
	var card: Control
	for child in game.assembly_list.get_children():
		if child.get_script() == load("res://scripts/part_card.gd") and child.part_id == part:
			card = child
	check(card != null, "Catalogue card exists")
	if card == null:
		return
	game.assembly_list.get_parent().ensure_control_visible(card)
	await process_frame
	await process_frame
	var origin := card.get_global_rect().get_center()
	var candidates: Array = game._snap_candidates(part)
	if slot == "engine" and (candidates.is_empty() or candidates[0][0] != slot):
		candidates = game._snap_candidates("sparrow")
	check(not candidates.is_empty(), "Connection surface exists")
	if candidates.is_empty(): return
	var target: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(candidates[0][1]))
	if part == "capsule": target.y -= 72.0
	if DisplayServer.get_name() == "headless":
		game._finish_build_drag(part, target)
		await process_frame
		await process_frame
		return
	if DisplayServer.get_name() != "headless":
		root.warp_mouse(origin)
		await process_frame
		await process_frame
	var hover := InputEventMouseMotion.new()
	hover.position = origin
	root.push_input(hover, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = origin
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = origin + Vector2(35, 0)
	motion.relative = Vector2(35, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	if part == "capsule":
		var invalid := Vector2(900, 180)
		root.warp_mouse(invalid)
		await process_frame
		motion = InputEventMouseMotion.new()
		motion.position = invalid
		motion.relative = invalid - origin
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await process_frame
		await capture("invalid-red")
	if DisplayServer.get_name() != "headless":
		root.warp_mouse(target)
		await process_frame
		await process_frame
	motion = InputEventMouseMotion.new()
	motion.position = target
	motion.relative = target - origin
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	if part == "capsule": await capture("snapped-green")
	var release := InputEventMouseButton.new()
	release.position = target
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	await process_frame

func drag_stage_action(action: String, destination: int) -> void:
	if DisplayServer.get_name() == "headless":
		game._move_action(action, destination)
		await process_frame
		await process_frame
		return
	var source: Control
	var target: Control
	for group in game.stage_preview.get_children():
		if group.get_script() != load("res://scripts/stage_group.gd"): continue
		if group.index == destination: target = group
		for label in group.find_children("*", "Label", true, false):
			if label.get("action") == action: source = label
	check(source != null and target != null, "Stage action and drop group exist")
	if source == null or target == null: return
	game.stage_preview.get_parent().ensure_control_visible(source)
	await process_frame
	var origin := source.get_global_rect().get_center()
	if DisplayServer.get_name() != "headless":
		root.warp_mouse(origin)
		await process_frame
		await process_frame
	var hover := InputEventMouseMotion.new()
	hover.position = origin
	root.push_input(hover, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = origin
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	var move := InputEventMouseMotion.new()
	move.position = origin + Vector2(-30, 0)
	move.relative = Vector2(-30, 0)
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(move, true)
	await process_frame
	game.stage_preview.get_parent().ensure_control_visible(target)
	await process_frame
	var destination_point := target.get_global_rect().position + Vector2(10, 10)
	if DisplayServer.get_name() != "headless":
		root.warp_mouse(destination_point)
		await process_frame
		await process_frame
	move = InputEventMouseMotion.new()
	move.position = destination_point
	move.relative = destination_point - origin
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(move, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = destination_point
	release.button_index = MOUSE_BUTTON_LEFT
	root.push_input(release, true)
	await process_frame
	await process_frame

func drag_installed_to_catalogue(id: String) -> void:
	if DisplayServer.get_name() == "headless":
		game._remove_part_to_catalogue(id)
		await process_frame
		await process_frame
		return
	var picker: Control
	for child in game.attachment_layer.get_children():
		if child.get("part_id") == id: picker = child
	check(picker != null, "Installed part exposes a draggable handle")
	if picker == null: return
	var card: Control
	for child in game.assembly_list.get_children():
		if child.get("part_id") == "capsule": card = child
	check(card != null, "Parts catalogue provides an inventory return target")
	if card == null: return
	game.assembly_list.get_parent().ensure_control_visible(card)
	await process_frame
	var origin := picker.get_global_rect().get_center()
	var target := card.get_global_rect().get_center()
	root.warp_mouse(origin)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = origin
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = origin + Vector2(30, 0)
	motion.relative = Vector2(30, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	root.warp_mouse(target)
	await process_frame
	motion = InputEventMouseMotion.new()
	motion.position = target
	motion.relative = target - origin
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	check(game.return_drag_id == id and game.world._preview_key.begins_with("return-group:"), "Installed part starts a moving full-subassembly return preview")
	var release := InputEventMouseButton.new()
	release.position = target
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	await process_frame
	check(game.return_drag_id.is_empty() and not is_instance_valid(game.world._edit_preview), "Return preview clears after the part is removed")

func capture(name: String) -> void:
	for frame in range(4):
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/aphelion-builder-" + name + ".png")

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(true)
	game.set_physics_process(false)
	game.design = load("res://scripts/parts.gd").default_design()
	game._refresh_design(false)
	game._new_craft()
	check(game.design.assembly.parts.is_empty(), "New craft starts with an empty assembly area")
	check(game.launch_button.disabled, "Incomplete craft cannot launch")
	await capture("empty-hangar")
	var locked_tank: Control
	for child in game.assembly_list.get_children():
		if child.get("part_id") == "tank": locked_tank = child
	check(locked_tank != null and locked_tank.locked, "Only the capsule is initially available")
	await drag_part("capsule", "capsule")
	check(game.design.capsule, "Capsule begins the vehicle")
	check(absf(float(game.design.assembly.root_height) - 7.5) > 0.2, "Capsule release height becomes the saved assembly height")
	var fixed_capsule_screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(Vector3(0, game.world._capsule_center_local, 0)))
	var viewport_center_x: float = game.world.camera.get_viewport().get_visible_rect().size.x * 0.5
	check(absf(fixed_capsule_screen.x - viewport_center_x) < 1.0, "Capsule is centered in the assembly bay")
	var unlocked_decoupler: Control
	var still_locked_tank: Control
	for child in game.assembly_list.get_children():
		if child.get("part_id") == "decoupler": unlocked_decoupler = child
		if child.get("part_id") == "tank": still_locked_tank = child
	check(unlocked_decoupler != null and not unlocked_decoupler.locked and still_locked_tank != null and not still_locked_tank.locked, "Capsule unlocks decoupler and fuel tanks")
	await drag_part("tank", "tank")
	var direct_tank: Dictionary = game.design.assembly.parts.filter(func(part): return part.kind == "tank")[0]
	var direct_capsule_base: float = game.world._capsule_center_local - 1.2
	var direct_tank_top: float = game.world.installed_part_position(direct_tank.id).y + 1.075
	check(absf(direct_capsule_base - direct_tank_top) < 0.01, "Fuel tank seats flush against capsule when no decoupler is installed")
	check(game._part_available("fins") and game._part_available("separator") and game._part_available("sparrow"), "Tank unlocks fins, separators and engines without a decoupler")
	await drag_part("fins", "fins@capsule")
	check(game.design.fins and not game.design.decoupler, "Fins install on a no-decoupler craft")
	game.radial_symmetry = 2
	await drag_part("separator", "separator@" + str(direct_tank.id))
	check(game.design.separator and not game.design.decoupler, "Separators install on a no-decoupler craft")
	check(game._part_available("boosters"), "No-decoupler separators unlock boosters")
	await drag_part("boosters", "boosters")
	check(game.design.boosters and not game.design.decoupler, "Boosters install on a no-decoupler craft")
	await drag_part("sparrow", "engine")
	check(game.design.engine == "sparrow" and not game.design.decoupler, "Engines install on a no-decoupler craft")
	check(game.Parts.Craft.blockers(game.design.assembly).is_empty(), "No-decoupler craft can pass flight checks")
	check(not game.launch_button.disabled, "No-decoupler craft can roll out to the pad")
	game._new_craft()
	await drag_part("capsule", "capsule")
	await drag_part("decoupler", "decoupler")
	var capsule_after_decoupler: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(Vector3(0, game.world._capsule_center_local, 0)))
	check(capsule_after_decoupler.distance_to(fixed_capsule_screen) < 0.5, "Decoupler grows downward without moving capsule")
	var fixed_decoupler_screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(game.world.installed_part_position("decoupler")))
	var unlocked_tank: Control
	for child in game.assembly_list.get_children():
		if child.get("part_id") == "tank": unlocked_tank = child
	check(unlocked_tank != null and not unlocked_tank.locked, "Fuel tanks stay available after adding a decoupler")
	await drag_part("tank", "tank")
	var capsule_after_tank: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(Vector3(0, game.world._capsule_center_local, 0)))
	check(capsule_after_tank.distance_to(fixed_capsule_screen) < 0.5, "Tank grows downward without moving capsule")
	var decoupler_after_tank: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(game.world.installed_part_position("decoupler")))
	var decoupler_picker := _part_picker("decoupler")
	check(decoupler_after_tank.distance_to(fixed_decoupler_screen) < 0.5, "Adding fuel keeps the decoupler visually fixed beneath the capsule")
	check(decoupler_picker != null and decoupler_picker.get_global_rect().get_center().distance_to(decoupler_after_tank) < 0.5, "Decoupler hitbox stays centered on its rendered model after adding fuel")
	game.world._distance = 48.0
	game.world._update_camera()
	await process_frame
	var distant_decoupler_picker := _part_picker("decoupler")
	check(distant_decoupler_picker != null and game._part_at(distant_decoupler_picker.get_global_rect().get_center()) == "decoupler", "Distant overlapping hitboxes still resolve hover to the decoupler ring")
	game.selected_part = "decoupler"
	game.highlight_action = "part:decoupler"
	game._deselect_part()
	check(game.selected_part.is_empty() and game.highlight_action.is_empty(), "Clicking empty assembly space clears part selection")
	game.world._distance = 25.0
	game.world._update_camera()
	await process_frame
	game.world.preview_drag("sparrow", Vector3.ZERO, false, Vector2(900, 500))
	var free_engine_preview: Node3D = game.world._edit_preview
	check(free_engine_preview.get_child_count() == 1 and free_engine_preview.get_child(0).name == "SparrowEngine1", "Free Sparrow drag uses the authored engine without exhaust")
	var free_engine_meshes := _mesh_count(free_engine_preview)
	game.world.preview_drag("sparrow", game._snap_candidates("sparrow")[0][1], true, Vector2.ZERO)
	check(_mesh_count(game.world._edit_preview) == free_engine_meshes, "Sparrow snap preview retains its authored mounting collar")
	await drag_part("sparrow", "engine")
	var capsule_after_engine: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(Vector3(0, game.world._capsule_center_local, 0)))
	check(capsule_after_engine.distance_to(fixed_capsule_screen) < 0.5, "Engine grows downward without moving capsule")
	check(game.design.decoupler and game.design.tanks == 1 and game.design.engine == "sparrow", "Build a connected launch core from catalogue drops")
	check(not game.launch_button.disabled, "Completed core can launch")
	check(game._part_available("decoupler"), "Engine bottom allows another decoupler below a complete core")
	var lower_mounts: Array = game._snap_candidates("decoupler")
	check(lower_mounts.size() == 1 and lower_mounts[0][0] == "engine_decoupler", "Lower decoupler snaps below the engine")
	await drag_part("kestrel", "engine")
	await drag_part("decoupler", "engine_decoupler")
	check(game.Parts.Craft.valid(game.design.assembly), "Engine decoupler produces a valid saved assembly")
	check(game.world._part_parent("engine_decoupler") == "engine", "Lower decoupler attaches to the engine")
	check(is_instance_valid(game.world._engine_shell), "Lower decoupler encloses the engine in a shell")
	check(_part_picker("engine_decoupler") != null, "Lower decoupler can be selected")
	var shell_mesh: MeshInstance3D = game.world._engine_shell.get_child(0)
	check(shell_mesh.mesh.cap_bottom and shell_mesh.material_override.cull_mode == BaseMaterial3D.CULL_DISABLED, "Engine shell covers the nozzle from below and inside")
	var engine_model: Node3D = game.world._engine_shell.get_parent().get_node("KestrelEngine1")
	for mesh_node in engine_model.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh_node.mesh.get_surface_count()):
			var vertices: PackedVector3Array = mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3 = shell_mesh.to_local(mesh_node.to_global(vertex))
				if Vector2(point.x, point.z).length() > shell_mesh.mesh.top_radius or absf(point.y) > shell_mesh.mesh.height * 0.5 + 0.001:
					check(false, "Kestrel geometry fits completely inside the engine shell")
					break
	var fixed_engine: Vector3 = game.world._rocket.to_global(game.world.installed_part_position("engine"))
	await drag_part("tank", "tank")
	var lower_tanks: Array = game.design.assembly.parts.filter(func(part): return part.kind == "tank" and part.parent == "engine_decoupler")
	check(lower_tanks.size() == 1, "Fuel tank attaches below engine decoupler")
	if lower_tanks.size() == 1:
		var tank_top: float = game.world.installed_part_position(lower_tanks[0].id).y + 1.075
		check(is_equal_approx(tank_top, game.world.installed_part_position("engine_decoupler").y - 0.1), "Lower fuel tank seats flush against decoupler")
	check(game.world._rocket.to_global(game.world.installed_part_position("engine")).distance_to(fixed_engine) < 0.001, "Adding lower fuel keeps the engine fixed in the workshop")
	await drag_part("sparrow", "engine")
	var both_engines: Array = game.Parts.Craft.engines(game.design)
	check(both_engines.size() == 2 and both_engines[0].kind == "kestrel" and both_engines[1].kind == "sparrow", "Lower tank accepts a second engine without replacing Kestrel")
	if both_engines.size() == 2:
		var lower_engine: Dictionary = both_engines[1]
		check(lower_engine.parent == lower_tanks[0].id and _part_picker(lower_engine.id) != null, "Second engine attaches to the lower tank and can be selected")
		check(game.world._engine_flames.size() == 2, "Both installed engines are rendered")
		check(game.world._rocket.to_global(game.world.installed_part_position("engine")).distance_to(fixed_engine) < 0.001, "Adding a second engine preserves the upper engine position")
		await drag_part("titan", "engine")
		check(game.Parts.Craft.engines(game.design).size() == 2 and game.Parts.Craft.engines(game.design)[1].kind == "titan", "Replacing the lower engine keeps the upper engine")
		check(game.Parts.Craft.valid(game.design.assembly), "Two-engine craft and ignition actions are valid")
	game._remove_attachment("engine_decoupler")
	await process_frame
	await process_frame
	check(not is_instance_valid(game.world._engine_shell) and game.design.engine == "kestrel" and game.Parts.Craft.engines(game.design).size() == 1, "Removing lower decoupler removes lower engine while preserving Kestrel")
	await drag_part("sparrow", "engine")
	var decoupler_subassembly: Array[String] = game._affected_part_ids("decoupler")
	check("decoupler" in decoupler_subassembly and decoupler_subassembly.any(func(id): return str(id).begins_with("tank_")) and "engine" in decoupler_subassembly, "Selecting the decoupler includes its connected lower stack")
	var fin_surfaces: Array = game._snap_candidates("fins")
	check(fin_surfaces.size() == 2, "Fins expose capsule and fuel-tank placement surfaces")
	var capsule_fin_target: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(fin_surfaces[0][1]))
	game._update_build_drag("fins", capsule_fin_target)
	var snapped_fin_material: StandardMaterial3D = game.world._edit_preview.get_meta("glow_material")
	check(not snapped_fin_material.no_depth_test, "Valid fin snap preview uses installed-model depth occlusion")
	var capsule_preview_vertices := _fin_vertices(game.world._edit_preview)
	game._finish_build_drag("fins", capsule_fin_target)
	await process_frame
	await process_frame
	var installed_fins: Array = game.design.assembly.parts.filter(func(part): return part.kind == "fins")
	check(installed_fins.size() == 1 and installed_fins[0].parent == "capsule", "Fins attach to the chosen capsule surface")
	_check_fin_geometry(capsule_preview_vertices, "Capsule snap preview")
	await capture("capsule-fins-aligned")
	var capsule_fin_model: Node3D = game.world._make_drag_model("fins", false, true)
	check(capsule_fin_model.get_children().any(func(fin): return fin is MeshInstance3D and fin.mesh.get_aabb().position.y < -0.8 and fin.mesh.get_aabb().end.y > 0.8), "Capsule-mounted fins stay upright while following the tapered hull")
	var shaped_capsule_fin: MeshInstance3D = capsule_fin_model.get_children()[0]
	var capsule_fin_arrays: Array = shaped_capsule_fin.mesh.surface_get_arrays(0)
	var capsule_fin_vertices: PackedVector3Array = capsule_fin_arrays[Mesh.ARRAY_VERTEX]
	var has_flush_upper_vertex := false
	for vertex in capsule_fin_vertices:
		if vertex.y > 0.8 and vertex.x < 0.35: has_flush_upper_vertex = true
	check(has_flush_upper_vertex, "Capsule fin inner edge closes against the narrowing upper hull")
	capsule_fin_model.queue_free()
	await drag_installed_to_catalogue("fins")
	check(not game.design.fins, "Dragging an installed part back to inventory removes it")
	game._undo_edit()
	check(game.design.fins, "Undo restores a part returned to inventory")
	fin_surfaces = game._snap_candidates("fins")
	var tank_surface: Array = fin_surfaces.filter(func(surface): return str(surface[0]).begins_with("fins@tank_"))
	check(not tank_surface.is_empty(), "Fuel tank remains an available fin repositioning surface")
	var tank_preview_vertices := PackedVector3Array()
	if not tank_surface.is_empty():
		var adjustable_tank_anchor: Vector3 = tank_surface[0][1] + Vector3(0, 0.55, 0)
		var tank_fin_target: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(adjustable_tank_anchor))
		game._begin_return_drag("fins")
		game._update_return_drag("fins", tank_fin_target)
		tank_preview_vertices = _fin_vertices(game.world._edit_preview.get_child(0))
		game._finish_return_drag("fins", tank_fin_target)
	await process_frame
	await process_frame
	installed_fins = game.design.assembly.parts.filter(func(part): return part.kind == "fins")
	check(installed_fins.size() == 1 and str(installed_fins[0].parent).begins_with("tank_"), "Installed fins reposition onto the chosen fuel-tank surface")
	check(installed_fins.size() == 1 and float(installed_fins[0].surface_offset) > 0.3, "Fin drag preserves the chosen height along its parent surface")
	_check_fin_geometry(tank_preview_vertices, "Tank reposition preview")
	var fin_ids: Array[String] = ["fins"]
	var fin_selection: Node3D = game.world._make_installed_group(fin_ids)
	game.world._rocket.add_child(fin_selection)
	_check_fin_geometry(_fin_vertices(fin_selection.get_child(0)), "Tank selection outline")
	fin_selection.queue_free()
	await drag_part("tank", "tank")
	await capture("parts")
	var selected_id: String = game.design.assembly.parts.filter(func(part): return part.kind == "tank")[0].id
	game.selected_part = ""
	game.hovered_part = selected_id
	await capture("hovered-mint")
	game.hovered_part = ""
	game.selected_part = selected_id
	await capture("selected-orange")
	var rotate := InputEventKey.new()
	rotate.physical_keycode = KEY_R
	rotate.pressed = true
	root.push_input(rotate, true)
	await process_frame
	check(game.design.assembly.parts.filter(func(part): return part.id == selected_id)[0].rotation == 90, "Selected tank rotation is stored on that part")
	game._undo_edit()
	check(game.design.assembly.parts.filter(func(part): return part.id == selected_id)[0].rotation == 0, "Undo restores part rotation")
	game.selected_part = ""

	await drag_part("tank", "tank")
	check(game.design.tanks == 3, "Add tank updates design")
	game._remove_attachment("tank")
	await process_frame
	await process_frame
	check(game.design.tanks == 2, "Remove tank updates design")
	check(not game._part_available("boosters"), "Boosters require separate mounting hardware")
	game.radial_symmetry = 2
	var camera_local: Vector3 = game.world._rocket.to_local(game.world.camera.global_position)
	var surface_angle := atan2(camera_local.x,camera_local.z)+.2
	var tanks_now: Array = game.design.assembly.parts.filter(func(part): return part.kind == "tank")
	var mount_parent: String = tanks_now[-1].id
	var surface_point := Vector3(sin(surface_angle)*.94,game.world.installed_part_position(mount_parent).y+.2,cos(surface_angle)*.94)
	var separator_target: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(surface_point))
	game._finish_build_drag("separator", separator_target)
	await process_frame
	await process_frame
	var mounts: Array = game.Parts.Craft.radial_instances(game.design,"separator")
	check(mounts.size() == 2, "Two-way surface symmetry installs independent separators")
	check(game._part_available("boosters"), "Mounted separators unlock boosters")
	var booster_position: Vector3 = mounts[0].position
	booster_position.x *= 1.96/1.17
	booster_position.z *= 1.96/1.17
	var booster_target: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(booster_position))
	game._finish_build_drag("boosters", booster_target)
	await process_frame
	await process_frame
	check(game.design.boosters, "Attach boosters updates design")
	check(game.world._booster_flames.size() == 8, "Four aligned exhausts per Booster-1")
	var mount_id: String = mounts[0].id
	var move_point := surface_point
	move_point.y = game.world.installed_part_position(tanks_now[0].id).y
	var relocation_mouse: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(move_point))
	game._begin_return_drag(mount_id)
	game._finish_return_drag(mount_id, relocation_mouse)
	await process_frame
	await process_frame
	check(game.world._part_parent(mount_id) == tanks_now[0].id, "Separator reattaches to another tank surface")
	check(game.Parts.Craft.valid(game.design.assembly), "Repositioned radial subassembly remains serializable")
	game._undo_edit()
	await process_frame
	await process_frame
	check(game.world._part_parent(mount_id) == mount_parent, "Undo restores side mount and its booster")
	await capture("radial-parts")
	await drag_part("kestrel", "engine")
	check(game.design.engine == "kestrel", "Drag engine replaces mounted engine")
	var unchanged_tanks: int = game.design.tanks
	game._finish_build_drag("tank", Vector2(850, 180))
	check(game.design.engine == "kestrel" and game.design.tanks == unchanged_tanks, "Dropping away from a connection rejects the tank")
	for index in range(game.Parts.Craft.MAX_TANKS - int(game.design.tanks) + 1):
		await drag_part("tank", "tank")
	check(game.design.tanks == game.Parts.Craft.MAX_TANKS, "Full tank stack rejects extra drops")
	game._remove_attachment("tank")
	await process_frame
	await process_frame
	check(game.design.engine.is_empty() and not game.design.boosters, "Removing a parent tank removes its connected lower subassembly")
	check(not game.design.assembly.stages.any(func(stage): return stage.has("ignite:engine") or stage.has("ignite:boosters")), "Subassembly removal clears all descendant stage actions")
	game._undo_edit()
	await process_frame
	check(game.design.engine == "kestrel" and game.design.boosters, "Undo restores the removed lower subassembly")
	# Continue the staging flight with a compact known-good booster craft; the
	# maximum-height graph above exists specifically to exercise subtree removal.
	var staging_legacy: Dictionary = load("res://scripts/parts.gd").default_design()
	staging_legacy.boosters = true
	staging_legacy.booster_first = false
	game.design = load("res://scripts/craft_model.gd").project(load("res://scripts/craft_model.gd").migrate(staging_legacy), staging_legacy)
	game._refresh_design(false)
	var booster_separation_stage := -1
	for index in range(game.design.assembly.stages.size()):
		if game.design.assembly.stages[index].has("separate:boosters"): booster_separation_stage = index
	check(booster_separation_stage >= 0, "Restored lower subassembly retains its booster separation stage")
	if booster_separation_stage >= 0: await drag_stage_action("ignite:engine", booster_separation_stage)
	await process_frame
	await process_frame
	check(game.design.booster_first, "Moving core action creates booster-first plan")
	game._undo_edit()
	check(not game.design.booster_first, "Undo restores stage assignment")
	game._redo_edit()
	check(game.design.booster_first, "Redo restores edited stage assignment")
	game._save_design()
	var reloaded = load("res://scripts/profile.gd").new()
	check(reloaded.data.design.booster_first, "Ignition plan survives saved profile reload")
	check(absf(float(reloaded.data.design.assembly.root_height) - float(game.design.assembly.root_height)) < 0.01, "Capsule assembly height survives saved profile reload")
	await capture("stages")
	await game._roll_out()
	game._stage()
	check(not game.flight.state.engine_on and game.flight.state.boosters_on, "Launch follows selected ignition plan")
	for frame in range(600):
		game.flight.step(1.0 / 60.0, {"throttle": 1.0})
	game.world.sync_flight(game.flight.telemetry(), 0.0)
	game._update_flight_ui()
	await capture("booster-flight")
	check(game.stage_button.text.to_lower().contains("ignite core"), "HUD previews the next planned action")
	game._stage()
	check(game.flight.state.engine_on and not game.flight.state.boosters_attached, "Space performs combined booster separation and core ignition")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for message in failures:
		push_error(message)
	if failures.is_empty():
		print("PASS: builder controls, saved staging plan, booster-first rollout and HUD")
	quit(0 if failures.is_empty() else 1)
