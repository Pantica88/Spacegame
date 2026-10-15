extends SceneTree
const Weather = preload("res://scripts/cloud_weather_map.gd")
const Design = preload("res://scripts/cloud_design.gd")
const Library = preload("res://scripts/cloud_brush_library.gd")
const Editor = preload("res://scripts/planet_editor.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var weather := Weather.new()
	weather.initialize(64, 32)
	weather.image.fill(Color(0.5, 0, 0, 0))
	weather.ensure_layers()
	weather.add_paint_layer()
	weather.paint_layers[1].image.fill(Color(0, 0, 1, 0))
	weather.paint_layers[1].opacity = 0.5
	weather.rebuild_layers()
	var color := weather.image.get_pixel(0, 0)
	assert(absf(color.r - 0.25) < 0.01 and absf(color.b - 0.5) < 0.01, "Layer opacity uses cloud coverage, not alpha transparency")
	var base: Image = weather.paint_layers[0].image
	var generated := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	generated.fill(Color(0, 0.5, 0, 0))
	var band := Design.region_mask(Vector2i(64, 32), {"region": 2, "south": -20, "north": 20})
	var replaced := Design.combine(base, generated, band, false)
	assert(replaced.get_pixel(0, 0) == base.get_pixel(0, 0), "Outside latitude band is unchanged")
	assert(replaced.get_pixel(0, 16) == generated.get_pixel(0, 16))
	var added := Design.combine(base, generated, band, true)
	assert(added.get_pixel(0, 16).r > 0.2 and added.get_pixel(0, 16).g > 0.4)
	var selection := Weather.new()
	selection.initialize(64, 32)
	selection.image.set_pixel(31, 16, Color(1, 0, 0, 0))
	var selected := Design.combine(base, generated, Design.region_mask(Vector2i(64, 32), {"region": 1}, selection), false)
	assert(selected.get_pixel(31, 16) == generated.get_pixel(31, 16))
	assert(selected.get_pixel(32, 16) == base.get_pixel(32, 16), "Paint selection confines generation")
	var weighted := {"weights": {"cumulus": 0, "overcast": 100}, "min_radius": 5, "max_radius": 5}
	var clouds: Resource = Library.generate_weather(55, 8, 0.9, "mixed", ["cumulus", "overcast"], weighted)
	var repeat: Resource = Library.generate_weather(55, 8, 0.9, "mixed", ["overcast", "cumulus"], weighted)
	assert(clouds.image.get_data() == repeat.image.get_data())
	var data: PackedByteArray = clouds.image.get_data()
	for offset in range(0, data.size(), 4): assert(data[offset] == 0, "Zero-weight type never generates")
	var large: Resource = Library.generate_weather(55, 8, 0.9, "mixed", ["cumulus", "overcast"], {"weights": weighted.weights, "min_radius": 35, "max_radius": 35})
	assert(_coverage(large.image) > _coverage(clouds.image) * 2, "Size controls change formation extent")
	weather.active_layer = 1
	weather.paint_layers[1].image.fill(Color(0, 0, 0, 0))
	weather.paint_layers[1].image.set_pixel(32, 16, Color(0, 0, 0, 1))
	weather.rebuild_layers()
	var lower := base.get_data()
	var center := Design.direction_at(32, 16, Vector2i(64, 32))
	assert(Design.retouch(weather, center, 0.4, 1, false))
	assert(weather.paint_layers[1].image.get_pixel(32, 16).a < 1)
	assert(weather.paint_layers[0].image.get_data() == lower)
	assert(Design.retouch(weather, center, 0.4, 1, true))
	var before_transform: Image = weather.paint_layers[1].image.duplicate()
	assert(Design.transform_region(weather, center, -center, 0.4, 0.5, 1.5))
	assert(weather.paint_layers[1].image.get_data() != before_transform.get_data())
	assert(weather.paint_layers[0].image.get_data() == lower)
	weather.paint_layers[1].locked = true
	assert(not Design.transform_region(weather, center, -center, 0.4, 0, 1))
	assert(not Design.retouch(weather, center, 0.4, 1, false))
	var editor := Editor.new()
	root.add_child(editor)
	editor.settings.cloud_weather = weather
	editor._edit_cloud_layer("duplicate")
	assert(editor.settings.cloud_weather.paint_layers.size() == 3)
	assert(not editor.settings.cloud_weather.paint_layers[2].locked)
	assert(editor.settings.cloud_weather.paint_layers[2].image != editor.settings.cloud_weather.paint_layers[1].image)
	editor._edit_cloud_layer("opacity", 0.35)
	assert(editor.settings.cloud_weather.paint_layers[2].opacity == 0.35)
	var original: Resource = editor.settings.cloud_weather.layer_snapshot()
	var undo_count: int = editor.cloud_undo.size()
	editor._generate_clouds(55, 8, "mixed", ["overcast"], {"region": 2, "south": -20, "north": 20}, true)
	assert(editor.cloud_generation_preview != null)
	assert(editor.settings.cloud_weather.image.get_data() == original.image.get_data(), "Preview leaves authored weather untouched")
	assert(editor.cloud_undo.size() == undo_count)
	editor._save_world()
	assert("Apply or cancel" in editor.status.text, "Saving cannot accidentally commit a preview")
	editor._cancel_cloud_preview()
	assert(editor.cloud_generation_preview == null)
	editor._generate_clouds(56, 8, "mixed", ["overcast"], {}, true)
	editor._apply_cloud_preview()
	assert(editor.cloud_undo.size() == undo_count + 1)
	assert(editor.settings.cloud_weather.paint_layers[0].image.get_data() == lower)
	editor._undo_clouds()
	assert(editor.settings.cloud_weather.image.get_data() == original.image.get_data())
	var panel: Node = editor.cloud_tools
	var controls: Node = panel.design
	editor.world_root.rotation = Vector3.ZERO
	editor.yaw = 0.0
	editor.pitch = 0.16
	editor.distance = float(editor.settings.radius) * 3.8
	editor._update_camera()
	var globe_center := Vector3(0, 0.16, 1).normalized()
	var screen: Vector2 = editor.camera.unproject_position(globe_center * (float(editor.settings.radius) + editor._cloud_brush_height()))
	var untouched: PackedByteArray = editor.settings.cloud_weather.image.get_data()
	controls._set_mode(3)
	editor._start_cloud_stroke(screen)
	editor._finish_cloud_stroke()
	assert(controls.selection != null and controls.selection.has_clouds(), "Globe selection input paints the mask")
	assert(editor.settings.cloud_weather.image.get_data() == untouched, "Selection input never paints the clouds")
	controls._set_mode(7)
	editor._start_cloud_stroke(screen)
	assert(controls.source_center != Vector3.ZERO, "Globe input picks a transform source")
	controls.values.rotation.get_line_edit().text = "30"
	controls.values.scale.get_line_edit().text = "150"
	editor._transform_cloud_region(controls.source_center)
	assert(controls.source_center == Vector3.ZERO, "A completed transform consumes its source")
	editor._undo_clouds()
	controls.selection = selection
	controls.region.select(1)
	controls.operation.select(1)
	controls.values.min_radius.get_line_edit().text = "7"
	controls.values.max_radius.get_line_edit().text = "19"
	panel.weather_weights.cumulus.get_line_edit().text = "60"
	panel.weather_seed.get_line_edit().text = "8001"
	controls.recipe_name.text = "Test weather recipe"
	controls.save_recipe()
	controls.clear_selection()
	controls.region.select(0)
	controls._read_recipes()
	controls.load_recipe()
	assert(controls.region.selected == 1 and controls.operation.selected == 1)
	assert(controls.values.min_radius.value == 7 and controls.values.max_radius.value == 19)
	assert(panel.weather_weights.cumulus.value == 60 and panel.weather_seed.value == 8001)
	assert(controls.selection.image.get_data() == selection.image.get_data(), "Recipe restores selection mask")
	editor._generate_clouds(55, 8, "mixed", ["overcast"], {}, true)
	editor._edit_cloud_layer("select", 0)
	assert(editor.cloud_generation_preview == null, "Changing layers cancels pending preview")
	assert(ResourceSaver.save(editor.settings, "user://cloud-design-planet.tres") == OK)
	var loaded: Resource = ResourceLoader.load("user://cloud-design-planet.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	assert(loaded.cloud_weather.paint_layers[2].opacity == 0.35)
	editor.queue_free()
	await process_frame
	print("PASS: weights, sizes, regional add/replace, layer opacity/duplication, retouch/transform, preview lifecycle, recipes and persistence")
	quit()

func _coverage(image: Image) -> float:
	var total := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			total += pixel.r + pixel.g + pixel.b + pixel.a
	return total
