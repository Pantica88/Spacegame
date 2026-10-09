extends Node

const PlanetTerrain = preload("res://scripts/planet_terrain.gd")
const PlanetSurface = preload("res://scripts/planet_surface.gd")
const PlanetList = preload("res://scripts/planet_list.gd")
const PlanetBaker = preload("res://scripts/planet_baker.gd")
const CloudWeather = preload("res://scripts/cloud_weather_map.gd")
const CloudPaintPanel = preload("res://scripts/cloud_paint_panel.gd")

const INK := Color("101e25")
const MINT := Color("7ce5c0")
const PAPER := Color("eef2e9")
const MUTED := Color("91a8aa")
const PANEL := Color(0.055, 0.094, 0.118, 0.96)
const PREVIEW_DELAY := 0.12
const DRAFT_RESOLUTION := Vector2i(64, 32)
const SURFACE_PREVIEW_SIZE := Vector2i(1024, 512)
const SHAPING_TITLES := {"coastline_irregularity": "Coast irregularity", "mountain_height": "Mountain height", "erosion": "Erosion", "terrain_detail": "Small ridges", "detail_frequency": "Ridge frequency"}
const PREVIEW_RUNTIME_FIELDS := ["rotation_seconds", "surface_gravity", "atmosphere_density", "atmosphere_height", "atmosphere_visual_density", "ocean", "map_color", "orbit_enabled", "orbit_distance_au", "orbit_period_days", "orbit_phase", "moon_orbit_distance_km"]
const SHAPE_PRESETS := [
	{"name": "Rolling hills", "coastline_irregularity": 0.2, "mountain_height": 0.35, "erosion": 0.3, "terrain_detail": 0.2, "detail_frequency": 24.0},
	{"name": "Rugged ranges", "coastline_irregularity": 0.35, "mountain_height": 1.8, "erosion": 0.25, "terrain_detail": 0.85, "detail_frequency": 56.0},
	{"name": "Weathered ridges", "coastline_irregularity": 0.45, "mountain_height": 1.2, "erosion": 0.85, "terrain_detail": 0.65, "detail_frequency": 42.0},
	{"name": "Island coasts", "coastline_irregularity": 0.9, "mountain_height": 0.8, "erosion": 0.4, "terrain_detail": 0.3, "detail_frequency": 32.0, "sea_threshold": 0.02, "continent_frequency": 4.2},
]

var parent_settings: Resource
var moon_index := -1
var body_picker: OptionButton
var remove_moon_button: Button
var settings: Resource
var planet_paths: Array[String] = []
var current_path := ""
var planet_picker: OptionButton
var detail_picker: OptionButton
var surface_view_picker: OptionButton
var preview_stats: Label
var spin_control: CheckBox
var terrain: RefCounted
var planet: MeshInstance3D
var camera: Camera3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var world_root: Node3D
var status: Label
var name_edit: LineEdit
var controls := {}
var value_labels := {}
var yaw := 0.55
var pitch := 0.16
var distance := 180000.0
var dragging := false
var last_mouse := Vector2.ZERO
var rebuild_pending := false
var _preview_delay := 0.0
var _preview_revision := 0
var _preview_thread: Thread
var _preview_refine_pending := false
var _preview_is_refined := false
var _preview_resolution := Vector2i.ZERO
var _preview_surface_cache := {}
var cloud_tools: ScrollContainer
var cloud_layer: MeshInstance3D
var brush_ring: MeshInstance3D
var cloud_tab_active := false
var painting_clouds := false
var stroke_before: Image
var stroke_changed := false
var last_cloud_stamp := Vector3.ZERO
var cloud_undo: Array[Dictionary] = []
var cloud_redo: Array[Dictionary] = []

func _input(event: InputEvent) -> void:
	# Releases must end a stroke even when the pointer is over the settings panel.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_cloud_stroke()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		dragging = false
	if event is InputEventKey and event.pressed and not event.echo and cloud_tab_active:
		if get_viewport().gui_get_focus_owner() is LineEdit: return
		if event.ctrl_pressed or event.meta_pressed:
			if event.keycode == KEY_Z:
				if event.shift_pressed: _redo_clouds()
				else: _undo_clouds()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_Y:
				_redo_clouds()
				get_viewport().set_input_as_handled()

func _ready() -> void:
	DisplayServer.window_set_title("Aphelion - Planet Editor")
	planet_paths = PlanetList.paths()
	current_path = "res://assets/planets/verdant.tres" if "res://assets/planets/verdant.tres" in planet_paths else (planet_paths[0] if not planet_paths.is_empty() else "")
	_load_current_planet()
	_build_world()
	_build_ui()
	_rebuild_preview()

func _unhandled_input(event: InputEvent) -> void:
	if cloud_tab_active and cloud_tools != null:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_start_cloud_stroke(event.position)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion and painting_clouds:
			_paint_cloud_to(event.position)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed: _finish_cloud_stroke()
			dragging = event.pressed
			last_mouse = event.position
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var hovered := get_viewport().gui_get_hovered_control()
			if hovered != null:
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom(-1.0)
			else:
				_zoom(1.0)
	if event is InputEventMouseMotion and dragging:
		var delta: Vector2 = event.position - last_mouse
		last_mouse = event.position
		yaw -= delta.x * 0.006
		yaw = fposmod(yaw, TAU)
		pitch += delta.y * 0.004
		pitch = wrapf(pitch, -PI, PI)
		_update_camera()

