extends RefCounted
## Versioned, locally stored profile. No account or connection required.

const SAVE_PATH: String = "user://profile.json"
const SAVE_VERSION: int = 2
const MAX_SAVE_BYTES: int = 262144
const MAX_COUNTER: int = 2147483647
const COMPLETED_IDS: Array[String] = ["hop", "sky", "orbit"]
const Parts = preload("res://scripts/parts.gd")
const AtmosphereQuality = preload("res://scripts/atmosphere_quality.gd")

var data: Dictionary = {}
var last_error: String = ""
var _save_path: String = SAVE_PATH
var _write_blocked: bool = false
var _backup_pending: bool = false


func _init(save_path: String = SAVE_PATH) -> void:
	_save_path = save_path
	data = _defaults()
	if not FileAccess.file_exists(_save_path):
		return
	var file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if file == null:
		last_error = "Could not read saved profile."
		return
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		last_error = "Saved profile is too large. Starting with a fresh design."
		return
	var contents: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(contents) != OK or not json.data is Dictionary:
		last_error = "Saved profile could not be loaded. Starting with a fresh design."
		return
	var stored: Dictionary = json.data
	var version: Variant = stored.get("version")
	# JSON numbers can be floats. Check type and exact value before conversion;
	# casts such as int([]) and float({}) otherwise raise runtime errors.
	if not _is_number(version) or not is_finite(float(version)) or float(version) < 1.0 or floorf(float(version)) != float(version):
		last_error = "Saved profile version is unsupported. Starting with a fresh design."
		return
	if float(version) > SAVE_VERSION:
		_write_blocked = true
		last_error = "Saved profile is from a newer version. The file has been preserved; saving is disabled."
		return
	var original_version: int = int(version)
	while int(stored["version"]) < SAVE_VERSION:
		var previous_version: int = int(stored["version"])
		match previous_version:
			1:
				stored = _migrate_v1_to_v2(stored)
			_:
				stored = {}
		# Every migration must advance exactly one version. Fail closed if a
		# future bump is missing its migration or returns an invalid result.
		if stored.get("version") != previous_version + 1:
			_write_blocked = true
			last_error = "Saved profile migration is unavailable. The file has been preserved; saving is disabled."
			return
	data = _sanitize(stored)
	if original_version < SAVE_VERSION:
		_backup_pending = true
		save()


static func _migrate_v1_to_v2(stored: Dictionary) -> Dictionary:
	# v1 allowed scalar craft settings as well as assemblies. Materialize the
	# legacy craft once, retaining an existing assembly and all profile records.
	var migrated: Dictionary = _sanitize(stored)
	if not Parts.Craft.valid(migrated.design.get("assembly")):
		migrated.design["assembly"] = Parts.Craft.migrate(migrated.design)
	migrated["version"] = 2
	return migrated


func save() -> bool:
	if _write_blocked:
		last_error = "Saved profile version is unsupported. The file has been preserved; saving is disabled."
		return false
	var clean: Dictionary = _sanitize(data)
	var contents: String = JSON.stringify(clean, "\t")
	# Never replace a usable save with a document our loader would reject.
	if contents.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		last_error = "Saved profile is too large. The previous save has been preserved."
		return false
	if _backup_pending:
		# Copy the exact original bytes before touching the destination. Keep
		# this pending on failure so later autosaves cannot skip the backup.
		var backup_error: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(_save_path), ProjectSettings.globalize_path(_save_path + ".bak"))
		if backup_error != OK:
			last_error = "Could not back up the saved profile. The previous save has been preserved."
			return false
	var temporary: String = _save_path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Could not save the profile to disk."
		return false
	file.store_string(contents)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = "Could not finish writing the saved profile."
		return false
	var error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(_save_path))
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = "Could not replace the saved profile."
		return false
	_backup_pending = false
	data = clean
	last_error = ""
	return true


static func _defaults() -> Dictionary:
	return {"version": SAVE_VERSION, "design": Parts.default_design(), "completed": [], "flights": 0, "recoveries": 0, "best_altitude": 0.0, "sound": true, "atmosphere_quality": AtmosphereQuality.DEFAULT}


static func _sanitize(stored: Dictionary) -> Dictionary:
	var clean: Dictionary = _defaults()
	var design: Dictionary = Parts.default_design()
	if stored.get("design") is Dictionary:
		var source: Dictionary = stored["design"]
		if source.get("name") is String:
			design["name"] = str(source["name"])
		if source.get("engine") is String:
			design["engine"] = str(source["engine"])
		if _is_number(source.get("tanks")) and is_finite(float(source["tanks"])):
			design["tanks"] = int(clampf(float(source["tanks"]), 1.0, float(Parts.Craft.MAX_TANKS)))
		for key: String in ["boosters", "fins", "booster_first"]:
			if source.get(key) is bool:
				design[key] = bool(source[key])
		if Parts.Craft.valid(source.get("assembly")):
			design["assembly"] = source.assembly
	clean["design"] = Parts.normalize_design(design)
	for key: String in ["flights", "recoveries"]:
		var value: Variant = stored.get(key)
		if _is_number(value) and is_finite(float(value)):
			clean[key] = int(clampf(float(value), 0.0, float(MAX_COUNTER)))
	clean["recoveries"] = mini(int(clean["recoveries"]), int(clean["flights"]))
	var altitude: Variant = stored.get("best_altitude")
	if _is_number(altitude) and is_finite(float(altitude)):
		clean["best_altitude"] = maxf(0.0, float(altitude))
	if stored.get("sound") is bool:
		clean["sound"] = bool(stored["sound"])
	if stored.get("atmosphere_quality") is String and stored["atmosphere_quality"] in AtmosphereQuality.MENU:
		clean["atmosphere_quality"] = str(stored["atmosphere_quality"])
	if stored.get("completed") is Array:
		for id: Variant in stored["completed"]:
			if id is String and id in COMPLETED_IDS and not id in clean["completed"]:
				clean["completed"].append(id)
	return clean


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
