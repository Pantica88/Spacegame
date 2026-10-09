extends SceneTree
## Sunset A/B of ocean.gdshader cloud_reflection_shading. PNGs to PROBE_SHOTS.
const HOVER = preload("res://scenes/hover_preview.tscn")
const PlanetSurface = preload("res://scripts/planet_surface.gd")
var hover

func _initialize() -> void: _run.call_deferred()

func _grab(frames: int) -> Image:
	for i in range(frames): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _sun_up() -> float:
	hover._update_camera()
	return hover._sun_direction.dot(hover._surface_up)

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
	# Nearest open water: below sea level here and 600 m around.
	var spot := Vector2.ZERO
	for ring in range(1, 200):
		var r := ring * 500.0
		var found := false
		for k in range(64):
			var a := TAU * k / 64.0
			var c := Vector2(cos(a), sin(a)) * r
			var wet := true
			for o in [Vector2.ZERO, Vector2(600, 0), Vector2(-600, 0), Vector2(0, 600), Vector2(0, -600)]:
				if PlanetSurface.terrain_height(c + o) > -5.0: wet = false
			if wet:
				spot = c
				found = true
				break
		if found: break
	print("WATER at %s" % spot)
	hover.hover_position = Vector3(spot.x, 30, spot.y)
	var target := float(OS.get_environment("PROBE_SUN")) if OS.get_environment("PROBE_SUN") != "" else 0.06
	var day := float(PlanetSurface.home().definition.rotation_seconds)
	var step := day / 384.0
	var t := 0.0
	var prev := _sun_up()
	for i in range(384):
		hover.hover_time = (i + 1) * step
		var s := _sun_up()
		if prev > target and s <= target:
			t = hover.hover_time
			break
		prev = s
	hover.hover_time = t
	_sun_up()
	var spin: Basis = PlanetSurface.home().rotation_at(t)
	var local_sun: Vector3 = (spin * PlanetSurface.LAUNCH_BASIS).inverse() * hover._sun_direction
	var sun_yaw := atan2(-local_sun.x, -local_sun.z)
	print("SUNSET time=%.1f sun_up=%.3f yaw=%.3f" % [t, _sun_up(), sun_yaw])
	var ocean: ShaderMaterial = hover._ocean.material()
	var out := OS.get_environment("PROBE_SHOTS")
	for view in [["sun", 0.0]]:
		hover.hover_yaw = sun_yaw + view[1]
		hover.hover_pitch = 0.05
		for mode in [0, 1, 3, 9]:
			# 9: sky reflection only, no mirrored clouds.
			ocean.set_shader_parameter("cloud_reflection_strength", 0.0 if mode == 9 else 1.0)
			ocean.set_shader_parameter("cloud_reflection_shading", mode)
			hover._update_camera()
			var image: Image = await _grab(300)
			var t0 := Time.get_ticks_usec()
			for f in range(120): await process_frame
			print("FRAME %s mode%d %.2f ms" % [view[0], mode, (Time.get_ticks_usec() - t0) / 120000.0])
			image.save_png("%s/%s_mode%d.png" % [out, view[0], mode])
			print("SHOT %s mode%d %s" % [view[0], mode, hover._view_state()])
	quit(0)
