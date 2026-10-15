extends SceneTree
## Captures the clouds from a fixed set of hover views, for looking at the
## renderer by eye. PNGs to CLOUD_SHOTS (default /tmp/aphelion-cloud-views).
##   CLOUD_WEATHER  saved (the planet as loaded), procedural, mixed, storms,
##                  mushrooms or uniform (CLOUD_MIX "r g b a" everywhere)
##   CLOUD_VIEWS    comma-separated subset of the view names below
##                  or ring_<tile> (eight stamps of one formation 60 km around the pad)
##   CLOUD_TIME     hover time offset in seconds (moves the sun)
##   CLOUD_SUN      instead of CLOUD_TIME: the sine of the sun's elevation at the
##                  pad, reached as the sun sets (e.g. 0.05 sunset, -0.3 night)
##   CLOUD_COST     1 shows the march's sample counts instead of light
## Run: tools/run.sh --resolution 1600x900 --script res://tests/_probe/cloud_views.gd
const HOVER = preload("res://scenes/hover_preview.tscn")
const Tiles = preload("res://scripts/cloud_brush_library.gd")
const PlanetSurface = preload("res://scripts/planet_surface.gd")

# name: [x, y, z (launch frame, m), yaw, pitch]
const VIEWS := {
	"ground_up": [0.0, 35.0, 100.0, 0.0, 0.35],
	"ground_horizon": [0.0, 35.0, 100.0, 0.6, 0.04],
	"low_flight": [0.0, 1500.0, 0.0, 1.2, 0.05],
	"in_deck": [0.0, 2600.0, 0.0, 0.3, 0.0],
	"above_deck": [0.0, 6000.0, 0.0, 0.8, -0.12],
	"ascent_12": [0.0, 12000.0, 0.0, 0.6, -0.08],
	"deck_12": [0.0, 12000.0, 0.0, 0.6, -0.45],
	"high": [0.0, 30000.0, 0.0, 0.0, -0.45],
	"orbit": [0.0, 160000.0, 0.0, 0.0, -1.1],
	"far": [0.0, 1500000.0, 0.0, 0.0, -1.5],
	"sea_low": [6000.0, 40.0, -6000.0, 2.2, -0.05],
	"sea_up": [6000.0, 400.0, -6000.0, 2.2, -0.35],
	"side_3": [0.0, 3000.0, 0.0, 0.4, 0.06],
	"side_8": [0.0, 8000.0, 0.0, 0.4, -0.02],
	"down_6": [0.0, 6000.0, 0.0, 0.0, -1.2],
	"down_30": [0.0, 30000.0, 0.0, 0.0, -1.2],
	"down_160": [0.0, 160000.0, 0.0, 0.0, -1.4],
}

func _initialize() -> void: _run.call_deferred()

func _grab(frames: int) -> Image:
	for i in range(frames): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var out := OS.get_environment("CLOUD_SHOTS")
	if out.is_empty(): out = "/tmp/aphelion-cloud-views"
	DirAccess.make_dir_recursive_absolute(out)
	var hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	hover._clouds.cost_view = OS.get_environment("CLOUD_COST") == "1"
	var definition: Resource = PlanetSurface.home().definition
	match OS.get_environment("CLOUD_WEATHER"):
		"procedural": definition.cloud_weather = null
		"mixed": definition.cloud_weather = Tiles.generate_weather(7, 90, 0.85, "mixed")
		"storms": definition.cloud_weather = Tiles.generate_weather(11, 40, 0.9, "storm")
		"mushrooms": definition.cloud_weather = Tiles.generate_weather(5, 60, 0.95, "mushroom")
		"uniform":
			# One flat mixture everywhere: CLOUD_MIX "r g b a" (default stratocumulus 0.7).
			var mix := Color(0, 0.7, 0, 0)
			if OS.get_environment("CLOUD_MIX") != "":
				var m := OS.get_environment("CLOUD_MIX").split(" ")
				mix = Color(float(m[0]), float(m[1]), float(m[2]), float(m[3]))
			var weather: Resource = load("res://scripts/cloud_weather_map.gd").new()
			var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
			image.fill(mix)
			weather.image = image
			definition.cloud_weather = weather
	var weather_name := OS.get_environment("CLOUD_WEATHER")
	if weather_name.begins_with("ring_"):
		var tile := weather_name.substr(5)
		var weather: Resource = load("res://scripts/cloud_weather_map.gd").new()
		weather.initialize(1024, 512)
		var up: Vector3 = PlanetSurface.LAUNCH_RADIAL.normalized()
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		var size := {"mushroom": 0.022, "storm": 0.05, "cumulus": 0.06, "streets": 0.06, "stratocumulus": 0.07, "overcast": 0.07, "cirrus": 0.07}
		for i in 8:
			var around := Basis(up, TAU * i / 8.0) * side
			weather.stamp(Basis(around, 0.1) * up, size.get(tile, 0.05), Tiles.tile(tile, i % 4), 0.95, 0.0, false, 0.4)
		definition.cloud_weather = weather
	var time_offset := float(OS.get_environment("CLOUD_TIME")) if OS.get_environment("CLOUD_TIME") != "" else 0.0
	if OS.get_environment("CLOUD_SUN") != "":
		var target := float(OS.get_environment("CLOUD_SUN"))
		var day := float(definition.rotation_seconds)
		var previous := 2.0
		for step in 800:
			hover.hover_time = day * step / 800.0
			hover._update_camera()
			var height: float = hover._sun_direction.dot(hover._surface_up)
			if previous >= target and height < target:
				time_offset = hover.hover_time
				break
			previous = height
	# CLOUD_POSES: "name:time x y z yaw pitch weather;..." copied from the hover HUD (C).
	var views := VIEWS.duplicate()
	var weather_times := {}
	for pose in OS.get_environment("CLOUD_POSES").split(";", false):
		var parts := pose.split(":")
		var f := parts[1].split(" ", false)
		views[parts[0]] = [float(f[1]), float(f[2]), float(f[3]), float(f[4]), float(f[5]), float(f[0])]
		weather_times[parts[0]] = float(f[6])
	var names: PackedStringArray = OS.get_environment("CLOUD_VIEWS").split(",", false)
	if names.is_empty(): names = PackedStringArray(views.keys())
	for view_name in names:
		var v: Array = views[view_name]
		hover.hover_time = v[5] if v.size() > 5 else time_offset
		if weather_times.has(view_name): hover._clouds.weather_time = weather_times[view_name]
		hover.hover_position = Vector3(v[0], v[1], v[2])
		hover.hover_yaw = v[3]
		hover.hover_pitch = v[4]
		var image: Image = await _grab(90)
		var march = hover._clouds.render_pass()
		print("VIEW %s alt=%.0f drawing=%s march=%s sun_up=%.3f" % [view_name, hover._last_altitude, hover._clouds.is_drawing(), march.target_size() if march else "-", hover._sun_direction.dot(hover._surface_up)])
		image.save_png("%s/%s%s.png" % [out, OS.get_environment("CLOUD_TAG"), view_name])
	quit(0)
