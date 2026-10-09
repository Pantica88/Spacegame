class_name OceanPatch
extends MeshInstance3D
# Camera-following wave surface drawn over the planet's ocean near sea level.
# The terrain mesh still supplies distant water and all physical contact.

# The patch always reaches past the horizon. Its unit disc is scaled in the
# shader. Rings are geometrically spaced: ~0.25 m cells around the player,
# where the tutorial's waves displace the surface, growing outward.
const MIN_EXTENT := 8000.0
const MAX_EXTENT := 220000.0
const RINGS := 384
const SEGMENTS := 512
const CENTER_CELL := 0.25
# The tutorial look is kept up to here, cross-fading with the terrain's water.
const FADE_START := 18000.0
const MAX_CAMERA_HEIGHT := 25000.0
const REANCHOR_DISTANCE := 30000.0
# Waves per swell tile relative to the shader's swell_scales (ocean.gdshader's
# swell_repeat): a longer, busier tile so the swell does not repeat as a lattice.
const SWELL_REPEAT := 4.0
const SHADER_DEFAULTS := {"time_scale": 0.1, "noise_scale": 20.0, "height_scale": 2.0, "seabed_shallow_m": 2.5, "seabed_depth_m": 70.0, "swell_scales": Vector4(97.0, 311.0, 1130.0, 3700.0), "swell_heights": Vector4(0.25, 0.45, 0.65, 0.8), "sea_state_scale": 5200.0, "swell_repeat": SWELL_REPEAT, "axis_u": Vector3(1.0, 0.0, 0.0), "axis_v": Vector3(0.0, 0.0, 1.0), "ocean_pos": Vector3.ZERO}

# Inside this distance the terrain draws a seabed below the patch.
var cutout_radius := 0.0
static var _ring_growth := 0.0165
# 1 below FADE_START, 0 at MAX_CAMERA_HEIGHT; the terrain uses the same value.
var fade := 0.0

var _material := ShaderMaterial.new()
var _anchor_body := Vector3.ZERO
var _axis_u_body := Vector3.RIGHT
var _axis_v_body := Vector3.BACK
var _surface_texture: Texture2D
var _wave_texture: NoiseTexture2D
var _swell_texture: NoiseTexture2D
var _wave_image: Image
var _swell_image: Image
var _decode_task := -1
var _wave_time := 0.0


func _init() -> void:
	name = "OceanPatch"
	mesh = _build_rings()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 64.0
	_material.shader = preload("res://assets/shaders/ocean.gdshader")
	# Set source colours as Color parameters, as in InfiniteOcean's material.
	# Darker than the tutorial's: its cyan read as shallow lagoon in full sun.
	var colors := {"albedo": Color(0.0, 0.04, 0.10), "albedo2": Color(0.0, 0.08, 0.18), "color_deep": Color(0.005, 0.025, 0.06), "color_shallow": Color(0.0, 0.08, 0.18), "edge_color": Color.WHITE}
	for parameter in colors:
		_material.set_shader_parameter(parameter, colors[parameter])
	# Draw before the cloud layer, which composites over finished surfaces.
	_material.render_priority = -1
	# NoiseTexture2D settings from the tutorial.
	var wave := _wave_noise()
	_wave_texture = _noise_texture(wave, false, 8.0)
	_material.set_shader_parameter("wave", _wave_texture)
	var bump := _wave_noise()
	bump.fractal_type = FastNoiseLite.FRACTAL_FBM
	_material.set_shader_parameter("wave_bump", _noise_texture(bump, true, 1.0))
	var normal := FastNoiseLite.new()
	normal.noise_type = FastNoiseLite.TYPE_PERLIN
	normal.frequency = 0.032
	_material.set_shader_parameter("texture_normal", _noise_texture(normal, true, 1.6))
	var normal2 := FastNoiseLite.new()
	normal2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	normal2.seed = 22
	normal2.frequency = 0.003
	normal2.fractal_lacunarity = 1.6
	normal2.fractal_gain = 0.47
	normal2.fractal_weighted_strength = 0.53
	var normal2_texture := _noise_texture(normal2, true, 21.8)
	normal2_texture.seamless_blend_skirt = 0.532
	_material.set_shader_parameter("texture_normal2", normal2_texture)
	# Smooth swell heights, separate from the tutorial's ridged ripples.
	var swell := FastNoiseLite.new()
	swell.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	swell.seed = 7
	swell.frequency = 0.0025 * SWELL_REPEAT
	swell.fractal_octaves = 3
	swell.fractal_gain = 0.45
	var swell_texture := _noise_texture(swell, false, 1.0)
	swell_texture.width = 1024
	swell_texture.height = 1024
	_swell_texture = swell_texture
	_material.set_shader_parameter("swell_noise", swell_texture)
	_material.set_shader_parameter("swell_size", 1024.0)
	_material.set_shader_parameter("swell_repeat", SWELL_REPEAT)
	material_override = _material
	visible = false
	# surface_height() needs CPU copies of the wave and swell noise. Building
	# them takes ~0.3 s, which stalled the first frame after a splashdown.
	_decode_task = WorkerThreadPool.add_task(_decode_images, false, "Ocean wave images")


