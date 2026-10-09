extends SceneTree
## Level view over open water: ocean configs (PROBE_CONFIGS) shot at pitch 0, so a
## perfect mirror is the sky flipped about the centre row. PNGs to PROBE_SHOTS.
const HOVER = preload("res://scenes/hover_preview.tscn")
const PlanetSurface = preload("res://scripts/planet_surface.gd")
var hover

func _initialize() -> void: _run.call_deferred()

func _grab(frames: int) -> Image:
	for i in range(frames): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	# The probe window can take focus; keep the user's mouse and keys out.
	hover.set_process_unhandled_input(false)
	hover.set_process(false)
	hover._clouds.time_scale = 0.0
	# Open water: below -20 m here and in a 5 km ring.
	var spot := Vector2.ZERO
	var found := false
	for ring in range(1, 400):
		for k in range(96):
			var c := Vector2(cos(TAU * k / 96.0), sin(TAU * k / 96.0)) * ring * 500.0
			var wet := true
			for j in range(13):
				var o := Vector2.ZERO if j == 0 else Vector2(cos(TAU * j / 12.0), sin(TAU * j / 12.0)) * 5000.0
				if PlanetSurface.terrain_height(c + o) > -20.0:
					wet = false
					break
			if wet:
				spot = c
				found = true
				break
		if found: break
	print("WATER at %s" % spot)
	hover.hover_position = Vector3(spot.x, float(OS.get_environment("PROBE_ALT")), spot.y)
	hover.hover_time = float(OS.get_environment("PROBE_TIME"))
	hover.hover_yaw = float(OS.get_environment("PROBE_YAW"))
	hover.hover_pitch = 0.0
	var ocean: ShaderMaterial = hover._ocean.material()
	var original: Shader = ocean.shader
	var out := OS.get_environment("PROBE_SHOTS")
	for config in OS.get_environment("PROBE_CONFIGS").split(","):
		var shader := Shader.new()
		var code := original.code
		if config.contains("flat"):
			code = code.replace("normalize(mix(up_world, normal_world, 0.35))", "up_world")
		if config.contains("nosky"):
			ocean.set_shader_parameter("sky_reflection_strength", 0.0)
		else:
			ocean.set_shader_parameter("sky_reflection_strength", 1.0)
		shader.code = code
		ocean.shader = shader
		hover.hover_time = float(OS.get_environment("PROBE_TIME"))
		hover.hover_yaw = float(OS.get_environment("PROBE_YAW"))
		hover.hover_pitch = 0.0
		hover._update_camera()
		# The hover frame is the pad's; level the camera to the local horizon.
		var up: Vector3 = hover._surface_up
		var ahead: Vector3 = -hover.camera.basis.z
		ahead = (ahead - up * ahead.dot(up)).normalized()
		hover.camera.basis = Basis.looking_at(ahead, up)
		print("LEVEL tilt was %.2f deg" % rad_to_deg(acos(clampf(hover.camera.basis.y.dot(up), -1.0, 1.0))))
		var image: Image = await _grab(400)
		image.save_png("%s/%s%s.png" % [out, OS.get_environment("PROBE_TAG"), config])
		print("SHOT %s %s" % [config, hover._view_state()])
	quit(0)
