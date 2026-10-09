extends SceneTree
## Captures the hover view from PROBE_VIEW ("time x y z yaw pitch [weather]") in several
## reflection configurations, PNGs to PROBE_SHOTS.
const HOVER = preload("res://scenes/hover_preview.tscn")
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
	hover._clouds.time_scale = 0.0
	var v := OS.get_environment("PROBE_VIEW").split(" ")
	hover.hover_time = float(v[0]) + float(OS.get_environment("PROBE_TIME_OFFSET") if OS.get_environment("PROBE_TIME_OFFSET") != "" else "0")
	hover.hover_position = Vector3(float(v[1]), float(v[2]), float(v[3]))
	hover.hover_yaw = float(v[4])
	hover.hover_pitch = float(v[5])
	if v.size() > 6: hover._clouds.weather_time = float(v[6])
	var out := OS.get_environment("PROBE_SHOTS")
	var ocean: ShaderMaterial = hover._ocean.material()
	for config in OS.get_environment("PROBE_CONFIGS").split(","):
		ocean.set_shader_parameter("sky_reflection_strength", 0.0 if config == "old" else 1.0)
		ocean.set_shader_parameter("sky_view_samples", 16 if config == "sky16" else 6)
		# Configs "b<brightness>d<density>" tune mirrored clouds, e.g. b0.6d2.
		var brightness := 1.0
		var density := 1.0
		if config.begins_with("b") and config.contains("d"):
			brightness = float(config.substr(1, config.find("d") - 1))
			density = float(config.substr(config.find("d") + 1))
		ocean.set_shader_parameter("cloud_reflection_brightness", brightness)
		ocean.set_shader_parameter("cloud_reflection_density", density)
		var image: Image = await _grab(300)
		print("STATE alt=%.0f ocean=%s fade=%.2f sun_up=%.3f planet_visible=%s view=%s" % [hover._last_altitude, hover._ocean.visible, hover._ocean.fade, hover._sun_direction.dot(hover._surface_up), hover._planet.visible, hover._view_state()])
		print("LIGHT ambient=%s energy=%.4f sun_energy=%.3f glow=%s cloud_light=%.3f refl=%s" % [hover._environment.ambient_light_color, hover._environment.ambient_light_energy, hover._sun.light_energy, hover._cloud_glow, hover._cloud_light, hover._sky_material.get_shader_parameter("reflection_strength")])
		image.save_png(out + "/view_" + OS.get_environment("PROBE_TAG") + config + ".png")
		print("SHOT " + config)
	quit(0)
