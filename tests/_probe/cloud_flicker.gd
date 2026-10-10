extends SceneTree
## Cloud renderer rebuild: replays an owner-reported straight, fast hover flight
## and saves every frame, once per cloud mode, so frames where a cloud patch
## vanishes can be found against the reference (which keeps no history, so each
## of its frames is exact). Saves half-size PNGs to $COMPARE_OUT as
## fNNN-<mode>.png; FLICKER_MODES (default "reference,compute,reduced").
const HOVER = preload("res://scenes/hover_preview.tscn")
const START := Vector3(39440.1, 24664.6, -46248.0)
const YAW := 2.301
const PITCH := -0.112
const TIME := -225.0
## Weather runs at real-time rate from here, as in the owner's session.
const WEATHER := 125.6
## The owner flew at hover speed 6487 m/s holding Shift (10x in hover_preview.gd):
## one frame at 60 FPS. Forward for 3 s, then back.
const STEP_M := 6487.0 * 10.0 / 60.0
const LEG := 180
var FRAMES := LEG * 2
## Saved frames are this fraction of the window size.
var SCALE := float(OS.get_environment("FLICKER_SCALE")) if OS.get_environment("FLICKER_SCALE") != "" else 0.5
const WARM := 30

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var out := OS.get_environment("COMPARE_OUT")
	var modes: Array = Array(OS.get_environment("FLICKER_MODES").split(",")) if OS.get_environment("FLICKER_MODES") != "" else ["reference", "compute", "reduced"]
	var hover = HOVER.instantiate()
	root.add_child(hover)
	# Ignore the desktop's mouse wheel and keys while capturing.
	hover.set_process_unhandled_input(false)
	hover.hover_hud.visible = false
	var clouds: Node = hover._clouds
	clouds.time_scale = 0.0
	hover.hover_time = TIME
	hover.hover_yaw = YAW
	hover.hover_pitch = PITCH
	# Hover moves along the camera's forward axis in its launch frame.
	var forward: Vector3 = -(Basis(Vector3.UP, YAW) * Basis(Vector3.RIGHT, PITCH)).z
	for mode in modes:
		clouds.full_resolution = mode != "reduced"
		clouds.compute = mode == "compute"
		clouds.temporal = mode != "reference"
		clouds.weather_time = WEATHER
		hover.hover_position = START - forward * STEP_M * WARM
		for i in range(120): await process_frame
		# Approach at speed first, so history is in its moving state.
		for frame in range(-WARM, FRAMES):
			hover.hover_position = START + forward * STEP_M * (frame if frame < LEG else LEG * 2 - frame)
			clouds.weather_time = WEATHER + (frame + WARM) / 60.0
			await process_frame
			if frame < 0: continue
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.resize(int(image.get_width() * SCALE), int(image.get_height() * SCALE), Image.INTERPOLATE_BILINEAR)
			image.save_png("%s/f%03d-%s.png" % [out, frame, mode])
		print("FLICKER %s done" % mode)
	quit(0)
