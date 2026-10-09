extends Control
## Independent asset inspection workspace. All dimensions are in metres.
signal close_requested
var embedded := false

const ASSETS := [
	["Canister–1 / fuel vessel", "res://assets/models/canister_1/canister_1.glb", Vector3.ZERO, 7.8],
	["Explorer–1 / crew capsule", "res://assets/models/explorer_1/explorer_1.glb", Vector3(0,1.23,0), 5.5],
	["Atlas–1 / decoupler", "res://assets/models/atlas_1/atlas_1.glb", Vector3.ZERO, 3.6],
	["Engine–1 / main engine", "res://assets/models/engine_1/engine_1.glb", Vector3(0,1.35,0), 5.5],
	["Booster–1 / solid rocket booster", "res://assets/models/booster_1/booster_1.glb", Vector3(0,2.63,0), 9.0],
	["Separator–1 / booster separator", "res://assets/models/separator_1/separator_1.glb", Vector3.ZERO, 3.0],
	["Parachute–1 / packed assembly", "res://assets/models/parachute_1/parachute_1.glb", Vector3(0,0.94,0), 4.5],
	["Parachute–1 / deployed canopy", "res://assets/models/parachute_1/parachute_1_deployed.glb", Vector3(0,3.6,0), 15.0],
	["Sparrow–1 / lightweight engine", "res://assets/models/sparrow_1/sparrow_1.glb", Vector3(0,1.0,0), 4.8],
	["Gyro–1 / reaction wheel", "res://assets/models/gyro_1/gyro_1.glb", Vector3.ZERO, 3.6]
]
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var model: Node3D
var components: Array[MeshInstance3D] = []
var rest: Array[Vector3] = []
var tree: Tree
var details: Label
var target := Vector3.ZERO
var yaw := 0.55
var pitch := 0.24
var distance := 7.8
var spinning := false
var exploded := 0.0
var selected := -1
var isolate := false
var asset_index := 0
var slider: HSlider

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("111923")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var layout := HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var margin := MarginContainer.new()
	margin.custom_minimum_size.x = 370
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	layout.add_child(margin)
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 14)
	margin.add_child(panel)
	_label(panel, "BLUFFTON FLIGHT WORKS", 14)
	_label(panel, "Asset laboratory", 26)
	if embedded:
		var back := Button.new()
		back.text = "← Back to game   /   Esc"
		back.pressed.connect(func(): close_requested.emit())
		panel.add_child(back)
	_label(panel, "PART LIBRARY", 12)
	var library := OptionButton.new()
	# Debug: print available assets to help in-game troubleshooting
	print("[AssetViewer] ASSETS count:", ASSETS.size())
	for entry in ASSETS:
		print("[AssetViewer] asset:", entry[0], "->", entry[1])
	for entry in ASSETS: library.add_item(entry[0])
	library.item_selected.connect(func(idx): print("[AssetViewer] option selected:", idx, ASSETS[idx]))
	library.item_selected.connect(_load_asset)
	panel.add_child(library)
	tree = Tree.new()
	tree.custom_minimum_size = Vector2(270, 220)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.hide_root = true
	tree.item_selected.connect(_select_component)
	tree.item_edited.connect(_visibility_edited)
	panel.add_child(tree)
	var solo := CheckButton.new()
	solo.text = "Isolate selected component"
	solo.toggled.connect(func(on: bool): isolate = on; _apply_visibility())
	panel.add_child(solo)
	_label(panel, "EXPLODED ASSEMBLY", 12)
	slider = HSlider.new()
	slider.max_value = 1.0
	slider.step = .01
	slider.value_changed.connect(func(value: float): exploded = value; _explode())
	panel.add_child(slider)
	var spin := CheckButton.new()
	spin.text = "Auto rotate"
	spin.toggled.connect(func(on: bool): spinning = on)
	panel.add_child(spin)
	var views := HBoxContainer.new()
	panel.add_child(views)
	for view_name in ["Front", "Top", "Bottom", "Reset"]:
		var button := Button.new()
		button.text = view_name
		button.pressed.connect(_view.bind(view_name))
		views.add_child(button)
	details = _label(panel, "", 14)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size.y = 85
	_label(panel, "Drag to orbit · Wheel to zoom\nSelect a row to inspect a component.\nCheckboxes show or hide components.", 13)
	var container := SubViewportContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.stretch = true
	container.gui_input.connect(_orbit_input)
	layout.add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("202a35")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c3d4e8")
	env.environment.ambient_light_energy = .7
	world.add_child(env)
	for item in [[Vector3(-40,-35,0), 1.5, Color("ffecd4")], [Vector3(-20,140,0), 1.2, Color("c3ddff")]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = item[0]
		light.light_energy = item[1]
		light.light_color = item[2]
		world.add_child(light)
	camera = Camera3D.new()
	camera.fov = 40
	world.add_child(camera)
	_load_asset(0)
	if "--asset-screenshot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://assets/models/canister_1/viewer.png")
		get_tree().quit()

