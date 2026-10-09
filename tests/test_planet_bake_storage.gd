extends SceneTree
const Storage = preload("res://scripts/planet_bake_storage.gd")
const Baker = preload("res://scripts/planet_baker.gd")
const Bake = preload("res://scripts/planet_bake.gd")
const Definition = preload("res://scripts/planet_definition.gd")
const Terrain = preload("res://scripts/planet_terrain.gd")
const ROOT := "user://bake-storage-test"

func _initialize() -> void:
	_check_scanning()
	_check_saving()
	_check_failed_save()
	print("PASS: reference-aware bake cleanup, exact body scope, legacy retention, dry run and planet/moon saves")
	quit(0)

func _check_scanning() -> void:
	var root := ROOT.path_join("scan")
	var body := root.path_join("world.tres")
	var orphan := _write(root.path_join("baked/world-" + "a".repeat(64) + ".res"), "orphan")
	var legacy_signature := Terrain.legacy_bake_signature(Definition.new())
	assert(legacy_signature.length() == 64)
	var legacy := _write(root.path_join("baked/world-" + legacy_signature + ".res"), "legacy")
	var shared := _write(root.path_join("baked/world-" + "b".repeat(64) + ".res"), "shared")
	var global_reference := _write(Storage.SAVED_PLANETS.path_join("nested/shared.tres"), '[gd_resource type="Resource" format=3]\n[ext_resource path="%s" type="Resource" id="1"]\n[resource]\n' % shared)
	var moon := _write(root.path_join("moons/baked/world-moon-0-" + "c".repeat(64) + ".res"), "moon")
	var other := _write(root.path_join("baked/world-other-" + "D".repeat(64) + ".res"), "other")
	var same_name := _write(root.path_join("moons/baked/world-" + "e".repeat(64) + ".res"), "same name, different directory")
	var untouched: Array[String] = []
	for name in ["world.res", "world-short.res", "world-" + "a".repeat(63) + ".res", "world-" + "a".repeat(65) + ".res", "world-" + "g".repeat(64) + ".res", "world-" + "a".repeat(64) + ".res.bak", "world-" + "a".repeat(64) + ".res\n"]:
		untouched.append(_write(root.path_join("baked").path_join(name), "not a bake"))
	untouched.append(_write(root.path_join("world-" + "f".repeat(64) + ".res"), "outside baked directory"))
	# A saved definition in a hidden nested directory, with a relative legacy
	# reference and reordered/multiline attributes, must protect its legacy bake.
	_write(root.path_join(".archive/kept.tres"), '[gd_resource type="Resource" format=3]\n[ext_resource id="1"\n path="../baked/world-%s.res" type="Resource"]\n[resource]\n' % legacy_signature)
	var report := Storage.cleanup(root, [body])
	assert(report.error == OK, report.message)
	assert(_paths(report) == [orphan], "Only exact body-name/hash matches without references are candidates")
	assert(report.bytes == 6 and report.deleted == 0)
	assert(FileAccess.file_exists(orphan), "Dry run is the default")
	report = Storage.cleanup(root, [body], true)
	assert(report.error == OK and report.deleted == 1)
	assert(not FileAccess.file_exists(orphan))
	for path in [legacy, shared, moon, other, same_name] + untouched:
		assert(FileAccess.file_exists(path), "Retain referenced, unrelated and nonmatching files: " + path)
	# All-body mode finds even bodies whose definitions have since been removed.
	report = Storage.cleanup(root)
	assert(report.error == OK and report.files.size() == 3)
	for path in [moon, other, same_name]:
		assert(path in _paths(report) and FileAccess.file_exists(path))
	var broken := _write(root.path_join("broken.tres"), '[ext_resource path="unfinished')
	report = Storage.cleanup(root, [], true)
	assert(report.error != OK and report.deleted == 0, "Incomplete reference scans fail closed")
	for path in [moon, other, same_name]:
		assert(FileAccess.file_exists(path))
	assert(DirAccess.remove_absolute(broken) == OK)
	report = Storage.cleanup(root, [], true)
	assert(report.error == OK and report.deleted == 3)
	assert(FileAccess.file_exists(legacy) and FileAccess.file_exists(shared))
	assert(Storage.cleanup(root).files.is_empty(), "Cleanup is idempotent")
	assert(Storage.cleanup(root.path_join("missing"), [], true).error != OK)
	assert(DirAccess.remove_absolute(global_reference) == OK)
	assert(_paths(Storage.cleanup(root)) == [shared], "References outside the candidate tree protect shared bakes")

