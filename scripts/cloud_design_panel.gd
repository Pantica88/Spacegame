extends VBoxContainer
const Design = preload("res://scripts/cloud_design.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
const RECIPE_PATH := "user://cloud_recipes.json"
var panel: Node
var editor: Node
var values := {}
var region: OptionButton
var operation: OptionButton
var selection: Resource
var selection_view: TextureRect
var preview_status: Label
var apply_button: Button
var cancel_button: Button
var recipe_name: LineEdit
var recipe_picker: OptionButton
var recipes := {}
var source_center := Vector3.ZERO
var source_radius := 0.0
var source_layer := -1
var transform_status: Label

func build(owner_panel: Node) -> void:
	panel = owner_panel
	editor = panel.editor
	editor._label(self, "GENERATION DESIGN", 11, editor.MINT)
	_number("min_radius", "Minimum radius °", 1, 70, 1, 12)
	_number("max_radius", "Maximum radius °", 1, 70, 1, 32)
	_number("density", "Cloud coverage %", 1, 100, 1, 90)
	operation = OptionButton.new()
	operation.add_item("Replace clouds in region")
	operation.add_item("Add to existing clouds")
	add_child(operation)
	region = OptionButton.new()
	for title in ["Whole planet", "Painted selection", "Latitude band"]: region.add_item(title)
	add_child(region)
	_number("south", "South latitude °", -90, 90, 1, -30)
	_number("north", "North latitude °", -90, 90, 1, 30)
	var row := HBoxContainer.new()
	add_child(row)
	editor._button(row, "Paint selection", func(): _set_mode(3))
	editor._button(row, "Subtract", func(): _set_mode(4))
	editor._button(self, "Clear selection", clear_selection)
	selection_view = TextureRect.new()
	selection_view.custom_minimum_size = Vector2(0, 90)
	selection_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	selection_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	selection_view.tooltip_text = "Selection map: white areas receive generation. Left/right edges wrap around the globe."
	add_child(selection_view)
	_refresh_selection()
	preview_status = editor._label(self, "Preview generation, then Apply or Cancel.", 12, editor.MUTED)
	preview_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	add_child(actions)
	apply_button = editor._button(actions, "Apply preview", editor._apply_cloud_preview)
	cancel_button = editor._button(actions, "Cancel", editor._cancel_cloud_preview)
	refresh_preview()
	editor._label(self, "GENERATION RECIPES", 11, editor.MINT)
	recipe_name = LineEdit.new()
	recipe_name.placeholder_text = "Recipe name"
	add_child(recipe_name)
	editor._button(self, "Save recipe", save_recipe)
	recipe_picker = OptionButton.new()
	add_child(recipe_picker)
	var recipe_actions := HBoxContainer.new()
	add_child(recipe_actions)
	editor._button(recipe_actions, "Load recipe", load_recipe)
	editor._button(recipe_actions, "Delete recipe", delete_recipe)
	_read_recipes()
	editor._label(self, "RETOUCH ACTIVE LAYER", 11, editor.MINT)
	var brushes := HBoxContainer.new()
	add_child(brushes)
	editor._button(brushes, "Smooth brush", func(): _set_mode(5))
	editor._button(brushes, "Soften brush", func(): _set_mode(6))
	_number("rotation", "Region rotation °", -180, 180, 5, 0)
	_number("scale", "Region scale %", 25, 300, 5, 100)
	editor._button(self, "Pick region to move / transform", func(): _set_mode(7))
	transform_status = editor._label(self, "Pick a source on the globe using the brush radius.", 12, editor.MUTED)
	transform_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor._button(self, "Rotate / resize at source", func():
		if source_center != Vector3.ZERO: editor._transform_cloud_region(source_center)
	)
	editor._button(self, "Place region on globe…", func(): _set_mode(8))
	var hint: Label = editor._label(self, "Pick source, set rotation/scale, then click a destination. The source is moved with a soft edge. Undo restores it. Selection painting uses the brush radius; smooth/soften also use its opacity.", 12, editor.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _number(key: String, title: String, minimum: float, maximum: float, step: float, initial: float) -> void:
	var row := HBoxContainer.new()
	add_child(row)
	editor._label(row, title, 12, editor.MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = initial
	row.add_child(spin)
	values[key] = spin

func _set_mode(index: int) -> void:
	editor._finish_cloud_stroke()
	editor._cancel_cloud_preview()
	panel.mode = index
	panel.mode_picker.select(index)
	if index in [3, 4]: region.select(1)

func options() -> Dictionary:
	for spin in values.values(): spin.apply()
	return {"min_radius": minf(values.min_radius.value, values.max_radius.value), "max_radius": maxf(values.min_radius.value, values.max_radius.value), "density": values.density.value / 100.0, "region": region.selected, "south": values.south.value, "north": values.north.value, "additive": operation.selected == 1}

func paint_selection(center: Vector3, erase: bool) -> void:
	if selection == null: selection = Weather.new()
	var tile := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	tile.fill(Color(1, 0, 0, 0))
	selection.stamp(center, deg_to_rad(panel.radius_degrees), tile, 1.0, 0.0, erase, panel.feather)
	_refresh_selection()

func clear_selection() -> void:
	selection = null
	_refresh_selection()

func _refresh_selection() -> void:
	if selection_view == null: return
	var display := Image.create(256, 128, false, Image.FORMAT_RGB8)
	display.fill(Color("102638"))
	if selection != null:
		var mask: Image = selection.image.duplicate()
		mask.resize(256, 128)
		for y in range(128):
			for x in range(256):
				display.set_pixel(x, y, Color("102638").lerp(Color.WHITE, mask.get_pixel(x, y).r))
	selection_view.texture = ImageTexture.create_from_image(display)

func refresh_preview() -> void:
	if apply_button == null: return
	var pending: bool = editor.cloud_generation_preview != null
	apply_button.disabled = not pending
	cancel_button.disabled = not pending
	preview_status.text = "Preview only — Apply to keep this result. Reroll previews another seed." if pending else "Preview generation, then Apply or Cancel."

func reset_region() -> void:
	clear_selection()
	source_center = Vector3.ZERO
	source_layer = -1
	if transform_status != null: transform_status.text = "Pick a source on the globe using the brush radius."

func pick_source(center: Vector3) -> void:
	if editor.settings.cloud_weather == null: return
	source_center = center
	source_radius = deg_to_rad(panel.radius_degrees)
	source_layer = editor.settings.cloud_weather.active_layer
	transform_status.text = "Source selected. Set rotation/scale, then transform here or place on the globe."

func save_recipe() -> void:
	var title := recipe_name.text.strip_edges()
	if title.is_empty():
		preview_status.text = "Enter a recipe name first."
		return
	panel.weather_seed.apply()
	panel.weather_count.apply()
	var recipe := options()
	recipe["seed"] = int(panel.weather_seed.value)
	recipe["count"] = int(panel.weather_count.value)
	recipe["types"] = panel._selected_weather_types()
	recipe["weights"] = panel._weather_weights()
	if selection != null:
		recipe["selection"] = Marshalls.raw_to_base64(selection.image.save_png_to_buffer())
	recipes[title] = recipe
	_write_recipes()

func load_recipe() -> void:
	if recipe_picker.selected < 0: return
	var title := recipe_picker.get_item_text(recipe_picker.selected)
	if not recipes.has(title): return
	var recipe: Dictionary = recipes[title]
	for key in ["min_radius", "max_radius", "south", "north"]:
		values[key].value = float(recipe.get(key, values[key].value))
	values.density.value = float(recipe.get("density", 0.9)) * 100.0
	# Set text too: SpinBox.apply() must not restore stale text on the next click.
	for spin in values.values(): spin.get_line_edit().text = str(spin.value)
	panel.weather_seed.get_line_edit().text = str(int(recipe.get("seed", 73129)))
	panel.weather_count.get_line_edit().text = str(int(recipe.get("count", 64)))
	panel.weather_seed.apply()
	panel.weather_count.apply()
	region.select(clampi(int(recipe.get("region", 0)), 0, 2))
	operation.select(1 if recipe.get("additive", false) else 0)
	for id in panel.weather_types:
		panel.weather_types[id].set_pressed_no_signal(id in recipe.get("types", []))
		panel.weather_weights[id].value = float(recipe.get("weights", {}).get(id, 1))
		panel.weather_weights[id].get_line_edit().text = str(panel.weather_weights[id].value)
	selection = null
	if recipe.has("selection"):
		var mask := Image.new()
		if mask.load_png_from_buffer(Marshalls.base64_to_raw(recipe.selection)) == OK:
			selection = Weather.new()
			selection.restore(mask)
	_refresh_selection()
	panel._refresh_generator()
	recipe_name.text = title
	preview_status.text = "Loaded recipe: " + title

func delete_recipe() -> void:
	if recipe_picker.selected < 0: return
	recipes.erase(recipe_picker.get_item_text(recipe_picker.selected))
	_write_recipes()

func _write_recipes() -> void:
	var file := FileAccess.open(RECIPE_PATH, FileAccess.WRITE)
	if file == null:
		preview_status.text = "Could not save recipes: " + error_string(FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(recipes))
	file.close()
	_reload_recipes()
	preview_status.text = "Recipes saved."

func _read_recipes() -> void:
	if FileAccess.file_exists(RECIPE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECIPE_PATH))
		if parsed is Dictionary: recipes = parsed
	_reload_recipes()

func _reload_recipes() -> void:
	recipe_picker.clear()
	for title in recipes: recipe_picker.add_item(title)
