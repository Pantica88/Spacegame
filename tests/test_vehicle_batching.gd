extends SceneTree
const World = preload("res://scripts/world_view.gd")
const Fixture = preload("res://tests/large_craft_fixture.gd")
var source_surfaces := 0
var triangles := 0
var bounds := AABB()
var has_bounds := false

func _initialize() -> void:
	for asset in World.BATCHED_MODELS:
		var source_path := "res://assets/models/%s/%s.glb" % [asset,asset]
		var source: Node3D = load(source_path).instantiate()
		source_surfaces = 0
		triangles = 0
		has_bounds = false
		inspect_source(source, Transform3D.IDENTITY)
		var mesh: ArrayMesh = World.BATCHED_MODELS[asset]
		assert(mesh.get_meta("source_sha256") == FileAccess.get_sha256(source_path), "Baked asset matches its authored source")
		assert(mesh.get_aabb().position.is_equal_approx(bounds.position) and mesh.get_aabb().end.is_equal_approx(bounds.end), "Batching preserves model bounds")
		assert(mesh_triangles(mesh) == triangles, "Full-detail geometry is preserved")
		var surfaces: Array = mesh.get("_surfaces")
		if asset in ["atlas_1", "gyro_1"]:
			assert(surfaces.all(func(surface): return surface.get("lods", {}).is_empty()), "Thin rings retain their layered faces at every zoom")
		else:
			assert(surfaces.any(func(surface): return not surface.get("lods", {}).is_empty()), "Simplified LOD indices survive the resource bake")
		assert(mesh.get_surface_count() <= source_surfaces, "Batching never increases draw surfaces")
		var preview: ArrayMesh = mesh.get_meta("preview_mesh")
		assert(preview.get_surface_count() == 1 and mesh_triangles(preview) == triangles, "Ghosts share a single-surface silhouette")
		print("BATCH %s: %d -> %d surfaces, %d full-detail triangles" % [asset,source_surfaces,mesh.get_surface_count(),triangles])
		source.free()
	var world := World.new()
	world._design = Fixture.design()
	var first := world._vehicle_model("canister_1", World.CanisterTank)
	var second := world._vehicle_model("canister_1", World.CanisterTank)
	assert(first.get_child(0).mesh == second.get_child(0).mesh, "Repeated parts share their mesh")
	world._set_preview_material(second, StandardMaterial3D.new())
	assert(first.get_child(0).mesh.get_surface_count() == 6 and second.get_child(0).mesh.get_surface_count() == 1, "Preview conversion does not mutate installed geometry")
	first.free()
	second.free()
	world.free()
	print("PASS: shared vehicle geometry, faithful bounds/detail, batching and preview isolation")
	quit()

func inspect_source(node: Node3D, parent_pose: Transform3D) -> void:
	var pose := parent_pose * node.transform
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		source_surfaces += mesh.get_surface_count()
		triangles += mesh_triangles(mesh)
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = pose * vertex
				if not has_bounds:
					bounds = AABB(point, Vector3.ZERO)
					has_bounds = true
				else: bounds = bounds.expand(point)
	for child in node.get_children():
		if child is Node3D: inspect_source(child, pose)

func mesh_triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		count += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return count
