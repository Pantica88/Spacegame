extends SceneTree
const Ocean = preload("res://scripts/ocean_patch.gd")
func _initialize() -> void:
	var mesh := Ocean._build_rings()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var failures := 0
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		# Godot's clockwise fronts face opposite the mathematical cross product.
		# Every water triangle must face the same side as its upward normal.
		if (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).dot(normals[a]) >= 0.0:
			failures += 1
	if failures > 0:
		push_error("Ocean has %d reversed or degenerate triangles" % failures)
		quit(1)
		return
	print("PASS: %d ocean triangles face upward with clockwise winding" % (indices.size() / 3))
	quit(0)
