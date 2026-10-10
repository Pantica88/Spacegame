extends MeshInstance3D
## Composites procedural or painted cloud volumes. The volume is integrated in
## a reduced-resolution offscreen pass and upsampled here; only pixels whose
## nearby geometry sits inside the cloud shell integrate at full resolution.
const CLOUD_SHADER = preload("res://assets/shaders/clouds.gdshader")
const LOWRES_SHADER = preload("res://assets/shaders/clouds_lowres.gdshader")
const RESOLVE_SHADER = preload("res://assets/shaders/clouds_resolve.gdshader")
## Order in which each 2x2 block's pixels are marched; every pixel is fresh at
## least once every four frames.
const TEMPORAL_OFFSETS := [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 1)]
## Rotation between frames beyond which reprojected history is discarded.
const TEMPORAL_MAX_TURN := deg_to_rad(15.0)
static var _bounded_shaders := {}
## Fraction of the view resolution integrated offscreen. 1.0 integrates every
## pixel in the composite instead.
var resolution_scale := 0.5
## Scales of the offscreen pass by height above the shell top (metres), in place
## of resolution_scale. Lower scales from altitude saved up to 1.9 ms but drew a
## staircase along the deck's edge against the sky, so the clouds keep half
## resolution. Far out the planet is small on screen and integrating every
## pixel in the composite costs less than the offscreen passes (0.45 ms at
## 1,500 km, 3.4 ms at 800 km, 16 ms at 400 km; 1080p, RX 580), with nothing
## reprojected to soften or flicker (2026-10-10).
## The owner chose where full resolution begins (about 3,000 km up) in the
## hover preview. Over the band below it, the composite crossfades from the
## half-resolution pass to integrating every pixel, so the switch itself at
## the top changes nothing visible. Above it the offscreen passes run at full
## resolution: every pixel there is still reprojected and averaged over frames,
## because integrating them afresh flickered while the camera moved (march
## samples are spaced from the camera, so travel slid them through the deck).
const FULL_RESOLUTION_FADE := Vector2(2450000.0, 2950000.0)
var _far_offscreen := false
## Marches a quarter of the reduced pass each frame and reprojects the rest
## from the previous frame. Comparisons disable it to march every pixel.
var temporal := true
var _resolve: Array[SubViewport] = []
var _resolve_cameras: Array[Camera3D] = []
var _resolve_materials: Array[ShaderMaterial] = []
var _temporal_frame := 0
var _temporal_valid := false
var _previous_basis := Basis.IDENTITY
var _previous_size := Vector2i.ZERO
var _temporal_process_frame := -1
var _frame_basis := Basis.IDENTITY
var _frame_size := Vector2i.ZERO
var _frame_used := false
var _frame_planet := Vector3.ZERO
var _previous_planet := Vector3.ZERO
## Benchmarks and comparisons disable this to pin resolution_scale.
var altitude_scaling := true
var _altitude_scale := 0.5
## Seconds of simulated weather; the editor raises time_scale for time-lapse.
var weather_time := 0.0
var time_scale := 1.0
var _drift := Basis.IDENTITY
var _lowres: SubViewport
var _lowres_camera: Camera3D
var _lowres_mesh: MeshInstance3D
var _lowres_material: ShaderMaterial
# Surfaces that mirror the clouds (the ocean) receive every volume uniform.
var _reflection_materials: Array[ShaderMaterial] = []
# CPU mirror of the volume's inputs, for lighting things that sit in the sky.
static var _noise_task := -1
static var _noise_bytes := PackedByteArray()
static var _noise_size := Vector3i.ZERO
# CPU copy of the volume's current inputs for vessel lighting (km, local frame).
var _shade_ready := false
var _shade_weather: Resource
var _shade_ground := 0.0
var _shade_bottom := 0.0
var _shade_top := 0.0
var _shade_thickness := 1.0
var _shade_deck := 1.0
var _shade_to_local := Basis.IDENTITY
var _shade_evolution := Vector3.ZERO
var _shade_coverage := 0.56
var _shade_density_scale := 1.0
var _shade_sun := Vector3.UP
# Views around a vessel that cloud_glow() traces, in a local frame (Y up): the
# zenith, rings at 55°, 15° and -25° elevation, and the nadir.
const GLOW_DIRECTIONS: Array[Vector3] = [
	Vector3(0, 1, 0),
	Vector3(0.574, 0.819, 0), Vector3(-0.287, 0.819, 0.497), Vector3(-0.287, 0.819, -0.497),
	Vector3(0.966, 0.259, 0), Vector3(0.483, 0.259, 0.837), Vector3(-0.483, 0.259, 0.837),
	Vector3(-0.966, 0.259, 0), Vector3(-0.483, 0.259, -0.837), Vector3(0.483, 0.259, -0.837),
	Vector3(0.453, -0.423, 0.785), Vector3(-0.906, -0.423, 0), Vector3(0.453, -0.423, -0.785),
	Vector3(0, -1, 0),
]
## Cloud path traced per view; dense views turn opaque well within it.
const GLOW_RANGE_KM := 6.0
## March spacing. Edge cells fade in and out and the noise is trilinear, so
## steps near the ~0.25 km billow texel size stay free of popping.
const GLOW_STEP_KM := 0.4
const GLOW_VIEWS_PER_CALL := 1
const SUN_STEP_KM := 0.25
const SUN_MAX_STEPS := 40
var _glow_views: Array[Color] = []
var _glow_cursor := 0