func _decode_images() -> void:
	# Own noise copies: NoiseTexture2D may be generating from the originals.
	_wave_image = _decoded(_wave_texture, _wave_texture.noise.duplicate())
	_swell_image = _decoded(_swell_texture, _swell_texture.noise.duplicate())


func _wait_for_images() -> void:
	if _decode_task < 0: return
	WorkerThreadPool.wait_for_task_completion(_decode_task)
	_decode_task = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE: _wait_for_images()


# Vessel hull as a capsule (segment a-b, radius) where edge foam is suppressed.
func set_hull(a: Vector3, b: Vector3, radius: float) -> void:
	_material.set_shader_parameter("hull_a", a)
	_material.set_shader_parameter("hull_b", b)
	_material.set_shader_parameter("hull_radius", radius)


func material() -> ShaderMaterial:
	return _material


func configure(terrain: RefCounted) -> void:
	var definition = terrain.definition
	_material.set_shader_parameter("planet_radius", float(definition.radius))
	_material.set_shader_parameter("baked_surface", terrain.surface_texture)
	# Matches the dry ground PlanetTerrain.color_at() keeps around the launch
	# complex, plus margin where its graded edge is still near sea level.
	_material.set_shader_parameter("launch_direction_body", terrain.LAUNCH_DIRECTION)
	_material.set_shader_parameter("launch_dry_radius", 300.0 if definition.launch_site else 0.0)
	_surface_texture = terrain.surface_texture
	_anchor_body = Vector3.ZERO


