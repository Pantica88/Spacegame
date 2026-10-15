extends Node3D
## Volumetric clouds for one planet (docs/CLOUDS.md).
##
## The field (assets/shaders/cloud_field.gdshaderinc) turns the planet's
## painted or procedural weather into density and light. cloud_render_pass.gd
## marches it on the GPU at half resolution before the transparent pass and
## keeps a temporal history; a screen triangle with cloud_composite.gdshader
## upsamples the result over the scene. The ocean mirrors the same field, and
## cloud_field.gd evaluates it on the CPU to light vessels.
##
## Parent this node to the planet: the parent's origin is the planet centre
## and its rotation carries the weather. update_weather() supplies the rest.

const CloudField = preload("res://scripts/cloud_field.gd")
const AtmosphereQuality = preload("res://scripts/atmosphere_quality.gd")
const RenderPass = preload("res://scripts/cloud_render_pass.gd")
const COMPOSITE_SHADER = preload("res://assets/shaders/cloud_composite.gdshader")

## Composite over the distant sun (0) and ocean (-1), before nearby exhaust and heat (2).
const RENDER_PRIORITY := 1
## Billow evolution: noise drift in km per second at evolution 1.
const EVOLUTION_RATE := 0.004
## Views around a vessel that cloud_glow() traces (local frame, Y up): the
## zenith, rings at 50, 12 and -30 degrees elevation, and the nadir.
const GLOW_DIRECTIONS: Array[Vector3] = [
	Vector3(0.0, 1.0, 0.0),
	Vector3(0.643, 0.766, 0.0), Vector3(-0.321, 0.766, 0.557), Vector3(-0.321, 0.766, -0.557),
	Vector3(0.978, 0.208, 0.0), Vector3(0.489, 0.208, 0.847), Vector3(-0.489, 0.208, 0.847),
	Vector3(-0.978, 0.208, 0.0), Vector3(-0.489, 0.208, -0.847), Vector3(0.489, 0.208, -0.847),
	Vector3(0.433, -0.5, 0.75), Vector3(-0.866, -0.5, 0.0), Vector3(0.433, -0.5, -0.75),
	Vector3(0.0, -1.0, 0.0),
]
const GLOW_RANGE_KM := 5.0
const GLOW_SAMPLES := 10

## Seconds of simulated weather; the editor raises time_scale for time-lapse.
var weather_time := 0.0
var time_scale := 1.0
## Sample-count colours instead of light (render_cost_overlay.gd, F9).
var cost_view := false:
	set(value):
		cost_view = value
		composite_material.set_shader_parameter("cost_view", value)
		if _pass != null: _pass.cost_view = value
## CPU copy of the field, kept in step with the shader uniforms.
var field := CloudField.new()
var composite: MeshInstance3D
var composite_material := ShaderMaterial.new()

var _pass: RenderPass
var _compositor := Compositor.new()
var _camera: Camera3D
var _reflections: Array[ShaderMaterial] = []
## PROTOTYPE: terrain materials darkened under the clouds. Off by default
## until the ocean patch takes the shadow too (about 0.3-0.6 ms on the RX 580).
var _shadow_receivers: Array[ShaderMaterial] = []
var ground_shadows := false
var _drift := Basis.IDENTITY
var _has_clouds := false
var _world_to_cloud := Basis.IDENTITY
var _glow_views: Array[Color] = []
var _glow_cursor := 0
var _prewarming := false
var _bound_targets := -1

func _init() -> void:
	name = "CloudLayer"
	# Weather keeps its own clock (paused trees freeze it below), but the
	# march must follow the camera while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	composite_material.shader = COMPOSITE_SHADER
	composite_material.render_priority = RENDER_PRIORITY
	# Haze over the clouds: a short view integration; sunlight comes from the
	# sky's own optical-depth table (set in update_weather), so it is tinted alike.
	composite_material.set_shader_parameter("atmosphere_view_samples", 4)
	composite_material.set_shader_parameter("atmosphere_light_samples", 6)
	composite = MeshInstance3D.new()
	composite.name = "CloudComposite"
	composite.mesh = _screen_triangle()
	# Its vertex shader covers the screen from any camera; never cull it.
	composite.custom_aabb = AABB(Vector3.ONE * -1.0e12, Vector3.ONE * 2.0e12)
	composite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	composite.top_level = true
	composite.material_override = composite_material
	composite.visible = false
	add_child(composite, false, Node.INTERNAL_MODE_FRONT)
	if RenderPass.supported():
		_pass = RenderPass.new()
		_pass.shape_texture = CloudField.shape_texture()
		_pass.detail_texture = CloudField.detail_texture()
		_compositor.compositor_effects = [_pass]