func _init() -> void:
	name = "CloudLayer"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	extra_cull_margin = 100.0
	# Weather keeps its own clock (paused trees freeze it below), but the
	# offscreen camera must follow the view even while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mesh = _screen_triangle()
	var material := _volume_material(CLOUD_SHADER)
	# Composite over the distant sun (0), before nearby exhaust and heat (2).
	# Transparent flames are absent from scene_depth and cannot clip this pass.
	material.render_priority = 1
	material_override = material
	# The offscreen pass needs nothing from the scene: rays come from its
	# mirrored camera and every other input is a uniform. Its own world keeps
	# it free of the scene's environment, tonemapping and geometry.
	_lowres = SubViewport.new()
	_lowres.name = "CloudLowRes"
	_lowres.own_world_3d = true
	_lowres.transparent_bg = true
	_lowres.msaa_3d = Viewport.MSAA_DISABLED
	_lowres.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_lowres.size = Vector2i(2, 2)
	add_child(_lowres, false, Node.INTERNAL_MODE_FRONT)
	_lowres_camera = Camera3D.new()
	_lowres_camera.current = true
	_lowres.add_child(_lowres_camera)
	_lowres_material = _volume_material(LOWRES_SHADER)
	_lowres_mesh = MeshInstance3D.new()
	_lowres_mesh.mesh = _screen_triangle()
	# Its vertex shader covers the target whatever the camera's offsets or
	# near plane; never let CPU frustum culling drop it.
	_lowres_mesh.custom_aabb = AABB(Vector3.ONE * -1.0e9, Vector3.ONE * 2.0e9)
	_lowres_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lowres_mesh.material_override = _lowres_material
	_lowres.add_child(_lowres_mesh)
	for index in range(2):
		var target := SubViewport.new()
		target.name = "CloudResolve%d" % index
		target.own_world_3d = true
		target.transparent_bg = true
		target.msaa_3d = Viewport.MSAA_DISABLED
		target.render_target_update_mode = SubViewport.UPDATE_DISABLED
		target.size = Vector2i(2, 2)
		# After the march viewport, so it renders first within each frame.
		add_child(target, false, Node.INTERNAL_MODE_FRONT)
		var resolve_camera := Camera3D.new()
		resolve_camera.current = true
		target.add_child(resolve_camera)
		var resolve_material := ShaderMaterial.new()
		resolve_material.shader = RESOLVE_SHADER
		resolve_material.set_shader_parameter("fresh_samples", _lowres.get_texture())
		var quad := MeshInstance3D.new()
		quad.mesh = _screen_triangle()
		quad.custom_aabb = AABB(Vector3.ONE * -1.0e9, Vector3.ONE * 2.0e9)
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.material_override = resolve_material
		target.add_child(quad)
		_resolve.append(target)
		_resolve_cameras.append(resolve_camera)
		_resolve_materials.append(resolve_material)
	# Each resolve target reads the other as its history.
	_resolve_materials[0].set_shader_parameter("history", _resolve[1].get_texture())
	_resolve_materials[1].set_shader_parameter("history", _resolve[0].get_texture())
	material.set_shader_parameter("cloud_lowres", _lowres.get_texture())
	_start_noise_mirror()

static func _screen_triangle() -> ArrayMesh:
	var triangle := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(3, -1, 0), Vector3(-1, 3, 0)])
	triangle.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return triangle

static func _volume_material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("cloud_noise", preload("res://assets/cloud_volume_noise.tres"))
	material.set_shader_parameter("cloud_detail_noise", preload("res://assets/cloud_detail_noise.tres"))
	# A single short haze integration, outside the volume's density loop.
	material.set_shader_parameter("atmosphere_view_samples", 4)
	material.set_shader_parameter("atmosphere_light_samples", 1)
	return material

static func _bounded(shader: Shader) -> Shader:
	if not _bounded_shaders.has(shader):
		var bounded := Shader.new()
		bounded.code = "#define CLOUD_OCCUPANCY\n" + shader.code
		_bounded_shaders[shader] = bounded
	return _bounded_shaders[shader]

## Both occupancy paths can be selected later as the camera leaves the planet.
## The caller pauses simulation and covers the view while these actually draw.
func prewarm_variants() -> void:
	var material := material_override as ShaderMaterial
	var original_shader := material.shader
	var original_lowres_shader := _lowres_material.shader
	var original_visibility := visible
	visible = true
	_sync_lowres()
	for bounded in [false, true]:
		material.shader = _bounded(CLOUD_SHADER) if bounded else CLOUD_SHADER
		_lowres_material.shader = _bounded(LOWRES_SHADER) if bounded else LOWRES_SHADER
		await RenderingServer.frame_post_draw
	material.shader = original_shader
	_lowres_material.shader = original_lowres_shader
	visible = original_visibility
	_sync_lowres()

