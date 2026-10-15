extends SceneTree
## Cloud renderer regression (docs/CLOUDS.md).
##   Always: the CPU field (noise volumes, layer heights, each formation's
##   shape, weather and visibility rules).
##   With a GPU: the shared include run in a compute shader must agree with
##   the GDScript port, and the production world must draw the clouds over
##   the sky, behind near geometry, and the same moving as standing still.
## Run: tools/run.sh --headless --script res://tests/test_clouds.gd
##      tools/run.sh --resolution 1280x720 --script res://tests/test_clouds.gd

const Weather = preload("res://scripts/cloud_weather_map.gd")
const Definition = preload("res://scripts/planet_definition.gd")
const CloudLayer = preload("res://scripts/cloud_layer.gd")
const CloudField = preload("res://scripts/cloud_field.gd")
const Tiles = preload("res://scripts/cloud_brush_library.gd")
const FIELD_INCLUDE = preload("res://assets/shaders/cloud_field.gdshaderinc")
const HOVER = preload("res://scenes/hover_preview.tscn")
const PlanetSurface = preload("res://scripts/planet_surface.gd")

var failures: Array[String] = []
var notes: Array[String] = []
var measured: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _run() -> void:
	_test_noise()
	_test_heights()
	_test_visibility()
	_test_formations()
	_test_drift()
	if DisplayServer.get_name() != "headless" and RenderingServer.get_rendering_device() != null:
		_test_gpu_parity()
		await _test_rendering()
	else:
		notes.append("GPU checks skipped (headless)")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS: cloud noise volumes, layer heights, visibility, formation shapes and wind drift%s. %s" % [
			"; GPU field matches the CPU port; clouds draw over sky, behind near geometry, and steadily in motion" if notes.is_empty() else "", " ".join(notes)])
		for line in measured: print("  " + line)
	quit(0 if failures.is_empty() else 1)

func _definition(weather: Resource = null) -> Resource:
	var definition: Resource = Definition.new()
	definition.cloud_wind_speed = 0.0
	definition.cloud_evolution = 0.0
	definition.cloud_weather = weather
	return definition

func _painted(weights: Color, radius: float = 0.4, center: Vector3 = Vector3.UP) -> Resource:
	var weather: Resource = Weather.new()
	weather.initialize(256, 128)
	var tile := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	tile.fill(weights)
	weather.stamp(center, radius, tile, 1.0, 0.0, false, 0.2)
	return weather

## A field set up as the layer sets it for this definition.
func _field(definition: Resource) -> CloudField:
	var layer: Node3D = CloudLayer.new()
	root.add_child(layer)
	layer.update_weather(definition, Vector3.UP * 700.0, Vector3(0.3, 0.8, 0.5).normalized(), true)
	var field: CloudField = layer.field
	layer.free()
	return field

func _test_noise() -> void:
	var shape: Texture3D = CloudField.shape_texture()
	var detail: Texture3D = CloudField.detail_texture()
	check(shape.get_width() == 64 and shape.get_depth() == 64 and shape.has_mipmaps(), "Shape volume is 64^3 with mipmaps")
	check(detail.get_width() == 32 and detail.get_depth() == 32, "Detail volume is 32^3")
	var largest := 0.0
	for i in range(64):
		var uvw := Vector3(fmod(i * 0.137, 1.0), fmod(i * 0.291, 1.0), fmod(i * 0.517, 1.0))
		var a := CloudField.shape(uvw)
		for offset in [Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 2)]:
			var b := CloudField.shape(uvw + offset)
			largest = maxf(largest, absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b))
	check(largest < 1e-4, "Noise volumes repeat seamlessly (difference %.6f)" % largest)

func _test_heights() -> void:
	var definition := _definition()
	var h: Vector3 = CloudLayer.heights(definition)
	check(h.x > 0.0 and h.x < h.y and h.y < h.z, "Cloud base, low tops and storm tops are ordered (%s)" % h)
	check(h.z <= float(definition.atmosphere_height) * 0.6 + 1.0, "Storms stay well inside the atmosphere")
	definition.atmosphere_height = 20000.0
	var thin: Vector3 = CloudLayer.heights(definition)
	check(thin.z <= 12000.0 and thin.x < thin.y, "A thin atmosphere keeps a shallow cloud layer (%s)" % thin)
	definition.relief = 7000.0
	check(CloudLayer.heights(definition).x >= 3500.0, "High relief lifts the cloud base above the mountains")