func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _load_asset(index: int) -> void:
	asset_index = index
	if is_instance_valid(model):
		world.remove_child(model)
		model.queue_free()
	components.clear()
	rest.clear()
	selected = -1
	var path: String = ASSETS[index][1]
	var model_res: Resource = ResourceLoader.load(path)
	model = (model_res as PackedScene).instantiate() if model_res else null
	if model == null:
		# Fallback: try instantiating a procedural placeholder if available
		print("[AssetViewer] Could not load asset, falling back to engine placeholder:", path)
		if ResourceLoader.exists("res://assets/models/engine/engine.tscn"):
			model = load("res://assets/models/engine/engine.tscn").instantiate()
		else:
			return
	world.add_child(model)
	# Wait two frames after drawing so an instantiated scene's `_ready()`
	# and any SubViewport-dependent setup has completed.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_collect(model)
	if components.size() == 0:
		details.text = "No mesh components found for this asset."
	tree.clear()
	var root := tree.create_item()
	var triangles := 0
	for i in range(components.size()):
		var item := tree.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, true)
		item.set_text(0, components[i].name.replace("_", " "))
		item.set_tooltip_text(0, components[i].name.replace("_", " "))
		item.set_metadata(0, i)
		triangles += _triangles(components[i])
	details.text = "%d components · %s triangles\nGLB / metallic–roughness materials" % [components.size(), triangles]
	_view("Reset")

func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		components.append(node)
		rest.append(node.position)
	for child in node.get_children(): _collect(child)

func _triangles(part: MeshInstance3D) -> int:
	var count := 0
	var mesh := part.mesh
	for surface in range(mesh.get_surface_count()):
		if mesh.has_method("surface_get_array_index_len"):
			var indices: int = mesh.surface_get_array_index_len(surface)
			if indices > 0:
				count += int(indices / 3)
			else:
				var arr_len: int = mesh.surface_get_array_len(surface)
				count += int(arr_len / 3)
		elif mesh.has_method("surface_get_array_len"):
			var arr_len2: int = mesh.surface_get_array_len(surface)
			count += int(arr_len2 / 3)
		else:
			# Fallback estimate for primitive meshes like CylinderMesh
			if mesh is CylinderMesh:
				var segs: int = int(mesh.radial_segments)
				var rings: int = int(mesh.rings) if mesh.rings != 0 else 1
				if segs <= 0: segs = 32
				count += int(segs * max(1, rings) * 2)
			else:
				count += 0
	return count

func _select_component() -> void:
	var sel := tree.get_selected()
	if sel == null:
		return
	var meta = sel.get_metadata(0)
	if meta == null:
		return
	selected = int(meta)
	if selected < 0 or selected >= components.size():
		return
	var part := components[selected]
	details.text = "%s\n%s triangles" % [part.name.replace("_", " "), _triangles(part)]
	_apply_visibility()

func _visibility_edited() -> void:
	_apply_visibility()

func _apply_visibility() -> void:
	var item := tree.get_root().get_first_child()
	while item:
		var meta = item.get_metadata(0)
		if meta != null:
			var i := int(meta)
			if i >= 0 and i < components.size():
				components[i].visible = item.is_checked(0) and (not isolate or selected < 0 or selected == i)
		item = item.get_next()

func _explode() -> void:
	for i in range(components.size()):
		var direction := Vector3(0, (float(i) - float(components.size()-1)/2.0)*.48, 0)
		components[i].position = rest[i] + direction*exploded

func _view(view_name: String) -> void:
	target = ASSETS[asset_index][2]
	if view_name == "Reset":
		yaw = .55
		pitch = .24
		distance = ASSETS[asset_index][3]
		slider.value = 0
	elif view_name == "Front": yaw = 0; pitch = 0
	elif view_name == "Top": yaw = 0; pitch = PI/2-.001
	elif view_name == "Bottom": yaw = 0; pitch = -PI/2+.001
	_update_camera()

func _orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		yaw -= event.relative.x*.008
		pitch = clampf(pitch+event.relative.y*.008, -PI/2+.001, PI/2-.001)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(1.2, distance*.9)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(24, distance/ .9)
	_update_camera()

func _process(delta: float) -> void:
	if spinning:
		yaw += delta*.25
		_update_camera()

func _update_camera() -> void:
	camera.position = target + Vector3(sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch))*distance
	camera.look_at(target)
