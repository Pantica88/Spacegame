extends SceneTree

func model_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (model.transform * mesh_node.transform) * mesh_node.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func _initialize() -> void:
	var world = load("res://scripts/world_view.gd").new()
	var assembly := Node3D.new()
	var flames: Array[Node3D] = []
	world._place_engine(assembly, Vector3(0,0.8,0), 0.57, flames, "sparrow")
	world._place_engine(assembly, Vector3(0,0.8,0), 0.78, flames, "kestrel")
	var sparrow := assembly.get_node("SparrowEngine1") as Node3D
	var kestrel := assembly.get_node("KestrelEngine1") as Node3D
	var meshes := sparrow.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() == 7)
	var small := model_bounds(sparrow)
	var large := model_bounds(kestrel)
	assert(is_equal_approx(small.end.y, 2.0), "Sparrow seats at the tank attachment plane")
	assert(is_equal_approx(small.end.y, kestrel.position.y + 2.69 * kestrel.scale.y), "Both engines share the attachment plane beneath Kestrel's latch hardware")
	assert(small.size.y < large.size.y * 0.76, "Sparrow is at least 24% shorter")
	# Compare the metal mounting rings, excluding Kestrel's protruding latch hardware.
	var small_collar: AABB = meshes[0].get_aabb()
	var large_collar: AABB = kestrel.find_children("*", "MeshInstance3D", true, false)[0].get_aabb()
	assert(is_equal_approx(small_collar.size.x * sparrow.scale.x, large_collar.size.x * kestrel.scale.x), "Mounting diameters match")
	assert(is_equal_approx(small_collar.size.z * sparrow.scale.z, large_collar.size.z * kestrel.scale.z))
	var bell: AABB = meshes[1].get_aabb()
	var large_bell: AABB = kestrel.find_children("*", "MeshInstance3D", true, false)[1].get_aabb()
	assert(bell.size.x * sparrow.scale.x < large_bell.size.x * kestrel.scale.x * 0.70, "Sparrow nozzle is narrower")
	assert(flames.size() == 2 and flames[0].position.is_equal_approx(sparrow.position))
	var opening := 0.454 * sparrow.scale.x
	var plume := flames[0].get_child(0) as MeshInstance3D
	var vertices: PackedVector3Array = plume.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var base_radius := 0.0
	for vertex in vertices:
		var v := plume.transform * vertex
		var r := Vector2(v.x,v.z).length()
		assert(r <= opening + 0.00001 and v.y <= 0.00001, "Exhaust stays below and within the nozzle")
		if is_zero_approx(v.y): base_radius = maxf(base_radius,r)
	assert(is_equal_approx(base_radius,opening))
	world._animate_flames(flames,0.5)
	assert(flames[0].visible)
	world._animate_flames(flames,0.0)
	assert(not flames[0].visible)
	for mounted in [false,true]:
		var preview: Node3D = world._make_drag_model("sparrow", mounted)
		var visual := preview.get_node("SparrowEngine1") as Node3D
		assert(visual.scale.is_equal_approx(sparrow.scale))
		assert((visual.position + Vector3(0,0.8,0)).is_equal_approx(sparrow.position))
		assert(preview.get_child_count() == 1, "Preview includes the complete engine and no exhaust")
		preview.free()
	assembly.free()
	world.free()
	print("PASS: smaller Sparrow, matching Kestrel mount, aligned exhaust, mounted and free previews")
	quit()