func _process(delta: float) -> void:
	if not cloud_tab_active and not dragging and (spin_control == null or spin_control.button_pressed):
		world_root.rotate_y(delta * 0.08)
	_tick_preview(delta)
	_update_cloud_preview()
	if painting_clouds and get_viewport().gui_get_hovered_control() != null:
		last_cloud_stamp = Vector3.ZERO
	_update_brush_ring()

func _exit_tree() -> void:
	# Jobs own only snapshots and CPU data, never scene nodes. Join before
	# shutdown so the engine cannot dispose a running Thread.
	if _preview_thread != null:
		_preview_thread.wait_to_finish()
		_preview_thread = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_finish_cloud_stroke()
		dragging = false

func _build_world() -> void:
	world_root = Node3D.new()
	add_child(world_root)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("071017")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8ac2cb")
	environment.ambient_light_energy = 0.22
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.light_color = Color("ffedcc")
	sun.light_energy = 1.55
	sun.look_at_from_position(Vector3(-90000.0, 70000.0, 120000.0), Vector3.ZERO)
	add_child(sun)
	fill = DirectionalLight3D.new()
	fill.light_color = Color("73c5d6")
	fill.light_energy = 0.18
	fill.rotation_degrees = Vector3(-25, 155, 0)
	add_child(fill)
	planet = MeshInstance3D.new()
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/terrain.gdshader")
	planet.material_override = material
	world_root.add_child(planet)
	cloud_layer = preload("res://scripts/cloud_layer.gd").new()
	world_root.add_child(cloud_layer)
	brush_ring = MeshInstance3D.new()
	brush_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = MINT
	ring_material.no_depth_test = true
	brush_ring.material_override = ring_material
	brush_ring.visible = false
	world_root.add_child(brush_ring)
	camera = Camera3D.new()
	camera.current = true
	camera.near = 20.0
	camera.far = 500000.0
	camera.fov = 38.0
	add_child(camera)
	_update_camera()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = _theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var header := Panel.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 84
	header.add_theme_stylebox_override("panel", _style(Color(0.035, 0.064, 0.081, 0.98), Color("31454a"), 0, 0))
	ui.add_child(header)
	_label(header, "A P H E L I O N", 25).position = Vector2(28, 15)
	_label(header, "P L A N E T   E D I T O R", 11, MINT).position = Vector2(31, 49)
	var back := _button(header, "Back to workshop", func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	_rect_offsets(back, Rect2(-204, 21, 176, 42))
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	_rect_offsets(panel, Rect2(-392, 108, 368, -132))
	panel.add_theme_stylebox_override("panel", _style(PANEL, Color("31454a"), 6, 18))
	ui.add_child(panel)
	var panel_box := VBoxContainer.new()
	panel_box.add_theme_constant_override("separation", 10)
	panel_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(panel_box)
	_label(panel_box, "WORLD & WEATHER", 11, MINT)
	planet_picker = OptionButton.new()
	for path in planet_paths:
		var resource := PlanetList.load_planet(path)
		var title: String = resource.planet_name if resource != null and "planet_name" in resource else path.get_file().get_basename().capitalize()
		planet_picker.add_item("%s  (%s)" % [title, path.get_file()])
	planet_picker.item_selected.connect(func(index: int):
		current_path = planet_paths[index]
		_load_current_planet()
		_refresh_controls()
		_queue_rebuild()
	)
	panel_box.add_child(planet_picker)
	body_picker = OptionButton.new()
	body_picker.item_selected.connect(func(index: int): _select_body(index - 1))
	panel_box.add_child(body_picker)
	var moon_actions := HBoxContainer.new()
	panel_box.add_child(moon_actions)
	_button(moon_actions, "Add moon", _add_moon).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_moon_button = _button(moon_actions, "Remove moon", _remove_moon)
	remove_moon_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Body name"
	name_edit.text_changed.connect(func(text: String):
		settings.planet_name = text
		_refresh_body_picker()
	)
	panel_box.add_child(name_edit)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_box.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.name = "World"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	moon_actions.reparent(box)
	name_edit.reparent(box)
	value_labels.seed = _label(box, "", 13, MUTED)
	var seed := SpinBox.new()
	seed.min_value = 1
	seed.max_value = 999999
	seed.step = 1
	seed.rounded = true
	seed.value_changed.connect(func(value: float):
		settings.terrain_seed = int(value)
		_queue_rebuild()
	)
	controls.seed = seed
	box.add_child(seed)
	_slider(box, "radius", "Radius", 1000.0, 900000.0, 500.0)
	_slider(box, "rotation_seconds", "Rotation", 300.0, 30000.0, 10.0)
	_slider(box, "surface_gravity", "Gravity", 1.0, 25.0, 0.05)
	_slider(box, "atmosphere_density", "Air density", 0.0, 3.0, 0.01)
	_slider(box, "atmosphere_height", "Atmosphere height", 0.0, 200000.0, 500.0)
	_slider(box, "atmosphere_visual_density", "Haze density", 0.0, 3.0, 0.01)
	_label(box, "TRAJECTORY", 11, MINT)
	_checkbox(box, "orbit_enabled", "Show orbit line")
	_slider(box, "orbit_distance_au", "Orbit distance", 0.05, 40.0, 0.01)
	_slider(box, "moon_orbit_distance_km", "Distance from planet center", 1.0, 100000.0, 1.0)
	_slider(box, "orbit_period_days", "Orbit period", 0.001, 100000.0, 0.001)
	_slider(box, "orbit_phase", "Orbit phase", 0.0, 1.0, 0.01)
	_color_row(box, "map_color", "Map color")
	var terrain_scroll := ScrollContainer.new()
	terrain_scroll.name = "Terrain"
	terrain_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	terrain_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(terrain_scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	terrain_scroll.add_child(box)
	value_labels.seed.reparent(box)
	seed.reparent(box)
	_label(box, "TERRAIN SHAPE", 11, MINT)
	var shape_picker := OptionButton.new()
	shape_picker.add_item("Apply a terrain style...")
	for preset in SHAPE_PRESETS: shape_picker.add_item(preset.name)
	shape_picker.item_selected.connect(func(index: int):
		if index > 0: _apply_shape_preset(index - 1)
		shape_picker.select(0)
	)
	box.add_child(shape_picker)
	_slider(box, "sea_threshold", "Sea level", -0.35, 0.25, 0.01)
	_slider(box, "continent_frequency", "Continents", 0.6, 6.0, 0.05)
	_slider(box, "continent_edge_smoothness", "Continent edge", 0.02, 1.0, 0.01)
	_slider(box, "relief", "Relief", 0.0, 5200.0, 50.0)
	_slider(box, "mountain_frequency", "Mountains", 2.0, 18.0, 0.1)
	_slider(box, "ridge_roundness", "Ridge roundness", 0.02, 0.5, 0.01)
	_slider(box, "coastline_irregularity", SHAPING_TITLES.coastline_irregularity, 0.0, 1.0, 0.01)
	_slider(box, "mountain_height", SHAPING_TITLES.mountain_height, 0.0, 2.0, 0.01)
	_slider(box, "erosion", SHAPING_TITLES.erosion, 0.0, 1.0, 0.01)
	_slider(box, "terrain_detail", SHAPING_TITLES.terrain_detail, 0.0, 1.0, 0.01)
	_slider(box, "detail_frequency", SHAPING_TITLES.detail_frequency, 12.0, 96.0, 1.0)
	controls.coastline_irregularity.tooltip_text = "Break up regular coastlines with bays and peninsulas."
	controls.mountain_height.tooltip_text = "Adjust mountain belts independently of continent heights."
	controls.erosion.tooltip_text = "Carve ridge shoulders and gullies."
	controls.terrain_detail.tooltip_text = "Add smaller ridges within land regions."
	controls.detail_frequency.tooltip_text = "Higher values make smaller, more frequent ridges."
	_label(box, "SURFACE & PALETTE", 11, MINT)
	_checkbox(box, "has_ocean", "Ocean")
	_checkbox(box, "has_snow", "Snow")
	_checkbox(box, "launch_site", "Launch island")
	_checkbox(box, "launch_coast", "Launch coast")
	_checkbox(box, "launch_rings", "Launch rings")
	_color_row(box, "lowland", "Lowland")
	_color_row(box, "highland", "Highland")
	_color_row(box, "dryland", "Dryland")
	_color_row(box, "snow", "Snow")
	_color_row(box, "ocean", "Ocean color")
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	box.add_child(footer)
	var actions := HBoxContainer.new()
	footer.add_child(actions)
	_button(actions, "Random", _randomize_seed).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(actions, "Reset", _reset).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var preview_panel := PanelContainer.new()
	preview_panel.anchor_top = 1.0
	preview_panel.anchor_bottom = 1.0
	preview_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_rect_offsets(preview_panel, Rect2(28, -150, 460, 126))
	preview_panel.add_theme_stylebox_override("panel", _style(PANEL, Color("31454a"), 6, 10))
	ui.add_child(preview_panel)
	var preview_box := VBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 6)
	preview_panel.add_child(preview_box)
	var view_row := HBoxContainer.new()
	preview_box.add_child(view_row)
	detail_picker = OptionButton.new()
	detail_picker.add_item("Preview: adaptive detail")
	for lod_settings in PlanetTerrain.RENDER_LODS:
		detail_picker.add_item("Preview: flight from %.0f km" % (float(lod_settings.altitude)/1000.0))
	detail_picker.item_selected.connect(func(_index: int): _queue_rebuild())
	detail_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_picker.tooltip_text = "Adaptive detail keeps editing responsive. Flight previews show each saved terrain layer."
	view_row.add_child(detail_picker)
	surface_view_picker = OptionButton.new()
	for view_name in ["View: natural", "View: elevation", "View: slopes", "View: land & water"]:
		surface_view_picker.add_item(view_name)
	surface_view_picker.item_selected.connect(func(index: int):
		if planet != null and planet.material_override is ShaderMaterial:
			planet.material_override.set_shader_parameter("surface_view", index)
	)
	surface_view_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_row.add_child(surface_view_picker)
	var info_row := HBoxContainer.new()
	preview_box.add_child(info_row)
	spin_control = CheckBox.new()
	spin_control.text = "Rotate preview"
	spin_control.button_pressed = true
	info_row.add_child(spin_control)
	preview_stats = _label(info_row, "", 12, MUTED)
	preview_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cloud_tools = CloudPaintPanel.new()
	tabs.add_child(cloud_tools)
	cloud_tools.build(self)
	tabs.tab_changed.connect(func(index: int):
		_finish_cloud_stroke()
		cloud_tab_active = tabs.get_tab_control(index) == cloud_tools
		if cloud_tools != null: cloud_tools.refresh()
	)
	tabs.current_tab = 1
	cloud_tab_active = false
	_button(panel_box, "Bake & Save Planet + Moons", _save_world, true)
	status = _label(panel_box, "", 12, MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refresh_controls()

func _load_current_planet() -> void:
	_reset_cloud_history()
	var resource := PlanetList.load_planet(current_path) if not current_path.is_empty() else null
	parent_settings = resource.duplicate(true) if resource != null else PlanetSurface.HOME.duplicate(true)
	moon_index = -1
	settings = parent_settings
	distance = float(settings.radius) * 3.8

func _refresh_body_picker() -> void:
	if body_picker == null or parent_settings == null:
		return
	body_picker.clear()
	body_picker.add_item("Planet: " + parent_settings.planet_name)
	for moon in parent_settings.moons:
		body_picker.add_item("Moon: " + moon.planet_name)
	body_picker.select(moon_index + 1)
	remove_moon_button.disabled = moon_index < 0

func _select_body(index: int) -> void:
	_reset_cloud_history()
	moon_index = index
	settings = parent_settings if index < 0 else parent_settings.moons[index]
	distance = float(settings.radius) * 3.8
	_refresh_controls()
	_queue_rebuild()

func _add_moon() -> void:
	if parent_settings == null:
		parent_settings = settings
	var moon := preload("res://scripts/planet_definition.gd").new()
	moon.planet_name = "Moon %d" % (parent_settings.moons.size() + 1)
	moon.terrain_seed = randi_range(1, 999999)
	moon.radius = 16000.0
	moon.surface_gravity = 1.62
	moon.atmosphere_density = 0.0
	moon.atmosphere_height = 0.0
	moon.atmosphere_visual_density = 0.0
	moon.has_ocean = false
	moon.launch_site = false
	moon.relief = 1200.0
	moon.lowland = Color("77777a")
	moon.highland = Color("aaaaaa")
	moon.dryland = Color("888480")
	moon.map_color = Color("aaaaaa")
	moon.orbit_period_days = 0.0833333333
	moon.moon_orbit_distance_km = float(parent_settings.radius) * 0.006 + parent_settings.moons.size() * 200.0
	parent_settings.moons.append(moon)
	_select_body(parent_settings.moons.size() - 1)

func _remove_moon() -> void:
	if moon_index < 0:
		return
	parent_settings.moons.remove_at(moon_index)
	_select_body(-1)

func _slider(parent: VBoxContainer, key: String, title: String, minimum: float, maximum: float, step: float) -> void:
	var label := _label(parent, "", 13, MUTED)
	value_labels[key] = label
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.scrollable = false
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float):
		settings.set(key, value)
		_update_value_label(key, title)
		_queue_rebuild(key)
	)
	controls[key] = slider
	parent.add_child(slider)

