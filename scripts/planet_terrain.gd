extends RefCounted
## Seeded spherical terrain with full-detail contact and altitude-scaled rendering.
const Definition = preload("res://scripts/planet_definition.gd")
const Bake = preload("res://scripts/planet_bake.gd")
const Physics = preload("res://scripts/physics_math.gd")
# Increment when mesh generation, colors, normals or LOD layout changes.
# Editor, map, moons and near-surface flight share the collision triangles.
const BAKE_VERSION := 9
# Move only the launch frame: +Z is on the equator of the unchanged +Y spin axis.
const LAUNCH_BASIS := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
const LAUNCH_DIRECTION := Vector3.BACK
const BAKE_FIELDS := ["terrain_seed", "radius", "continent_frequency", "continent_edge_smoothness", "sea_threshold", "relief", "mountain_frequency", "ridge_roundness", "coastline_irregularity", "mountain_height", "erosion", "terrain_detail", "detail_frequency", "has_ocean", "launch_site", "launch_central_hill", "launch_apron", "launch_coast", "launch_rings", "lowland", "highland", "dryland", "snow", "has_snow"]
const SHAPING_DEFAULTS := {"coastline_irregularity": 0.0, "mountain_height": 1.0, "erosion": 0.0, "terrain_detail": 0.0, "detail_frequency": 24.0}
const SEGMENTS := 512
const RINGS := 256
const RENDER_LODS := [
	{"altitude": 0.0, "segments": 512, "rings": 256, "launch": true},
	{"altitude": 8000.0, "segments": 256, "rings": 128, "launch": false},
	{"altitude": 22000.0, "segments": 128, "rings": 64, "launch": false},
	{"altitude": 65000.0, "segments": 64, "rings": 32, "launch": false},
	{"altitude": 120000.0, "segments": 64, "rings": 32, "launch": false},
]
const LAUNCH_RING_DISTANCES := [25,50,75,100,150,200,300,400,500,650,800,1000,1200,1400,1550,1600,1700,1800,1850,1900,1950,2000,2100,2200,2400,2700,3000,3400,3800,4400,5000,6000]
var definition: Resource
var mesh: ArrayMesh
var collision: TriangleMesh
var _contact_vertices := PackedVector3Array()
var _contact_indices := PackedInt32Array()
var _render_meshes := {}
var _preview_meshes := {}
var surface_texture: Texture2D
var topography_texture: Texture2D
var _continents := FastNoiseLite.new()
var _mountains := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _climate := FastNoiseLite.new()
var _coast_warp := FastNoiseLite.new()

func _init(settings: Resource) -> void:
	definition = settings.duplicate()
	var baked: Resource = definition.baked_terrain
	var legacy_signature := legacy_bake_signature(definition)
	var valid_signature: bool = baked is Bake and ((baked.signature == bake_signature(definition) and baked.topography_texture != null) or (not legacy_signature.is_empty() and baked.signature == legacy_signature))
	if valid_signature and baked.layers.size() == RENDER_LODS.size() and baked.preview != null and baked.surface_texture != null:
		var complete: bool = baked.preview == baked.layers[0] and baked.preview.get_surface_count() == 1
		for layer in baked.layers:
			complete = complete and layer != null and layer.get_surface_count() == 1
		if complete:
			surface_texture = baked.surface_texture
			topography_texture = baked.topography_texture
			for index in range(baked.layers.size()):
				_render_meshes[index] = baked.layers[index]
			_preview_meshes[Vector2i(SEGMENTS, RINGS)] = baked.preview
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
	_detail.frequency = definition.detail_frequency
	_coast_warp.seed = int(definition.terrain_seed) + 4093
	_coast_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_coast_warp.frequency = 4.0
	_coast_warp.fractal_octaves = 2

func spin_axis() -> Vector3:
	return Vector3.UP

func rotation_at(time: float) -> Basis:
	return Basis(spin_axis(),TAU*fposmod(time,definition.rotation_seconds)/definition.rotation_seconds)

func surface_velocity(radial: Vector3) -> Vector3:
	return spin_axis().cross(radial)*(TAU/definition.rotation_seconds)

