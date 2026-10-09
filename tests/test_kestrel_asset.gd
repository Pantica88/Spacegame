extends SceneTree

func _initialize() -> void:
	var world = load("res://scripts/world_view.gd").new()
	var assembly := Node3D.new()
	var flames: Array[Node3D] = []
	world._place_engine(assembly, Vector3(0,0.8,0), 0.78, flames, "kestrel")
	var model := assembly.get_node("KestrelEngine1") as Node3D
	assert(model.find_children("*", "MeshInstance3D", true, false).size() == 8)
	assert(is_equal_approx(model.position.y, 0.20))
	assert(is_equal_approx(model.position.y + 2.69 * model.scale.y, 2.0))
	assert(flames.size() == 1)
	assert(flames[0].position.is_equal_approx(model.position))
	var opening := 0.670 * model.scale.x
	var plume := flames[0].get_child(0) as MeshInstance3D
	var vertices: PackedVector3Array = plume.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert(vertices.size() < 1200, "Exhaust uses a compact indexed mesh")
	assert(plume.mesh == world._shared_exhaust_mesh(), "Engine nozzles share exhaust geometry")
	var base_radius := 0.0
	for vertex in vertices:
		var v := plume.transform * vertex
		var r := Vector2(v.x,v.z).length()
		assert(r <= opening + 0.00001, "Exhaust stays inside nozzle aperture")
		assert(v.y <= 0.00001, "Exhaust flows down from exit")
		if is_zero_approx(v.y): base_radius = maxf(base_radius,r)
	assert(is_equal_approx(base_radius,opening))
	var glow := flames[0].get_child(1) as MeshInstance3D
	assert((glow.mesh as QuadMesh).size.is_equal_approx(Vector2.ONE * opening * 2.0))
	world._animate_flames(flames,0.35)
	assert(flames[0].visible and is_equal_approx(flames[0].scale.x,1.0))
	assert(is_equal_approx(flames[0].scale.z,1.0))
	world._animate_flames(flames,0.0)
	assert(not flames[0].visible)

	for mounted in [false, true]:
		var preview: Node3D = world._make_drag_model("kestrel", mounted)
		var visual := preview.get_node("KestrelEngine1") as Node3D
		assert(visual.scale.is_equal_approx(model.scale))
		assert((visual.position + Vector3(0,0.8,0)).is_equal_approx(model.position))
		assert(preview.get_child_count() == 1, "Authored engine includes its own mounting collar")
		preview.free()
	assembly.free()
	world.free()
	print("PASS: Kestrel GLB, attachment fit, exhaust origin, mounted and free previews")
	quit()
