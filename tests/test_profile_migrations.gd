extends SceneTree
## Fixed historical documents; run only with isolated XDG homes.
const Profile = preload("res://scripts/profile.gd")
const Parts = preload("res://scripts/parts.gd")
const FIXTURES: Array[String] = ["v1_legacy", "v1_assembly"]
var _directory: String = "user://profile-migrations-%d" % OS.get_process_id()

func _init() -> void:
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory)) == OK)
	for fixture: String in FIXTURES:
		_test_fixture(fixture)
	_test_future()
	_test_failures()
	print("PASS: historical profile migrations, backups, retries and future-version protection.")
	quit(0)

func _write(path: String, contents: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(contents)
	file.close()

func _fixture(name: String) -> String:
	return FileAccess.get_file_as_string("res://tests/fixtures/profile/" + name + ".json")

func _test_fixture(name: String) -> void:
	var path: String = _directory + "/" + name + ".json"
	var original: String = _fixture(name)
	var source: Dictionary = JSON.parse_string(original)
	_write(path, original)
	var profile = Profile.new(path)
	assert(profile.last_error.is_empty(), profile.last_error)
	assert(profile.data.version == Profile.SAVE_VERSION)
	for key: String in ["completed", "flights", "recoveries", "best_altitude", "sound"]:
		assert(profile.data[key] == source[key], name + " preserves " + key)
	for key: String in ["name", "tanks", "engine", "boosters", "fins", "booster_first"]:
		assert(profile.data.design[key] == source.design[key], name + " preserves design " + key)
	assert(Parts.Craft.valid(profile.data.design.assembly))
	if name == "v1_legacy":
		assert(profile.data.design.assembly.parts.size() == 9)
		assert(profile.data.design.assembly.stages == [["ignite:boosters"], ["separate:boosters", "ignite:engine"], ["separate:decoupler"], ["deploy:capsule"]])
	else:
		assert(JSON.parse_string(JSON.stringify(profile.data.design.assembly)) == source.design.assembly, "Existing assembly is preserved")
	assert(FileAccess.get_file_as_string(path + ".bak") == original, "Backup preserves exact original bytes")
	assert(not FileAccess.file_exists(path + ".tmp"))
	var saved: String = FileAccess.get_file_as_string(path)
	assert(JSON.parse_string(saved).version == Profile.SAVE_VERSION, "Migration persists automatically")
	var reloaded = Profile.new(path)
	assert(reloaded.last_error.is_empty() and reloaded.data == profile.data)
	assert(FileAccess.get_file_as_string(path) == saved, "Current version load does not rewrite")
	reloaded.data.flights += 1
	assert(reloaded.save())
	assert(FileAccess.get_file_as_string(path + ".bak") == original, "Subsequent saves retain pre-migration backup")

func _test_future() -> void:
	var path: String = _directory + "/future.json"
	for version: float in [float(Profile.SAVE_VERSION + 1), 1e100]:
		var original: String = JSON.stringify({"version": version, "flights": 123, "future_world": {"stations": ["keep me"]}})
		_write(path, original)
		var profile = Profile.new(path)
		assert(not profile.last_error.is_empty())
		assert(profile.data.flights == 0, "Future schema is not loaded")
		profile.data.flights = 1
		for attempt: int in range(2):
			assert(not profile.save(), "Autosave must not replace a future profile")
		assert(FileAccess.get_file_as_string(path) == original)
		assert(not FileAccess.file_exists(path + ".bak"))
		assert(not FileAccess.file_exists(path + ".tmp"))

func _test_failures() -> void:
	var original: String = _fixture("v1_legacy")
	# A directory at each output path injects backup and temporary-write failures.
	for suffix: String in [".bak", ".tmp"]:
		var path: String = _directory + "/blocked" + suffix + ".json"
		_write(path, original)
		var obstacle: String = ProjectSettings.globalize_path(path + suffix)
		assert(DirAccess.make_dir_absolute(obstacle) == OK)
		Engine.print_error_messages = false
		var profile = Profile.new(path)
		var retry_saved: bool = profile.save()
		Engine.print_error_messages = true
		assert(not profile.last_error.is_empty())
		assert(profile.data.flights == 19, "Migrated data remains usable in memory")
		assert(not retry_saved, "Retry cannot bypass failed migration persistence")
		assert(FileAccess.get_file_as_string(path) == original)
		assert(DirAccess.remove_absolute(obstacle) == OK)
		assert(profile.save(), profile.last_error)
		assert(profile.last_error.is_empty())
		assert(FileAccess.get_file_as_string(path + ".bak") == original)
		assert(JSON.parse_string(FileAccess.get_file_as_string(path)).version == Profile.SAVE_VERSION)
