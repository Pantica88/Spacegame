extends SceneTree
## Mount an immutable planet PCK: saving back into res:// can appear to succeed
## but reload the bundled original. Use isolated XDG_DATA_HOME for this test.
const Editor = preload("res://scripts/planet_editor.gd")
const Planets = preload("res://scripts/planet_list.gd")
const Surface = preload("res://scripts/planet_surface.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
const Tiles = preload("res://scripts/cloud_brush_library.gd")
const SOURCE := "res://assets/planets/verdant.tres"
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _run() -> void:
	if "verify-restart" in OS.get_cmdline_user_args():
		var expected := FileAccess.get_file_as_bytes("user://expected-clouds.bin")
		var loaded := Planets.load_planet(SOURCE)
		check(loaded.cloud_weather != null and loaded.cloud_weather.image.get_data() == expected, "Fresh process loads the saved cloud map")
		check(Surface.home().definition.cloud_weather.image.get_data() == expected, "Fresh flight world loads the saved cloud map")
		_finish()
		return
	var bundled: Resource = Surface.HOME.duplicate(true)
	bundled.cloud_weather = null
	check(ResourceSaver.save(bundled, "user://bundled-cloud-fixture.tres") == OK, "Write bundled fixture")
	var pack := PCKPacker.new()
	check(pack.pck_start("user://cloud-save-fixture.pck") == OK, "Create PCK fixture")
	check(pack.add_file(SOURCE, "user://bundled-cloud-fixture.tres") == OK, "Add immutable planet")
	check(pack.flush() == OK, "Finish fixture PCK")
	check(ProjectSettings.load_resource_pack("user://cloud-save-fixture.pck", true), "Mount bundled planet")
	check(Planets.save_path(SOURCE) == "user://planets/verdant.tres", "Bundled worlds save to writable user storage")
	var editor := Editor.new()
	root.add_child(editor)
	editor._clear_clouds()
	editor.settings.cloud_weather.stamp(Vector3.BACK, 0.4, Tiles.tile("storm"), 0.9)
	if not editor.parent_settings.moons.is_empty():
		editor.parent_settings.moons[0].cloud_weather = Weather.new()
		editor.parent_settings.moons[0].cloud_weather.stamp(Vector3.RIGHT, 0.4, Tiles.tile("cumulus"), 0.9)
	for pass_index in range(2):
		editor.settings.cloud_weather.stamp(Vector3(0.15 * pass_index, 0.2, 1).normalized(), 0.3, Tiles.tile("mushroom"), 0.9)
		var expected: PackedByteArray = editor.settings.cloud_weather.image.get_data()
		var before: Resource = editor.parent_settings.duplicate(true)
		editor._save_world()
		check(editor.settings.cloud_weather != null and editor.settings.cloud_weather.image.get_data() == expected, "Save keeps clouds visible, including repeated saves")
		var loaded := Planets.load_planet(SOURCE)
		check(editor._same_saved_clouds(before, loaded), "Parent and moon clouds persist byte-for-byte")
		check(Surface.home().definition.cloud_weather.image.get_data() == expected, "Flight uses saved clouds immediately")
		editor._load_current_planet()
		check(editor.settings.cloud_weather.image.get_data() == expected, "Reopening the editor uses the override")
		var expected_file := FileAccess.open("user://expected-clouds.bin", FileAccess.WRITE)
		expected_file.store_buffer(expected)
		expected_file.close()
	var catalog_match := false
	for definition in Planets.load_all():
		if definition.get_meta("source_planet_path", "") == SOURCE:
			catalog_match = editor._same_saved_clouds(editor.parent_settings, definition)
	check(catalog_match, "Planet catalog loads the edited world with its original identity")
	var immutable := ResourceLoader.load(SOURCE, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(immutable.cloud_weather == null, "Bundled original is unchanged; saved weather lives in the override")
	var output: Array = []
	var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/test_cloud_save_persistence.gd", "--", "verify-restart"], output, true)
	check(result == 0, "Saved clouds survive a fresh game process: " + str(output))
	editor.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: PCK cloud save, repeated saves, preview retention, moon weather, editor/catalog reload and process restart.")
	quit(0 if failures.is_empty() else 1)
