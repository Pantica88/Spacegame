extends SceneTree

const PATH := "res://assets/planets/ochre.tres"
const PlanetEditor = preload("res://scripts/planet_editor.gd")
const PlanetSurface = preload("res://scripts/planet_surface.gd")
const Definition = preload("res://scripts/planet_definition.gd")

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
		var editor := PlanetEditor.new()
		editor._build_world()
		editor._build_ui()
		var settings := Definition.new()
		settings.planet_name = "Editor Reset"
		settings.terrain_seed = 987654
		settings.radius = 61000.0
		settings.rotation_seconds = 1100.0
		settings.surface_gravity = 8.3
		settings.baked_terrain = null
		var fallback := "user://editor-reset/planet.tres"
		DirAccess.make_dir_recursive_absolute(fallback.get_base_dir())
		editor.current_path = fallback
		editor.settings = settings
		var previous_seed := int(PlanetSurface.home().definition.terrain_seed)
		editor._save_world()
		assert(int(PlanetSurface.home().definition.terrain_seed) == 987654, "Saving a non-default planet resets the shared terrain backing")
		assert(int(PlanetSurface.home().definition.radius) == 61000, "Saved planet settings are applied to the shared terrain backing")
		assert(int(PlanetSurface.home().definition.terrain_seed) != previous_seed, "World backing changes when saving a new editor preset")
		editor._add_moon()
		assert(editor.parent_settings.moons.size() == 1)
		assert(editor.settings != editor.parent_settings)
		assert(not editor.settings.has_ocean and not editor.settings.launch_site)
		editor.controls.has_snow.toggled.emit(false)
		assert(not editor.settings.has_snow and editor.parent_settings.has_snow)
		editor.controls.relief.value_changed.emit(850.0)
		editor.controls.continent_frequency.value_changed.emit(3.5)
		editor.controls.coastline_irregularity.value_changed.emit(0.6)
		editor.controls.terrain_detail.value_changed.emit(0.7)
		editor.controls.erosion.value_changed.emit(0.4)
		var moon_seed: int = editor.settings.terrain_seed
		assert(editor.settings.relief == 850.0)
		assert(editor.parent_settings.relief != 850.0)
		editor._select_body(-1)
		assert(editor.settings.terrain_seed == 987654)
		editor._select_body(0)
		assert(editor.settings.terrain_seed == moon_seed)
		editor._save_world()
		var system := ResourceLoader.load(fallback, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert(system.moons.size() == 1)
		assert(not system.moons[0].has_snow and system.has_snow)
		assert(system.moons[0].relief == 850.0)
		assert(system.moons[0].continent_frequency == 3.5)
		assert(system.moons[0].coastline_irregularity == 0.6)
		assert(system.moons[0].terrain_detail == 0.7)
		assert(system.moons[0].erosion == 0.4)
		assert(system.coastline_irregularity == 0.0, "Moon shaping does not alter its parent")
		assert(system.moons[0].baked_terrain != null)
		assert(system.moons[0].baked_terrain.topography_texture != null)
		assert(PlanetSurface.home().definition.terrain_seed == 987654)
		editor._remove_moon()
		assert(editor.parent_settings.moons.is_empty())
		editor._reset()
		assert(editor.parent_settings.moons.size() == 1, "Reset restores saved moons")
		print("PASS: moons have independent terrain, baked persistence, selection and removal.")
		editor.dragging = true
		editor.pitch = 1.6
		editor.last_mouse = Vector2.ZERO
		var orbit_move := InputEventMouseMotion.new()
		orbit_move.position = Vector2(0.0, 400.0)
		orbit_move.relative = Vector2(0.0, 400.0)
		editor._unhandled_input(orbit_move)
		assert(absf(editor.pitch) > 1.45, "Map editor orbit can pass over the top of the planet and view it upside down.")
		print("PASS: map editor save refreshes the shared terrain backing for non-default planets.")
		editor.free()
		quit(0)
	else:
		push_error("Planet save did not round-trip from disk.")
		quit(1)

func _restore(absolute: String, contents: String) -> void:
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file != null:
		file.store_string(contents)
		file.close()
