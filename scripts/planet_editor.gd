extends Node

const PlanetTerrain = preload("res://scripts/planet_terrain.gd")
const PlanetSurface = preload("res://scripts/planet_surface.gd")
const PlanetList = preload("res://scripts/planet_list.gd")
const PlanetBaker = preload("res://scripts/planet_baker.gd")

const INK := Color("101e25")
const MINT := Color("7ce5c0")
const PAPER := Color("eef2e9")
const MUTED := Color("91a8aa")
const PANEL := Color(0.055, 0.094, 0.118, 0.96)

var settings: Resource
var planet_paths: Array[String] = []
var current_path := ""
var planet_picker: OptionButton
var detail_picker: OptionButton
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

func _ready() -> void:
	DisplayServer.window_set_title("Aphelion - Planet Editor")
	planet_paths = PlanetList.paths()
	current_path = "res://assets/planets/verdant.tres" if "res://assets/planets/verdant.tres" in planet_paths else (planet_paths[0] if not planet_paths.is_empty() else "")
	_load_current_planet()
	_build_world()
	_build_ui()
	_rebuild_preview()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			last_mouse = event.position
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-1.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0)
	if event is InputEventMouseMotion and dragging:
		var delta: Vector2 = event.position - last_mouse
		last_mouse = event.position
		yaw -= delta.x * 0.006
		pitch = clampf(pitch + delta.y * 0.004, -1.15, 1.15)
		_update_camera()