func elevation(direction: Vector3, include_launch_site: bool = true) -> float:
	var p := direction.normalized()
	var continent_point := p
	if definition.coastline_irregularity > 0.0:
		var warp := Vector3(_coast_warp.get_noise_3dv(p), _coast_warp.get_noise_3dv(p + Vector3(7.1, 3.7, 1.9)), _coast_warp.get_noise_3dv(p + Vector3(2.8, 9.2, 5.4)))
		continent_point = (p + warp * float(definition.coastline_irregularity) * 0.22).normalized()
	var continent_noise := _continents.get_noise_3dv(continent_point)
	var edge_smoothness: float = definition.continent_edge_smoothness
	var continent := continent_noise-float(definition.sea_threshold)
	var land := smoothstep(-edge_smoothness * 0.5, edge_smoothness * 2.4, continent)
	var mountain_noise := _mountains.get_noise_3dv(p)
	# Smooth absolute value rounds ridge crests instead of creating a cusp.
	var rounding: float = definition.ridge_roundness
	var rounded_distance := (sqrt(mountain_noise*mountain_noise+rounding*rounding)-rounding)/(sqrt(1.0+rounding*rounding)-rounding)
	var ridges := pow(1.0-rounded_distance,2.0)
	var mountain_belt := smoothstep(-0.12,0.35,_climate.get_noise_3dv(p))
	var detail := _detail.get_noise_3dv(p)
	# Carve ridge shoulders and branching gullies without a runtime simulation.
	if definition.erosion > 0.0:
		ridges = lerpf(ridges, pow(ridges, 1.8) * (0.72 + 0.28 * smoothstep(-0.35, 0.35, detail)), float(definition.erosion))
	var fine_relief := 0.0
	if definition.terrain_detail > 0.0:
		var small_ridges := pow(1.0 - absf(detail), 3.0) - 0.45
		fine_relief = small_ridges * float(definition.terrain_detail) * 0.12 * land
	var height := (continent*0.65+ridges*land*mountain_belt*0.32*float(definition.mountain_height)+detail*0.009+fine_relief)*float(definition.relief)
	if not definition.has_ocean: height = 250.0+absf(height)
	var launch_local := LAUNCH_BASIS.transposed() * p
	var launch_weight := smoothstep(0.80, 1.0, maxf(launch_local.y, 0.0))
	if definition.launch_site and include_launch_site and launch_weight > 0.001:
		var point := Vector2(launch_local.x,launch_local.z)*float(definition.radius)
		var distance := point.length()
		# Grade a tangent plane beneath the entire complex (including its road).
		# Constant radial elevation curves away from a level foundation; compensate
		# for that curvature so rendering and contact share the launch datum.
		var island_weight := 1.0 - smoothstep(150.0, 3000.0, distance)
		var grade_height := float(definition.radius) / launch_local.y - float(definition.radius)
		height = lerpf(height, grade_height, island_weight)
	return clampf(height,-float(definition.relief),float(definition.relief)*1.5)

func color_at(direction: Vector3, height: float, include_launch_site: bool = true) -> Color:
	var moisture := _climate.get_noise_3dv(direction)
	var fine_variation := _detail.get_noise_3dv(direction)
	var local_land := 0.0
	var launch_local := LAUNCH_BASIS.transposed() * direction
	var launch_weight := smoothstep(0.80, 1.0, maxf(launch_local.y, 0.0))
	if definition.launch_site and include_launch_site and definition.launch_coast and launch_weight > 0.001:
		var point := Vector2(launch_local.x,launch_local.z)*float(definition.radius)
		var coast := 1900.0+sin(point.angle()*3.0)*400.0+cos(point.angle()*5.0)*170.0
		local_land = (1.0-smoothstep(-30.0,50.0,point.length()-coast)) * launch_weight
	# The launch facility's flat ground stays dry even with decorative coast off.
	if definition.launch_site and include_launch_site and launch_local.y > 0.0:
		var distance := Vector2(launch_local.x, launch_local.z).length() * float(definition.radius)
		local_land = maxf(local_land, 1.0 - smoothstep(150.0, 250.0, distance))
	var dry := (1.0-smoothstep(0.12,0.38,absf(absf(direction.y)-0.35)))*smoothstep(-0.20,0.32,-moisture+fine_variation*0.28)
	var color: Color = definition.lowland.lerp(definition.dryland,dry)
	color = color.lerp(color.lightened(0.10), smoothstep(0.15, 0.85, fine_variation))
	color = color.lerp(color.darkened(0.08), smoothstep(0.20, 0.90, -fine_variation))
	color = color.lerp(definition.highland,smoothstep(definition.relief*0.30,definition.relief*0.78,height))
	if definition.has_snow:
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
	var arrays := mesh.surface_get_arrays(0)
	_contact_vertices = arrays[Mesh.ARRAY_VERTEX]
	_contact_indices = arrays[Mesh.ARRAY_INDEX]
	return mesh

