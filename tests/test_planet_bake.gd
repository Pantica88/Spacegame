extends SceneTree
const Definition = preload("res://scripts/planet_definition.gd")
const Terrain = preload("res://scripts/planet_terrain.gd")
const Baker = preload("res://scripts/planet_baker.gd")
const Fixture = preload("res://tests/terrain_fixture.gd")

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
	assert(runtime.topography_texture == loaded.baked_terrain.topography_texture, "Every LOD reuses saved topography")
	assert(runtime.topography_texture.get_width() == 2048 and runtime.topography_texture.get_height() == 1024)
	assert(runtime.topography_texture.get_image().has_mipmaps(), "Normal detail fades with distance")
	for key in ["coastline_irregularity", "mountain_height", "erosion", "terrain_detail", "detail_frequency"]:
		var original: float = loaded.get(key)
		loaded.set(key, original + 0.1)
		assert(Terrain.new(loaded)._render_meshes.is_empty(), "Shaping controls reject stale bakes")
		loaded.set(key, original)
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
	assert(runtime.preview_mesh() == runtime.mesh, "Editor, map, moons and collision share one saved mesh")
	print("PASS: saved color/topography maps, exact mesh channels and shaping cache invalidation")
	if not _check_visible_contacts(runtime):
		quit(1)
		return
	var moon := Definition.new()
	moon.radius = 16000.0
	moon.relief = 500.0
	moon.has_ocean = false
	moon.launch_site = false
	if not _check_visible_contacts(Terrain.new(moon)):
		quit(1)
		return

	assert(absf(float(runtime.contact(Terrain.LAUNCH_DIRECTION * loaded.radius).radius) - loaded.radius) < 0.1)
	var snowy_color := runtime.color_at(Vector3.DOWN, loaded.relief * 1.5, false)
	loaded.has_snow = false
	var snowless := Terrain.new(loaded)
	assert(snowless._render_meshes.is_empty(), "Snow toggle rejects stale baked colors")
	assert(not snowless.color_at(Vector3.DOWN, loaded.relief * 1.5, false).is_equal_approx(snowy_color), "Disabling snow exposes highland terrain")
	loaded.has_snow = true
	loaded.terrain_seed += 1
	var changed := Terrain.new(loaded)
	assert(changed._render_meshes.is_empty() and changed._preview_meshes.is_empty(), "Changed settings reject stale bake")
	loaded.terrain_seed -= 1
	loaded.baked_terrain.signature = "old-generator-version"
	assert(Terrain.new(loaded)._render_meshes.is_empty(), "Changed generator rejects stale bake")
	print("PASS: baked layer persistence, exact mesh channels, collision, stale bake rejection")
	quit()

func _check_visible_contacts(terrain: RefCounted) -> bool:
	var arrays: Array = terrain.preview_mesh().surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for offset in range(0, indices.size(), 3003):
		var a := vertices[indices[offset]]
		var b := vertices[indices[offset + 1]]
		var c := vertices[indices[offset + 2]]
		var point := a + ((b - a) + (c - a)) / 3.0
		for time in [0.0, 360.0]:
			var rotation: Basis = terrain.rotation_at(time)
			var radial: Vector3 = rotation * point
			var expected_radius := Fixture.plane_radius(a, b, c, radial, rotation)
			if absf(float(terrain.contact(radial, time).radius) - expected_radius) >= 0.0001:
				push_error("Baked visible triangle must lie on the physical surface, including rotation")
				return false
			var start := radial + radial.normalized() * 10.0
			var finish := radial - radial.normalized() * 10.0
			var hit: Dictionary = terrain.segment_hit(start, finish, time, time)
			var expected_fraction := Fixture.plane_fraction(a, b, c, rotation.transposed() * start, rotation.transposed() * finish)
			if hit.is_empty() or absf(float(hit.fraction) - expected_fraction) >= 0.000001:
				push_error("Swept impacts must stop at the visible baked triangle")
				return false
	return true
