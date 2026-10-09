extends RefCounted

const DIRECTORY := "res://assets/planets"
const SAVED_DIRECTORY := "user://planets"

## Bundled res:// files cannot be replaced inside an exported PCK. Keep the
## logical planet identity, but save an editable override outside the bundle.
static func save_path(path: String) -> String:
	if path.begins_with(DIRECTORY + "/"):
		return SAVED_DIRECTORY.path_join(path.trim_prefix(DIRECTORY + "/"))
	return path

static func load_planet(path: String) -> Resource:
	var saved_path := save_path(path)
	var actual_path := saved_path if FileAccess.file_exists(saved_path) else path
	var resource := ResourceLoader.load(actual_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if resource != null:
		resource.set_meta("source_planet_path", path)
	return resource

static func paths() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(DIRECTORY)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file := dir.get_next()
	while not file.is_empty():
		var resource_name := file.trim_suffix(".remap")
		if not dir.current_is_dir() and resource_name.ends_with(".tres") and not DIRECTORY.path_join(resource_name) in result:
			result.append(DIRECTORY.path_join(resource_name))
		file = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result

static func load_all() -> Array[Resource]:
	var result: Array[Resource] = []
	for path in paths():
		var resource := load_planet(path)
		if resource != null:
			resource.set_meta("source_planet_path", path)
			result.append(resource)
	return result