static func bake_signature(settings: Resource) -> String:
	var values: Array = [BAKE_VERSION, Engine.get_version_info().string, RENDER_LODS, LAUNCH_RING_DISTANCES]
	for field in BAKE_FIELDS:
		values.append(settings.get(field))
	return var_to_bytes(values).hex_encode().sha256_text()

static func legacy_bake_signature(settings: Resource) -> String:
	# Neutral shaping has exactly the old height/color field. Reuse v8 mesh
	# caches until the next save adds normal detail, avoiding a load-time rebuild.
	for key in SHAPING_DEFAULTS:
		if float(settings.get(key)) != float(SHAPING_DEFAULTS[key]): return ""
	var values: Array = [8, Engine.get_version_info().string, RENDER_LODS, LAUNCH_RING_DISTANCES]
	for field in BAKE_FIELDS:
		if field not in SHAPING_DEFAULTS: values.append(settings.get(field))
	return var_to_bytes(values).hex_encode().sha256_text()

func bake() -> Resource:
	var result := Bake.new()
	result.signature = bake_signature(definition)
	for lod in range(RENDER_LODS.size()):
		result.layers.append(render_mesh_for_lod(lod))
	result.preview = preview_mesh()
	if surface_texture == null or topography_texture == null:
		var images := surface_images()
		surface_texture = ImageTexture.create_from_image(images.surface)
		topography_texture = ImageTexture.create_from_image(images.topography)
	result.surface_texture = surface_texture
	result.topography_texture = topography_texture
	return result

func _bake_surface_texture() -> Texture2D:
	return ImageTexture.create_from_image(surface_images().surface)

func surface_images(width: int = 2048, height: int = 1024) -> Dictionary:
	# CPU-only image generation can run in the editor's worker. GPU resources
	# are created by the caller on the main thread. Heights are sampled once.
	# Sample land color and water coverage independently of the geometry LOD.
	# Linear half-floats preserve the same color space as mesh vertex colors.
	var pixels := Image.create(width, height, false, Image.FORMAT_RGBAH)
	var topography := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var heights := PackedFloat32Array()
	heights.resize(width * height)
	var longitude_sin := PackedFloat32Array()
	var longitude_cos := PackedFloat32Array()
	longitude_sin.resize(width)
	longitude_cos.resize(width)
	for x in range(width):
		var longitude := TAU * (float(x) + 0.5) / width
		longitude_sin[x] = sin(longitude)
		longitude_cos[x] = cos(longitude)
	var include_launch_site: bool = definition.launch_site
	for y in range(height):
		var latitude := PI*(float(y)+0.5)/height
		var latitude_sin := sin(latitude)
		var latitude_cos := cos(latitude)
		for x in range(width):
			var direction := Vector3(longitude_sin[x]*latitude_sin, latitude_cos, longitude_cos[x]*latitude_sin)
			var elevation_value := elevation(direction, include_launch_site)
			heights[y * width + x] = elevation_value
			pixels.set_pixel(x,y,color_at(direction,elevation_value, include_launch_site))
	for y in range(height):
		var latitude := PI * (float(y) + 0.5) / height
		var latitude_sin := sin(latitude)
		var latitude_cos := cos(latitude)
		var north := maxi(y - 1, 0)
		var south := mini(y + 1, height - 1)
		for x in range(width):
			var east := (x + 1) % width
			var west := (x + width - 1) % width
			var direction := Vector3(longitude_sin[x]*latitude_sin, latitude_cos, longitude_cos[x]*latitude_sin)
			var latitude_tangent := Vector3(longitude_sin[x]*latitude_cos, -latitude_sin, longitude_cos[x]*latitude_cos)
			var longitude_tangent := Vector3(longitude_cos[x], 0.0, -longitude_sin[x])
			var radius := float(definition.radius) + maxf(heights[y * width + x], 0.0)
			var latitude_slope := (maxf(heights[south * width + x], 0.0) - maxf(heights[north * width + x], 0.0)) / (radius * PI * float(south - north) / height)
			var longitude_slope := (maxf(heights[y * width + east], 0.0) - maxf(heights[y * width + west], 0.0)) / (radius * 2.0 * TAU / width * maxf(latitude_sin, 0.001))
			var normal := (direction - latitude_tangent * latitude_slope - longitude_tangent * longitude_slope).normalized()
			if heights[y * width + x] <= 0.0: normal = direction
			var normalized_height := clampf((heights[y * width + x] / maxf(float(definition.relief), 1.0) + 1.0) / 2.5, 0.0, 1.0)
			topography.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, normalized_height))
	pixels.generate_mipmaps()
	topography.generate_mipmaps()
	return {"surface": pixels, "topography": topography}

