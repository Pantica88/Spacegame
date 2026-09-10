extends SceneTree
const Definition = preload("res://scripts/planet_definition.gd")
const Terrain = preload("res://scripts/planet_terrain.gd")
const Baker = preload("res://scripts/planet_baker.gd")

func _initialize() -> void:
	var settings := Definition.new()
	var path := "user://bake-test/planet.tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert(Baker.save_planet(settings, path) == OK, "Bake and settings save successfully")
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var runtime := Terrain.new(loaded)
	assert(runtime._render_meshes.size() == 5, "All flight layers load from the bake")
	assert(runtime.preview_mesh() == loaded.baked_terrain.preview, "Map uses the saved preview")
	assert(runtime.surface_texture == loaded.baked_terrain.surface_texture, "All LODs share baked surface colors")
	assert(runtime.surface_texture.get_width() == 2048 and runtime.surface_texture.get_height() == 1024)
	assert(runtime.surface_texture.get_image().has_mipmaps(), "Baked surface supports filtered distant rendering")
	for lod in range(5):
		var mesh := runtime.render_mesh_for_lod(lod)
		assert(mesh == loaded.baked_terrain.layers[lod], "Runtime consumes the saved mesh")
		var expected: Array = settings.baked_terrain.layers[lod].surface_get_arrays(0)
		var actual: Array = mesh.surface_get_arrays(0)
		for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
			assert(actual[channel] == expected[channel], "Mesh channels survive serialization")
	runtime.build()
	assert(runtime.mesh == loaded.baked_terrain.layers[0])
	assert(runtime.collision != null, "Collision is derived from the baked full-detail mesh")
	assert(absf(float(runtime.contact(Vector3.UP*60000.0).radius)-60000.0) < 0.1)
	loaded.terrain_seed += 1
	var changed := Terrain.new(loaded)
	assert(changed._render_meshes.is_empty() and changed._preview_meshes.is_empty(), "Changed settings reject stale bake")
	loaded.terrain_seed -= 1
	loaded.baked_terrain.signature = "old-generator-version"
	assert(Terrain.new(loaded)._render_meshes.is_empty(), "Changed generator rejects stale bake")
	print("PASS: baked layer persistence, exact mesh channels, collision, stale bake rejection")
	quit()
