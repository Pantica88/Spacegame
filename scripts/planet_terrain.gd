extends RefCounted
## Seeded spherical terrain with full-detail contact and altitude-scaled rendering.
const Definition = preload("res://scripts/planet_definition.gd")
const Bake = preload("res://scripts/planet_bake.gd")
# Increment when mesh generation, colors, normals or LOD layout changes.
const BAKE_VERSION := 2
const BAKE_FIELDS := ["terrain_seed", "radius", "continent_frequency", "continent_edge_smoothness", "sea_threshold", "relief", "mountain_frequency", "ridge_roundness", "has_ocean", "launch_site", "lowland", "highland", "dryland", "snow"]
const SEGMENTS := 512
const RINGS := 256
const RENDER_LODS := [
	{"altitude": 0.0, "segments": 512, "rings": 256, "launch": true},
	{"altitude": 8000.0, "segments": 256, "rings": 128, "launch": true},
	{"altitude": 22000.0, "segments": 128, "rings": 64, "launch": false},
	{"altitude": 65000.0, "segments": 64, "rings": 32, "launch": false},
	{"altitude": 120000.0, "segments": 32, "rings": 16, "launch": false},
]
const LAUNCH_RING_DISTANCES := [25,50,75,100,150,200,300,400,500,650,800,1000,1200,1400,1550,1600,1700,1800,1850,1900,1950,2000,2100,2200,2400,2700,3000,3400,3800,4400,5000,6000]
var definition: Resource
var mesh: ArrayMesh
var collision: TriangleMesh
var _render_meshes := {}
var _preview_meshes := {}
var surface_texture: Texture2D
var _continents := FastNoiseLite.new()
var _mountains := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _climate := FastNoiseLite.new()

func _init(settings: Resource) -> void:
	definition = settings.duplicate()
	var baked: Resource = definition.baked_terrain
	if baked is Bake and baked.signature == bake_signature(definition) and baked.layers.size() == RENDER_LODS.size() and baked.preview != null and baked.surface_texture != null:
		var complete: bool = baked.preview.get_surface_count() == 1
		for layer in baked.layers:
			complete = complete and layer != null and layer.get_surface_count() == 1
		if complete:
			surface_texture = baked.surface_texture
			for index in range(baked.layers.size()):
				_render_meshes[index] = baked.layers[index]
			_preview_meshes[Vector2i(1024, 512)] = baked.preview
	for index in range(4):
		var noise: FastNoiseLite = [_continents,_mountains,_detail,_climate][index]
		noise.seed = int(definition.terrain_seed)+index*1009
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = [definition.continent_frequency,definition.mountain_frequency,24.0,5.0][index]
		noise.fractal_octaves = [3,2,2,2][index]
		noise.fractal_gain = 0.48
	var smoothness: float = clampf(float(definition.continent_edge_smoothness), 0.02, 1.0)
	var sharpness := inverse_lerp(1.0, 0.02, smoothness)
	_continents.fractal_octaves = 1 + int(round(sharpness * 3.0))
	_continents.fractal_gain = lerpf(0.03, 0.62, sharpness)
	_continents.fractal_lacunarity = lerpf(1.25, 2.35, sharpness)

func rotation_at(time: float) -> Basis:
	return Basis(Vector3.UP,TAU*fposmod(time,definition.rotation_seconds)/definition.rotation_seconds)

func surface_velocity(radial: Vector3) -> Vector3:
	return Vector3.UP.cross(radial)*(TAU/definition.rotation_seconds)

func elevation(direction: Vector3) -> float:
	var p := direction.normalized()
	var continent_noise := _continents.get_noise_3dv(p)
	var edge_smoothness: float = definition.continent_edge_smoothness
	var continent := continent_noise-float(definition.sea_threshold)
	var land := smoothstep(-edge_smoothness * 0.5, edge_smoothness * 2.4, continent)
	var mountain_noise := _mountains.get_noise_3dv(p)
	# Smooth absolute value rounds ridge crests instead of creating a cusp.
	var rounding: float = definition.ridge_roundness
	var rounded_distance := (sqrt(mountain_noise*mountain_noise+rounding*rounding)-rounding)/(sqrt(1.0+rounding*rounding)-rounding)
	var ridges := pow(1.0-rounded_distance,2.0)
	var mountain_belt := smoothstep(-0.12,0.35,_climate.get_noise_3dv(p))
	var height := (continent*0.65+ridges*land*mountain_belt*0.32+_detail.get_noise_3dv(p)*0.009)*float(definition.relief)
	if not definition.has_ocean: height = 250.0+absf(height)
	if definition.launch_site and p.y > 0.0:
		var point := Vector2(p.x,p.z)*float(definition.radius)
		var distance := point.length()
		# A permanent launch island with a level clearing, generated in body coordinates.
		var shore := 1900.0+sin(point.angle()*3.0)*400.0+cos(point.angle()*5.0)*170.0-distance
		var hills := (45.0*(sin(point.x*0.004)*cos(point.y*0.003)+1.0)+90.0*maxf(0.0,sin(point.x*0.002+1.2)*sin(point.y*0.002)))*smoothstep(130.0,680.0,distance)
		var island := clampf(shore/600.0,-1.0,1.0)*hills-maxf(0.0,-shore/600.0)*80.0
		height = lerpf(island,height,smoothstep(3000.0,6000.0,distance))
	return clampf(height,-float(definition.relief),float(definition.relief)*1.5)