func configure_surface_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter("BODY_RADIUS", float(definition.radius) * 0.001)
	material.set_shader_parameter("AIR_RADIUS", (float(definition.radius) + float(definition.atmosphere_height)) * 0.001)
	material.set_shader_parameter("atmosphere_density_scale", float(definition.atmosphere_visual_density))
	material.set_shader_parameter("ocean_color", definition.ocean)
	material.set_shader_parameter("terrain_relief_m", maxf(float(definition.relief), 1.0))
	var distant_color: Color = definition.lowland.lerp(definition.highland, 0.35)
	if definition.has_ocean:
		distant_color = distant_color.lerp(definition.ocean, 0.45)
	material.set_shader_parameter("distant_body_color", distant_color)
	material.set_shader_parameter("has_baked_surface", surface_texture != null)
	material.set_shader_parameter("baked_surface", surface_texture)
	material.set_shader_parameter("has_baked_topography", topography_texture != null)
	material.set_shader_parameter("baked_topography", topography_texture)

func preview_mesh(segment_count: int = SEGMENTS, ring_count: int = RINGS) -> ArrayMesh:
	# Independent sampling changes triangle planes by metres, even with the
	# same noise seed. The editor and moon renderer must show the physical mesh.
	if segment_count == SEGMENTS and ring_count == RINGS:
		return render_mesh_for_lod(0)
	var resolution := Vector2i(segment_count, ring_count)
	if not _preview_meshes.has(resolution):
		_preview_meshes[resolution] = _build_mesh(segment_count, ring_count, true)
	return _preview_meshes[resolution]

func _build_mesh(segment_count: int, ring_count: int, include_launch_rings: bool) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays(segment_count, ring_count, include_launch_rings))
	return result

func mesh_arrays(segment_count: int, ring_count: int, include_launch_rings: bool = true) -> Array:
	# No RenderingServer calls: safe to generate in an isolated editor worker.
	# include_launch_rings parameter indicates whether to include the extra
	# launch-related ring geometry. The planet definition now controls which
	# parts are active independently.
	var include_launch_site: bool = definition.launch_site and include_launch_rings
	var angles: Array[float] = []
	if include_launch_site:
		for distance in LAUNCH_RING_DISTANCES:
			if float(distance) >= float(definition.radius): break
			# Preserve the flat facility footprint even with detail rings disabled.
			if distance <= 150 or definition.launch_rings:
				angles.append(asin(float(distance)/definition.radius))
	var start: float = angles.back() if not angles.is_empty() else 0.0
	for index in range(1,ring_count):
		angles.append(lerpf(start,PI,float(index)/ring_count))
	var sampling_basis := LAUNCH_BASIS if definition.launch_site else Basis.IDENTITY
	var top := sampling_basis * Vector3.UP
	var bottom := -top
	var vertices := PackedVector3Array([top*float(definition.radius)])
	var colors := PackedColorArray([color_at(top,elevation(top, include_launch_site), include_launch_site)])
	vertices[0] *= 1.0+maxf(0.0,elevation(top, include_launch_site))/float(definition.radius)
	for angle in angles:
		for segment in range(segment_count):
			var longitude := TAU*float(segment)/segment_count
			var local_direction := Vector3(sin(longitude)*sin(angle),cos(angle),cos(longitude)*sin(angle))
			var direction := sampling_basis * local_direction
			var height := elevation(direction, include_launch_site)
			var vertex := direction*(float(definition.radius)+maxf(0.0,height))
			# At planetary coordinates float rounding can exceed the thin deck
			# finish. Pin the shared render/contact vertices to the exact plane.
			if include_launch_site and local_direction.y > 0.0 and Vector2(local_direction.x, local_direction.z).length()*float(definition.radius) <= 150.01:
				vertex.z = float(definition.radius)
			vertices.append(vertex)
			colors.append(color_at(direction,height, include_launch_site))
	var south := vertices.size()
	vertices.append(bottom*(float(definition.radius)+maxf(0.0,elevation(bottom, include_launch_site))))
	colors.append(color_at(bottom,elevation(bottom, include_launch_site), include_launch_site))
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
	return arrays