func _checkbox(parent: VBoxContainer, key: String, title: String) -> void:
	var checkbox := CheckBox.new()
	checkbox.text = title
	checkbox.toggled.connect(func(value: bool):
		settings.set(key, value)
		_queue_rebuild(key)
	)
	controls[key] = checkbox
	parent.add_child(checkbox)

func _color_row(parent: VBoxContainer, key: String, title: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, title, 13, MUTED)
	label.custom_minimum_size.x = 120
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(120, 34)
	picker.color_changed.connect(func(color: Color):
		settings.set(key, color)
		_queue_rebuild(key)
	)
	controls[key] = picker
	row.add_child(picker)

func _queue_rebuild(key: String = "") -> void:
	if not key.is_empty() and key not in PlanetTerrain.BAKE_FIELDS:
		if terrain != null and planet != null:
			_configure_preview()
		return
	_preview_revision += 1
	rebuild_pending = true
	_preview_delay = PREVIEW_DELAY
	_preview_refine_pending = false
	_preview_is_refined = false
	if status != null:
		status.text = "Updating terrain..."

func _adaptive_resolution() -> Vector2i:
	return Vector2i(128, 64) if settings != null and distance > float(settings.radius) * 4.5 else Vector2i(256, 128)

func _tick_preview(delta: float) -> void:
	_preview_delay = maxf(0.0, _preview_delay - delta)
	if _preview_thread != null and not _preview_thread.is_alive():
		var result: Dictionary = _preview_thread.wait_to_finish()
		_preview_thread = null
		if int(result.revision) == _preview_revision:
			_apply_preview_result(result)
	if _preview_thread != null or settings == null or planet == null:
		return
	if rebuild_pending and _preview_delay <= 0.0:
		rebuild_pending = false
		_start_preview_job(false)
	elif _preview_refine_pending and not rebuild_pending:
		_preview_refine_pending = false
		_start_preview_job(true)