func _check_saving() -> void:
	var root := ROOT.path_join("save")
	var path := root.path_join("world.tres")
	var moon_path := root.path_join("moons/world-moon-0.tres")
	var settings := Definition.new()
	var moon := Definition.new()
	moon.radius = 16000.0
	moon.launch_site = false
	settings.moons.append(moon)
	_use_small_bake(settings)
	_use_small_bake(moon)
	assert(Baker.save_planet(settings, path) == OK)
	var first: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var first_bake: String = first.baked_terrain.resource_path
	var first_moon_bake: String = first.moons[0].baked_terrain.resource_path
	# A second saved .tres owns the planet's old bake, but does not own its moon.
	var archived: Resource = first.duplicate(true)
	archived.moons.clear()
	assert(ResourceSaver.save(archived, root.path_join("archive.tres")) == OK)
	settings.terrain_seed += 1
	moon.terrain_seed += 1
	_use_small_bake(settings)
	_use_small_bake(moon)
	var unrelated := _write(root.path_join("baked/world-other-" + "a".repeat(64) + ".res"), "unrelated")
	var orphan := _write(root.path_join("baked/world-" + "b".repeat(64) + ".res"), "orphan")
	assert(Baker.save_planet(settings, path) == OK)
	assert(FileAccess.file_exists(first_bake), "Other saved definitions protect old bakes")
	assert(not FileAccess.file_exists(first_moon_bake), "Moon cleanup runs after parent references advance")
	assert(not FileAccess.file_exists(orphan))
	assert(FileAccess.file_exists(unrelated), "Saving one system does not clean unrelated bodies")
	var saved: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var saved_moon: Resource = ResourceLoader.load(moon_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	assert(saved.baked_terrain.signature == Terrain.bake_signature(settings))
	assert(saved.moons[0].baked_terrain.signature == Terrain.bake_signature(moon))
	assert(saved.moons[0].baked_terrain.resource_path == saved_moon.baked_terrain.resource_path)
	assert(FileAccess.file_exists(saved.baked_terrain.resource_path))
	assert(FileAccess.file_exists(saved_moon.baked_terrain.resource_path))
	assert(Baker.save_planet(settings, path) == OK, "Saving an unchanged signature retains its bake")
	assert(FileAccess.file_exists(saved.baked_terrain.resource_path))
	assert(FileAccess.file_exists(saved_moon.baked_terrain.resource_path))

func _check_failed_save() -> void:
	var root := ROOT.path_join("failed-save")
	var path := root.path_join("world.tres")
	# Force the final .tres write to fail after the moon and parent bakes save.
	assert(DirAccess.make_dir_recursive_absolute(path) == OK)
	var parent_orphan := _write(root.path_join("baked/world-" + "a".repeat(64) + ".res"), "parent")
	var moon_orphan := _write(root.path_join("moons/baked/world-moon-0-" + "b".repeat(64) + ".res"), "moon")
	var settings := Definition.new()
	var moon := Definition.new()
	settings.moons.append(moon)
	_use_small_bake(settings)
	_use_small_bake(moon)
	var original_bake: Resource = settings.baked_terrain
	# ResourceSaver reports this intentional filesystem failure to stderr too.
	var print_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	var error := Baker.save_planet(settings, path)
	Engine.print_error_messages = print_errors
	assert(error != OK)
	assert(settings.baked_terrain == original_bake, "A failed save does not replace the edited resource")
	assert(FileAccess.file_exists(root.path_join("moons/world-moon-0.tres")), "The child save completed before the failure")
	assert(FileAccess.file_exists(parent_orphan) and FileAccess.file_exists(moon_orphan), "No cleanup runs for a failed system save")

func _paths(report: Dictionary) -> Array[String]:
	var paths: Array[String] = []
	for candidate: Dictionary in report.files:
		paths.append(candidate.path)
	return paths

func _write(path: String, contents: String) -> String:
	assert(DirAccess.make_dir_recursive_absolute(path.get_base_dir()) == OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(contents)
	file.close()
	return path

func _use_small_bake(settings: Resource) -> void:
	# Exercise actual ResourceSaver and recursive Baker calls without generating
	# megabytes of terrain. Full mesh persistence is covered by test_planet_bake.
	var bake := Bake.new()
	bake.signature = Terrain.bake_signature(settings)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.UP, Vector3.RIGHT, Vector3.BACK])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	for _lod in Terrain.RENDER_LODS:
		bake.layers.append(mesh)
	bake.preview = mesh
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	bake.surface_texture = ImageTexture.create_from_image(image)
	bake.topography_texture = ImageTexture.create_from_image(image)
	settings.baked_terrain = bake
