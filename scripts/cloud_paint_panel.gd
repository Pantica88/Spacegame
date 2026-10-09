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
var weather_pattern: OptionButton
var dynamics_sliders := {}

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
	_build_generator(box)
	_build_dynamics(box)
	mode_picker = OptionButton.new()
	for title in ["Paint formations", "Erase to clear sky", "Capture region as tile"]:
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
	editor._button(actions, "Clear sky", editor._clear_clouds).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor._button(actions, "Procedural", editor._procedural_clouds).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var note: Label = editor._label(box, "The first paint stroke starts a clear weather map. Bake & Save stores it with this body. Custom tiles are shared between planets.", 12, editor.MUTED)
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
	weather_pattern = OptionButton.new()
	weather_pattern.add_item("Mixed cloud types")
	for entry in Library.categories():
		weather_pattern.add_item(entry.name)
		weather_pattern.set_item_metadata(weather_pattern.item_count - 1, entry.id)
	section.add_child(weather_pattern)
	var actions := HBoxContainer.new()
	section.add_child(actions)
	editor._button(actions, "Generate", _generate_weather).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor._button(actions, "Randomize", func():
		var random := RandomNumberGenerator.new()
		random.randomize()
		weather_seed.value = random.randi_range(1, 999999999)
		_generate_weather()
	).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hint: Label = editor._label(section, "Replaces this body's weather. Undo restores it.\nSame seed and settings reproduce the same sky.", 12, editor.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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

func _generate_weather() -> void:
	# Commit typed SpinBox text even when Generate was clicked before Enter.
	weather_seed.apply()
	weather_count.apply()
	var pattern := "mixed" if weather_pattern.selected == 0 else String(weather_pattern.get_item_metadata(weather_pattern.selected))
	editor._generate_clouds(int(weather_seed.value), int(weather_count.value), pattern)

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
	for key in dynamics_sliders:
		var slider: HSlider = dynamics_sliders[key]
		slider.set_value_no_signal(float(editor.settings.get(key)))
		slider.get_meta("show").call(slider.value)
	undo_button.disabled = editor.cloud_undo.is_empty()
	redo_button.disabled = editor.cloud_redo.is_empty()