func _enter_tree() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(_before_draw):
		RenderingServer.frame_pre_draw.connect(_before_draw)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_before_draw):
		RenderingServer.frame_pre_draw.disconnect(_before_draw)
	_attach(null)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _pass != null:
		composite_material.set_shader_parameter("cloud_light", null)
		composite_material.set_shader_parameter("cloud_depth", null)
		_pass.release()

static func _screen_triangle() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(3, -1, 0), Vector3(-1, 3, 0)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Cloud base, top of the low formations and top of storms, in metres above
## sea level. Scaled to the atmosphere, and lifted over high relief.
static func heights(definition: Resource) -> Vector3:
	var air := float(definition.atmosphere_height)
	var base := clampf(maxf(air * 0.03, float(definition.relief) * 0.5), 600.0, 6000.0)
	var low_top := base + clampf(air * 0.025, 600.0, 3000.0)
	var top := maxf(minf(base + clampf(air * 0.13, 2000.0, 13000.0), air * 0.6), low_top + 500.0)
	return Vector3(base, low_top, top)

func _process(delta: float) -> void:
	if not get_tree().paused:
		weather_time += delta * time_scale
	if _pass == null: return
	# The pass reports the scene size it is asked to draw; until it has, the
	# viewport's own size is the best guess.
	var scene := _pass.observed_scene_size
	if scene == Vector2i.ZERO:
		var view := get_viewport()
		scene = Vector2i(Vector2(view.get_visible_rect().size) * float(view.scaling_3d_scale))
	_pass.ensure_targets(scene)
	if _bound_targets != _pass.targets_revision:
		_bound_targets = _pass.targets_revision
		composite_material.set_shader_parameter("cloud_light", _pass.light_texture)
		composite_material.set_shader_parameter("cloud_depth", _pass.depth_texture)

## Whether the last update_weather() found cloud to draw.
func has_clouds() -> bool:
	return _has_clouds

## Whether the clouds are being drawn for the current view.
func is_drawing() -> bool:
	return _pass != null and _pass.enabled and composite.visible

## The GPU pass, for diagnostics; null where compute is unavailable.
func render_pass() -> RenderPass:
	return _pass

## Attach the march to whatever camera the viewport is about to draw with,
## and fix the cloud frame for this frame from the final transforms.
func _before_draw() -> void:
	if not is_inside_tree(): return
	var camera := get_viewport().get_camera_3d()
	var drawing := _pass != null and _has_clouds and is_visible_in_tree() and is_instance_valid(camera) \
		and not get_viewport().disable_3d
	_attach(camera if drawing else null)
	if _pass != null:
		_pass.enabled = drawing
	composite.visible = drawing or _prewarming
	composite_material.set_shader_parameter("cloud_ready", drawing and _pass.is_ready() and _pass.dispatched > 0)
	if not drawing: return
	var planet := get_parent() as Node3D
	_pass.planet_origin = planet.global_position if planet != null else Vector3.ZERO
	_pass.world_to_cloud = _cloud_frame()

func _cloud_frame() -> Basis:
	var planet := get_parent() as Node3D
	var spin := planet.global_basis.orthonormalized() if planet != null else Basis.IDENTITY
	return (spin * _drift).inverse()

func _attach(camera: Camera3D) -> void:
	if camera == _camera: return
	if is_instance_valid(_camera):
		if _camera.compositor == _compositor:
			_camera.compositor = null
		elif _camera.compositor != null and _camera.compositor.compositor_effects.has(_pass):
			var kept := _camera.compositor.compositor_effects.duplicate()
			kept.erase(_pass)
			_camera.compositor.compositor_effects = kept
	_camera = null
	if camera == null or _pass == null: return
	# A camera keeps any compositor of its own; the march joins its effects.
	if camera.compositor == null:
		camera.compositor = _compositor
	elif not camera.compositor.compositor_effects.has(_pass):
		var effects := camera.compositor.compositor_effects.duplicate()
		effects.append(_pass)
		camera.compositor.compositor_effects = effects
	_camera = camera
	_pass.reset_history()

