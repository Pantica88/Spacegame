extends RefCounted
const Terrain = preload("res://scripts/planet_terrain.gd")

static func save_planet(settings: Resource, path: String) -> Error:
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
	var saved_settings: Resource = settings.duplicate()
	saved_settings.baked_terrain = ResourceLoader.load(bake_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if saved_settings.baked_terrain == null:
		return ERR_CANT_OPEN
	error = ResourceSaver.save(saved_settings, path)
	if error == OK:
		settings.baked_terrain = saved_settings.baked_terrain
	return error
