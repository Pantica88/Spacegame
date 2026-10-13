extends MeshInstance3D
## Fixed ribbon identities; the shader follows the hull and current airflow each frame.
## Only changes to the visible parts rebuild the hull profile and seed geometry.
const HEIGHT_SLICES := 48
const ANGLE_SLICES := 24
const PATH_STEPS := 36
var _radii := PackedFloat32Array()
var _bottom := 0.0
var _top := 1.0
var _hull_key: Array[int] = []
var flow_direction := Vector3.ZERO
var _profile_ready := false
var _material: ShaderMaterial
var _profile_texture: ImageTexture
var flow_phase := 0.0
var path_count := 0
var profile_build_count := 0
const OUTLINE_BANDS := 32
const OUTLINE_DIRECTIONS := 64
var _outlines := {}

func _init() -> void:
	name = "AtmosphericWake"
	set_meta("heat_trail", true)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = preload("res://assets/shaders/aerothermal_trail.gdshader")
	# Clouds composite first; opaque geometry continues to occlude the wake.
	_material.render_priority = 2
	material_override = _material

func update_flow(hull: Array[MeshInstance3D], rocket: Node3D, direction: Vector3, speed: float, strength: float, delta: float) -> void:
	visible = strength > 0.005 and direction.length_squared() > 0.5
	if not visible: return
	flow_direction = direction
	prepare_hull(hull, rocket)
	if not _profile_ready:
		hide()
		return
	var local_flow := -(rocket.global_basis.inverse() * direction).normalized()
	flow_phase = fmod(flow_phase + maxf(delta, 0.0) * (5.0 + speed * 0.055), 4096.0)
	_material.set_shader_parameter("local_flow", local_flow)
	_material.set_shader_parameter("flow_phase", flow_phase)
	_material.set_shader_parameter("strength", strength)
	_material.set_shader_parameter("airspeed", speed)

## Gives the heat halo (aerothermal_halo.gdshader) the same hull envelope, so
## its shells extrude smoothly instead of along split hard-edge normals.
func share_hull(material: ShaderMaterial, rocket: Node3D) -> void:
	var available := _profile_ready and _profile_texture != null
	material.set_shader_parameter("hull_profile_ready", available)
	if not available: return
	material.set_shader_parameter("hull_profile", _profile_texture)
	material.set_shader_parameter("hull_bottom", _bottom)
	material.set_shader_parameter("hull_top", _top)
	material.set_shader_parameter("hull_to_local", Projection(rocket.global_transform.affine_inverse()))

func prepare_hull(hull: Array[MeshInstance3D], rocket: Node3D) -> void:
	var key: Array[int] = []
	for part in hull:
		if is_instance_valid(part) and part.is_visible_in_tree(): key.append(part.get_instance_id())
	if key != _hull_key:
		_hull_key = key
		_sample_hull(hull, rocket)
		if _profile_ready: _build_seed_mesh()

## The outermost vertices of a mesh: per height band and direction around its
## own axis, the one farthest out. Staging resamples the hull; reading every
## part's vertex arrays back again stalled separation for a second, and stacks
## repeat the same tank mesh many times.
func _outline(mesh: Mesh) -> PackedVector3Array:
	if _outlines.has(mesh): return _outlines[mesh]
	var aabb := mesh.get_aabb()
	var bands := maxi(1, mini(OUTLINE_BANDS, int(ceil(aabb.size.y / 0.25))))
	var outline := {}
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty(): continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		# Detailed authored meshes need only a bounded sample for the envelope.
		var stride := maxi(1, vertices.size() / 1600)
		for index in range(0, vertices.size(), stride):
			var vertex := vertices[index]
			var band := clampi(int((vertex.y - aabb.position.y) / maxf(aabb.size.y, 0.0001) * bands), 0, bands - 1)
			var key := band * OUTLINE_DIRECTIONS + posmod(int(round(atan2(vertex.z, vertex.x) / TAU * OUTLINE_DIRECTIONS)), OUTLINE_DIRECTIONS)
			if not outline.has(key) or Vector2(vertex.x, vertex.z).length_squared() > Vector2(outline[key].x, outline[key].z).length_squared():
				outline[key] = vertex
	# Keep the extreme heights so the envelope's ends are unchanged.
	var points := PackedVector3Array(outline.values())
	points.append(aabb.position + Vector3(aabb.size.x * 0.5, 0.0, aabb.size.z * 0.5))
	points.append(aabb.end - Vector3(aabb.size.x * 0.5, 0.0, aabb.size.z * 0.5))
	_outlines[mesh] = points
	return points