func color_at(direction: Vector3, height: float) -> Color:
	var moisture := _climate.get_noise_3dv(direction)
	var fine_variation := _detail.get_noise_3dv(direction)
	var local_land := 0.0
	if definition.launch_site and direction.y > 0.0:
		var point := Vector2(direction.x,direction.z)*float(definition.radius)
		var coast := 1900.0+sin(point.angle()*3.0)*400.0+cos(point.angle()*5.0)*170.0
		local_land = 1.0-smoothstep(-30.0,50.0,point.length()-coast)
	var dry := (1.0-smoothstep(0.12,0.38,absf(absf(direction.y)-0.35)))*smoothstep(-0.20,0.32,-moisture+fine_variation*0.28)
	var color: Color = definition.lowland.lerp(definition.dryland,dry)
	color = color.lerp(color.lightened(0.10), smoothstep(0.15, 0.85, fine_variation))
	color = color.lerp(color.darkened(0.08), smoothstep(0.20, 0.90, -fine_variation))
	color = color.lerp(definition.highland,smoothstep(definition.relief*0.30,definition.relief*0.78,height))
	var snowline := float(definition.relief)*lerpf(0.8,0.10,pow(absf(direction.y),4.0))
	color = color.lerp(definition.snow,smoothstep(snowline,snowline+420.0,height))
	var water_weight := 0.0
	if definition.has_ocean:
		var coast_width := clampf(float(definition.relief) * float(definition.continent_edge_smoothness) * 0.18, 25.0, 120.0)
		color = definition.dryland.lerp(color,smoothstep(0.0,100.0,height))
		water_weight = (1.0-smoothstep(-coast_width,coast_width,height))*(1.0-local_land)
		# Keep land albedo separate; the shader resolves water coverage per
		# fragment so a coastal triangle does not blur blue into inland ground.
	var island_color: Color = definition.lowland.lerp(definition.highland,smoothstep(60.0,180.0,height))
	color = color.lerp(island_color,local_land)
	color = color.srgb_to_linear()
	color.a = water_weight
	return color

func render_lod_for_altitude(altitude: float, current_lod: int = -1) -> int:
	var target := 0
	for index in range(RENDER_LODS.size()):
		if altitude >= float(RENDER_LODS[index].altitude):
			target = index
	if current_lod >= 0 and current_lod < RENDER_LODS.size() and current_lod != target:
		var boundary := float(RENDER_LODS[maxi(current_lod, target)].altitude)
		var hysteresis := maxf(300.0, boundary * 0.08)
		if target > current_lod and altitude < boundary + hysteresis:
			return current_lod
		if target < current_lod and altitude > boundary - hysteresis:
			return current_lod
	return target

func render_mesh_for_lod(lod: int) -> ArrayMesh:
	lod = clampi(lod, 0, RENDER_LODS.size() - 1)
	if not _render_meshes.has(lod):
		var settings: Dictionary = RENDER_LODS[lod]
		_render_meshes[lod] = _build_mesh(int(settings.segments), int(settings.rings), bool(settings.launch))
	return _render_meshes[lod]

func build() -> ArrayMesh:
	if mesh != null: return mesh
	mesh = render_mesh_for_lod(0)
	collision = mesh.generate_triangle_mesh()
	return mesh

static func bake_signature(settings: Resource) -> String:
	var values: Array = [BAKE_VERSION, Engine.get_version_info().string, RENDER_LODS, LAUNCH_RING_DISTANCES]
	for field in BAKE_FIELDS:
		values.append(settings.get(field))
	return var_to_bytes(values).hex_encode().sha256_text()

func bake() -> Resource:
	var result := Bake.new()
	result.signature = bake_signature(definition)
	for lod in range(RENDER_LODS.size()):
		result.layers.append(render_mesh_for_lod(lod))
	result.preview = preview_mesh()
	result.surface_texture = surface_texture if surface_texture != null else _bake_surface_texture()
	return result

func _bake_surface_texture() -> Texture2D:
	# Sample land color and water coverage independently of the geometry LOD.
	# Linear half-floats preserve the same color space as mesh vertex colors.
	var width := 2048
	var height := 1024
	var pixels := Image.create(width, height, false, Image.FORMAT_RGBAH)
	for y in range(height):
		var latitude := PI*(float(y)+0.5)/height
		for x in range(width):
			var longitude := TAU*(float(x)+0.5)/width
			var direction := Vector3(sin(longitude)*sin(latitude),cos(latitude),cos(longitude)*sin(latitude))
			pixels.set_pixel(x,y,color_at(direction,elevation(direction)))
	pixels.generate_mipmaps()
	return ImageTexture.create_from_image(pixels)