func _process(delta: float) -> void:
	world_root.rotate_y(delta * 0.08)
	if rebuild_pending:
		rebuild_pending = false
		_rebuild_preview()

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
	_rect_offsets(panel, Rect2(-392, 108, 368, -24))
	panel.add_theme_stylebox_override("panel", _style(PANEL, Color("31454a"), 6, 18))
	ui.add_child(panel)
	var panel_box := VBoxContainer.new()
	panel_box.add_theme_constant_override("separation", 10)
	panel.add_child(panel_box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_box.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	_label(box, "LIVE WORLD SETTINGS", 11, MINT)
	_label(box, "Procedural planet", 24)
	planet_picker = OptionButton.new()
	for path in planet_paths:
		var resource := ResourceLoader.load(path)
		var title: String = resource.planet_name if resource != null and "planet_name" in resource else path.get_file().get_basename().capitalize()
		planet_picker.add_item("%s  (%s)" % [title, path.get_file()])
	planet_picker.item_selected.connect(func(index: int):
		current_path = planet_paths[index]
		_load_current_planet()
		_refresh_controls()
		_queue_rebuild()
	)
	box.add_child(planet_picker)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Planet name"
	name_edit.text_changed.connect(func(text: String): settings.planet_name = text)
	box.add_child(name_edit)
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
	_slider(box, "radius", "Radius", 16000.0, 90000.0, 500.0)
	_slider(box, "rotation_seconds", "Rotation", 300.0, 6000.0, 10.0)
	_slider(box, "surface_gravity", "Gravity", 1.0, 25.0, 0.05)
	_slider(box, "atmosphere_density", "Air density", 0.0, 3.0, 0.01)
	_slider(box, "atmosphere_height", "Atmosphere height", 0.0, 80000.0, 500.0)
	_slider(box, "atmosphere_visual_density", "Haze density", 0.0, 3.0, 0.01)
	_label(box, "TRAJECTORY", 11, MINT)
	_checkbox(box, "orbit_enabled", "Show in solar map")
	_slider(box, "orbit_distance_au", "Orbit distance", 0.05, 40.0, 0.01)
	_slider(box, "orbit_period_days", "Orbit period", 1.0, 100000.0, 1.0)
	_slider(box, "orbit_phase", "Orbit phase", 0.0, 1.0, 0.01)
	_color_row(box, "map_color", "Map color")
	_slider(box, "sea_threshold", "Sea level", -0.35, 0.25, 0.01)
	_slider(box, "continent_frequency", "Continents", 0.6, 6.0, 0.05)
	_slider(box, "continent_edge_smoothness", "Continent edge", 0.02, 1.0, 0.01)
	_slider(box, "relief", "Relief", 600.0, 5200.0, 50.0)
	_slider(box, "mountain_frequency", "Mountains", 2.0, 18.0, 0.1)
	_slider(box, "ridge_roundness", "Ridge roundness", 0.02, 0.5, 0.01)
	_checkbox(box, "has_ocean", "Ocean")
	_checkbox(box, "launch_site", "Launch island")
	_color_row(box, "lowland", "Lowland")
	_color_row(box, "highland", "Highland")
	_color_row(box, "dryland", "Dryland")
	_color_row(box, "snow", "Snow")
	_color_row(box, "ocean", "Ocean color")
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	panel_box.add_child(footer)
	var actions := HBoxContainer.new()
	footer.add_child(actions)
	_button(actions, "Random", _randomize_seed).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(actions, "Reset", _reset).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_picker = OptionButton.new()
	detail_picker.add_item("Preview: editor / map")
	for lod_settings in PlanetTerrain.RENDER_LODS:
		detail_picker.add_item("Preview: flight from %.0f km" % (float(lod_settings.altitude)/1000.0))
	detail_picker.item_selected.connect(func(_index: int): _update_preview_mesh())
	box.add_child(detail_picker)
	_button(footer, "Bake & Save Planet", _save_world, true)
	status = _label(footer, "", 13, MUTED)
	_refresh_controls()

func _load_current_planet() -> void:
	var resource := ResourceLoader.load(current_path, "", ResourceLoader.CACHE_MODE_IGNORE) if not current_path.is_empty() else null
	settings = resource.duplicate() if resource != null else PlanetSurface.HOME.duplicate()

func _slider(parent: VBoxContainer, key: String, title: String, minimum: float, maximum: float, step: float) -> void:
	var label := _label(parent, "", 13, MUTED)
	value_labels[key] = label
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value_changed.connect(func(value: float):
		settings.set(key, value)
		_update_value_label(key, title)
		_queue_rebuild()
	)
	controls[key] = slider
	parent.add_child(slider)

func _checkbox(parent: VBoxContainer, key: String, title: String) -> void:
	var checkbox := CheckBox.new()
	checkbox.text = title
	checkbox.toggled.connect(func(value: bool):
		settings.set(key, value)
		_queue_rebuild()
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
		_queue_rebuild()
	)
	controls[key] = picker
	row.add_child(picker)

func _queue_rebuild() -> void:
	rebuild_pending = true
	if status != null:
		status.text = "Rebuilding preview..."

func _rebuild_preview() -> void:
	terrain = PlanetTerrain.new(settings)
	_update_preview_mesh()
	var material: ShaderMaterial = planet.material_override
	terrain.configure_surface_material(material)
	material.set_shader_parameter("camera_planet_km", camera.global_position * 0.001)
	material.set_shader_parameter("sun_direction", Vector3(-0.45, 0.42, 0.72).normalized())
	material.set_shader_parameter("atmosphere_density_scale", settings.atmosphere_visual_density)
	planet.scale = Vector3.ONE
	distance = clampf(distance, float(settings.radius) * 1.55, float(settings.radius) * 5.0)
	_update_camera()
	if status != null:
		status.text = "Preview rebuilt. Right-drag to orbit, mouse wheel to zoom."

func _update_camera() -> void:
	if camera == null:
		return
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = offset * distance
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.far = maxf(500000.0, distance + float(settings.radius) * 3.0 if settings != null else 500000.0)
	if planet != null and planet.material_override is ShaderMaterial:
		var material: ShaderMaterial = planet.material_override
		material.set_shader_parameter("camera_planet_km", camera.global_position * 0.001)

func _zoom(amount: float) -> void:
	var radius := float(settings.radius) if settings != null else 60000.0
	distance = clampf(distance * exp(amount * 0.12), radius * 1.35, radius * 5.0)
	_update_camera()

func _randomize_seed() -> void:
	settings.terrain_seed = randi_range(1, 999999)
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
	planet.mesh = terrain.preview_mesh() if choice == 0 else terrain.render_mesh_for_lod(choice-1)

func _save_world() -> void:
	if current_path.is_empty():
		status.text = "Save failed: no planet file selected."
		return
	status.text = "Baking terrain layers..."
	var error := PlanetBaker.save_planet(settings, current_path)
	if error == OK:
		ResourceLoader.load(current_path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if current_path == "res://assets/planets/verdant.tres":
			PlanetSurface.reset_home(settings)
		_rebuild_preview()
		status.text = "Saved planet + 5 flight layers + map."
	else:
		status.text = "Save failed: %s" % error_string(error)

func _refresh_controls() -> void:
	if name_edit == null:
		return
	if planet_picker != null and current_path in planet_paths:
		planet_picker.select(planet_paths.find(current_path))
	name_edit.text = settings.planet_name
	controls.seed.set_value_no_signal(int(settings.terrain_seed))
	value_labels.seed.text = "Seed: %d" % int(settings.terrain_seed)
	for key in ["radius", "rotation_seconds", "surface_gravity", "atmosphere_density", "atmosphere_height", "atmosphere_visual_density", "orbit_distance_au", "orbit_period_days", "orbit_phase", "sea_threshold", "continent_frequency", "continent_edge_smoothness", "relief", "mountain_frequency", "ridge_roundness"]:
		controls[key].set_value_no_signal(float(settings.get(key)))
	var titles := {"radius": "Radius", "rotation_seconds": "Rotation", "surface_gravity": "Gravity", "atmosphere_density": "Air density", "atmosphere_height": "Atmosphere height", "atmosphere_visual_density": "Haze density", "orbit_distance_au": "Orbit distance", "orbit_period_days": "Orbit period", "orbit_phase": "Orbit phase", "sea_threshold": "Sea level", "continent_frequency": "Continents", "continent_edge_smoothness": "Continent edge", "relief": "Relief", "mountain_frequency": "Mountains", "ridge_roundness": "Ridge roundness"}
	for key in titles:
		_update_value_label(key, titles[key])
	for key in ["has_ocean", "launch_site", "orbit_enabled"]:
		controls[key].button_pressed = bool(settings.get(key))
	for key in ["lowland", "highland", "dryland", "snow", "ocean", "map_color"]:
		controls[key].color = settings.get(key)

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
	elif key == "orbit_period_days":
		value_labels[key].text = "%s: %.0f days" % [title, value]
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