func _test_visibility() -> void:
	var layer: Node3D = CloudLayer.new()
	root.add_child(layer)
	var definition := _definition(Weather.new())
	layer.update_weather(definition, Vector3.UP * 601.0, Vector3.UP, true)
	check(not layer.has_clouds(), "Empty painted weather draws nothing")
	definition.cloud_weather = _painted(Color(0, 0, 0, 1), 0.3)
	layer.update_weather(definition, Vector3.UP * 601.0, Vector3.UP, true)
	check(layer.has_clouds(), "Painting a storm shows the clouds at once")
	definition.cloud_weather.clear()
	layer.update_weather(definition, Vector3.UP * 601.0, Vector3.UP, true)
	check(not layer.has_clouds(), "Clearing the weather hides them again")
	definition.cloud_weather = null
	layer.update_weather(definition, Vector3.UP * 601.0, Vector3.UP, true)
	check(layer.has_clouds(), "Without a painted map the procedural weather shows")
	layer.update_weather(definition, Vector3.UP * 601.0, Vector3.UP, false)
	check(not layer.has_clouds(), "Disabled clouds draw nothing")
	definition.atmosphere_visual_density = 0.0
	layer.update_weather(definition, Vector3.UP * 601.0, Vector3.UP, true)
	check(not layer.has_clouds(), "Airless bodies have no clouds")
	layer.free()

## Fraction of sample columns over the painted cap with any cloud in them,
## and the mean density at a height fraction of the low formations.
func _columns(field: CloudField, height: float) -> Vector2:
	var covered := 0
	var total := 0.0
	var count := 0
	for i in range(160):
		var direction := Vector3(sin(i * 0.61) * 0.25, 1.0, cos(i * 0.83) * 0.25).normalized()
		var any := false
		for k in range(24):
			var r := field.radii.y + (field.radii.z - field.radii.y) * (k + 0.5) / 24.0
			var p := direction * r
			if field.coarse(p, r, field.weather_at(p)).x > 0.05: any = true
		if any: covered += 1
		var q := direction * (field.radii.y + (field.radii.z - field.radii.y) * height)
		total += field.coarse(q, q.length(), field.weather_at(q)).x
		count += 1
	return Vector2(covered / 160.0, total / count)

func _test_formations() -> void:
	var overcast := _columns(_field(_definition(_painted(Color(0, 0, 1, 0)))), 0.12)
	check(overcast.x > 0.98 and overcast.y > 0.6, "Overcast closes into a dense sheet (%s)" % overcast)
	var strato := _columns(_field(_definition(_painted(Color(0, 0.8, 0, 0)))), 0.15)
	check(strato.x > 0.55 and strato.x < 0.97, "Heavy stratocumulus is a deck with seams and holes (%.2f covered)" % strato.x)
	var light_cumulus := _columns(_field(_definition(_painted(Color(0.15, 0, 0, 0)))), 0.1)
	var heavy_cumulus := _columns(_field(_definition(_painted(Color(0.8, 0, 0, 0)))), 0.1)
	check(light_cumulus.x < heavy_cumulus.x and heavy_cumulus.x < 0.97 and light_cumulus.x > 0.0, "Cumulus thicken with paint but keep clear gaps (%.2f light, %.2f heavy)" % [light_cumulus.x, heavy_cumulus.x])
	var faint := _columns(_field(_definition(_painted(Color(0, 0, 0, 0.1)))), 0.5)
	check(faint.x == 0.0, "Faint storm paint makes no cloud (%.2f covered)" % faint.x)
	# A mushroom: a narrow stem under a wide cap.
	var weather: Resource = Weather.new()
	weather.initialize(512, 256)
	weather.stamp(Vector3.UP, 0.05, Tiles.tile("mushroom"), 1.0, 0.0, false, 0.3)
	var field := _field(_definition(weather))
	var stem := _radius(field, 0.3)
	var cap := _radius(field, 0.8)
	check(stem > 0.0 and cap > stem * 1.5, "Mushroom cap spreads well beyond its stem (stem %.4f, cap %.4f rad)" % [stem, cap])
	check(_radius(field, 0.99) == 0.0, "Nothing rises past the storm tops")

