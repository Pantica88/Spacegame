extends SceneTree
## Isolate and remove each weather channel at the two reported cloud views.
## Only changes in-memory copies of the loaded weather map; never saves it.
const HOVER = preload("res://scenes/hover_preview.tscn")
const Surface = preload("res://scripts/planet_surface.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
const POSES = {
	"chunky": [65984.6, -3794.1, -58158.0, 1.446, -0.143, 167.4],
	"natural": [69213.6, -3246.9, -56708.7, 2.892, -0.638, 154.9],
}
const MASKS = {
	"all": [1,1,1,1], "none": [0,0,0,0],
	"only_cumulus": [1,0,0,0], "without_cumulus": [0,1,1,1],
	"only_stratocumulus": [0,1,0,0], "without_stratocumulus": [1,0,1,1],
	"only_stratus": [0,0,1,0], "without_stratus": [1,1,0,1],
	"only_storm": [0,0,0,1], "without_storm": [1,1,1,0],
}
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	var definition: Resource = Surface.home().definition
	var original: Resource = definition.cloud_weather
	if original == null:
		push_error("This probe requires the saved painted weather map")
		quit(1)
		return
	var source: Image = original.snapshot()
	var out := OS.get_environment("CLOUD_SHOTS")
	if out.is_empty(): out = "/tmp/cloud-classes"
	DirAccess.make_dir_recursive_absolute(out)
	for name in POSES:
		var p: Array = POSES[name]
		hover.hover_time = 3150.0
		hover.hover_position = Vector3(p[0], p[1], p[2])
		hover.hover_yaw = p[3]
		hover.hover_pitch = p[4]
		hover._clouds.weather_time = p[5]
		for variant in MASKS:
			var bytes := source.get_data()
			var mask: Array = MASKS[variant]
			for i in range(bytes.size()):
				if mask[i % 4] == 0: bytes[i] = 0
			var weather = Weather.new()
			weather.image = Image.create_from_data(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8, bytes)
			definition.cloud_weather = weather
			hover._clouds.render_pass().reset_history()
			for i in 60: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s-%s.png" % [out, name, variant])
			print("CLASS %s %s" % [name, variant])
	definition.cloud_weather = original
	quit(0)