func _process(delta: float) -> void:
	if not get_tree().paused:
		weather_time += delta * time_scale
	_sync_lowres()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _lowres != null:
		_sync_lowres()

func effective_scale() -> float:
	return _altitude_scale if altitude_scaling else resolution_scale

func _update_altitude_scale(above_top: float) -> void:
	var fade := smoothstep(FULL_RESOLUTION_FADE.x, FULL_RESOLUTION_FADE.y, above_top) if altitude_scaling else 0.0
	_far_offscreen = fade >= 1.0
	_altitude_scale = 1.0 if _far_offscreen else 0.5
	# Above the band the offscreen passes already run at full resolution.
	(material_override as ShaderMaterial).set_shader_parameter("full_blend", 0.0 if _far_offscreen else fade)

## Whether the volume integrates offscreen rather than in the composite.
func integrates_offscreen() -> bool:
	return effective_scale() < 1.0 or (altitude_scaling and _far_offscreen)

## The offscreen march viewport, for tools that measure its render time.
func lowres_viewport() -> SubViewport:
	return _lowres

## Keeps the offscreen pass sized to the view and its camera on the view's
## pose. Runs after the scene has placed its camera for this frame; the
## subviewport then renders before the view that composites it.
func _sync_lowres() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	# The map disables the host's 3D pass; the offscreen clouds would go unseen.
	var active := integrates_offscreen() and is_visible_in_tree() and is_instance_valid(camera) and not get_viewport().disable_3d
	_lowres.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	var composite := material_override as ShaderMaterial
	composite.set_shader_parameter("lowres_enabled", active)
	if not active or not temporal:
		for target in _resolve: target.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_frame_used = false
	if not active:
		return
	var view := get_viewport()
	var pixels := Vector2(view.get("size")) * float(view.scaling_3d_scale)
	var size := Vector2i((pixels * effective_scale()).round()).max(Vector2i.ONE)
	if temporal:
		# Even, so the half-size march target spans exactly the same frustum.
		size = Vector2i(size.x + size.x % 2, size.y + size.y % 2).max(Vector2i(2, 2))
		_sync_temporal(size, camera)
		size /= 2
	else:
		_lowres_material.set_shader_parameter("temporal_march", false)
		composite.set_shader_parameter("cloud_lowres", _lowres.get_texture())
	if _lowres.size != size:
		_lowres.size = size
	_lowres_camera.projection = camera.projection
	_lowres_camera.keep_aspect = camera.keep_aspect
	_lowres_camera.fov = camera.fov
	_lowres_camera.size = camera.size
	_lowres_camera.frustum_offset = camera.frustum_offset
	_lowres_camera.near = camera.near
	_lowres_camera.far = camera.far
	_lowres_camera.h_offset = camera.h_offset
	_lowres_camera.v_offset = camera.v_offset
	_lowres_camera.global_transform = camera.global_transform

func _sync_temporal(size: Vector2i, camera: Camera3D) -> void:
	# This runs several times a frame; advance the cycle once per drawn frame,
	# treating the last pose of the previous frame as its rendered pose.
	var process_frame := Engine.get_process_frames()
	if process_frame != _temporal_process_frame:
		_temporal_process_frame = process_frame
		_temporal_frame += 1
		_temporal_valid = _frame_used
		_previous_basis = _frame_basis
		_previous_size = _frame_size
		_previous_planet = _frame_planet
	var current := _temporal_frame % 2
	var offset: Vector2 = TEMPORAL_OFFSETS[_temporal_frame % TEMPORAL_OFFSETS.size()]
	var basis := camera.global_basis.orthonormalized()
	# History survives ordinary turns; resizes, cuts and teleports refill it.
	var turn := (_previous_basis.inverse() * basis).get_rotation_quaternion().get_angle()
	# The flight camera stays near the floating origin; judge jumps in planet space.
	# Unset until the first weather update; a frame without it starts fresh.
	var planet_value: Variant = (material_override as ShaderMaterial).get_shader_parameter("camera_planet_km")
	var planet: Vector3 = planet_value if planet_value is Vector3 else Vector3.ZERO
	var moved_km := planet.distance_to(_previous_planet)
	# Travel is reprojected (clouds_resolve.gdshader), so only a jump that is
	# large against the distance to the clouds refills history; far above them a
	# fast camera covers many kilometres a frame.
	var max_jump_km := maxf(5.0, (planet.length() - _shade_top) * 0.1)
	var valid := _temporal_valid and size == _previous_size and turn < TEMPORAL_MAX_TURN and moved_km < max_jump_km
	_lowres_material.set_shader_parameter("temporal_march", true)
	_lowres_material.set_shader_parameter("temporal_offset", offset)
	_lowres_material.set_shader_parameter("temporal_target_size", Vector2(size))
	var target := _resolve[current]
	if target.size != size:
		target.size = size
	var resolve_material := _resolve_materials[current]
	resolve_material.set_shader_parameter("fresh_offset", offset)
	resolve_material.set_shader_parameter("history_valid", valid)
	resolve_material.set_shader_parameter("previous_view_rotation", _previous_basis.inverse())
	# Travel since the previous frame, computed here in double precision, and
	# the middle of the low deck, where history is assumed to lie.
	resolve_material.set_shader_parameter("camera_motion_km", planet - _previous_planet if valid else Vector3.ZERO)
	resolve_material.set_shader_parameter("camera_planet_km", planet)
	resolve_material.set_shader_parameter("reprojection_radius_km", _shade_bottom + _shade_thickness * _shade_deck * 0.5)
	# Far above the clouds, average fresh samples with history (see the shader),
	# but not while the camera travels, where averaging only softens.
	var above_km := planet.length() - _shade_top
	var travel := smoothstep(0.0005, 0.005, moved_km / maxf(above_km, 1.0))
	var far := smoothstep(100.0, 600.0, above_km) * (1.0 - travel)
	resolve_material.set_shader_parameter("history_blend", 0.7 * far)
	resolve_material.set_shader_parameter("history_tolerance", 0.15 * far)
	_mirror_camera(_resolve_cameras[current], camera)
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_resolve[1 - current].render_target_update_mode = SubViewport.UPDATE_DISABLED
	(material_override as ShaderMaterial).set_shader_parameter("cloud_lowres", target.get_texture())
	_frame_basis = basis
	_frame_size = size
	_frame_planet = planet
	_frame_used = true

