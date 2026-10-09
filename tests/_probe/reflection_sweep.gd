extends SceneTree
## Hover view at PROBE_ALTS (m), each with reflections all/no-cloud/no-sky.
## Prints mean below-horizon difference from "all", so fades show by altitude.
const HOVER = preload("res://scenes/hover_preview.tscn")
var hover

func _initialize() -> void: _run.call_deferred()

func _grab(frames: int) -> Image:
	for i in range(frames): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _diff(a: Image, b: Image, top: int) -> float:
	var total := 0.0
	var n := 0
	for y in range(top, a.get_height(), 6):
		for x in range(0, a.get_width(), 6):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
	return total / maxf(n, 1) / 3.0 * 255.0

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(960, 540)
	DisplayServer.window_set_size(root.size)
	hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	var v := OS.get_environment("PROBE_VIEW").split(" ")
	hover.hover_time = float(v[0])
	hover.hover_yaw = float(v[4])
	hover.hover_pitch = float(OS.get_environment("PROBE_PITCH"))
	if v.size() > 6: hover._clouds.weather_time = float(v[6])
	var out := OS.get_environment("PROBE_SHOTS")
	var ocean: ShaderMaterial = hover._ocean.material()
	if OS.get_environment("PROBE_HIDE_CLOUDS") != "":
		# Hide the deck from the camera only; its uniforms (and the water's
		# mirrored clouds) still update, so reflections can be seen from above.
		hover._clouds.layers = 1 << 19
		hover.camera.cull_mask &= ~(1 << 19)
	if OS.get_environment("PROBE_OLD_DECK") != "":
		# Diagnostic: restore the former cutoff above the low cloud deck.
		var old := Shader.new()
		old.code = ocean.shader.code.replace("float cloud_weight = reflectance * cloud_reflection_strength;", "float deck_top = cloud_bottom_km() + cloud_thickness_km * cloud_deck_fraction; float below_deck = 1.0 - smoothstep(deck_top, deck_top + 0.5, length(camera_planet_km)); float cloud_weight = reflectance * below_deck * cloud_reflection_strength;")
		ocean.shader = old
	var first := true
	for alt_text in OS.get_environment("PROBE_ALTS").split(","):
		var alt := float(alt_text)
		hover.hover_position = Vector3(float(v[1]), float(v[2]) + alt - float(OS.get_environment("PROBE_BASE_ALT")), float(v[3]))
		var shots := {}
		for config in ["all", "nocloud", "nosky"]:
			ocean.set_shader_parameter("cloud_reflection_strength", 0.0 if config == "nocloud" else 1.0)
			ocean.set_shader_parameter("sky_reflection_strength", 0.0 if config == "nosky" else 1.0)
			shots[config] = await _grab(400 if first else 150)
			first = false
		shots["all"].save_png("%s/alt_%05d.png" % [out, int(alt)])
		print("ALT %6.0f actual=%6.0f fade=%.2f ocean=%s cloud_diff=%.2f sky_diff=%.2f" % [alt, hover._last_altitude, hover._ocean.fade, hover._ocean.visible, _diff(shots["all"], shots["nocloud"], 330), _diff(shots["all"], shots["nosky"], 330)])
	quit(0)
