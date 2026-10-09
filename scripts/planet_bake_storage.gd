extends RefCounted
## Reference-aware garbage collection. Reading .tres headers avoids loading meshes.
const PLANETS := "res://assets/planets"
const SAVED_PLANETS := "user://planets"

## An empty body_paths list selects all bodies under root. Deletion is opt-in.
## A body path is its saved .tres path, not its display name or a filename prefix.
static func cleanup(root: String = PLANETS, body_paths: PackedStringArray = [], delete_files := false) -> Dictionary:
	var result := {"error": OK, "message": "", "files": [], "bytes": 0, "deleted": 0}
	var files: Array[String] = []
	var error := _collect_files(root, files)
	if error != OK:
		return _failure(result, error, "Cannot scan " + root)
	var reference_files := files.duplicate()
	# User overrides can still point at bundled bakes, and a saved moon can be
	# referenced by a parent outside its own directory. Always check both trees.
	for extra_root in [PLANETS, SAVED_PLANETS]:
		if _absolute(extra_root) == _absolute(root) or not DirAccess.dir_exists_absolute(extra_root):
			continue
		error = _collect_files(extra_root, reference_files)
		if error != OK:
			return _failure(result, error, "Cannot scan " + extra_root)
	var references := {}
	var header_start := RegEx.create_from_string('(?m)^\\s*\\[ext_resource\\b')
	var header := RegEx.create_from_string('(?m)^\\s*\\[ext_resource\\b(?:[^"\\]]|"(?:\\\\.|[^"\\\\])*")*\\]')
	var path_attribute := RegEx.create_from_string('(?:^|\\s)path\\s*=\\s*("(?:\\\\.|[^"\\\\])*")')
	for path: String in reference_files:
		if not path.ends_with(".tres"):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _failure(result, FileAccess.get_open_error(), "Cannot read " + path)
		var contents := file.get_as_text()
		error = file.get_error()
		file.close()
		if error != OK and error != ERR_FILE_EOF:
			return _failure(result, error, "Cannot read " + path)
		var headers := header.search_all(contents)
		if headers.size() != header_start.search_all(contents).size():
			return _failure(result, ERR_PARSE_ERROR, "Incomplete ext_resource in " + path)
		for match_header in headers:
			var match_path := path_attribute.search(match_header.get_string())
			if match_path == null:
				return _failure(result, ERR_PARSE_ERROR, "Missing ext_resource path in " + path)
			var referenced: Variant = str_to_var(match_path.get_string(1))
			if not referenced is String or referenced.is_empty():
				return _failure(result, ERR_PARSE_ERROR, "Invalid ext_resource path in " + path)
			if referenced.is_relative_path():
				referenced = path.get_base_dir().path_join(referenced)
			references[_absolute(referenced)] = true
	var bodies := {}
	for body_path in body_paths:
		var bake_prefix := body_path.get_base_dir().path_join("baked").path_join(body_path.get_file().get_basename())
		bodies[_absolute(bake_prefix)] = true
	var bake_name := RegEx.create_from_string('^(.+)-[0-9a-fA-F]{64}\\.res\\z')
	files.sort()
	for path in files:
		if path.get_base_dir().get_file() != "baked":
			continue
		var match_name := bake_name.search(path.get_file())
		if match_name == null:
			continue
		var body := _absolute(path.get_base_dir().path_join(match_name.get_string(1)))
		if not body_paths.is_empty() and not bodies.has(body):
			continue
		if references.has(_absolute(path)):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _failure(result, FileAccess.get_open_error(), "Cannot read " + path)
		var size := file.get_length()
		file.close()
		result.files.append({"path": path, "bytes": size})
		result.bytes += size
	# Finish the entire reference scan before deleting anything. A failed scan
	# must never turn an unreadable reference into an apparent orphan.
	if delete_files:
		for candidate: Dictionary in result.files:
			error = DirAccess.remove_absolute(candidate.path)
			if error != OK:
				return _failure(result, error, "Cannot delete " + candidate.path)
			result.deleted += 1
	return result

static func root_for_body(path: String) -> String:
	for root in [PLANETS, SAVED_PLANETS]:
		if _absolute(path).begins_with(_absolute(root) + "/"):
			return root
	return path.get_base_dir()

static func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path).simplify_path()

static func _failure(result: Dictionary, error: Error, message: String) -> Dictionary:
	result.error = error
	result.message = message
	return result

static func _collect_files(root: String, files: Array[String]) -> Error:
	var directory := DirAccess.open(root)
	if directory == null:
		return DirAccess.get_open_error()
	directory.include_hidden = true
	var error := directory.list_dir_begin()
	if error != OK:
		return error
	var name := directory.get_next()
	while not name.is_empty():
		var path := root.path_join(name)
		# Do not traverse links outside the tree or miss references through aliases.
		# Refuse cleanup in that case, leaving all bakes intact.
		if directory.is_link(name):
			return ERR_UNAVAILABLE
		if directory.current_is_dir():
			error = _collect_files(path, files)
			if error != OK:
				return error
		else:
			files.append(path)
		name = directory.get_next()
	directory.list_dir_end()
	return OK
