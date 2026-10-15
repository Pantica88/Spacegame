extends SceneTree
const Library = preload("res://scripts/cloud_brush_library.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
const Editor = preload("res://scripts/planet_editor.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var mixed: Resource = Library.generate_weather(9123, 8, 0.9, "mixed", ["cumulus", "overcast"], {"weights": {"cumulus": 1, "overcast": 1}})
	var repeated: Resource = Library.generate_weather(9123, 8, 0.9, "mixed", ["overcast", "cumulus"], {"weights": {"cumulus": 1, "overcast": 1}})
	assert(mixed.image.get_data() == repeated.image.get_data(), "Seed is reproducible regardless of selection order")
	var red := 0
	var blue := 0
	var bytes: PackedByteArray = mixed.image.get_data()
	for offset in range(0, bytes.size(), 4):
		red += bytes[offset]
		blue += bytes[offset + 2]
		assert(bytes[offset + 1] == 0 and bytes[offset + 3] == 0, "Unselected formations are excluded")
	assert(red > 0 and blue > 0, "Both selected types are generated")
	var editor := Editor.new()
	root.add_child(editor)
	editor.settings.cloud_weather = Weather.new()
	editor.settings.cloud_weather.image.fill(Color(0, 0.4, 0, 0))
	editor._edit_cloud_layer("add")
	var before: Resource = editor.settings.cloud_weather.layer_snapshot()
	var panel: Node = editor.cloud_tools
	panel._select_weather_types(false)
	assert(panel.weather_generate.disabled and panel.weather_randomize.disabled)
	panel._generate_weather()
	assert(editor.settings.cloud_weather.image.get_data() == before.image.get_data(), "Empty selection changes nothing")
	panel.weather_types["cumulus"].button_pressed = true
	panel.weather_types["overcast"].button_pressed = true
	panel.weather_seed.get_line_edit().text = "9123"
	panel.weather_count.get_line_edit().text = "8"
	assert(not panel.weather_generate.disabled)
	assert("Clouds 2" in panel.weather_target.text)
	panel._generate_weather()
	assert(editor.settings.cloud_weather.paint_layers[1].image.get_data() == mixed.image.get_data())
	assert(editor.settings.cloud_weather.paint_layers[0].image.get_data() == before.paint_layers[0].image.get_data(), "Generation preserves the other layer")
	editor._undo_clouds()
	assert(editor.settings.cloud_weather.image.get_data() == before.image.get_data())
	editor._redo_clouds()
	assert(editor.settings.cloud_weather.paint_layers[1].image.get_data() == mixed.image.get_data())
	panel.weather_randomize.pressed.emit()
	assert(int(panel.weather_seed.value) != 9123, "Randomize commits its new seed")
	var randomized: Resource = Library.generate_weather(int(panel.weather_seed.value), 8, 0.9, "mixed", ["cumulus", "overcast"], {"weights": {"cumulus": 1, "overcast": 1}})
	assert(editor.cloud_generation_preview.paint_layers[1].image.get_data() == randomized.image.get_data())
	editor._apply_cloud_preview()
	assert(editor.settings.cloud_weather.paint_layers[1].image.get_data() == randomized.image.get_data())
	assert(editor.settings.cloud_weather.paint_layers[0].image.get_data() == before.paint_layers[0].image.get_data())
	editor._edit_cloud_layer("locked", true)
	assert(panel.weather_generate.disabled)
	var locked: PackedByteArray = editor.settings.cloud_weather.image.get_data()
	panel._generate_weather()
	assert(editor.settings.cloud_weather.image.get_data() == locked)
	editor._edit_cloud_layer("locked", false)
	editor._edit_cloud_layer("visible", false)
	assert(panel.weather_generate.disabled)
	editor._edit_cloud_layer("select", 0)
	assert(not panel.weather_generate.disabled and "Clouds 1" in panel.weather_target.text)
	editor.queue_free()
	await process_frame
	print("PASS: custom cloud mixes, deterministic seeds, layer target, isolation, history and disabled generation guards")
	quit()