func _start_preview_job(refined: bool) -> void:
	var snapshot: Resource = settings.duplicate()
	var choice := detail_picker.selected if detail_picker != null else 0
	var signature := PlanetTerrain.bake_signature(snapshot)
	var cached: Dictionary = _preview_surface_cache.get(signature, {})
	_preview_thread = Thread.new()
	var error := _preview_thread.start(_generate_preview.bind(snapshot, choice, _adaptive_resolution(), refined, _preview_revision, cached))
	if error != OK:
		_preview_thread = null
		if status != null: status.text = "Preview could not start: %s" % error_string(error)

static func _generate_preview(snapshot: Resource, choice: int, adaptive: Vector2i, refined: bool, revision: int, cached: Dictionary) -> Dictionary:
	var generated := PlanetTerrain.new(snapshot)
	var resolution := adaptive if refined else DRAFT_RESOLUTION
	var include_launch := true
	var saved_mesh: ArrayMesh
	if refined and choice > 0:
		var layer: Dictionary = PlanetTerrain.RENDER_LODS[choice - 1]
		resolution = Vector2i(layer.segments, layer.rings)
		include_launch = layer.launch
		saved_mesh = generated._render_meshes.get(choice - 1)
	var result := {"terrain": generated, "resolution": resolution, "refined": refined, "revision": revision, "choice": choice, "mesh": saved_mesh, "images": {}, "cached": cached, "signature": PlanetTerrain.bake_signature(snapshot)}
	if saved_mesh == null:
		result.arrays = generated.mesh_arrays(resolution.x, resolution.y, include_launch)
	if refined and (generated.surface_texture == null or generated.topography_texture == null) and cached.is_empty():
		result.images = generated.surface_images(SURFACE_PREVIEW_SIZE.x, SURFACE_PREVIEW_SIZE.y)
	return result