# planet: the terrain's MeshInstance3D (body space at its origin and basis).
# player: the tutorial's ocean_pos; waves displace within 85 m of it.
# sea_point: optional exact sea-level point under the player. Positions built
# from planet-scale coordinates round to ~6 cm and shift each frame, which
# shook the water against a floating hull.
func follow(planet: Node3D, camera_position: Vector3, player_position: Vector3, terrain: RefCounted, sea_point: Variant = null) -> void:
	var definition = terrain.definition
	var radius := float(definition.radius)
	var to_camera := camera_position - planet.global_position
	var height := to_camera.length() - radius
	visible = planet.visible and bool(definition.has_ocean) and terrain.surface_texture != null and height < MAX_CAMERA_HEIGHT
	if not visible:
		cutout_radius = 0.0
		fade = 0.0
		return
	# Baked maps can arrive after the flight scene is built.
	if terrain.surface_texture != _surface_texture: configure(terrain)
	fade = 1.0 - smoothstep(FADE_START, MAX_CAMERA_HEIGHT, height)
	_material.set_shader_parameter("fade", fade)
	_material.set_shader_parameter("ocean_pos", player_position)
	# Godot's TIME also wraps hourly; an explicit clock lets surface_height() match.
	_wave_time = fmod(Time.get_ticks_msec() * 0.001, 3600.0)
	_material.set_shader_parameter("wave_time", _wave_time)
	# Centre the dense rings under the player, as the tutorial's grid follows it.
	var up := (player_position - planet.global_position).normalized()
	var horizon := sqrt(maxf(2.0 * radius * height + height * height, 0.0))
	var extent := clampf(horizon * 1.15 + MIN_EXTENT, MIN_EXTENT, MAX_EXTENT)
	cutout_radius = extent * 0.95
	_material.set_shader_parameter("patch_extent", extent)
	_material.set_shader_parameter("first_cell", CENTER_CELL)
	_material.set_shader_parameter("ring_growth", _ring_growth)
	var spin := planet.global_basis.orthonormalized()
	var body_up := spin.inverse() * up
	# Waves live in a planet-fixed tangent frame. Re-anchor rarely so the
	# coordinates stay small enough for single-precision shader maths.
	if _anchor_body == Vector3.ZERO or _anchor_body.distance_to(body_up * radius) > REANCHOR_DISTANCE:
		_anchor_body = body_up * radius
		var reference := Vector3.UP if absf(body_up.y) < 0.9 else Vector3.RIGHT
		_axis_u_body = reference.cross(body_up).normalized()
		_axis_v_body = _axis_u_body.cross(body_up).normalized()
	var forward := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	global_transform = Transform3D(Basis(up.cross(forward), up, forward).orthonormalized(), sea_point if sea_point is Vector3 else planet.global_position + up * radius)
	_material.set_shader_parameter("anchor_world", planet.global_position + spin * _anchor_body)
	_material.set_shader_parameter("axis_u", spin * _axis_u_body)
	_material.set_shader_parameter("axis_v", spin * _axis_v_body)
	_material.set_shader_parameter("planet_center_world", planet.global_position)
	_material.set_shader_parameter("body_from_world", spin.inverse())


# Displacement of the drawn water above sea level at a world point, matching
# the vertex shader near the player (finest cells, so every octave is present).
# coverage: the planet's water coverage there (0.5 coast, 1.0 open sea).
func surface_height(world_point: Vector3, coverage: float) -> float:
	if not visible: return 0.0
	_wait_for_images()
	if _wave_image == null or _swell_image == null: return 0.0
	var anchor: Variant = _param("anchor_world")
	var offset: Vector3 = world_point - (anchor if anchor is Vector3 else Vector3.ZERO)
	var p := Vector2(offset.dot(_param("axis_u")), offset.dot(_param("axis_v")))
	var t := _wave_time * float(_param("time_scale"))
	var noise_scale := float(_param("noise_scale"))
	var ripple := (_sample(_wave_image, p / noise_scale + Vector2(0.5, -0.2) * t) + _sample(_wave_image, p / noise_scale + Vector2(-0.5, 0.5) * t)) * 0.5
	# Match the smooth displacement fade around the player.
	var ripple_weight := 1.0 - smoothstep(0.0, 85.0, world_point.distance_to(_param("ocean_pos")))
	var height := (ripple - 0.5) * float(_param("height_scale")) * ripple_weight
	var shallow := float(_param("seabed_shallow_m"))
	var deep := float(_param("seabed_depth_m"))
	var shoal := clampf(lerpf(shallow, deep, smoothstep(0.5, 0.95, coverage)) / deep, 0.0, 1.0)
	shoal *= shoal
	var scales: Vector4 = _param("swell_scales")
	var heights: Vector4 = _param("swell_heights")
	var drift := Vector2(0.5, -0.2).normalized()
	var repeat := float(_param("swell_repeat"))
	var state_scale := float(_param("sea_state_scale")) * repeat
	for i in range(4):
		var a := 1.3 + i * 2.4
		var n := _sample(_swell_image, p.rotated(a) / (state_scale * (1.0 + 0.37 * i)) + Vector2(0.31, 0.17) * i)
		var mm := _sample(_swell_image, p.rotated(-a) / (state_scale * 2.9))
		var sea := lerpf(0.35, 1.1, smoothstep(0.2, 0.8, n * 0.65 + mm * 0.35))
		var span := scales[i] * repeat
		var uv := p.rotated(0.7 + i * 1.9) / span + drift.rotated(0.9 + i * 2.1) * _wave_time * float(_param("time_scale")) * (8.0 / span)
		height += (_sample(_swell_image, uv) - 0.5) * 2.0 * heights[i] * sea * shoal
	return height


