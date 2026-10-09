extends "res://tests/test_atmosphere.gd"
## Graphical regression for the missing far cloud bank near the deck at sunset.
## tools/run.sh --resolution 800x450 --script res://tests/test_cloud_horizon.gd
const Surface = preload("res://scripts/planet_surface.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")

func _run() -> void:
	output_dir = "/tmp/aphelion-cloud-horizon"
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
	# Use a known elevated slab to isolate ray traversal from random weather.
	# The observer and near segment are below it; only the far bank contributes.
	var source := FileAccess.get_file_as_string("res://assets/shaders/clouds.gdshader")
	var diagnostic := Shader.new()
	diagnostic.code = source.replace("float density = formation.x;",
		"float density = 0.7 * smoothstep(0.05, 0.06, height) * (1.0 - smoothstep(0.11, 0.12, height));")
	material.shader = diagnostic
	_pose(Vector3(0, 3400, 0))
	world._landscape.hide()
	world.camera.position = Vector3.ZERO
	world.camera.look_at(Vector3(0, 0, -1000), Vector3.UP)
	world.set_sun_direction(Vector3(0, 0.025, -1))
	# Test synthetic density independently of production weather occupancy.
	material.shader = diagnostic
	material.set_shader_parameter("cloud_occupancy_enabled", false)
	for authored in [true, false]:
		material.set_shader_parameter("authored_weather", authored)
		world._clouds.show()
		var cloudy := await capture("far-bank-" + str(authored))
		world._clouds.hide()
		var clear := await capture("clear-" + str(authored))
		var total := 0.0
		var count := 0
		for y in range(cloudy.get_height()):
			for x in range(cloudy.get_width() / 3, cloudy.get_width() * 2 / 3, 4):
				var ray: Vector3 = world.camera.project_ray_normal(Vector2(x, y) * root.get_visible_rect().size / Vector2(cloudy.get_size()))
				# Rays cross the bottom sphere but miss the solid planet.
				if ray.y > -0.08 and ray.y < -0.04:
					var a := cloudy.get_pixel(x, y)
					var b := clear.get_pixel(x, y)
					total += absf(a.r-b.r) + absf(a.g-b.g) + absf(a.b-b.b)
					count += 1
		var delta := total / maxf(count * 3.0, 1.0)
		print("Far cloud bank, authored=%s: %d pixels, difference %.6f" % [authored, count, delta])
		check(count > 50 and delta > 0.02, "Far bank remains visible across the clear-air gap: " + str(authored))
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: sunset rays retain far clouds in painted and procedural weather")
	quit(0 if failures.is_empty() else 1)
