extends SceneTree
const Definition = preload("res://scripts/planet_definition.gd")
const Terrain = preload("res://scripts/planet_terrain.gd")

func _init() -> void:
	var settings := Definition.new()
	var baseline := Terrain.new(settings)
	# Version 8 saves remain reusable when the new shaping controls are neutral.
	var legacy := Terrain.Bake.new()
	legacy.signature = Terrain.legacy_bake_signature(settings)
	var legacy_mesh := baseline.preview_mesh(64, 32)
	for index in range(Terrain.RENDER_LODS.size()): legacy.layers.append(legacy_mesh)
	legacy.preview = legacy_mesh
	legacy.surface_texture = ImageTexture.create_from_image(Image.create(4, 2, false, Image.FORMAT_RGBAH))
	settings.baked_terrain = legacy
	var legacy_runtime := Terrain.new(settings)
	assert(legacy_runtime._render_meshes.size() == 5 and legacy_runtime.topography_texture == null, "Neutral v8 bakes avoid regeneration")
	settings.terrain_detail = 0.5
	assert(Terrain.new(settings)._render_meshes.is_empty(), "New shaping invalidates v8 bakes")
	settings.terrain_detail = 0.0
	settings.baked_terrain = null
	for key in ["coastline_irregularity", "mountain_height", "erosion", "terrain_detail", "detail_frequency"]:
		var changed_settings := settings.duplicate()
		changed_settings.set(key, 48.0 if key == "detail_frequency" else 0.8)
		var changed := Terrain.new(changed_settings)
		var repeated := Terrain.new(changed_settings)
		var differences := 0
		for i in range(400):
			var direction := Vector3(sin(i * 2.4), sin(i * 0.31), cos(i * 2.4)).normalized()
			var value: float = changed.elevation(direction)
			assert(is_finite(value) and value >= -settings.relief and value <= settings.relief * 1.5)
			assert(value == repeated.elevation(direction), "Shaping is deterministic")
			if absf(value - baseline.elevation(direction)) > 0.05: differences += 1
		assert(differences > 30, "%s affects geographic detail" % key)
		assert(changed.elevation(Terrain.LAUNCH_DIRECTION) == 0.0, "Shaping keeps the launch datum flat")
		assert(changed.color_at(Terrain.LAUNCH_DIRECTION, 0.0).a < 0.001, "Launch center stays dry")
	var shaped := settings.duplicate()
	shaped.coastline_irregularity = 0.7
	shaped.mountain_height = 1.7
	shaped.terrain_detail = 0.8
	shaped.erosion = 0.6
	shaped.radius = 32000.0
	shaped.launch_site = false
	var terrain := Terrain.new(shaped)
	var images := terrain.surface_images(256, 128)
	assert(images.surface.has_mipmaps() and images.topography.has_mipmaps())
	assert(images.topography.get_format() == Image.FORMAT_RGBA8, "Topography uses four bytes per texel")
	var water_samples := 0
	var slope_samples := 0
	for y in range(128):
		for x in range(256):
			var theta := PI * (y + 0.5) / 128.0
			var phi := TAU * (x + 0.5) / 256.0
			var radial := Vector3(sin(phi) * sin(theta), cos(theta), cos(phi) * sin(theta))
			var color: Color = images.topography.get_pixel(x, y)
			var normal := (Vector3(color.r, color.g, color.b) * 2.0 - Vector3.ONE).normalized()
			assert(normal.is_finite() and normal.dot(radial) > 0.0, "Detail normals point outwards at poles and seam")
			if images.surface.get_pixel(x, y).a > 0.99 and color.a < 0.3:
				assert(normal.dot(radial) > 0.9999, "Deep ocean normals remain spherical")
				water_samples += 1
			if normal.dot(radial) < 0.999 and images.surface.get_pixel(x, y).a < 0.1: slope_samples += 1
	assert(water_samples > 100 and slope_samples > 100, "Detail map contains both smooth ocean and finer land slopes")
	# Editor radius slider permits worlds smaller than the launch-ring footprint.
	shaped.radius = 1000.0
	shaped.launch_site = true
	var tiny := Terrain.new(shaped)
	var arrays := tiny.mesh_arrays(64, 32)
	for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]: assert(vertex.is_finite())
	var default_triangles: int = baseline.mesh_arrays(128, 64)[Mesh.ARRAY_INDEX].size() / 3
	var detailed_settings := settings.duplicate()
	detailed_settings.coastline_irregularity = 0.7
	detailed_settings.terrain_detail = 0.8
	var detailed_triangles: int = Terrain.new(detailed_settings).mesh_arrays(128, 64)[Mesh.ARRAY_INDEX].size() / 3
	assert(default_triangles == detailed_triangles, "Terrain shaping does not increase mesh density")
	print("PASS: five deterministic shaping controls, finite bounds, launch grading, spherical detail normals and compact mipmapped maps")
	quit()
