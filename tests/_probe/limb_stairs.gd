extends SceneTree
## Renders PROBE_VIEW under limb-staircase ablations; crops to PROBE_SHOTS.
const HOVER = preload("res://scenes/hover_preview.tscn")
const INC := "res://assets/shaders/clouds_volume.gdshaderinc"
var hover

func _initialize() -> void: _run.call_deferred()

func _grab(frames: int) -> Image:
	for i in range(frames): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _patched(base: Shader, bounded: bool, edits: Dictionary) -> Shader:
	var inc := FileAccess.get_file_as_string(INC)
	for k in edits:
		assert(inc.contains(k), k)
		inc = inc.replace(k, edits[k])
	var s := Shader.new()
	s.code = ("#define CLOUD_OCCUPANCY\n" if bounded else "") + base.code.replace('#include "%s"' % INC, inc)
	return s

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1920, 1080)
	hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	var clouds = hover._clouds
	clouds.time_scale = 0.0
	var v := OS.get_environment("PROBE_VIEW").split(" ")
	hover.hover_time = float(v[0])
	hover.hover_position = Vector3(float(v[1]), float(v[2]), float(v[3]))
	hover.hover_yaw = float(v[4]); hover.hover_pitch = float(v[5])
	clouds.weather_time = float(v[6])
	await _grab(60)
	var comp: ShaderMaterial = clouds.material_override
	var low: ShaderMaterial = clouds._lowres_material
	var comp_base: Shader = comp.shader
	var low_base: Shader = low.shader
	var bounded: bool = comp_base.code.begins_with("#define CLOUD_OCCUPANCY")
	print("bounded=", bounded, " alt=", hover._last_altitude, " angle=", comp.get_shader_parameter("cloud_pixel_angle"), " thick=", comp.get_shader_parameter("cloud_thickness_km"), " deck=", comp.get_shader_parameter("cloud_deck_fraction"))
	var JIT := {"if (authored_weather) { jitter = 0.5; }": ""}
	var FINE := {"low_path / 96.0": "low_path / 768.0", "AUTHORED_CLOUD_STEPS = 320": "AUTHORED_CLOUD_STEPS = 1400"}
	var configs := {"still": {}, "turn_slow": {}, "turn_med": {}, "turn_fast": {}, "pitch_med": {}}
	for name in configs:
		var edits: Dictionary = configs[name]
		clouds.altitude_scaling = true
		clouds.resolution_scale = 0.5
		clouds.temporal = name != "notemporal"
		if edits.is_empty():
			comp.shader = comp_base; low.shader = low_base
		else:
			comp.shader = _patched(_plain(comp_base), bounded, edits)
			low.shader = _patched(_plain(low_base), bounded, edits)
		root.scaling_3d_scale = 2.0 if name == "ssaa" else 1.0
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		var start: Vector3 = hover.hover_position
		var yaw: float = hover.hover_yaw
		var speed := 1281.0 if name == "move1281" else (6000.0 if name == "move6000" else 0.0)
		var img: Image
		for f in range(180):
			var k := f - 179
			var dir := Vector3(sin(yaw), 0, cos(yaw)) if name.begins_with("strafe") else Vector3(cos(yaw), 0, -sin(yaw))
			if name.begins_with("strafe"): speed = 1281.0
			hover.hover_position = start + dir * speed * k / 60.0
			if k > -6 and k % 1 == 0: print(name, " f", k, " valid=", clouds._resolve_materials[clouds._temporal_frame % 2].get_shader_parameter("history_valid"))
			var rate := {"turn_slow": 0.003, "turn_med": 0.015, "turn_fast": 0.05}.get(name, 0.0) as float
			hover.hover_yaw = yaw + rate * k
			if name == "pitch_med": hover.hover_pitch = -0.471 + 0.01 * k
			await process_frame
		await RenderingServer.frame_post_draw
		img = root.get_texture().get_image()
		img.save_png(OS.get_environment("PROBE_SHOTS") + "/full_" + name + ".png")
		print(name, " valid=", clouds._resolve_materials[clouds._temporal_frame % 2].get_shader_parameter("history_valid"))
		hover.hover_position = start; hover.hover_yaw = yaw; hover.hover_pitch = -0.471
		continue
		img = await _grab(120)
		var t0 := Time.get_ticks_usec()
		img = await _grab(300)
		print("TIME ", name, " ms/frame ", (Time.get_ticks_usec() - t0) / 300000.0)
		img.save_png(OS.get_environment("PROBE_SHOTS") + "/full_" + name + ".png")
		img.get_region(Rect2i(700, 380, 640, 420)).save_png(OS.get_environment("PROBE_SHOTS") + "/crop_" + name + ".png")
		print("SHOT ", name)
	quit(0)

func _plain(s: Shader) -> Shader:
	if not s.code.begins_with("#define CLOUD_OCCUPANCY\n"): return s
	var p := Shader.new(); p.code = s.code.substr("#define CLOUD_OCCUPANCY\n".length()); return p