func _refine_surface_hit(hit: Dictionary, origin: Vector3, direction: Vector3) -> void:
	# TriangleMesh locates the face, but its float32 ray intersection can drift
	# centimetres from narrow polar triangles. Re-intersect that exact plane
	# with scalar doubles before returning contact to the flight simulation.
	var face := int(hit.face_index) * 3
	var a := _contact_vertices[_contact_indices[face]]
	var b := _contact_vertices[_contact_indices[face + 1]]
	var c := _contact_vertices[_contact_indices[face + 2]]
	var normal := (c - a).cross(b - a).normalized()
	var denominator := float(normal.x) * direction.x + float(normal.y) * direction.y + float(normal.z) * direction.z
	if absf(denominator) < 0.000000001: return
	var distance := (float(normal.x) * (float(a.x) - origin.x) + float(normal.y) * (float(a.y) - origin.y) + float(normal.z) * (float(a.z) - origin.z)) / denominator
	var x := float(origin.x) + float(direction.x) * distance
	var y := float(origin.y) + float(direction.y) * distance
	var z := float(origin.z) + float(direction.z) * distance
	hit.position = Vector3(x, y, z)
	hit.radius = sqrt(x * x + y * y + z * z)
	hit.distance = distance
	hit.normal = normal

func contact(radial: Vector3, time: float = 0.0) -> Dictionary:
	build()
	var rotation := rotation_at(time)
	var direction := (rotation.transposed()*radial).normalized()
	if direction.length_squared() < 0.5: direction = Vector3.UP
	var origin := direction * (float(definition.radius) + float(definition.relief) * 2.0 + 100.0)
	var hit := collision.intersect_ray(origin, -direction)
	if hit.is_empty(): return {"radius":float(definition.radius),"normal":rotation*direction}
	_refine_surface_hit(hit, Vector3.ZERO, direction)
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	if normal.dot(direction) < 0.0: normal = -normal
	return {"radius":hit.radius,"normal":rotation*normal,"position":rotation*point}

func clearance(radial: Vector3, time: float = 0.0) -> float:
	return sqrt(Physics.dot_double(radial, radial))-float(contact(radial,time).radius)

func segment_hit(start: Vector3, finish: Vector3, start_time: float, end_time: float) -> Dictionary:
	var rotation := rotation_at(end_time)
	# Transform both endpoints at their respective times: include ground rotation.
	var local_start := rotation_at(start_time).transposed()*start
	var local_end := rotation.transposed()*finish
	var enter := 0.0
	var leave := 1.0
	var bound := float(definition.radius) + float(definition.relief) * 2.0 + 100.0
	if maxf(local_start.length(), local_end.length()) > bound:
		# Clip distant map/solar rays to the body's vicinity before handing them
		# to TriangleMesh. Planet-sized triangles disappear in float32 arithmetic
		# when a segment spans billions of metres. Scalars keep the clipping stable.
		var travel := local_end - local_start
		var length_squared := Physics.dot_double(travel, travel)
		if length_squared < 0.000001: return {}
		var middle := -Physics.dot_double(local_start, travel) / length_squared
		var closest := Vector3.ZERO
		for axis in range(3): closest[axis] = float(local_start[axis]) + float(travel[axis]) * middle
		var distance_squared := Physics.dot_double(closest, closest)
		if distance_squared > bound * bound: return {}
		var half_span := sqrt((bound * bound - distance_squared) / length_squared)
		enter = maxf(0.0, middle - half_span)
		leave = minf(1.0, middle + half_span)
		if enter > leave: return {}
		for axis in range(3):
			local_end[axis] = float(local_start[axis]) + float(travel[axis]) * leave
			local_start[axis] = float(local_start[axis]) + float(travel[axis]) * enter
	# Distant debris must not build every moon's collision mesh on separation.
	build()
	var hit := collision.intersect_segment(local_start,local_end)
	if hit.is_empty(): return {}
	_refine_surface_hit(hit, local_start, local_end - local_start)
	var local_point: Vector3 = hit.position
	var fraction := lerpf(enter, leave, clampf(float(hit.distance), 0.0, 1.0))
	var normal: Vector3 = hit.normal
	if normal.dot(local_point) < 0.0: normal = -normal
	return {"position":rotation*local_point,"normal":rotation*normal,"fraction":fraction}
