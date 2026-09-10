extends SceneTree
## Topology and height checks for the continuous launch-to-orbit surface.

const PlanetSurface = preload("res://scripts/planet_surface.gd")
var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	var mesh := PlanetSurface.build_mesh()
	_check(mesh.get_surface_count() == 1, "Planet is one surface without overlapping ocean and terrain layers")
	var lods := []
	for altitude in [0.0, 10000.0, 26000.0, 80000.0, 140000.0]:
		var lod := PlanetSurface.render_lod_for_altitude(altitude)
		lods.append(lod)
		_check(PlanetSurface.home().render_mesh_for_lod(lod).get_surface_count() == 1, "Terrain LOD %d is renderable" % lod)
	_check(lods == [0, 1, 2, 3, 4], "Altitude selects five terrain detail layers")
	var full_triangles := _triangle_count(PlanetSurface.home().render_mesh_for_lod(0))
	var lowest_triangles := _triangle_count(PlanetSurface.home().render_mesh_for_lod(4))
	_check(lowest_triangles * 100 < full_triangles, "Highest-altitude terrain uses far fewer triangles")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(vertices.size() == normals.size(), "Every vertex has a normal")
	_check(indices.size() % 3 == 0, "Index buffer contains complete triangles")
	_check(indices.size() / 3 < 300000, "Surface remains below the triangle budget")
	_check(absf(vertices[0].y - PlanetSurface.RADIUS) < 0.01, "Launch clearing meets its physical surface")

	var edges := {}
	var faces := {}
	var unique_vertices := {}
	var valid_vertices := true
	var valid_normals := true
	var valid_heights := true
	var hills := 0
	var south_hills := 0
	var sea_samples := 0
	for index in range(vertices.size()):
		var vertex := vertices[index]
		var direction := vertex.normalized()
		valid_vertices = valid_vertices and vertex.is_finite()
		valid_normals = valid_normals and normals[index].is_finite() and absf(normals[index].length() - 1.0) < 0.001 and normals[index].dot(direction) > 0.0
		var expected_height: float = maxf(0.0,PlanetSurface.home().elevation(direction))
		var actual_height := vertex.length() - PlanetSurface.RADIUS
		valid_heights = valid_heights and absf(actual_height-expected_height) < 0.15 # Float32 direction round-trip through 60 km coordinates.
		if actual_height > 100.0:
			hills += 1
			if direction.y < 0.0: south_hills += 1
		if actual_height < 0.01: sea_samples += 1
		unique_vertices[vertex] = true
	_check(valid_vertices, "All surface vertices are finite")
	_check(unique_vertices.size() == vertices.size(), "Poles and seam vertices are shared instead of duplicated")
	_check(valid_normals, "All normals are finite, normalized and outward")
	_check(valid_heights, "Every rendered vertex uses the seeded elevation field")
	_check(hills > 100 and south_hills > 100, "Physical highlands exist in both hemispheres")
	_check(sea_samples > 1000, "Planet retains ocean basins")
	var valid_indices := true
	var nondegenerate := true
	var clockwise := true
	for offset in range(0, indices.size(), 3):
		var a := indices[offset]
		var b := indices[offset + 1]
		var c := indices[offset + 2]
		if mini(a, mini(b, c)) < 0 or maxi(a, maxi(b, c)) >= vertices.size():
			valid_indices = false
			continue
		var face_normal := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		nondegenerate = nondegenerate and face_normal.length_squared() > 0.000001
		clockwise = clockwise and face_normal.dot(vertices[a] + vertices[b] + vertices[c]) < 0.0
		var face := [a, b, c]
		face.sort()
		faces[Vector3i(face[0], face[1], face[2])] = true
		for edge: Vector2i in [Vector2i(a, b), Vector2i(b, c), Vector2i(c, a)]:
			var key := Vector2i(mini(edge.x, edge.y), maxi(edge.x, edge.y))
			var count: Vector2i = edges.get(key, Vector2i.ZERO)
			count.x += 1
			count.y += 1 if edge.x < edge.y else -1
			edges[key] = count
	_check(valid_indices, "Every triangle references existing vertices")
	_check(nondegenerate, "There are no degenerate pole, seam or ring triangles")
	_check(clockwise, "All faces use Godot's outward clockwise winding")
	_check(faces.size() == indices.size() / 3, "No triangle is duplicated")
	var closed := true
	for count: Vector2i in edges.values():
		closed = closed and count == Vector2i(2, 0)
	_check(closed, "Every edge belongs to two oppositely oriented faces: no holes or overlapping cells")
	_check(vertices.size() - edges.size() + faces.size() == 2, "Closed surface has spherical Euler topology")
	if _failures.is_empty():
		print("PASS: %d planet surface checks (%d triangles)." % [_checks, indices.size() / 3])
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _triangle_count(mesh: ArrayMesh) -> int:
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return indices.size() / 3