func _sample_hull(hull: Array[MeshInstance3D], rocket: Node3D) -> void:
	var points := PackedVector3Array()
	_bottom = INF
	_top = -INF
	for part in hull:
		if not is_instance_valid(part) or not part.is_visible_in_tree() or part.mesh == null: continue
		var frame := rocket.global_transform.affine_inverse() * part.global_transform
		for point in _outline(part.mesh):
			point = frame * point
			points.append(point)
			_bottom = minf(_bottom, point.y)
			_top = maxf(_top, point.y)
	_profile_ready = points.size() > 0 and _top - _bottom > 0.01
	if not _profile_ready: return
	_radii.resize(HEIGHT_SLICES * ANGLE_SLICES)
	_radii.fill(0.0)
	for point in points:
		var y := clampi(int((point.y - _bottom) / (_top - _bottom) * (HEIGHT_SLICES - 1)), 0, HEIGHT_SLICES - 1)
		var angle := posmod(int(round(atan2(point.z, point.x) / TAU * ANGLE_SLICES)), ANGLE_SLICES)
		var radius := Vector2(point.x, point.z).length()
		var index := y * ANGLE_SLICES + angle
		_radii[index] = maxf(_radii[index], radius)
		index = mini(y + 1, HEIGHT_SLICES - 1) * ANGLE_SLICES + angle
		_radii[index] = maxf(_radii[index], radius)
	# Fill sparse tessellation gaps from the nearest occupied profile slice.
	var sampled := _radii.duplicate()
	for y in range(HEIGHT_SLICES):
		for angle in range(ANGLE_SLICES):
			var index := y * ANGLE_SLICES + angle
			if sampled[index] > 0.01: continue
			for distance in range(1, HEIGHT_SLICES):
				var found := false
				for row in [maxi(0, y - distance), mini(HEIGHT_SLICES - 1, y + distance)]:
					for offset in range(-mini(distance, 3), mini(distance, 3) + 1):
						var radius := sampled[row * ANGLE_SLICES + posmod(angle + offset, ANGLE_SLICES)]
						if radius > 0.01:
							_radii[index] = maxf(_radii[index], radius)
							found = true
				if found: break
	# Plasma bridges small grooves without losing the capsule/tank/fin outline.
	for pass_index in range(2):
		var previous := _radii.duplicate()
		for y in range(HEIGHT_SLICES):
			for angle in range(ANGLE_SLICES):
				var index := y * ANGLE_SLICES + angle
				var neighbors := previous[maxi(0, y-1)*ANGLE_SLICES+angle] + previous[mini(HEIGHT_SLICES-1, y+1)*ANGLE_SLICES+angle]
				neighbors += previous[y*ANGLE_SLICES+posmod(angle-1,ANGLE_SLICES)] + previous[y*ANGLE_SLICES+posmod(angle+1,ANGLE_SLICES)]
				_radii[index] = maxf(previous[index], neighbors * 0.25) + 0.015

func _radius(y: float, angle: float) -> float:
	var row := clampf((y - _bottom) / (_top - _bottom) * (HEIGHT_SLICES - 1), 0.0, HEIGHT_SLICES - 1.0)
	var column := fposmod(angle / TAU * ANGLE_SLICES, ANGLE_SLICES)
	var a := int(row)
	var b := mini(a + 1, HEIGHT_SLICES - 1)
	var c := int(column)
	var d := (c + 1) % ANGLE_SLICES
	return lerpf(lerpf(_radii[a*ANGLE_SLICES+c], _radii[a*ANGLE_SLICES+d], column-c), lerpf(_radii[b*ANGLE_SLICES+c], _radii[b*ANGLE_SLICES+d], column-c), row-a)

func _distance(point: Vector3) -> float:
	return maxf(Vector2(point.x, point.z).length() - _radius(point.y, atan2(point.z, point.x)), maxf(_bottom-point.y, point.y-_top))

func _build_seed_mesh() -> void:
	profile_build_count += 1
	var image := Image.create_from_data(ANGLE_SLICES, HEIGHT_SLICES, false, Image.FORMAT_RF, _radii.to_byte_array())
	_profile_texture = ImageTexture.create_from_image(image)
	_material.set_shader_parameter("hull_profile", _profile_texture)
	_material.set_shader_parameter("hull_bottom", _bottom)
	_material.set_shader_parameter("hull_top", _top)
	# Emit indexed strips directly; SurfaceTool.index hashes every triangle corner.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	path_count = 0
	for ring in range(10):
		var y := lerpf(_bottom + 0.04, _top - 0.04, float(ring) / 9.0)
		for spoke in range(12):
			var angle := (float(spoke) + float(ring % 2) * 0.5) * TAU / 12.0
			var radial := Vector3(cos(angle), 0, sin(angle))
			var seed := radial * (_radius(y, angle) + 0.10) + Vector3(0,y,0)
			var base := vertices.size()
			for k in range(PATH_STEPS + 1):
				for side in [-1.0, 1.0]:
					vertices.append(seed)
					normals.append(radial)
					uvs.append(Vector2(side, float(k)))
					uv2s.append(Vector2(float(k) / PATH_STEPS, float(ring * 12 + spoke) * 0.618034))
			for k in range(PATH_STEPS):
				var start := base + k * 2
				indices.append_array(PackedInt32Array([start, start+1, start+2, start+1, start+3, start+2]))
			path_count += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var seeds := ArrayMesh.new()
	seeds.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = seeds
	# The shader extends these seeds into a wake in any direction.
	custom_aabb = mesh.get_aabb().grow(30.0)
