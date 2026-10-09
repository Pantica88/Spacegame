extends "res://tests/test_atmosphere.gd"
## GPU regression for distance truncation and endpoint-dependent cloud lighting.
const Surface = preload("res://scripts/planet_surface.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")

func _run() -> void:
	output_dir = "/tmp/aphelion-cloud-distance"
	DirAccess.make_dir_recursive_absolute(output_dir)
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	Surface.home().definition.cloud_weather = Weather.new()
	# The diagnostic replaces density below. Keep authored weather occupied so
	# production empty-pass culling still updates the camera and shell uniforms.
	var occupied := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	occupied.fill(Color(0, 0, 0, 1))
	Surface.home().definition.cloud_weather.restore(occupied)
	var material: ShaderMaterial = world._clouds.material_override
	var noise: NoiseTexture3D = material.get_shader_parameter("cloud_noise")
	if noise.get_data().is_empty(): await noise.changed
	var source := FileAccess.get_file_as_string("res://assets/shaders/clouds.gdshader")
	# Controlled cloud distances make both failures independent of weather noise.
	var diagnostic := Shader.new()
	diagnostic.code = source.replace("uniform bool authored_weather", "uniform float test_limit = 1000.0;\nuniform bool distant_test = true;\nuniform bool authored_weather").replace(
		"float gap_start = end;", "end = min(end, test_limit);\n\tfloat gap_start = end;").replace(
		"float density = formation.x;", "float density = distant_test ? (step(180.0, distance) * (1.0 - step(220.0, distance))) : (step(3.0, distance) * (1.0 - step(6.0, distance))); ")
	material.shader = diagnostic
	_pose(Vector3(0, 13000, 0))
	world._landscape.hide()
	world.camera.position = Vector3.ZERO
	world.camera.look_at(Vector3(0, 0, -1000), Vector3.UP)
	world.set_sun_direction(Vector3(0, -0.08, -1))
	# Test synthetic density independently of production weather occupancy.
	material.shader = diagnostic
	material.set_shader_parameter("cloud_occupancy_enabled", false)
	world._clouds.show()
	var distant := await capture("beyond-160km")
	world._clouds.hide()
	var clear := await capture("clear")
	var delta := difference(distant, clear)
	print("Clouds beyond 160 km: %.6f" % delta)
	check(delta > 0.001, "Clouds beyond the former render radius remain visible")
	world._clouds.show()
	material.set_shader_parameter("distant_test", false)
	material.set_shader_parameter("test_limit", 100.0)
	var near_end := await capture("endpoint-100km")
	material.set_shader_parameter("test_limit", 150.0)
	var far_end := await capture("endpoint-150km")
	delta = difference(near_end, far_end)
	print("Near-cloud lighting difference when endpoint changes: %.6f" % delta)
	check(delta < 0.0001, "Empty ray length does not change near-cloud sunset lighting")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: complete cloud distance and stable sunset illumination")
	quit(0 if failures.is_empty() else 1)