static func _mirror_camera(target: Camera3D, camera: Camera3D) -> void:
	target.projection = camera.projection
	target.keep_aspect = camera.keep_aspect
	target.fov = camera.fov
	target.size = camera.size
	target.frustum_offset = camera.frustum_offset
	target.near = camera.near
	target.far = camera.far
	target.h_offset = camera.h_offset
	target.v_offset = camera.v_offset
	target.global_transform = camera.global_transform

func _param(parameter: String, value: Variant) -> void:
	(material_override as ShaderMaterial).set_shader_parameter(parameter, value)
	_lowres_material.set_shader_parameter(parameter, value)
	for target in _reflection_materials:
		target.set_shader_parameter(parameter, value)

## Lets a surface that includes clouds_volume.gdshaderinc mirror the deck.
func add_reflection(target: ShaderMaterial) -> void:
	target.set_shader_parameter("cloud_noise", preload("res://assets/cloud_volume_noise.tres"))
	target.set_shader_parameter("cloud_detail_noise", preload("res://assets/cloud_detail_noise.tres"))
	_reflection_materials.append(target)

## Rotation carrying weather-map space into planet-local space. Painting tools
## apply its inverse so strokes land under the cursor while the sky moves.
func drift_basis() -> Basis:
	return _drift

func _update_drift(definition: Resource) -> void:
	var speed := float(definition.get("cloud_wind_speed") if definition.get("cloud_wind_speed") != null else 0.0)
	if speed == 0.0 or float(definition.radius) <= 0.0:
		_drift = Basis.IDENTITY
		return
	# Heading 90° flows along latitude bands; other headings tilt the jet.
	var heading := float(definition.cloud_wind_heading)
	var axis := Basis(Vector3.RIGHT, deg_to_rad(heading - 90.0)) * Vector3.UP
	_drift = Basis(axis, fmod(speed * weather_time / float(definition.radius), TAU))