func _apply_preview_result(result: Dictionary) -> void:
	terrain = result.terrain
	var cached: Dictionary = result.cached
	if not result.images.is_empty():
		cached = {"surface": terrain.surface_texture if terrain.surface_texture != null else ImageTexture.create_from_image(result.images.surface), "topography": ImageTexture.create_from_image(result.images.topography)}
		# Bound the cache to the last two worlds, rather than every slider value.
		if _preview_surface_cache.size() >= 2: _preview_surface_cache.erase(_preview_surface_cache.keys()[0])
		_preview_surface_cache[result.signature] = cached
	if not cached.is_empty():
		terrain.surface_texture = cached.surface
		terrain.topography_texture = cached.topography
	var preview_mesh: ArrayMesh = result.mesh
	if preview_mesh == null:
		preview_mesh = ArrayMesh.new()
		preview_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result.arrays)
	planet.mesh = preview_mesh
	_preview_resolution = result.resolution
	_preview_is_refined = result.refined
	_preview_refine_pending = not result.refined
	_configure_preview()
	_update_preview_stats()
	if status != null:
		status.text = "Preview ready. Bake & Save applies your terrain." if result.refined else "Refining terrain detail..."

func _rebuild_preview() -> void:
	if settings == null:
		return
	terrain = PlanetTerrain.new(settings)
	_preview_revision += 1
	rebuild_pending = false
	if planet == null:
		return
	if planet.material_override == null:
		var material := ShaderMaterial.new()
		material.shader = preload("res://assets/shaders/terrain.gdshader")
		planet.material_override = material
	_update_preview_mesh()
	_preview_is_refined = terrain.surface_texture != null and terrain.topography_texture != null
	_preview_refine_pending = not _preview_is_refined
	_configure_preview()
	_update_preview_stats()
	if status != null:
		status.text = "Right-drag orbits; wheel zooms. Clouds has painting tools."
	if cloud_tools != null: cloud_tools.refresh()
	_update_cloud_preview()

func _configure_preview() -> void:
	for key in PREVIEW_RUNTIME_FIELDS:
		terrain.definition.set(key, settings.get(key))
	var material: ShaderMaterial = planet.material_override
	terrain.configure_surface_material(material)
	if camera != null and camera.is_inside_tree():
		material.set_shader_parameter("camera_planet_km", camera.get_camera_transform().origin * 0.001)
	material.set_shader_parameter("sun_direction", Vector3(-0.45, 0.42, 0.72).normalized())
	material.set_shader_parameter("atmosphere_density_scale", settings.atmosphere_visual_density)
	material.set_shader_parameter("surface_view", surface_view_picker.selected if surface_view_picker != null else 0)
	planet.scale = Vector3.ONE
	distance = clampf(distance, float(settings.radius) * 1.35, float(settings.radius) * 5.0)
	_update_camera()

func _update_preview_stats() -> void:
	if preview_stats == null or planet.mesh == null: return
	var triangles: int = planet.mesh.surface_get_array_index_len(0) / 3
	preview_stats.text = "%s · %s triangles" % ["Detailed preview" if _preview_is_refined else "Quick preview", str(triangles)]

