extends SceneTree

const Terrain = preload("res://scripts/planet_terrain.gd")
const Definition = preload("res://scripts/planet_definition.gd")
const Complex = preload("res://assets/models/launch_site/launch_complex.tscn")

func _init() -> void:
	var site := Complex.instantiate()
	var count := 0
	for prop in site.get_children():
		for visual in prop.find_children("*", "MeshInstance3D", true, false):
			count += 1
			var bounds: AABB = visual.mesh.get_aabb()
			for corner in range(8):
				var point: Vector3 = prop.transform * visual.transform * bounds.get_endpoint(corner)
				assert(Vector2(point.x, point.z).length() < 150.0, "Facility exceeds graded footprint")
	assert(count >= 20, "Missing facility assets")
	site.free()
	for seed_value in [73129, 591677, 591678]:
		var settings := Definition.new()
		settings.terrain_seed = seed_value
		settings.launch_rings = false
		var terrain := Terrain.new(settings)
		var mesh := terrain.build()
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for point in vertices:
			if point.y > 0 and Vector2(point.x, point.z).length() <= 149.0:
				assert(point.y == settings.radius, "Terrain triangles must not protrude through the deck")
		for distance in [0.0, 25.0, 60.0, 100.0, 125.0, 149.0]:
			for azimuth in range(0, 360, 30):
				var angle := deg_to_rad(float(azimuth))
				var direction := Vector3(sin(angle)*distance, settings.radius, cos(angle)*distance).normalized()
				var surface := direction * (settings.radius + terrain.elevation(direction))
				assert(absf(surface.y - settings.radius) <= .065, "Graded terrain must share the deck datum")
	print("PASS: launch complex assets fit graded footprint; terrain remains level across seeds and detail settings.")
	quit()
