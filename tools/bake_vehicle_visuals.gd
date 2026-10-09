extends SceneTree
## Run with the editor binary: tools/run.sh --headless --script tools/bake_vehicle_visuals.gd
## Keep authored component scenes for the asset viewer; bake shared flight meshes.
const ASSETS := ["canister_1", "engine_1", "sparrow_1", "separator_1", "atlas_1", "booster_1", "explorer_1", "gyro_1"]
const OUTPUT := "res://assets/models/flight"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var requested := OS.get_cmdline_user_args()
	for asset in ASSETS:
		if requested.is_empty() or asset in requested: bake(asset)
	quit()

func bake(asset: String) -> void:
	var source := "res://assets/models/%s/%s.glb" % [asset, asset]
	var model := (load(source) as PackedScene).instantiate() as Node3D
	var batches: Dictionary = {}
	var silhouette := SurfaceTool.new()
	silhouette.begin(Mesh.PRIMITIVE_TRIANGLES)
	_collect(model, Transform3D.IDENTITY, batches, silhouette)
	var merged := ArrayMesh.new()
	for surface: SurfaceTool in batches.values():
		surface.index()
		surface.commit(merged)
	silhouette.index()
	# Thin layered rings must retain their faces: automatic simplification can
	# pull the white panels through the dark housing at workshop zoom levels.
	var simplify := asset not in ["gyro_1", "atlas_1"]
	var result := _with_lods(merged, simplify)
	result.set_meta("preview_mesh", _with_lods(silhouette.commit(), simplify))
	result.set_meta("source_sha256", FileAccess.get_sha256(source))
	result.set_meta("model_name", model.name)
	var error := ResourceSaver.save(result, OUTPUT.path_join(asset + ".res"), ResourceSaver.FLAG_COMPRESS)
	assert(error == OK, "Flight mesh saves successfully")
	print("Baked %s: %d material surfaces, one preview surface" % [asset, result.get_surface_count()])
	model.free()

func _collect(node: Node3D, parent_transform: Transform3D, batches: Dictionary, silhouette: SurfaceTool) -> void:
	var pose := parent_transform * node.transform
	if node is MeshInstance3D:
		assert(node.skin == null and node.get_blend_shape_count() == 0, "Only rigid vehicle assets can be baked")
		for index in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(index)
			if not batches.has(material):
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				surface.set_material(material)
				batches[material] = surface
			batches[material].append_from(node.mesh, index, pose)
			silhouette.append_from(node.mesh, index, pose)
	for child in node.get_children():
		if child is Node3D: _collect(child, pose, batches, silhouette)

func _with_lods(mesh: ArrayMesh, simplify: bool = true) -> ArrayMesh:
	if not simplify: return mesh
	var imported := ImporterMesh.new()
	for surface in range(mesh.get_surface_count()):
		imported.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface), [], {}, mesh.surface_get_material(surface))
	# Simplification happens here, never on a drag or flight frame. Preserve the
	# full-resolution surface and let screen-space error select cheaper indices.
	imported.generate_lods(25.0, 60.0, [])
	return imported.get_mesh()