func update_weather(definition: Resource, observer: Vector3, sunlight: Vector3, enabled: bool) -> void:
	var radius := float(definition.radius)
	var atmosphere_height := float(definition.atmosphere_height)
	var weather: Resource = definition.cloud_weather
	_update_drift(definition)
	visible = enabled and atmosphere_height > 0.0 and float(definition.atmosphere_visual_density) > 0.0
	if visible and weather != null:
		visible = weather.has_clouds()
	_shade_ready = false
	for target in _reflection_materials:
		target.set_shader_parameter("cloud_reflection_enabled", visible)
	if not visible:
		return
	var camera := get_viewport().get_camera_3d()
	if is_instance_valid(camera):
		# Frustum culling uses the camera's offset origin too. Anchoring at
		# global_position alone puts the screen triangle outside an offset
		# editor camera even though its vertex shader covers the viewport.
		global_position = camera.get_camera_transform().origin
	var height := minf(maxf(minf(atmosphere_height * 0.22, 6000.0), float(definition.relief) + 1600.0), atmosphere_height * 0.65)
	var thickness := minf(1400.0, atmosphere_height * 0.15)
	var bounds := PackedVector3Array()
	var bounded := false
	var deck := 1.0
	if weather != null:
		bounds = weather.get_occupancy_bounds()
		# Broad global bounds cost more than they reject. Compile the checks out
		# for those maps; a missing storm family still saves high-shell traversal.
		var minimum := bounds[0].min(bounds[2])
		var maximum := bounds[1].max(bounds[3])
		var size := maximum - minimum
		bounded = bounds[2].x > bounds[3].x or size.x * size.y * size.z < 4.0
		# At very distant cameras, cancellation in ray/sphere intersections and
		# transformed origins can exceed the tight outward padding. Use the full
		# original traversal there instead of risking a false empty intersection.
		bounded = bounded and observer.length() <= radius * 0.001 * 4.0
	_select_shader(material_override as ShaderMaterial, CLOUD_SHADER, bounded)
	_select_shader(_lowres_material, LOWRES_SHADER, bounded)

	_param("authored_weather", weather != null)
	_param("cloud_occupancy_enabled", bounded)
	if weather != null:
		# The resource owns the ImageTexture and only uploads changed pixels.
		# Flight and editor previews share it without reading back GPU images.
		_param("cloud_weather_map", weather.get_texture())
		var bottom := height - thickness * 0.5
		var storm_thickness := maxf(thickness, minf(10000.0, atmosphere_height * 0.88 - bottom))
		deck = thickness / storm_thickness
		_param("cloud_deck_fraction", deck)
		# Direction bounds include the entire linearly filtered weather footprint.
		# Scale both ends of each component over the family's full radial shell.
		if bounded:
			_bind_bounds("cloud_low", bounds[0], bounds[1], (radius + bottom) * 0.001, (radius + bottom + thickness) * 0.001)
			_bind_bounds("cloud_storm", bounds[2], bounds[3], (radius + bottom) * 0.001, (radius + bottom + storm_thickness) * 0.001)
		height = bottom + storm_thickness * 0.5
		thickness = storm_thickness
	else:
		_param("cloud_weather_map", null)
		_param("cloud_deck_fraction", 1.0)
	_param("BODY_RADIUS", radius * 0.001)
	_param("AIR_RADIUS", (radius + atmosphere_height) * 0.001)
	_param("cloud_height_km", height * 0.001)
	_update_altitude_scale(observer.length() * 1000.0 - radius - (height + thickness * 0.5))
	_param("cloud_thickness_km", thickness * 0.001)
	_param("atmosphere_density_scale", float(definition.atmosphere_visual_density))
	_param("camera_planet_km", observer)
	_param("sun_direction", sunlight)
	# The drift rotation moves the occupancy bounds, weather map and noise
	# together, so the whole sky advects rigidly without shader-side seams.
	var to_local := ((get_parent() as Node3D).global_basis * _drift).transposed()
	_param("cloud_world_to_local", to_local)
	var evolution := float(definition.get("cloud_evolution") if definition.get("cloud_evolution") != null else 0.0)
	var evolution_offset := Vector3(0.19, 0.11, -0.15) * (evolution * weather_time)
	_param("cloud_evolution_offset", evolution_offset)
	var coverage := 0.56
	var density_scale := 1.0
	if definition.get("cloud_coverage") != null:
		coverage = float(definition.cloud_coverage)
		density_scale = float(definition.cloud_density)
		_param("cloud_coverage", coverage)
		_param("cloud_density_scale", density_scale)
	# Without storm paint nothing exists above the low deck; CPU marches stop there.
	var has_storms := weather == null or bounds[2].x <= bounds[3].x
	_shade_weather = weather
	_shade_ground = radius * 0.001
	_shade_bottom = (radius + height - thickness * 0.5) * 0.001
	_shade_top = (radius + height - thickness * 0.5 + (thickness if has_storms else thickness * deck)) * 0.001
	_shade_thickness = thickness * 0.001
	_shade_deck = deck
	_shade_to_local = to_local
	_shade_evolution = evolution_offset
	_shade_coverage = coverage
	_shade_density_scale = density_scale
	_shade_sun = sunlight
	_shade_ready = true
	_sync_lowres()

## Swaps between the plain and occupancy-bounded variants, leaving any other
## shader a tool has installed untouched.
func _select_shader(material: ShaderMaterial, base: Shader, bounded: bool) -> void:
	if material.shader != base and material.shader != _bounded(base):
		return
	material.shader = _bounded(base) if bounded else base

func _bind_bounds(prefix: String, minimum: Vector3, maximum: Vector3, inner: float, outer: float) -> void:
	if minimum.x > maximum.x:
		_param(prefix + "_min", Vector3.ONE)
		_param(prefix + "_max", -Vector3.ONE)
		return
	# Outward rounding also covers float matrix/intersection arithmetic at grazing
	# rays. False positives only do extra work; no density or opacity is changed.
	var padding := Vector3.ONE * maxf(0.002, outer * 0.000002)
	_param(prefix + "_min", (minimum * inner).min(minimum * outer) - padding)
	_param(prefix + "_max", (maximum * inner).max(maximum * outer) + padding)

