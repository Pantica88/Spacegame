extends ScrollContainer
## Brush controls kept separate from planet generation controls.
const Library = preload("res://scripts/cloud_brush_library.gd")
const TILE_DIR := "user://cloud_tiles"

var editor: Node
var mode := 0
var category := "cumulus"
var variant := 0
var radius_degrees := 14.0
var strength := 0.65
var feather := 0.65
var tile_rotation_degrees := 0.0
var selected_tile: Image
var tile_buttons: Array[Button] = []
var description: Label
var map_status: Label
var undo_button: Button
var redo_button: Button
var custom_picker: OptionButton
var custom_name: LineEdit
var mode_picker: OptionButton
var custom_paths: Array[String] = []
var weather_seed: SpinBox
var weather_count: SpinBox
var weather_types: Dictionary = {}
var weather_weights: Dictionary = {}
var design: VBoxContainer
var layer_opacity: SpinBox
var weather_target: Label
var weather_mix_status: Label
var weather_generate: Button
var weather_randomize: Button
var dynamics_sliders := {}
var layer_picker: OptionButton
var layer_name: LineEdit
var layer_visible: CheckButton
var layer_locked: CheckButton
var layer_delete: Button
var layer_up: Button
var layer_down: Button

func build(owner_editor: Node) -> void:
	editor = owner_editor
	name = "Clouds"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 9)
	add_child(box)
	editor._label(box, "CLOUD FORMATIONS", 11, editor.MINT)
	editor._label(box, "Paint the sky", 24)
	var help: Label = editor._label(box, "Left-drag to paint • Right-drag to orbit\nWheel to zoom • Ctrl+Z to undo", 13, editor.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_status = editor._label(box, "", 12, editor.MINT)
	map_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_layers(box)
	_build_generator(box)
	_build_dynamics(box)
	mode_picker = OptionButton.new()
	for title in ["Paint formations", "Erase selected layer", "Capture region as tile", "Paint generation selection", "Subtract selection", "Smooth layer", "Soften layer", "Pick transform source", "Place transformed region"]:
		mode_picker.add_item(title)
	mode_picker.item_selected.connect(func(index: int): mode = index)
	box.add_child(mode_picker)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for entry in Library.categories():
		var button := Button.new()
		button.text = entry.name
		button.tooltip_text = entry.description
		button.icon = ImageTexture.create_from_image(Library.preview(entry.id, 0, 80))
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 132)
		button.custom_minimum_size = Vector2(144, 89)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", 13)
		button.set_meta("category", entry.id)
		button.pressed.connect(func(): _select_category(entry.id, entry.description))
		grid.add_child(button)
		tile_buttons.append(button)
	description = editor._label(box, "", 12, editor.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var variation := HBoxContainer.new()
	box.add_child(variation)
	editor._label(variation, "Tile variant", 13, editor.MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var variant_picker := OptionButton.new()
	for number in range(4): variant_picker.add_item("%02d" % (number + 1))
	variant_picker.item_selected.connect(func(index: int):
		variant = index
		_select_category(category)
		for button in tile_buttons:
			button.icon = ImageTexture.create_from_image(Library.preview(button.get_meta("category"), variant, 80))
	)
	variation.add_child(variant_picker)
	_brush_slider(box, "Brush radius", 3.0, 38.0, 1.0, radius_degrees, "°", func(v: float): radius_degrees = v)
	_brush_slider(box, "Opacity", 0.1, 1.0, 0.05, strength, "%", func(v: float): strength = v)
	_brush_slider(box, "Soft edge", 0.1, 1.0, 0.05, feather, "%", func(v: float): feather = v)
	_brush_slider(box, "Tile rotation", -180.0, 180.0, 5.0, tile_rotation_degrees, "°", func(v: float): tile_rotation_degrees = v)
	var history := HBoxContainer.new()
	box.add_child(history)
	undo_button = editor._button(history, "Undo", editor._undo_clouds)
	redo_button = editor._button(history, "Redo", editor._redo_clouds)
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor._label(box, "YOUR TILE LIBRARY", 11, editor.MINT)
	custom_name = LineEdit.new()
	custom_name.placeholder_text = "Name this formation"
	box.add_child(custom_name)
	var capture: Button = editor._button(box, "Capture a painted region…", func():
		mode = 2
		mode_picker.select(2)
		description.text = "Click the globe to save the area inside the brush as a reusable tile."
	)
	capture.tooltip_text = "Compose a formation with several brushes, then capture and reuse it."
	custom_picker = OptionButton.new()
	custom_picker.item_selected.connect(_select_custom)
	box.add_child(custom_picker)
	_reload_custom_tiles()
	var actions := HBoxContainer.new()
	box.add_child(actions)
	editor._button(actions, "Clear layer", editor._clear_clouds).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor._button(actions, "Reset to procedural", editor._procedural_clouds).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var note: Label = editor._label(box, "Paint and erase affect only the selected visible, unlocked layer. Reset to procedural removes all layers (undoable). Bake & Save stores it with this body. Custom tiles are shared between planets.", 12, editor.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_select_category(category)
	refresh()

func _build_generator(box: VBoxContainer) -> void:
	var section := VBoxContainer.new()
	var toggle := CheckButton.new()
	toggle.text = "Random weather generator"
	toggle.toggled.connect(func(open: bool): section.visible = open)
	box.add_child(toggle)
	box.add_child(section)
	section.visible = false
	editor._label(section, "RANDOM WEATHER", 11, editor.MINT)
	var row := HBoxContainer.new()
	section.add_child(row)
	editor._label(row, "Seed", 13, editor.MUTED)
	weather_seed = SpinBox.new()
	weather_seed.min_value = 1
	weather_seed.max_value = 999999999
	weather_seed.step = 1
	weather_seed.value = 73129
	weather_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(weather_seed)
	var count_row := HBoxContainer.new()
	section.add_child(count_row)
	editor._label(count_row, "Formations", 13, editor.MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weather_count = SpinBox.new()
	weather_count.min_value = 8
	weather_count.max_value = 160
	weather_count.step = 8
	weather_count.value = 64
	count_row.add_child(weather_count)
	weather_target = editor._label(section, "", 13, editor.MINT)
	weather_target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor._label(section, "Choose types to mix", 13, editor.MUTED)
	var choices := GridContainer.new()
	choices.columns = 2
	section.add_child(choices)
	for entry in Library.categories():
		var check := CheckBox.new()
		check.text = entry.name
		check.tooltip_text = entry.description
		check.button_pressed = true
		check.toggled.connect(func(_pressed: bool): _refresh_generator())
		weather_types[entry.id] = check
		choices.add_child(check)
		var weight := SpinBox.new()
		weight.min_value = 0
		weight.max_value = 100
		weight.value = 1
		weight.suffix = " parts"
		weight.value_changed.connect(func(_value: float): _refresh_generator())
		weather_weights[entry.id] = weight
		choices.add_child(weight)
	var selection := HBoxContainer.new()
	section.add_child(selection)
	editor._button(selection, "Select all", func(): _select_weather_types(true))
	editor._button(selection, "Clear selection", func(): _select_weather_types(false))
	weather_mix_status = editor._label(section, "", 12, editor.MUTED)
	weather_mix_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	section.add_child(actions)
	weather_generate = editor._button(actions, "Preview generation", func(): _generate_weather(true))
	weather_generate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weather_randomize = editor._button(actions, "Reroll preview", func():
		var random := RandomNumberGenerator.new()
		random.randomize()
		weather_seed.get_line_edit().text = str(random.randi_range(1, 999999999))
		_generate_weather(true)
	)
	weather_randomize.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hint: Label = editor._label(section, "Replaces only the selected visible, unlocked layer. Add a layer to keep its existing clouds. Undo restores it.\nSame seed and settings reproduce the same sky.", 12, editor.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	design = preload("res://scripts/cloud_design_panel.gd").new()
	section.add_child(design)
	design.build(self)

func _build_dynamics(box: VBoxContainer) -> void:
	editor._label(box, "SKY DYNAMICS", 11, editor.MINT)
	dynamics_sliders.clear()
	_setting_slider(box, "Wind speed", "cloud_wind_speed", 0.0, 120.0, 1.0, " m/s")
	_setting_slider(box, "Wind heading", "cloud_wind_heading", -180.0, 180.0, 5.0, "°")
	_setting_slider(box, "Billow evolution", "cloud_evolution", 0.0, 1.0, 0.05, "%")
	_setting_slider(box, "Procedural coverage", "cloud_coverage", 0.0, 1.0, 0.05, "%")
	_setting_slider(box, "Cloud density", "cloud_density", 0.2, 2.5, 0.05, "%")
	_brush_slider(box, "Preview time-lapse", 1.0, 600.0, 1.0, 60.0, "×", func(v: float):
		if editor.cloud_layer != null: editor.cloud_layer.time_scale = v
	)
	var hint: Label = editor._label(box, "Wind, evolution, coverage and density are saved with this body. Time-lapse only speeds up the editor preview.", 12, editor.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _setting_slider(box: VBoxContainer, title: String, key: String, minimum: float, maximum: float, step_size: float, unit: String) -> void:
	var label: Label = editor._label(box, "", 13, editor.MUTED)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.scrollable = false
	var show := func(value: float):
		label.text = "%s: %.0f%s" % [title, value * 100.0 if unit == "%" else value, unit]
	slider.value_changed.connect(func(value: float):
		show.call(value)
		if editor.settings != null: editor.settings.set(key, value)
	)
	slider.set_meta("show", show)
	box.add_child(slider)
	dynamics_sliders[key] = slider

func _generate_weather(preview: bool = false) -> void:
	# Commit typed SpinBox text even when Generate was clicked before Enter.
	weather_seed.apply()
	weather_count.apply()
	var selected := _selected_weather_types()
	if selected.is_empty(): return
	var options: Dictionary = design.options() if design != null else {}
	options["weights"] = _weather_weights()
	var total := 0.0
	for id in selected: total += float(options.weights[id])
	if total <= 0: return
	editor._generate_clouds(int(weather_seed.value), int(weather_count.value), "mixed", selected, options, preview)

func _brush_slider(box: VBoxContainer, title: String, minimum: float, maximum: float, step_size: float, initial: float, unit: String, callback: Callable) -> void:
	var label: Label = editor._label(box, "", 13, editor.MUTED)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.value = initial
	slider.scrollable = false
	var update := func(value: float):
		label.text = "%s: %.0f%s" % [title, value * 100.0 if unit == "%" else value, unit]
		callback.call(value)
	slider.value_changed.connect(update)
	update.call(initial)
	box.add_child(slider)

func _select_category(id: String, explanation: String = "") -> void:
	category = id
	selected_tile = Library.tile(id, variant)
	for button in tile_buttons:
		button.set_pressed_no_signal(button.get_meta("category") == id)
	if explanation.is_empty():
		for entry in Library.categories():
			if entry.id == id: explanation = entry.description
	description.text = explanation
	if custom_picker != null: custom_picker.select(0)
	mode = 0
	mode_picker.select(0)

func _reload_custom_tiles() -> void:
	custom_picker.clear()
	custom_picker.add_item("Saved tiles…")
	custom_paths.clear()
	var directory := DirAccess.open(TILE_DIR)
	if directory == null: return
	for filename in directory.get_files():
		if filename.get_extension() != "res": continue
		var path := TILE_DIR.path_join(filename)
		var tile := ResourceLoader.load(path) as Image
		if tile == null: continue
		custom_paths.append(path)
		custom_picker.add_item(tile.resource_name if not tile.resource_name.is_empty() else filename.get_basename())

func _select_custom(index: int) -> void:
	if index <= 0: return
	selected_tile = ResourceLoader.load(custom_paths[index - 1]) as Image
	for button in tile_buttons: button.set_pressed_no_signal(false)
	description.text = "Custom formation: " + custom_picker.get_item_text(index)
	mode = 0
	mode_picker.select(0)

func save_capture(tile: Image) -> bool:
	var title := custom_name.text.strip_edges()
	if title.is_empty(): title = "Formation %d" % (custom_paths.size() + 1)
	tile.resource_name = title
	var error := DirAccess.make_dir_recursive_absolute(TILE_DIR)
	var path := TILE_DIR.path_join("tile-%d-%d.res" % [Time.get_unix_time_from_system(), Time.get_ticks_msec()])
	if error == OK: error = ResourceSaver.save(tile, path, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		description.text = "Tile could not be saved: " + error_string(error)
		return false
	_reload_custom_tiles()
	var index := custom_paths.find(path) + 1
	custom_picker.select(index)
	_select_custom(index)
	return true

func refresh() -> void:
	if editor.settings == null: return
	if float(editor.settings.atmosphere_height) <= 0.0 or float(editor.settings.atmosphere_visual_density) <= 0.0:
		map_status.text = "Airless body — add atmosphere in World to see clouds."
	else:
		map_status.text = "Painted weather • saved with this body" if editor.settings.cloud_weather != null else "Procedural weather • ready to paint"
	_refresh_layers()
	_refresh_generator()
	for key in dynamics_sliders:
		var slider: HSlider = dynamics_sliders[key]
		slider.set_value_no_signal(float(editor.settings.get(key)))
		slider.get_meta("show").call(slider.value)
	undo_button.disabled = editor.cloud_undo.is_empty()
	redo_button.disabled = editor.cloud_redo.is_empty()

func _build_layers(box: VBoxContainer) -> void:
	editor._label(box, "CLOUD PAINT LAYERS", 11, editor.MINT)
	layer_picker = OptionButton.new()
	layer_picker.item_selected.connect(func(index: int): editor._edit_cloud_layer("select", layer_picker.get_item_id(index)))
	box.add_child(layer_picker)
	layer_name = LineEdit.new()
	layer_name.placeholder_text = "Layer name"
	layer_name.text_submitted.connect(func(value: String): editor._edit_cloud_layer("name", value))
	layer_name.focus_exited.connect(func():
		if editor.settings.cloud_weather != null and layer_name.text != editor.settings.cloud_weather.paint_layers[editor.settings.cloud_weather.active_layer].name:
			editor._edit_cloud_layer("name", layer_name.text)
	)
	box.add_child(layer_name)
	var flags := HBoxContainer.new()
	box.add_child(flags)
	layer_visible = CheckButton.new()
	layer_visible.text = "Visible"
	layer_visible.toggled.connect(func(value: bool): editor._edit_cloud_layer("visible", value))
	flags.add_child(layer_visible)
	layer_locked = CheckButton.new()
	layer_locked.text = "Locked"
	layer_locked.toggled.connect(func(value: bool): editor._edit_cloud_layer("locked", value))
	flags.add_child(layer_locked)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	editor._button(actions, "Add", func(): editor._edit_cloud_layer("add"))
	editor._button(box, "Duplicate selected layer", func(): editor._edit_cloud_layer("duplicate"))
	layer_opacity = SpinBox.new()
	layer_opacity.min_value = 0
	layer_opacity.max_value = 100
	layer_opacity.value = 100
	layer_opacity.suffix = "% layer opacity"
	layer_opacity.value_changed.connect(func(value: float): editor._edit_cloud_layer("opacity", value / 100.0))
	box.add_child(layer_opacity)
	layer_up = editor._button(actions, "Up", func(): editor._edit_cloud_layer("up"))
	layer_down = editor._button(actions, "Down", func(): editor._edit_cloud_layer("down"))
	layer_delete = editor._button(actions, "Delete", func(): editor._edit_cloud_layer("delete"))
	var hint: Label = editor._label(box, "Top layers cover lower layers. Erasing reveals the clouds below. Add a layer before generating a separate formation pass.", 12, editor.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _refresh_layers() -> void:
	layer_picker.clear()
	var weather: Resource = editor.settings.cloud_weather
	var present := weather != null
	layer_opacity.editable = present
	layer_name.editable = present
	layer_visible.disabled = not present
	layer_locked.disabled = not present
	layer_delete.disabled = true
	layer_up.disabled = true
	layer_down.disabled = true
	if not present:
		layer_picker.add_item("No painted layers — Add to start")
		layer_picker.disabled = true
		layer_name.text = ""
		layer_visible.set_pressed_no_signal(false)
		layer_locked.set_pressed_no_signal(false)
		return
	weather.ensure_layers()
	layer_picker.disabled = false
	for index in range(weather.paint_layers.size() - 1, -1, -1):
		var entry: Dictionary = weather.paint_layers[index]
		layer_picker.add_item(String(entry.name) + (" [hidden]" if not entry.visible else "") + (" [locked]" if entry.locked else ""), index)
		if index == weather.active_layer: layer_picker.select(layer_picker.item_count - 1)
	var layer: Dictionary = weather.paint_layers[weather.active_layer]
	layer_opacity.set_value_no_signal(float(layer.get("opacity", 1.0)) * 100.0)
	layer_opacity.editable = not layer.locked
	layer_name.text = layer.name
	layer_visible.set_pressed_no_signal(layer.visible)
	layer_locked.set_pressed_no_signal(layer.locked)
	layer_delete.disabled = layer.locked or weather.paint_layers.size() <= 1
	layer_up.disabled = weather.active_layer == weather.paint_layers.size() - 1
	layer_down.disabled = weather.active_layer == 0

func _selected_weather_types() -> Array[String]:
	var selected: Array[String] = []
	for id in weather_types:
		if weather_types[id].button_pressed: selected.append(id)
	return selected

func _select_weather_types(selected: bool) -> void:
	for check in weather_types.values(): check.set_pressed_no_signal(selected)
	_refresh_generator()

func _refresh_generator() -> void:
	if weather_generate == null or editor.settings == null: return
	var weather: Resource = editor.settings.cloud_weather
	var editable := true
	if weather == null:
		weather_target.text = "Target: new Clouds 1 layer"
	else:
		weather.ensure_layers()
		var layer: Dictionary = weather.paint_layers[weather.active_layer]
		editable = weather.layer_editable()
		weather_target.text = "Target: %s%s" % [layer.name, " (hidden or locked)" if not editable else ""]
	var count := _selected_weather_types().size()
	var total := 0.0
	for id in _selected_weather_types(): total += weather_weights[id].value
	var shares: Array[String] = []
	if total > 0:
		for id in _selected_weather_types(): shares.append("%s %.0f%%" % [weather_types[id].text, weather_weights[id].value / total * 100])
	weather_mix_status.text = "Select types with at least one positive mix weight." if total == 0 else ", ".join(shares)
	weather_generate.disabled = count == 0 or total == 0 or not editable
	weather_randomize.disabled = weather_generate.disabled

func _weather_weights() -> Dictionary:
	var weights := {}
	for id in weather_weights:
		weather_weights[id].apply()
		weights[id] = weather_weights[id].value
	return weights