## Lets a material that includes cloud_field.gdshaderinc mirror the clouds.
func add_reflection(target: ShaderMaterial) -> void:
	target.set_shader_parameter("cloud_shape_noise", CloudField.shape_texture())
	target.set_shader_parameter("cloud_detail_noise", CloudField.detail_texture())
	_reflections.append(target)

## PROTOTYPE: lets a terrain material take the clouds' shadow.
func add_shadow_receiver(target: ShaderMaterial) -> void:
	target.set_shader_parameter("cloud_shape_noise", CloudField.shape_texture())
	target.set_shader_parameter("cloud_detail_noise", CloudField.detail_texture())
	_shadow_receivers.append(target)

## Rotation carrying weather-map space into planet-local space. Painting tools
## apply its inverse so strokes land under the cursor while the sky moves.
func drift_basis() -> Basis:
	return _drift

func _update_drift(definition: Resource) -> void:
	var speed := float(definition.get("cloud_wind_speed") if definition.get("cloud_wind_speed") != null else 0.0)
	if speed == 0.0 or float(definition.radius) <= 0.0:
		_drift = Basis.IDENTITY
		return
	# Heading 90 degrees blows east along the latitude bands: a spin about
	# the pole. Other headings tilt that axis toward the meridian.
	var heading := deg_to_rad(float(definition.cloud_wind_heading) - 90.0)
	var axis := Vector3(0.0, cos(heading), -sin(heading))
	_drift = Basis(axis, fmod(speed * weather_time / float(definition.radius), TAU))

## Sets the weather, the camera's position relative to the planet centre
## (km, world axes) and the sun direction (world axes). Clouds draw only
## when enabled and the body has air and cloud.
func update_weather(definition: Resource, observer: Vector3, sunlight: Vector3, enabled: bool) -> void:
	var radius := float(definition.radius)
	var atmosphere := float(definition.atmosphere_height)
	var weather: Resource = definition.get("cloud_weather")
	_update_drift(definition)
	_has_clouds = enabled and atmosphere > 0.0 and float(definition.atmosphere_visual_density) > 0.0 \
		and (weather == null or weather.has_clouds())
	for target in _reflections:
		target.set_shader_parameter("cloud_reflection_enabled", _has_clouds)
	for target in _shadow_receivers:
		target.set_shader_parameter("cloud_shadow_enabled", _has_clouds and ground_shadows and visible)
	if not _has_clouds:
		composite.visible = false
		if _pass != null: _pass.enabled = false
		return
	var h := heights(definition)
	var coverage := float(definition.get("cloud_coverage") if definition.get("cloud_coverage") != null else 0.56)
	var density := float(definition.get("cloud_density") if definition.get("cloud_density") != null else 1.0)
	var evolution := float(definition.get("cloud_evolution") if definition.get("cloud_evolution") != null else 0.0)
	field.radii = Vector4(radius, radius + h.x, radius + h.y, radius + h.z) * 0.001
	# Procedural weather has no storms; painted maps say whether they do.
	var storms := weather != null and _has_storms(weather)
	field.params = Vector4(coverage, density, 1.0 if weather != null else 0.0, 1.0 if storms else 0.0)
	field.evolution = Vector3(0.62, 0.36, -0.49) * (evolution * EVOLUTION_RATE * weather_time)
	_world_to_cloud = _cloud_frame()
	field.sun = (_world_to_cloud * sunlight).normalized()
	field.air = Vector4(radius * 0.001, (radius + atmosphere) * 0.001, float(definition.atmosphere_visual_density), 0.0)
	field.weather = weather
	var values := {
		"cloud_radii": field.radii,
		"cloud_params": field.params,
		"cloud_evolution": Vector4(field.evolution.x, field.evolution.y, field.evolution.z, 0.0),
		"cloud_sun": Vector4(field.sun.x, field.sun.y, field.sun.z, 0.0),
		"cloud_air": field.air,
	}
	# The resource owns the ImageTexture and only uploads changed pixels.
	var weather_texture: Texture2D = weather.get_texture() if weather != null else null
	for target in _reflections + _shadow_receivers:
		for key in values: target.set_shader_parameter(key, values[key])
		target.set_shader_parameter("cloud_weather_map", weather_texture)
		target.set_shader_parameter("cloud_to_local", _world_to_cloud)
	# The composite hazes the clouds with the same air as the sky.
	if composite_material.get_shader_parameter("AIR_RADIUS") != field.air.y or composite_material.get_shader_parameter("BODY_RADIUS") != field.air.x:
		AtmosphereQuality.apply_sun_depth_table(composite_material, field.air.x, field.air.y, 6)
	composite_material.set_shader_parameter("BODY_RADIUS", field.air.x)
	composite_material.set_shader_parameter("AIR_RADIUS", field.air.y)
	composite_material.set_shader_parameter("atmosphere_density_scale", field.air.z)
	composite_material.set_shader_parameter("camera_planet_km", observer)
	composite_material.set_shader_parameter("sun_direction", sunlight)
	if _pass != null:
		var packed := PackedFloat32Array()
		for key in ["cloud_radii", "cloud_params", "cloud_evolution", "cloud_sun", "cloud_air"]:
			var v: Vector4 = values[key]
			packed.append_array([v.x, v.y, v.z, v.w])
		_pass.field_values = packed
		_pass.weather_texture = weather_texture
		_pass.march_top_km = field.radii.w if storms else field.radii.z

