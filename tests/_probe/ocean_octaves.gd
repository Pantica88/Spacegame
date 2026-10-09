extends SceneTree
## Renders the hover view from PROBE_VIEW with swell octaves isolated, to
## attribute ocean patterns. PNGs to PROBE_SHOTS.
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
	hover.hover_time = float(v[0])
	hover.hover_position = Vector3(float(v[1]), float(v[2]), float(v[3]))
	hover.hover_yaw = float(v[4])
	hover.hover_pitch = float(v[5])
	if v.size() > 6: hover._clouds.weather_time = float(v[6])
	var out := OS.get_environment("PROBE_SHOTS")
	var ocean: ShaderMaterial = hover._ocean.material()
	var heights := Vector4(0.25, 0.45, 0.65, 0.8)
	var original: Shader = ocean.shader
	var no_shore := Shader.new()
	# Diagnostic: draw distant water without its coverage fade or discard.
	no_shore.code = original.code.replace("float shore = -VERTEX.z > 15000.0", "float shore = -VERTEX.z > 1.0e30")
	var first := true
	for config in OS.get_environment("PROBE_CONFIGS").split(","):
		var h := heights
		var state_scale := 5200.0
		if config.begins_with("s") and config.length() == 2:
			var keep := int(config.substr(1))
			h = Vector4.ZERO
			h[keep] = heights[keep]
		elif config == "noswell": h = Vector4.ZERO
		elif config == "flatstate": state_scale = 1.0e9
		# "nopatch" hides the ocean patch from the camera, leaving the terrain's water.
		hover._ocean.layers = (1 << 18) if config == "nopatch" else 1
		hover.camera.cull_mask = hover.camera.cull_mask & ~(1 << 18)
		ocean.shader = no_shore if config == "noshore" else original
		# "deepbed" sinks the terrain's shallows 2 km under the patch: a depth tie test.
		hover._planet.material_override.set_shader_parameter("seabed_shallow_m", 2000.0 if config == "deepbed" else 2.5)
		ocean.set_shader_parameter("swell_heights", h)
		ocean.set_shader_parameter("sea_state_scale", state_scale)
		var image: Image = await _grab(400 if first else 60)
		first = false
		image.save_png(out + "/oct_" + config + ".png")
		print("SHOT " + config)
	quit(0)