# Uniforms left at their shader defaults are not returned by the material.
func _param(name: String) -> Variant:
	var value: Variant = _material.get_shader_parameter(name)
	if value == null: value = RenderingServer.shader_get_parameter_default(_material.shader.get_rid(), name)
	# Headless renderers report no defaults; mirror ocean.gdshader's.
	if value == null: value = SHADER_DEFAULTS.get(name)
	return value


# The same pixels NoiseTexture2D builds, generated here without waiting on its thread.
static func _decoded(texture: NoiseTexture2D, noise: Noise) -> Image:
	if texture == null or noise == null: return null
	return noise.get_seamless_image(texture.width, texture.height, texture.invert, texture.in_3d_space, texture.seamless_blend_skirt, texture.normalize)


# Bilinear, repeating, red channel: textureLod(..., 0.0).r.
static func _sample(image: Image, uv: Vector2) -> float:
	var size := Vector2(image.get_size())
	var texel := uv * size - Vector2(0.5, 0.5)
	var base := texel.floor()
	var f := texel - base
	var w := int(size.x)
	var h := int(size.y)
	var x0 := posmod(int(base.x), w)
	var y0 := posmod(int(base.y), h)
	var x1 := (x0 + 1) % w
	var y1 := (y0 + 1) % h
	var top := lerpf(image.get_pixel(x0, y0).r, image.get_pixel(x1, y0).r, f.x)
	var bottom := lerpf(image.get_pixel(x0, y1).r, image.get_pixel(x1, y1).r, f.x)
	return lerpf(top, bottom, f.y)


static func _build_rings() -> ArrayMesh:
	# Solve the ring growth g so the outermost ring lands on the unit radius.
	var first := CENTER_CELL / MIN_EXTENT
	var low := 1.0000001
	var high := 1.2
	for i in range(60):
		var g := (low + high) * 0.5
		if first * (pow(g, RINGS) - 1.0) / (g - 1.0) > 1.0: high = g
		else: low = g
	var growth := (low + high) * 0.5
	_ring_growth = growth - 1.0
	var vertices := PackedVector3Array([Vector3.ZERO])
	var radius := 0.0
	var step := first
	for ring in range(RINGS):
		radius = minf(radius + step, 1.0) if ring < RINGS - 1 else 1.0
		step *= growth
		for segment in range(SEGMENTS):
			var angle := TAU * float(segment) / SEGMENTS
			vertices.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	var indices := PackedInt32Array()
	# Godot fronts are clockwise; reversed winding lights the water underside.
	for segment in range(SEGMENTS):
		indices.append_array([0, 1 + segment, 1 + (segment + 1) % SEGMENTS])
	for ring in range(RINGS - 1):
		var inner := 1 + ring * SEGMENTS
		var outer := inner + SEGMENTS
		for segment in range(SEGMENTS):
			var next := (segment + 1) % SEGMENTS
			indices.append_array([inner + segment, outer + segment, inner + next, inner + next, outer + segment, outer + next])
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	result.custom_aabb = AABB(Vector3(-MAX_EXTENT, -45000.0, -MAX_EXTENT), Vector3(MAX_EXTENT * 2.0, 45100.0, MAX_EXTENT * 2.0))
	return result


# Value Cubic, ridged fractal, gain 0.34, weighted strength 0.6.
static func _wave_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_gain = 0.34
	noise.fractal_weighted_strength = 0.6
	return noise


static func _noise_texture(noise: FastNoiseLite, normal_map: bool, bump_strength: float) -> NoiseTexture2D:
	var texture := NoiseTexture2D.new()
	texture.seamless = true
	texture.as_normal_map = normal_map
	texture.bump_strength = bump_strength
	texture.generate_mipmaps = true
	texture.noise = noise
	return texture
