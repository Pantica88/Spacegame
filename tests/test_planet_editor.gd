extends SceneTree

const PATH := "res://assets/planets/ochre.tres"

func _init() -> void:
	var absolute := ProjectSettings.globalize_path(PATH)
	var file := FileAccess.open(absolute, FileAccess.READ)
	assert(file != null)
	var original := file.get_as_text()
	file.close()
	var planet := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE).duplicate(true)
	planet.resource_path = PATH
	var old_phase: float = planet.orbit_phase
	planet.orbit_phase = 0.77 if absf(old_phase - 0.77) > 0.01 else 0.33
	var error := ResourceSaver.save(planet, PATH)
	if error != OK:
		_restore(absolute, original)
		push_error("Planet save failed: %s" % error_string(error))
		quit(1)
		return
	var loaded := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var saved := loaded != null and absf(float(loaded.orbit_phase) - float(planet.orbit_phase)) < 0.0001
	_restore(absolute, original)
	if saved:
		print("PASS: planet editor resource save round-trips.")
		quit(0)
	else:
		push_error("Planet save did not round-trip from disk.")
		quit(1)

func _restore(absolute: String, contents: String) -> void:
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file != null:
		file.store_string(contents)
		file.close()