func configure_surface_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter("ocean_color", definition.ocean)
	material.set_shader_parameter("has_baked_surface", surface_texture != null)
	material.set_shader_parameter("baked_surface", surface_texture)

func preview_mesh(segment_count: int = 1024, ring_count: int = 512) -> ArrayMesh:
	var resolution := Vector2i(segment_count, ring_count)
	if not _preview_meshes.has(resolution):
		_preview_meshes[resolution] = _build_mesh(segment_count, ring_count, true)
	return _preview_meshes[resolution]

func _build_mesh(segment_count: int, ring_count: int, include_launch_rings: bool) -> ArrayMesh:
	var angles: Array[float] = []
	if definition.launch_site and include_launch_rings:
		for distance in LAUNCH_RING_DISTANCES:
			angles.append(asin(float(distance)/definition.radius))
	var start: float = angles.back() if not angles.is_empty() else 0.0
	for index in range(1,ring_count):
		angles.append(lerpf(start,PI,float(index)/ring_count))
	var vertices := PackedVector3Array([Vector3.UP*float(definition.radius)])
	var colors := PackedColorArray([color_at(Vector3.UP,elevation(Vector3.UP))])
	vertices[0] *= 1.0+maxf(0.0,elevation(Vector3.UP))/float(definition.radius)
	for angle in angles:
		for segment in range(segment_count):
			var longitude := TAU*float(segment)/segment_count
			var direction := Vector3(sin(longitude)*sin(angle),cos(angle),cos(longitude)*sin(angle))
			var height := elevation(direction)
			vertices.append(direction*(float(definition.radius)+maxf(0.0,height)))
			colors.append(color_at(direction,height))
	var south := vertices.size()
	vertices.append(Vector3.DOWN*(float(definition.radius)+maxf(0.0,elevation(Vector3.DOWN))))
	colors.append(color_at(Vector3.DOWN,elevation(Vector3.DOWN)))
	var indices := PackedInt32Array()
	for segment in range(segment_count):
		indices.append_array(PackedInt32Array([0,1+(segment+1)%segment_count,1+segment]))
	for ring in range(angles.size()-1):
		var first := 1+ring*segment_count
		var following := first+segment_count
		for segment in range(segment_count):
			var next := (segment+1)%segment_count
			indices.append_array(PackedInt32Array([first+segment,first+next,following+segment,first+next,following+next,following+segment]))
	var last := 1+(angles.size()-1)*segment_count
	for segment in range(segment_count):
		indices.append_array(PackedInt32Array([last+segment,last+(segment+1)%segment_count,south]))
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for offset in range(0,indices.size(),3):
		var a := indices[offset]
		var b := indices[offset+1]
		var c := indices[offset+2]
		var normal := (vertices[c]-vertices[a]).cross(vertices[b]-vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for index in range(normals.size()): normals[index] = normals[index].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

func contact(radial: Vector3, time: float = 0.0) -> Dictionary:
	build()
	var rotation := rotation_at(time)
	var direction := (rotation.transposed()*radial).normalized()
	if direction.length_squared() < 0.5: direction = Vector3.UP
	var hit := collision.intersect_ray(direction*(float(definition.radius)+float(definition.relief)*2.0+100.0),-direction)
	if hit.is_empty(): return {"radius":float(definition.radius),"normal":rotation*direction}
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	if normal.dot(direction) < 0.0: normal = -normal
	return {"radius":point.length(),"normal":rotation*normal,"position":rotation*point}

func clearance(radial: Vector3, time: float = 0.0) -> float:
	return radial.length()-float(contact(radial,time).radius)

func segment_hit(start: Vector3, finish: Vector3, start_time: float, end_time: float) -> Dictionary:
	build()
	if minf(start.length(),finish.length()) > float(definition.radius)+float(definition.relief)*2.0:
		# A chord can still cross the globe even when both endpoints are above it.
		var segment := finish-start
		var closest := start+segment*clampf(-start.dot(segment)/maxf(segment.length_squared(),0.000001),0.0,1.0)
		if closest.length() > float(definition.radius)+float(definition.relief)*2.0: return {}
	var rotation := rotation_at(end_time)
	# Transform both endpoints at their respective times: include ground rotation.
	var local_start := rotation_at(start_time).transposed()*start
	var local_end := rotation.transposed()*finish
	var hit := collision.intersect_segment(local_start,local_end)
	if hit.is_empty(): return {}
	var local_point: Vector3 = hit.position
	var fraction := clampf(local_start.distance_to(local_point)/maxf(local_start.distance_to(local_end),0.000001),0.0,1.0)
	var normal: Vector3 = hit.normal
	if normal.dot(local_point) < 0.0: normal = -normal
	return {"position":rotation*local_point,"normal":rotation*normal,"fraction":fraction}