## Fraction of direct sunlight reaching a point (planet frame, km) through the
## cloud volume: the CPU counterpart of the shader's sun_optical_depth, marched
## along the whole sun ray so vessels darken under and inside cloud. Uses the
## same coarse-shadow density (no fine erosion) and the close-range billows.
func sun_transmittance(point: Vector3) -> float:
	if not _shade_ready or not _noise_ready():
		return 1.0
	var sun: Vector3 = _shade_sun
	var bottom: float = _shade_bottom
	var thickness: float = _shade_thickness
	var top: float = _shade_top
	var outer := _sphere_exit(point, sun, top)
	if outer <= 0.0:
		return 1.0
	# Below the deck the sun ray first crosses clear air.
	var start := 0.0
	if point.length() < bottom:
		start = _sphere_exit(point, sun, bottom)
	elif point.length() > top:
		# Above the deck only a sun below the local horizontal re-enters it.
		start = 2.0 * -point.dot(sun) - outer
	# Toward a sun near the horizon the ray grazes a long way through the
	# shell; the light is mostly eclipsed by then, so cap the work there.
	var end := minf(outer, start + SUN_STEP_KM * SUN_MAX_STEPS)
	if end <= start:
		return 1.0
	var authored: bool = _shade_weather != null
	var extinction: float = _shade_density_scale * (1.2 if authored else 3.0)
	var optical := 0.0
	for cell in _grid_cells(start, end, SUN_STEP_KM):
		var sample := point + sun * cell.x
		var height := (sample.length() - bottom) / thickness
		if height < 0.0 or height >= 1.0:
			continue
		optical += _formation(sample, height, authored).x * cell.y
		if optical * extinction > 5.0:
			return 0.0
	return exp(-optical * extinction)

## Cells of a fixed grid along a ray (distance multiples of step from its
## origin) that overlap [start, end]: x is the sample distance, y the overlap
## length. Samples stay put while the segment ends move, and partial cells fade
## in and out, so a sweeping sun or drifting deck cannot pop samples on or off.
static func _grid_cells(start: float, end: float, step: float) -> PackedVector2Array:
	var cells := PackedVector2Array()
	var index := floori(start / step)
	while float(index) * step < end:
		var a := maxf(float(index) * step, start)
		var b := minf(float(index + 1) * step, end)
		if b > a:
			cells.append(Vector2((float(index) + 0.5) * step, b - a))
		index += 1
	return cells

## Far intersection of a ray with a planet-centred sphere, or -1 for a miss.
static func _sphere_exit(origin: Vector3, ray: Vector3, radius: float) -> float:
	var b := origin.dot(ray)
	var c := origin.length_squared() - radius * radius
	var h := b * b - c
	return -b + sqrt(h) if h >= 0.0 else -1.0

## Density, local lighting height and storm proportion, as sample_formation()
## returns them in the shader with fine erosion off.
func _formation(point: Vector3, height: float, authored: bool) -> Vector3:
	var p: Vector3 = _shade_to_local * point
	var evolution: Vector3 = _shade_evolution
	if not authored:
		var weather := _noise((p + evolution * 0.35) / 360.0)
		var billow := _noise((p + evolution) / 16.0)
		var field := weather * 0.48 + billow * 0.52 - 0.05
		var threshold: float = 0.73 - _shade_coverage * 0.55
		var top := lerpf(0.45, 1.0, smoothstep(0.35, 0.70, billow))
		return Vector3(smoothstep(threshold, threshold + 0.18, field) * smoothstep(0.0, 0.14, height) * (1.0 - smoothstep(top * 0.45, top, height)), height, 0.0)
	var weights: Color = _shade_weather.sample_direction(p)
	if weights.r + weights.g + weights.b + weights.a < 0.002:
		return Vector3.ZERO
	var deck: float = maxf(_shade_deck, 0.001)
	if height >= deck and weights.a == 0.0:
		return Vector3.ZERO
	var billow := _noise((p + evolution) / 16.0)
	var low := height / deck
	var puff_top := 1.0
	var cell_top := 1.0
	var sheet_top := 1.0
	var families := Vector3.ZERO
	if low < 1.0 and weights.r + weights.g + weights.b > 0.0:
		var outline := Vector3(weights.r, weights.g, weights.b)
		var edge := Vector3.ONE * billow + (outline - Vector3.ONE * 0.5) * Vector3(0.8, 0.9, 1.2)
		var amount := Vector3(
			smoothstep(0.0, 0.06, outline.x) * lerpf(0.35, 1.0, outline.x) * smoothstep(0.2, 0.6, edge.x),
			smoothstep(0.0, 0.06, outline.y) * lerpf(0.35, 1.0, outline.y) * smoothstep(0.2, 0.6, edge.y),
			smoothstep(0.0, 0.06, outline.z) * lerpf(0.35, 1.0, outline.z) * smoothstep(0.2, 0.6, edge.z))
		puff_top = lerpf(0.46, 1.0, smoothstep(0.30, 0.73, billow))
		families.x = amount.x * smoothstep(0.0, 0.11, low) * (1.0 - smoothstep(puff_top * 0.48, puff_top, low))
		cell_top = lerpf(0.40, 0.66, billow)
		families.y = amount.y * smoothstep(0.03, 0.13, low) * (1.0 - smoothstep(cell_top * 0.62, cell_top, low))
		sheet_top = 0.33 + billow * 0.08
		families.z = amount.z * smoothstep(0.02, 0.10, low) * (1.0 - smoothstep(sheet_top - 0.12, sheet_top, low))
	var tower := 0.0
	if weights.a > 0.0:
		var cap_height := (height - 0.76) / (0.20 + billow * 0.06)
		var cap_width := (0.82 + billow * 0.08) * sqrt(maxf(0.0, 1.0 - cap_height * cap_height))
		var stem_width := (0.22 + billow * 0.06) * (1.0 - smoothstep(0.69, 0.86, height))
		var tower_width := maxf(stem_width, cap_width)
		tower = smoothstep((1.0 - tower_width) * 0.7 - 0.06, (1.0 - tower_width) * 0.7 + 0.08, weights.a + (billow - 0.5) * 0.20) \
			* smoothstep(0.0, 0.04, height) * (1.0 - smoothstep(0.96, 0.99, height))
		tower *= smoothstep(0.0, 0.08, weights.a)
		tower = maxf(tower, weights.a * 0.025 * smoothstep(0.0, 0.06, height) * (1.0 - smoothstep(0.85, 1.0, height))) * 1.12
	var density := families.x + families.y + families.z + tower
	if density <= 0.0:
		return Vector3.ZERO
	var light_height := (families.x * clampf(low / puff_top, 0.0, 1.0) + families.y * clampf(low / cell_top, 0.0, 1.0)
		+ families.z * clampf(low / sheet_top, 0.0, 1.0) + tower * clampf(height / 0.99, 0.0, 1.0)) / density
	return Vector3(density, light_height, tower / density)