static func _has_storms(weather: Resource) -> bool:
	var bounds: PackedVector3Array = weather.get_occupancy_bounds()
	return bounds.size() >= 4 and bounds[2].x <= bounds[3].x

## Fraction of direct sunlight reaching a point (km from the planet centre,
## world axes) through the clouds, so vessels darken under and inside them.
func sun_transmittance(point: Vector3) -> float:
	if not _has_clouds: return 1.0
	return field.sun_transmittance(_world_to_cloud * point)

## Light of the surrounding cloud for a vessel's ambient: RGB the mean light
## of the cloud seen around the point, A the share of views it fills. One of
## GLOW_DIRECTIONS is traced per call (all of them with refresh_all).
func cloud_glow(point: Vector3, refresh_all: bool = false) -> Color:
	if not _has_clouds:
		_glow_views.clear()
		return Color(0, 0, 0, 0)
	if _glow_views.size() != GLOW_DIRECTIONS.size():
		_glow_views.resize(GLOW_DIRECTIONS.size())
		_glow_views.fill(Color(0, 0, 0, 0))
		refresh_all = true
	# The views turn with the weather, so planet spin and drift carry them
	# along instead of sweeping them across the clouds.
	var p := _world_to_cloud * point
	var up := p.normalized()
	var east := up.cross(Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP).normalized()
	var frame := Basis(east, up, east.cross(up))
	for i in range(GLOW_DIRECTIONS.size() if refresh_all else 1):
		var index := i if refresh_all else _glow_cursor
		_glow_views[index] = field.trace(p, (frame * GLOW_DIRECTIONS[index]).normalized(), GLOW_RANGE_KM, GLOW_SAMPLES)
		if not refresh_all:
			_glow_cursor = (_glow_cursor + 1) % GLOW_DIRECTIONS.size()
	var total := Color(0, 0, 0, 0)
	for view in _glow_views:
		total += Color(view.r * view.a, view.g * view.a, view.b * view.a, view.a)
	if total.a <= 0.0: return Color(0, 0, 0, 0)
	return Color(total.r / total.a, total.g / total.a, total.b / total.a, total.a / float(GLOW_DIRECTIONS.size()))

## Compiles the composite while the caller covers the view: the compute
## shaders compiled when the pass was made; a material compiles on first draw.
func prewarm() -> void:
	if _pass == null or DisplayServer.get_name() == "headless": return
	_prewarming = true
	await RenderingServer.frame_post_draw
	_prewarming = false