func _update_camera() -> void:
	if camera == null:
		return
	var radial := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	).normalized()
	camera.position = radial * distance
	# Reserve the right-hand controls while keeping the globe centered in the canvas.
	camera.h_offset = distance * 0.105
	camera.v_offset = distance * 0.025
	if camera.is_inside_tree():
		# The pitch tangent stays continuous through both poles, including when
		# upside down. Projecting world-up onto the view plane flips at a pole.
		var up := Vector3(-sin(yaw) * sin(pitch), cos(pitch), -cos(yaw) * sin(pitch))
		camera.look_at(Vector3.ZERO, up)
	camera.far = maxf(500000.0, distance + float(settings.radius) * 3.0 if settings != null else 500000.0)
	if planet != null and planet.material_override is ShaderMaterial:
		var material: ShaderMaterial = planet.material_override
		if camera.is_inside_tree():
			material.set_shader_parameter("camera_planet_km", camera.get_camera_transform().origin * 0.001)

func _zoom(amount: float) -> void:
	var previous_resolution := _adaptive_resolution()
	var radius := float(settings.radius) if settings != null else PlanetSurface.RADIUS
	distance = clampf(distance * exp(amount * 0.12), radius * 1.35, radius * 5.0)
	_update_camera()
	if detail_picker != null and detail_picker.selected == 0 and previous_resolution != _adaptive_resolution():
		_queue_rebuild()

func _randomize_seed() -> void:
	settings.terrain_seed = randi_range(1, 999999)
	_refresh_controls()
	_queue_rebuild()

func _apply_shape_preset(index: int) -> void:
	var preset: Dictionary = SHAPE_PRESETS[index]
	for key in preset:
		if key != "name": settings.set(key, preset[key])
	_refresh_controls()
	_queue_rebuild()

func _reset() -> void:
	_load_current_planet()
	_refresh_controls()
	_queue_rebuild()

func _update_preview_mesh() -> void:
	if terrain == null:
		return
	var choice := detail_picker.selected if detail_picker != null else 0
	_preview_resolution = _adaptive_resolution() if choice == 0 else Vector2i(PlanetTerrain.RENDER_LODS[choice - 1].segments, PlanetTerrain.RENDER_LODS[choice - 1].rings)
	planet.mesh = terrain.preview_mesh(_preview_resolution.x, _preview_resolution.y) if choice == 0 else terrain.render_mesh_for_lod(choice-1)

