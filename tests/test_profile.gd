extends SceneTree
## Separate process-specific profile path preserves player and smoke-test saves.
## tools/check.sh additionally provides an isolated XDG_DATA_HOME.
const Profile = preload("res://scripts/profile.gd")
const Parts = preload("res://scripts/parts.gd")
var _checks: int = 0
var _failures: Array[String] = []
var _directory: String = ""
var _path: String = ""

func _init() -> void:
	_directory = "user://profile-tests-%d" % OS.get_process_id()
	_path = _directory + "/profile.json"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory)) != OK:
		push_error("Cannot create isolated profile test directory.")
		quit(1)
		return
	_test_round_trip()
	_test_documents()
	_test_fields()
	_test_limits()
	_test_assembly_height()
	_test_write_failures()
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_directory))
	if _failures.is_empty():
		print("PASS: %d profile persistence checks." % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _write(contents: String) -> void:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	_check(file != null, "Fixture can be written")
	if file != null:
		file.store_string(contents)
		file.close()

func _test_round_trip() -> void:
	var profile = Profile.new(_path)
	_check(profile.last_error.is_empty(), "Missing save is a normal first run")
	_check(profile.data["design"] == Parts.default_design(), "Default craft is preserved")
	_check(profile.data["flights"] == 0 and profile.data["completed"].is_empty(), "Default progress is empty")
	profile.data = {"version": 1, "design": {"name": "Test craft", "tanks": 3, "engine": "kestrel", "boosters": true, "fins": false}, "completed": ["hop", "sky"], "flights": 9, "recoveries": 4, "best_altitude": 42500.25, "sound": false}
	_check(profile.save(), "Valid profile saves")
	_check(not FileAccess.file_exists(_path + ".tmp"), "Atomic save leaves no temporary file")
	var reloaded = Profile.new(_path)
	_check(reloaded.last_error.is_empty() and reloaded.data == profile.data, "All valid fields survive round trip")
	profile.data["flights"] = 10
	_check(profile.save(), "Existing save can be atomically replaced")
	reloaded = Profile.new(_path)
	_check(reloaded.data["flights"] == 10, "Replacement contains updated profile")
	var first = Profile.new(_directory + "/missing.json")
	first.data["design"]["tanks"] = 4
	var second = Profile.new(_directory + "/missing.json")
	_check(second.data["design"]["tanks"] == 2, "Defaults do not share mutable data")

func _test_documents() -> void:
	var documents: Array[String] = ["", "{broken", "null", "[]", "true", "12", "\"text\"", "{}", '{"version":[]}', '{"version":{}}', '{"version":null}', '{"version":true}', '{"version":"1"}', '{"version":0}', JSON.stringify({"version": Profile.SAVE_VERSION + 1}), '{"version":1.9}', '{"version":1e999}']
	for document: String in documents:
		_write(document)
		var profile = Profile.new(_path)
		_check(not profile.last_error.is_empty(), "Invalid document/version is reported: " + document)
		_check(profile.data["design"] == Parts.default_design() and profile.data["flights"] == 0, "Invalid document leaves usable defaults")
		_check(FileAccess.get_file_as_string(_path) == document, "Loading preserves the original invalid file")
	_write(" ".repeat(Profile.MAX_SAVE_BYTES + 1))
	var oversized = Profile.new(_path)
	_check(not oversized.last_error.is_empty(), "Oversized saves are rejected")
	_write('{"version":1.0}')
	var numeric_version = Profile.new(_path)
	_check(numeric_version.last_error.is_empty(), "JSON numeric version 1.0 is accepted")

func _test_fields() -> void:
	for value: Variant in [null, [], {}, "wrong", true, false]:
		_write(JSON.stringify({"version": 1, "design": {"name": value, "tanks": value, "engine": value, "boosters": value, "fins": value}, "completed": value, "flights": value, "recoveries": value, "best_altitude": value, "sound": value}))
		var profile = Profile.new(_path)
		_check(profile.data["design"]["tanks"] == 2 and profile.data["design"]["engine"] == "sparrow", "Wrong field types preserve valid parts")
		_check(profile.data["flights"] == 0 and profile.data["best_altitude"] == 0.0, "Wrong record types cannot become numeric records")
		_check(profile.data["completed"].is_empty(), "Wrong completion types do not create achievements")
		_check(profile.save(), "Repaired fields remain serializable")
	_write(JSON.stringify({"version": 1, "design": {"name": "   ", "tanks": 999, "engine": "missing", "boosters": false, "fins": false}, "completed": ["hop", "hop", 12, {}, null, "unknown", "sky", "orbit", "sky"], "flights": 5, "recoveries": 100, "sound": false}))
	var sanitized = Profile.new(_path)
	_check(sanitized.data["design"]["name"] == "Pioneer 01", "Blank names use default")
	_check(sanitized.data["design"]["tanks"] == Parts.Craft.MAX_TANKS and sanitized.data["design"]["engine"] == "sparrow", "Parts stay inside supported catalog")
	_check(sanitized.data["completed"] == ["hop", "sky", "orbit"], "Completion IDs are known, unique and ordered")
	_check(sanitized.data["recoveries"] == 5, "Recoveries cannot exceed flights")
	_check(sanitized.data["sound"] == false and sanitized.data["design"]["fins"] == false, "Valid false settings remain false")
	_write('{"version":1,"design":[],"sound":"false"}')
	var wrong_container = Profile.new(_path)
	_check(JSON.parse_string(JSON.stringify(wrong_container.data["design"]["assembly"])) == JSON.parse_string(JSON.stringify(Parts.Craft.migrate(Parts.default_design()))), "Wrong design container is safe")
	_check(wrong_container.data["sound"] == true, "String booleans preserve sound default")

func _test_limits() -> void:
	_write('{"version":1,"flights":1e100,"recoveries":1e100,"best_altitude":-12,"design":{"tanks":-1e100}}')
	var profile = Profile.new(_path)
	_check(profile.data["flights"] == Profile.MAX_COUNTER and profile.data["recoveries"] == Profile.MAX_COUNTER, "Counters clamp before integer conversion")
	_check(profile.data["best_altitude"] == 0.0 and profile.data["design"]["tanks"] == 1, "Negative records and parts are bounded")
	_write('{"version":1,"flights":-42,"recoveries":-5,"best_altitude":1e999,"design":{"tanks":1e999}}')
	profile = Profile.new(_path)
	_check(profile.data["flights"] == 0 and profile.data["recoveries"] == 0, "Counters cannot be negative")
	_check(is_finite(float(profile.data["best_altitude"])) and profile.data["design"]["tanks"] == 2, "Overflowed numbers cannot poison profile")
	profile.data["best_altitude"] = INF
	profile.data["flights"] = NAN
	profile.data["recoveries"] = INF
	profile.data["design"] = {"tanks": INF, "name": "  " + "Long name".repeat(10), "fins": {}}
	profile.data["completed"] = ["orbit", "orbit", "invented"]
	_check(profile.save(), "Non-finite runtime values are repaired on save")
	var saved: String = FileAccess.get_file_as_string(_path)
	_check(not saved.contains("NaN") and not saved.contains("Infinity"), "Serialized numbers are valid JSON")
	var reloaded = Profile.new(_path)
	_check(reloaded.last_error.is_empty() and reloaded.data["best_altitude"] == 0.0, "Repaired numbers reload cleanly")
	_check(reloaded.data["design"]["name"].length() <= 40, "Rocket name length is bounded")
	_check(reloaded.data["completed"] == ["orbit"], "Runtime completion IDs also sanitize on save")

func _test_write_failures() -> void:
	var profile = Profile.new(_directory + "/missing-directory/profile.json")
	_check(not profile.save() and not profile.last_error.is_empty(), "Unwritable destination returns a useful save error")
	var directory_path: String = _directory + "/occupied"
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(directory_path))
	profile = Profile.new(directory_path)
	_check(not profile.save(), "Atomic replacement cannot overwrite a directory")
	_check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory_path)), "Failed save preserves existing destination")
	_check(not FileAccess.file_exists(directory_path + ".tmp"), "Failed save cleans temporary file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory_path))
	profile = Profile.new(_path)
	profile.last_error = "Previous error"
	_check(profile.save() and profile.last_error.is_empty(), "Successful retry clears old error")

func _test_assembly_height() -> void:
	var profile = Profile.new(_path)
	var assembly: Dictionary = Parts.Craft.migrate(Parts.default_design())
	var expected_parts: Array = Parts.Craft.load_craft({"assembly": assembly}).parts
	for height: Variant in [NAN, INF, -INF, "bad", null, [], {}]:
		assembly["root_height"] = height
		profile.data["design"] = {"assembly": assembly}
		_check(profile.save(), "Invalid assembly height can be repaired and saved")
		var reloaded = Profile.new(_path)
		_check(reloaded.last_error.is_empty(), "Repaired assembly reloads")
		_check(reloaded.data.design.assembly.root_height == 9.0, "Invalid height uses safe default")
		_check(reloaded.data.design.assembly.parts == expected_parts, "Height repair preserves the assembled craft")
		_check(FileAccess.get_file_as_bytes(_path).size() <= Profile.MAX_SAVE_BYTES, "Saved document fits loader limit")
	for height: float in [-10.0, 12.5, 100.0]:
		assembly["root_height"] = height
		profile.data["design"] = {"assembly": assembly}
		_check(profile.save(), "Finite assembly height saves")
		var reloaded = Profile.new(_path)
		_check(reloaded.data.design.assembly.root_height == clampf(height, 3.5, Parts.Craft.MAX_ROOT_HEIGHT), "Finite height remains within workshop bounds")