## Glow of the surrounding cloud as the shader lights it, for ambient light:
## RGB is the mean radiance of the cloud seen around a point, A the fraction of
## those views that cloud fills. Sunset decks glow red, shaded bases grey.
## One of GLOW_DIRECTIONS views is re-traced per call (all of them with
## refresh_all), so the estimate costs a few dozen samples per frame.
func cloud_glow(point: Vector3, refresh_all: bool = false) -> Color:
	if not _shade_ready or not _noise_ready():
		_glow_views.clear()
		return Color(0, 0, 0, 0)
	if _glow_views.size() != GLOW_DIRECTIONS.size():
		_glow_views.resize(GLOW_DIRECTIONS.size())
		_glow_views.fill(Color(0, 0, 0, 0))
		refresh_all = true
	# Build the view frame in the clouds' own space, so planet spin and wind
	# drift carry the views with the weather instead of sweeping them across it.
	var to_local: Basis = _shade_to_local
	var up := (to_local * point).normalized()
	var east := up.cross(Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP).normalized()
	var frame := to_local.transposed() * Basis(east, up, east.cross(up))
	for i in range(GLOW_DIRECTIONS.size() if refresh_all else GLOW_VIEWS_PER_CALL):
		var index := i if refresh_all else _glow_cursor
		_glow_views[index] = _trace_glow(point, (frame * GLOW_DIRECTIONS[index]).normalized())
		if not refresh_all:
			_glow_cursor = (_glow_cursor + 1) % GLOW_DIRECTIONS.size()
	var total := Color(0, 0, 0, 0)
	for view in _glow_views:
		total += Color(view.r * view.a, view.g * view.a, view.b * view.a, view.a)
	if total.a <= 0.0:
		return Color(0, 0, 0, 0)
	return Color(total.r / total.a, total.g / total.a, total.b / total.a, total.a / float(GLOW_DIRECTIONS.size()))

## Opacity-weighted cloud light along one view ray (unmultiplied RGB, A opacity).
func _trace_glow(origin: Vector3, ray: Vector3) -> Color:
	var bottom: float = _shade_bottom
	var thickness: float = _shade_thickness
	var shell_top: float = _shade_top
	var outer := _sphere_exit(origin, ray, shell_top)
	if outer <= 0.0:
		return Color(0, 0, 0, 0)
	var start := 0.0
	if origin.length() < bottom:
		start = _sphere_exit(origin, ray, bottom)
	elif origin.length() > shell_top:
		start = 2.0 * -origin.dot(ray) - outer
	var end := minf(outer, start + GLOW_RANGE_KM)
	# The ground hides cloud beyond it.
	var b := origin.dot(ray)
	var ground: float = _shade_ground
	var h := b * b - origin.length_squared() + ground * ground
	if h >= 0.0 and -b - sqrt(h) > 0.0:
		end = minf(end, -b - sqrt(h))
	if end <= start:
		return Color(0, 0, 0, 0)
	var authored: bool = _shade_weather != null
	var extinction: float = _shade_density_scale * (1.2 if authored else 3.0)
	var sun: Vector3 = _shade_sun
	var sun_cos := ray.dot(sun)
	var phase := lerpf(_hg_phase(sun_cos, -0.2), _hg_phase(sun_cos, 0.5), 0.5)
	var remaining := 1.0
	var color := Vector3.ZERO
	for cell in _grid_cells(start, end, GLOW_STEP_KM):
		var sample := origin + ray * cell.x
		var radius := sample.length()
		var height := (radius - bottom) / thickness
		if height < 0.0 or height >= 1.0:
			continue
		var formation := _formation(sample, height, authored)
		var density: float = formation.x * _shade_density_scale
		if density <= 0.0:
			continue
		var opacity := 1.0 - exp(-density * cell.y * (1.2 if authored else 3.0))
		var sun_height := (sample / radius).dot(sun)
		var horizon := -sqrt(maxf(0.0, 1.0 - pow(bottom / radius, 2.0)))
		var daylight := smoothstep(horizon - 0.025, horizon + 0.045, sun_height)
		var top := lerpf(_shade_deck, 1.0, formation.z)
		var sun_shadow := 0.0
		if daylight > 0.0:
			# The shader's single midpoint tap toward the sun (sun_optical_depth).
			var column := minf(maxf(top - height, 0.02) / maxf(sun_height, 0.2), top * 1.5) * thickness
			var tap := sample + sun * (column * 0.5)
			var tap_height := (tap.length() - bottom) / thickness
			var depth := _formation(tap, tap_height, authored).x if tap_height < 1.0 and tap_height >= 0.0 else 0.0
			sun_shadow = exp(-depth * column * extinction)
		var sunset := 1.0 - smoothstep(0.0, 0.28, maxf(sun_height, 0.0))
		var sunlight := Vector3(1.0, 0.98, 0.94).lerp(Vector3(1.0, 0.36, 0.12), sunset)
		var light_height := clampf(formation.y, 0.0, 1.0)
		var ambient := Vector3(0.002, 0.003, 0.006) \
			+ Vector3(0.14, 0.19, 0.27) * daylight * lerpf(0.5, 1.15, maxf(light_height, 1.0 - density)) \
			+ Vector3(0.07, 0.06, 0.045) * daylight * maxf(sun_height, 0.0) * (1.0 - light_height)
		var direct := sun_shadow * (0.15 + 0.55 * phase) + 0.2 * pow(sun_shadow, 0.25)
		color += (ambient + sunlight * daylight * direct) * remaining * opacity
		remaining *= 1.0 - opacity
		if remaining < 0.025:
			break
	var alpha := 1.0 - remaining
	if alpha < 0.005:
		return Color(0, 0, 0, 0)
	return Color(color.x / alpha, color.y / alpha, color.z / alpha, alpha)