func _save_world() -> void:
	_finish_cloud_stroke()
	if current_path.is_empty():
		if status != null:
			status.text = "Save failed: no planet file selected."
		return
	if status != null:
		status.text = "Baking terrain layers..."
	if parent_settings == null:
		parent_settings = settings
	var destination := PlanetList.save_path(current_path)
	var error := PlanetBaker.save_planet(parent_settings, destination)
	if error == OK:
		var saved := ResourceLoader.load(destination, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		# Never replace the visible weather or report success if the disk round
		# trip differs. Keep the edited world available so the player can retry.
		if saved == null or not _same_saved_clouds(parent_settings, saved):
			if status != null: status.text = "Save verification failed; your edited clouds are still in the preview."
			return
		parent_settings = saved.duplicate(true)
		settings = parent_settings if moon_index < 0 else parent_settings.moons[moon_index]
		parent_settings.set_meta("source_planet_path", current_path)
		PlanetSurface.reset_home(parent_settings)
		_refresh_controls()
		_rebuild_preview()
		if status != null:
			status.text = "Saved planet and moons with terrain and cloud maps."
	else:
		if status != null:
			status.text = "Save failed: %s" % error_string(error)

func _same_saved_clouds(expected: Resource, actual: Resource) -> bool:
	if (expected.cloud_weather == null) != (actual.cloud_weather == null): return false
	if expected.cloud_weather != null:
		var before: Image = expected.cloud_weather.image
		var after: Image = actual.cloud_weather.image
		if before == null or after == null: return false
		if before.get_size() != after.get_size() or before.get_format() != after.get_format(): return false
		if before.get_data() != after.get_data(): return false
	if expected.moons.size() != actual.moons.size(): return false
	for index in range(expected.moons.size()):
		if not _same_saved_clouds(expected.moons[index], actual.moons[index]): return false
	return true

func _refresh_controls() -> void:
	if settings == null:
		return
	if name_edit == null:
		return
	if planet_picker != null and current_path in planet_paths:
		planet_picker.select(planet_paths.find(current_path))
	_refresh_body_picker()
	for key in ["orbit_distance_au", "moon_orbit_distance_km"]:
		var show_control := (moon_index < 0) if key == "orbit_distance_au" else (moon_index >= 0)
		controls[key].visible = show_control
		value_labels[key].visible = show_control
	name_edit.text = settings.planet_name
	controls.seed.set_value_no_signal(int(settings.terrain_seed))
	value_labels.seed.text = "Seed: %d" % int(settings.terrain_seed)
	for key in ["radius", "rotation_seconds", "surface_gravity", "atmosphere_density", "atmosphere_height", "atmosphere_visual_density", "orbit_distance_au", "moon_orbit_distance_km", "orbit_period_days", "orbit_phase", "sea_threshold", "continent_frequency", "continent_edge_smoothness", "relief", "mountain_frequency", "ridge_roundness"]:
		controls[key].set_value_no_signal(float(settings.get(key)))
	var titles := {"radius": "Radius", "rotation_seconds": "Rotation", "surface_gravity": "Gravity", "atmosphere_density": "Air density", "atmosphere_height": "Atmosphere height", "atmosphere_visual_density": "Haze density", "orbit_distance_au": "Orbit distance", "moon_orbit_distance_km": "Distance from planet center", "orbit_period_days": "Orbit period", "orbit_phase": "Orbit phase", "sea_threshold": "Sea level", "continent_frequency": "Continents", "continent_edge_smoothness": "Continent edge", "relief": "Relief", "mountain_frequency": "Mountains", "ridge_roundness": "Ridge roundness"}
	for key in titles:
		_update_value_label(key, titles[key])
	for key in SHAPING_TITLES:
		controls[key].set_value_no_signal(float(settings.get(key)))
		_update_value_label(key, SHAPING_TITLES[key])
	for key in ["has_ocean", "has_snow", "launch_site", "orbit_enabled", "launch_coast", "launch_rings"]:
		controls[key].set_pressed_no_signal(bool(settings.get(key)))
	for key in ["lowland", "highland", "dryland", "snow", "ocean", "map_color"]:
		controls[key].color = settings.get(key)
	if cloud_tools != null: cloud_tools.refresh()

func _update_cloud_preview() -> void:
	if settings == null or cloud_layer == null or not is_inside_tree(): return
	cloud_layer.update_weather(settings, camera.get_camera_transform().origin * 0.001, Vector3(-0.45, 0.42, 0.72).normalized(), true)

func _cloud_direction(screen_position: Vector2) -> Vector3:
	if camera == null or settings == null or not camera.is_inside_tree(): return Vector3.ZERO
	var origin := camera.project_ray_origin(screen_position)
	var ray := camera.project_ray_normal(screen_position)
	var radius := float(settings.radius) + _cloud_brush_height()
	var b := origin.dot(ray)
	var discriminant := b * b - (origin.length_squared() - radius * radius)
	if discriminant < 0.0: return Vector3.ZERO
	var hit_distance := -b - sqrt(discriminant)
	if hit_distance <= 0.0: return Vector3.ZERO
	return (world_root.global_basis.inverse() * (origin + ray * hit_distance)).normalized()

## Wind drifts the painted map; undo that rotation so paint lands under the cursor.
func _weather_space(direction: Vector3) -> Vector3:
	return (cloud_layer.drift_basis().inverse() * direction).normalized()

func _cloud_brush_height() -> float:
	var atmosphere := float(settings.atmosphere_height)
	return minf(maxf(minf(atmosphere * 0.22, 6000.0), float(settings.relief) + 1600.0), atmosphere * 0.65)

func _start_cloud_stroke(position: Vector2) -> void:
	var direction := _cloud_direction(position)
	if direction == Vector3.ZERO: return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()
	if cloud_tools.mode == 2:
		if settings.cloud_weather == null:
			status.text = "Paint a formation before capturing a reusable tile."
			return
		var captured: bool = cloud_tools.save_capture(settings.cloud_weather.capture(_weather_space(direction), deg_to_rad(cloud_tools.radius_degrees), 128, deg_to_rad(cloud_tools.tile_rotation_degrees)))
		status.text = "Formation captured in your tile library." if captured else "Could not save the tile. See the cloud panel for details."
		return
	if cloud_tools.mode == 1 and settings.cloud_weather == null:
		status.text = "Use Clear sky or paint a tile to start an editable weather map."
		return
	stroke_before = _cloud_snapshot()
	if settings.cloud_weather == null:
		settings.cloud_weather = CloudWeather.new()
		settings.cloud_weather.initialize()
	painting_clouds = true
	stroke_changed = false
	last_cloud_stamp = direction
	_stamp_cloud(direction)

func _paint_cloud_to(position: Vector2) -> void:
	var direction := _cloud_direction(position)
	if direction == Vector3.ZERO:
		last_cloud_stamp = Vector3.ZERO
		return
	if last_cloud_stamp == Vector3.ZERO:
		last_cloud_stamp = direction
		_stamp_cloud(direction)
		return
	var spacing := deg_to_rad(cloud_tools.radius_degrees) * 0.22
	var angle := last_cloud_stamp.angle_to(direction)
	if angle < spacing: return
	var count := mini(64, int(floor(angle / spacing)))
	var start := last_cloud_stamp
	for index in range(1, count + 1):
		var point := start.slerp(direction, minf(1.0, spacing * float(index) / angle)).normalized()
		_stamp_cloud(point)
		last_cloud_stamp = point

func _stamp_cloud(direction: Vector3) -> void:
	stroke_changed = settings.cloud_weather.stamp(_weather_space(direction), deg_to_rad(cloud_tools.radius_degrees), cloud_tools.selected_tile, cloud_tools.strength, deg_to_rad(cloud_tools.tile_rotation_degrees), cloud_tools.mode == 1, cloud_tools.feather) or stroke_changed

func _finish_cloud_stroke() -> void:
	if not painting_clouds: return
	painting_clouds = false
	if stroke_changed:
		_record_cloud_change(stroke_before)
		if status != null: status.text = "Cloud map edited. Bake & Save keeps these formations."
	elif stroke_before == null:
		settings.cloud_weather = null
	stroke_before = null
	last_cloud_stamp = Vector3.ZERO

func _cloud_snapshot() -> Image:
	return settings.cloud_weather.snapshot() if settings != null and settings.cloud_weather != null else null

func _restore_cloud_snapshot(snapshot: Image) -> void:
	if snapshot == null:
		settings.cloud_weather = null
	else:
		if settings.cloud_weather == null: settings.cloud_weather = CloudWeather.new()
		settings.cloud_weather.restore(snapshot)
	if cloud_tools != null: cloud_tools.refresh()
	_update_cloud_preview()

func _record_cloud_change(before: Image) -> void:
	cloud_undo.append({"before": before, "after": _cloud_snapshot()})
	if cloud_undo.size() > 24: cloud_undo.pop_front()
	cloud_redo.clear()
	if cloud_tools != null: cloud_tools.refresh()

func _undo_clouds() -> void:
	_finish_cloud_stroke()
	if cloud_undo.is_empty(): return
	var change: Dictionary = cloud_undo.pop_back()
	cloud_redo.append(change)
	_restore_cloud_snapshot(change.before)

func _redo_clouds() -> void:
	_finish_cloud_stroke()
	if cloud_redo.is_empty(): return
	var change: Dictionary = cloud_redo.pop_back()
	cloud_undo.append(change)
	_restore_cloud_snapshot(change.after)

func _generate_clouds(seed_value: int, count: int, category: String = "mixed") -> void:
	_finish_cloud_stroke()
	var before := _cloud_snapshot()
	settings.cloud_weather = preload("res://scripts/cloud_brush_library.gd").generate_weather(seed_value, count, 0.9, category)
	_record_cloud_change(before)
	_update_cloud_preview()
	if status != null:
		status.text = "Generated %d formations (seed %d). Paint to refine, or Bake & Save." % [count, seed_value]

func _clear_clouds() -> void:
	_finish_cloud_stroke()
	var before := _cloud_snapshot()
	settings.cloud_weather = CloudWeather.new()
	settings.cloud_weather.initialize()
	_record_cloud_change(before)

func _procedural_clouds() -> void:
	_finish_cloud_stroke()
	if settings.cloud_weather == null: return
	var before := _cloud_snapshot()
	settings.cloud_weather = null
	_record_cloud_change(before)

func _reset_cloud_history() -> void:
	_finish_cloud_stroke()
	cloud_undo.clear()
	cloud_redo.clear()

func _update_brush_ring() -> void:
	if brush_ring == null: return
	brush_ring.visible = false
	if not cloud_tab_active or dragging or cloud_tools == null: return
	if get_viewport().gui_get_hovered_control() != null: return
	var direction := _cloud_direction(get_viewport().get_mouse_position())
	if direction == Vector3.ZERO: return
	var tangent := Vector3.UP.cross(direction).normalized()
	if tangent.length_squared() < 0.5: tangent = Vector3.RIGHT
	var bitangent := direction.cross(tangent).normalized()
	var angular_radius := deg_to_rad(cloud_tools.radius_degrees)
	var radius := float(settings.radius) + _cloud_brush_height() + 300.0
	var ring := ImmediateMesh.new()
	ring.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for index in range(97):
		var angle := TAU * float(index) / 96.0
		var point := direction * cos(angular_radius) + (tangent * cos(angle) + bitangent * sin(angle)) * sin(angular_radius)
		ring.surface_add_vertex(point * radius)
	ring.surface_end()
	brush_ring.mesh = ring
	brush_ring.visible = true

func _update_value_label(key: String, title: String) -> void:
	var value := float(settings.get(key))
	if key in ["radius", "relief", "atmosphere_height"]:
		value_labels[key].text = "%s: %.0f m" % [title, value]
	elif key == "rotation_seconds":
		value_labels[key].text = "%s: %.0f s" % [title, value]
	elif key == "surface_gravity":
		value_labels[key].text = "%s: %.2f m/s^2" % [title, value]
	elif key == "atmosphere_density":
		value_labels[key].text = "%s: %.2f kg/m^3" % [title, value]
	elif key == "orbit_distance_au":
		value_labels[key].text = "%s: %.2f AU" % [title, value]
	elif key == "moon_orbit_distance_km":
		value_labels[key].text = "%s: %.0f km" % [title, value]
	elif key == "orbit_period_days":
		value_labels[key].text = "%s: %.2f hours" % [title, value * 24.0] if value < 1.0 else "%s: %.3f days" % [title, value]
	else:
		value_labels[key].text = "%s: %.2f" % [title, value]

func _theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_hover_color", "Button", MINT)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_stylebox("normal", "Button", _style(Color("203138"), Color("3c5056"), 6, 12))
	theme.set_stylebox("hover", "Button", _style(Color("30474b"), MINT, 6, 12))
	theme.set_stylebox("pressed", "Button", _style(MINT, MINT, 6, 12))
	theme.set_stylebox("normal", "LineEdit", _style(Color("101d25"), Color("3b5158"), 6, 10))
	theme.set_color("font_color", "LineEdit", PAPER)
	theme.set_color("caret_color", "LineEdit", MINT)
	return theme

func _style(bg: Color, border: Color, radius: int = 8, margin: int = 20) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box

func _label(parent: Node, text: String, font_size: int = 16, color: Color = PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable, accent: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if accent:
		button.add_theme_stylebox_override("normal", _style(MINT, MINT, 6, 12))
		button.add_theme_color_override("font_color", INK)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _rect_offsets(control: Control, rect: Rect2) -> void:
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y