## Widest angular radius around +Y with storm cloud at a storm-height fraction.
func _radius(field: CloudField, height: float) -> float:
	var widest := 0.0
	var r := field.radii.y + (field.radii.w - field.radii.y) * height
	for ring in range(1, 60):
		var angle := 0.001 * ring
		for spoke in range(12):
			var direction := Basis(Vector3.UP, TAU * spoke / 12.0) * Vector3(sin(angle), cos(angle), 0.0)
			var p := direction * r
			if field.coarse(p, r, field.weather_at(p)).x > 0.1:
				widest = maxf(widest, angle)
	return widest

func _test_drift() -> void:
	var layer: Node3D = CloudLayer.new()
	root.add_child(layer)
	var definition := _definition(_painted(Color(0, 0.6, 0, 0)))
	definition.cloud_wind_speed = 30.0
	definition.cloud_wind_heading = 90.0
	layer.weather_time = 0.0
	layer.update_weather(definition, Vector3.UP * 700.0, Vector3.UP, true)
	check(layer.drift_basis().is_equal_approx(Basis.IDENTITY), "Weather starts undrifted")
	layer.weather_time = 3600.0
	layer.update_weather(definition, Vector3.UP * 700.0, Vector3.UP, true)
	var moved: Vector3 = layer.drift_basis() * Vector3.RIGHT
	var expected := 30.0 * 3600.0 / float(definition.radius)
	check(absf(moved.angle_to(Vector3.RIGHT) - expected) < 1e-4 and absf(moved.y) < 1e-6, "An eastward wind carries the weather along the latitude bands")
	check((layer.drift_basis() * Vector3.UP).is_equal_approx(Vector3.UP), "An eastward wind leaves the poles in place")
	layer.free()

