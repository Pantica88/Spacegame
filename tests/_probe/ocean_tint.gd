extends SceneTree
## Ocean tint ablation: PROBE_VIEWS "time x y z yaw pitch weather;..." x PROBE_CONFIGS.
const HOVER = preload("res://scenes/hover_preview.tscn")
var hover

func _initialize() -> void: _run.call_deferred()

func _grab(frames: int) -> Image:
	for i in range(frames): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _avg(img: Image, x0: int, y0: int, x1: int, y1: int) -> Color:
	var c := Color(0, 0, 0, 0)
	var n := 0
	for y in range(y0, y1, 8):
		for x in range(x0, x1, 8):
			c += img.get_pixel(x, y); n += 1
	return c / n

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	var out := OS.get_environment("PROBE_SHOTS")
	var ocean: ShaderMaterial = hover._ocean.material()
	var base_code: String = ocean.shader.code
	var vi := 0
	for view in OS.get_environment("PROBE_VIEWS").split(";"):
		var v := view.split(" ")
		hover.hover_time = float(v[0])
		hover.hover_position = Vector3(float(v[1]), float(v[2]), float(v[3]))
		hover.hover_yaw = float(v[4])
		hover.hover_pitch = float(v[5])
		hover._clouds.weather_time = float(v[6])
		for config in OS.get_environment("PROBE_CONFIGS").split(","):
			ocean.set_shader_parameter("edge_scale", -1.0 if config.contains("noedge") else 0.3)
			ocean.set_shader_parameter("albedo", Color.BLACK if config.contains("noalb") else Color(0.0, 0.32, 0.43))
			ocean.set_shader_parameter("albedo2", Color.BLACK if config.contains("noalb") else Color(0.0, 0.47, 0.76))
			var code: String = base_code
			if config.contains("flat"):
				code = code.replace("float fine_weight = 1.0 - smoothstep(0.4, 3.0, footprint);", "float fine_weight = 0.0;").replace("float ripple_weight = 1.0 - smoothstep(0.8, 6.0, footprint);", "float ripple_weight = 0.0;")
			if config.contains("noswell"):
				code = code.replace("grad += swell_gradient", "grad += 0.0 * swell_gradient")
			if config.contains("analytic"):
				code = code.replace("smoothstep(1500.0, 4000.0, -VERTEX.z)", "1.0")
			if config.contains("nolight"):
				code = code.replace("void fragment() {", "void light() { DIFFUSE_LIGHT += vec3(0.0); }\nvoid fragment() {")
			var sh := Shader.new()
			sh.code = code
			ocean.shader = sh
			var img: Image = await _grab(400)
			img.save_png("%s/v%d_%s.png" % [out, vi, config])
			print("LIGHT ambient=%s energy=%.4f sun_energy=%.3f sun_color=%s cloud_light=%.3f glow=%s" % [hover._environment.ambient_light_color, hover._environment.ambient_light_energy, hover._sun.light_energy, hover._sun.light_color, hover._cloud_light, hover._cloud_glow])
			print("SHOT v%d %s alt=%.0f fade=%.2f lower=%s mid=%s" % [vi, config, hover._last_altitude, hover._ocean.fade, _avg(img, 0, 650, img.get_width(), img.get_height()), _avg(img, 0, 380, img.get_width(), 650)])
		vi += 1
	quit(0)