## Henyey-Greenstein, scaled so an isotropic medium scatters 1.0.
static func _hg_phase(cos_angle: float, g: float) -> float:
	return (1.0 - g * g) / pow(maxf(1.0 + g * g - 2.0 * g * cos_angle, 1e-4), 1.5)

## The volume noise is regenerated on the CPU from the same FastNoiseLite
## settings; NoiseTexture3D keeps its texels on the GPU only. Built once on a
## worker; until it lands, sunlight is simply unshadowed.
static func _start_noise_mirror() -> void:
	if _noise_task >= 0:
		return
	_noise_task = WorkerThreadPool.add_task(_build_noise_mirror)

static func _build_noise_mirror() -> void:
	var texture: NoiseTexture3D = preload("res://assets/cloud_volume_noise.tres")
	var noise: Noise = texture.noise
	var size := Vector3i(texture.width, texture.height, texture.depth)
	var slices: Array[Image]
	if texture.seamless:
		slices = noise.get_seamless_image_3d(size.x, size.y, size.z, texture.invert, texture.seamless_blend_skirt, texture.normalize)
	else:
		slices = noise.get_image_3d(size.x, size.y, size.z, texture.invert, texture.normalize)
	var bytes := PackedByteArray()
	for slice in slices:
		if slice.get_format() != Image.FORMAT_L8:
			slice.convert(Image.FORMAT_L8)
		bytes.append_array(slice.get_data())
	_noise_bytes = bytes
	_noise_size = size

static func _noise_ready() -> bool:
	if _noise_task < 0:
		_start_noise_mirror()
	if _noise_size == Vector3i.ZERO and WorkerThreadPool.is_task_completed(_noise_task):
		WorkerThreadPool.wait_for_task_completion(_noise_task)
	return _noise_size != Vector3i.ZERO

## Trilinear, repeating lookup matching texture(cloud_noise, uvw).
static func _noise(uvw: Vector3) -> float:
	var size := _noise_size
	var f := uvw * Vector3(size) - Vector3.ONE * 0.5
	var base := f.floor()
	var t := f - base
	var x0 := posmod(int(base.x), size.x)
	var y0 := posmod(int(base.y), size.y)
	var z0 := posmod(int(base.z), size.z)
	var x1 := (x0 + 1) % size.x
	var y1 := (y0 + 1) % size.y
	var z1 := (z0 + 1) % size.z
	var row := size.x
	var slice := size.x * size.y
	var c00 := lerpf(_noise_bytes[z0 * slice + y0 * row + x0], _noise_bytes[z0 * slice + y0 * row + x1], t.x)
	var c10 := lerpf(_noise_bytes[z0 * slice + y1 * row + x0], _noise_bytes[z0 * slice + y1 * row + x1], t.x)
	var c01 := lerpf(_noise_bytes[z1 * slice + y0 * row + x0], _noise_bytes[z1 * slice + y0 * row + x1], t.x)
	var c11 := lerpf(_noise_bytes[z1 * slice + y1 * row + x0], _noise_bytes[z1 * slice + y1 * row + x1], t.x)
	return lerpf(lerpf(c00, c10, t.y), lerpf(c01, c11, t.y), t.z) / 255.0
