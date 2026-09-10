extends RefCounted

const DIRECTORY := "res://assets/planets"

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
		var resource := ResourceLoader.load(path)
		if resource != null:
			resource.resource_path = path
			result.append(resource)
	return result
