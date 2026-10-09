extends RefCounted
const Terrain = preload("res://scripts/planet_terrain.gd")
const BakeStorage = preload("res://scripts/planet_bake_storage.gd")

static func save_planet(settings: Resource, path: String) -> Error:
	var saved_paths := PackedStringArray()
	var error := _save_planet(settings, path, saved_paths)
	if error == OK:
		# Parent .tres files can embed moon bake references. Wait until the whole
		# system is saved so those references have also advanced to the new bake.
		var cleanup := BakeStorage.cleanup(BakeStorage.root_for_body(path), saved_paths, true)
		if cleanup.error != OK:
			push_warning("Planet saved, but bake cleanup was skipped or incomplete: %s (%s)" % [cleanup.message, error_string(cleanup.error)])
	return error

static func _save_planet(settings: Resource, path: String, saved_paths: PackedStringArray) -> Error:
	# Work on copies so a failed child bake leaves the editor and saved system intact.
	var saved_settings: Resource = settings.duplicate(true)
	for index in range(saved_settings.moons.size()):
		var moon: Resource = saved_settings.moons[index]
		var moon_path := path.get_base_dir().path_join("moons").path_join(path.get_file().get_basename() + "-moon-%d.tres" % index)
		var moon_error := _save_planet(moon, moon_path, saved_paths)
		if moon_error != OK:
			return moon_error
	var terrain := Terrain.new(settings)
	var baked: Resource = terrain.bake()
	var directory := path.get_base_dir().path_join("baked")
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	# Write the complete bake before changing the planet's reference. A failed
	# bake cannot replace the data used by the previously saved planet.
	var bake_path := directory.path_join(path.get_file().get_basename()+"-"+baked.signature+".res")
	error = ResourceSaver.save(baked, bake_path, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		return error
	saved_settings.baked_terrain = ResourceLoader.load(bake_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if saved_settings.baked_terrain == null:
		return ERR_CANT_OPEN
	error = ResourceSaver.save(saved_settings, path)
	if error == OK:
		settings.baked_terrain = saved_settings.baked_terrain
		saved_paths.append(path)
	return error
