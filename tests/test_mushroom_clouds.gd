extends SceneTree
## Side-on render check for the painted mushroom's connected stem and wider cap.
const Definition = preload("res://scripts/planet_definition.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
const Tiles = preload("res://scripts/cloud_brush_library.gd")
const Clouds = preload("res://scripts/cloud_layer.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Mushroom silhouette check requires a graphical display")
		quit(1)
		return
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("4686b6")
	scene.add_child(environment)
	var camera := Camera3D.new()
	camera.near = 10.0
	camera.far = 2000000.0
	camera.fov = 40.0
	scene.add_child(camera)
	camera.position = Vector3(0, 608000, 35000)
	camera.look_at(Vector3(0, 608000, 0), Vector3.UP)
	camera.current = true
	var definition := Definition.new()
	definition.cloud_weather = Weather.new()
	definition.cloud_weather.stamp(Vector3.UP, 0.025, Tiles.tile("mushroom"), 1.0)
	var clouds := Clouds.new()
	scene.add_child(clouds)
	var noise: NoiseTexture3D = clouds.material_override.get_shader_parameter("cloud_noise")
	if noise.get_data().is_empty(): await noise.changed
	clouds.update_weather(definition, camera.global_position * 0.001, Vector3(0.3, 0.9, 0.3).normalized(), true)
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var cloudy := root.get_texture().get_image()
	cloudy.save_png("/tmp/aphelion-mushroom-cloud.png")
	clouds.hide()
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var clear := root.get_texture().get_image()
	var material: ShaderMaterial = clouds.material_override
	var thickness: float = material.get_shader_parameter("cloud_thickness_km") * 1000.0
	var bottom: float = material.get_shader_parameter("cloud_height_km") * 1000.0 - thickness * 0.5
	var cap_row := roundi(camera.unproject_position(Vector3(0, definition.radius + bottom + thickness * 0.76, 0)).y)
	var stem_row := roundi(camera.unproject_position(Vector3(0, definition.radius + bottom + thickness * 0.3, 0)).y)
	var cap_width := _width(cloudy, clear, cap_row)
	var stem_width := _width(cloudy, clear, stem_row)
	print("Mushroom silhouette cap/stem: %d / %d pixels" % [cap_width, stem_width])
	if stem_width < 10 or cap_width < stem_width * 1.35:
		push_error("Mushroom needs a visible stem and a substantially broader cap")
		quit(1)
		return
	scene.queue_free()
	await process_frame
	print("PASS: painted mushroom cloud has a narrow stem and broad cap. /tmp/aphelion-mushroom-cloud.png")
	quit()

func _width(cloudy: Image, clear: Image, row: int) -> int:
	var count := 0
	for x in range(cloudy.get_width()):
		var a := cloudy.get_pixel(x, clampi(row, 0, cloudy.get_height() - 1))
		var b := clear.get_pixel(x, clampi(row, 0, clear.get_height() - 1))
		if (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0 > 0.04:
			count += 1
	return count