## Runs the shader include in a compute shader and compares it with the
## GDScript port at points through a mixed painted sky.
func _test_gpu_parity() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		notes.append("GPU parity skipped (no local rendering device)")
		return
	var weather: Resource = Weather.new()
	weather.initialize(256, 128)
	var mixes := [Color(0.8, 0, 0, 0), Color(0, 0.8, 0, 0), Color(0, 0, 0.9, 0), Color(0, 0, 0, 1), Color(0.3, 0.3, 0.1, 0.3)]
	var centers: Array[Vector3] = []
	for i in mixes.size():
		var tile := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		tile.fill(mixes[i])
		centers.append(Basis(Vector3.UP, i * 1.2) * Vector3(0.5, 1.0, 0.0).normalized())
		weather.stamp(centers[i], 0.35, tile, 1.0)
	var definition := _definition(weather)
	definition.cloud_evolution = 0.5
	var layer: Node3D = CloudLayer.new()
	root.add_child(layer)
	layer.weather_time = 1234.0
	layer.update_weather(definition, Vector3.UP * 700.0, Vector3(0.3, 0.8, 0.5).normalized(), true)
	var field: CloudField = layer.field
	layer.free()
	var count := 512
	var points := PackedFloat32Array()
	var expected: Array[PackedFloat32Array] = []
	for i in count:
		# Inside each stamp, mostly through the low formations, some up to the storm tops.
		var center := centers[i % centers.size()]
		var direction := (center + Vector3(sin(i * 1.37), cos(i * 2.11), sin(i * 0.71)) * 0.25).normalized()
		var top := field.radii.z if i % 4 != 3 else field.radii.w
		var r := lerpf(field.radii.y - 0.05, top, fmod(i * 0.618034, 1.0))
		var p := direction * r
		points.append_array([p.x, p.y, p.z, 0.0])
		var w := field.weather_at(p)
		var c := field.coarse(p, r, w)
		var d := field.density_at(p, w, 1.0)
		var sun := field.sunlight_at(p)
		expected.append(PackedFloat32Array([w.r, w.g, w.b, w.a, c.x, c.y, c.z, c.w, d.x, d.y, 0.0, 0.0, sun.x, sun.y, sun.z, 0.0]))
	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = """
#version 450
#define CLOUD_COMPUTE
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std140) uniform CloudField {
	vec4 cloud_radii;
	vec4 cloud_params;
	vec4 cloud_evolution;
	vec4 cloud_sun;
	vec4 cloud_air;
};
layout(set = 0, binding = 1) uniform sampler3D cloud_shape_noise;
layout(set = 0, binding = 2) uniform sampler3D cloud_detail_noise;
layout(set = 0, binding = 3) uniform sampler2D cloud_weather_map;
layout(set = 0, binding = 4, std430) restrict readonly buffer Points { vec4 points[]; };
layout(set = 0, binding = 5, std430) restrict writeonly buffer Results { vec4 results[]; };
""" + FIELD_INCLUDE.code + """
void main() {
	uint i = gl_GlobalInvocationID.x;
	vec3 p = points[i].xyz;
	vec4 w = cloud_weather(p);
	float light_height;
	float d = cloud_density(p, w, 1.0, 0.0, light_height);
	results[i * 4u] = w;
	results[i * 4u + 1u] = cloud_coarse(p, length(p), w, 0.0);
	results[i * 4u + 2u] = vec4(d, light_height, 0.0, 0.0);
	results[i * 4u + 3u] = vec4(cloud_sunlight(p), 0.0);
}
"""
	var spirv := rd.shader_compile_spirv_from_source(source)
	check(spirv.compile_error_compute.is_empty(), "The field include compiles as compute GLSL: " + spirv.compile_error_compute)
	if not spirv.compile_error_compute.is_empty():
		rd.free()
		return
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	var values := PackedFloat32Array()
	for v: Vector4 in [field.radii, field.params, Vector4(field.evolution.x, field.evolution.y, field.evolution.z, 0.0),
			Vector4(field.sun.x, field.sun.y, field.sun.z, 0.0), field.air]:
		values.append_array([v.x, v.y, v.z, v.w])
	var ubo := rd.uniform_buffer_create(values.size() * 4, values.to_byte_array())
	var shape_rid := _volume(rd, load("res://assets/clouds/shape_noise.png"))
	var detail_rid := _volume(rd, load("res://assets/clouds/detail_noise.png"))
	var image: Image = weather.image
	var format := RDTextureFormat.new()
	format.width = image.get_width()
	format.height = image.get_height()
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var weather_rid := rd.texture_create(format, RDTextureView.new(), [image.get_data()])
	var state := RDSamplerState.new()
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	var sampler := rd.sampler_create(state)
	var input := rd.storage_buffer_create(points.size() * 4, points.to_byte_array())
	var output := rd.storage_buffer_create(count * 16 * 4)
	var uniforms: Array[RDUniform] = []
	var bindings := [[RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, [ubo]],
		[RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, [sampler, shape_rid]],
		[RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, [sampler, detail_rid]],
		[RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, [sampler, weather_rid]],
		[RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, [input]],
		[RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, [output]]]
	for binding in bindings.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = bindings[binding][0]
		uniform.binding = binding
		for id in bindings[binding][1]: uniform.add_id(id)
		uniforms.append(uniform)
	var uniform_set := rd.uniform_set_create(uniforms, shader, 0)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	rd.compute_list_dispatch(list, count / 64, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var results := rd.buffer_get_data(output).to_float32_array()
	# Filtering hardware rounds its weights to 8 bits; the smoothstep edges of
	# the formations then amplify that slightly. Lighting height is a ratio
	# of tiny numbers at a cloud's faint edge, so compare it inside cloud only.
	var worst_weather := 0.0
	var worst_density := 0.0
	var worst_height := 0.0
	var worst_sun := 0.0
	var outliers := 0
	var cloudy := 0
	for i in count:
		var cpu := expected[i]
		var gpu := results.slice(i * 16, i * 16 + 16)
		for k in 4: worst_weather = maxf(worst_weather, absf(gpu[k] - cpu[k]))
		for k in [12, 13, 14]: worst_sun = maxf(worst_sun, absf(gpu[k] - cpu[k]))
		for k in [4, 8]:
			var difference := absf(gpu[k] - cpu[k])
			worst_density = maxf(worst_density, difference)
			if difference > 0.05: outliers += 1
			if cpu[k] > 0.1: worst_height = maxf(worst_height, absf(gpu[k + 1] - cpu[k + 1]))
		if cpu[4] > 0.05: cloudy += 1
	check(cloudy > count / 8, "Parity points sample real cloud (%d of %d)" % [cloudy, count])
	check(worst_weather < 0.01, "GPU and CPU read the same weather (worst %.4f)" % worst_weather)
	check(worst_sun < 0.005, "GPU and CPU agree on sunlight (worst %.4f)" % worst_sun)
	check(outliers <= count / 50, "GPU and CPU agree on cloud density (%d beyond 0.05, worst %.3f)" % [outliers, worst_density])
	check(worst_height < 0.1, "GPU and CPU agree on lighting height inside cloud (worst %.3f)" % worst_height)
	measured.append("GPU/CPU field at %d points (%d in cloud): worst weather %.4f, sunlight %.4f, density %.3f (%d beyond 0.05), lighting height in cloud %.3f" % [count, cloudy, worst_weather, worst_sun, worst_density, outliers, worst_height])
	# Freeing the shader frees its pipeline and uniform set too.
	for rid in [shader, input, output, sampler, weather_rid, shape_rid, detail_rid, ubo]:
		rd.free_rid(rid)
	rd.free()

static func _volume(rd: RenderingDevice, atlas: Image) -> RID:
	atlas.convert(Image.FORMAT_RGBA8)
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	format.width = atlas.get_width()
	format.height = atlas.get_width()
	format.depth = atlas.get_width()
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	return rd.texture_create(format, RDTextureView.new(), [atlas.get_data()])

func _grab(frames: int) -> Image:
	for i in frames: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

static func _difference(a: Image, b: Image, region: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(region.position.y, region.end.y, 3):
		for x in range(region.position.x, region.end.x, 3):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			total += (absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)) / 3.0
			count += 1
	return total / maxf(count, 1.0)

func _test_rendering() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var definition: Resource = PlanetSurface.home().definition
	var original: Resource = definition.cloud_weather
	# Stratocumulus overhead, so every view from the pad looks into cloud.
	var up: Vector3 = PlanetSurface.LAUNCH_RADIAL.normalized()
	definition.cloud_weather = _painted(Color(0, 0.8, 0, 0), 0.3, up)
	var hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	hover.hover_position = Vector3(0, 300, 0)
	hover.hover_yaw = 0.4
	hover.hover_pitch = 0.5
	var cloudy: Image = await _grab(40)
	check(hover._clouds.is_drawing() and hover._clouds.render_pass().dispatched > 0, "The cloud march runs for the flight camera")
	hover._clouds.hide()
	var clear: Image = await _grab(10)
	var full := Rect2i(Vector2i.ZERO, cloudy.get_size())
	var shown := _difference(cloudy, clear, full)
	check(shown > 0.05, "Clouds overhead change the view (mean difference %.4f)" % shown)
	measured.append("Clouds overhead vs hidden: mean difference %.4f" % shown)
	var finite := true
	for y in range(0, cloudy.get_height(), 7):
		for x in range(0, cloudy.get_width(), 7):
			var c := cloudy.get_pixel(x, y)
			finite = finite and is_finite(c.r) and is_finite(c.g) and is_finite(c.b)
	check(finite, "Every cloud pixel is finite")
	# A wall 40 m ahead covering the left of the view hides the clouds there.
	hover._clouds.show()
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40, 40, 1)
	wall.mesh = box
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color(0.9, 0.1, 0.1)
	wall.material_override = paint
	root.add_child(wall)
	var camera: Camera3D = hover.camera
	wall.global_transform = Transform3D(camera.global_basis, camera.global_position + camera.global_basis * Vector3(-20.5, 0, -40))
	var walled: Image = await _grab(20)
	var left := Rect2i(Vector2i(10, 10), Vector2i(cloudy.get_width() / 2 - 40, cloudy.get_height() - 20))
	var red := walled.get_pixel(left.get_center().x, left.get_center().y)
	check(red.r > 0.6 and red.g < 0.3, "Near geometry stays in front of the clouds (%s)" % red)
	var right := Rect2i(Vector2i(cloudy.get_width() / 2 + 40, 10), Vector2i(cloudy.get_width() / 2 - 50, cloudy.get_height() - 20))
	check(_difference(walled, cloudy, right) < 0.02, "Clouds beside near geometry are unchanged")
	wall.free()
	# Flying level through the deck: moving frames must match the same pose held still.
	hover.hover_position = Vector3(0, 2600, 0)
	hover.hover_pitch = 0.05
	await _grab(30)
	var worst := 0.0
	for leg in 3:
		for frame in 30:
			hover.hover_position += Vector3(5.0, 0, -5.0)
			hover.hover_yaw += 0.004
			await process_frame
		await RenderingServer.frame_post_draw
		var moving := root.get_texture().get_image()
		var still: Image = await _grab(40)
		worst = maxf(worst, _difference(moving, still, full))
	check(worst < 0.03, "Clouds in motion match the same pose held still (worst mean difference %.4f)" % worst)
	measured.append("Moving vs held still: worst mean difference %.4f" % worst)
	definition.cloud_weather = original
	hover.queue_free()
	await process_frame
