extends SceneTree
## Capture the reported storm-base view while moving forward and back.
const START := Vector3(127.0, 5984.9, -400.4)
const SNAPSHOTS := [1, 16, 32, 64, 96, 120]
const STEP := 4.0
var hover: Node
var motion_frame := 0
var direction := 0.0
var forward := Vector3.ZERO
var out := ""
var captures: Array[Dictionary] = []
var start := START
var vertical := false
var step := STEP
var frames_per_leg := 120
var snapshots: Array = SNAPSHOTS

func _initialize() -> void:
	_run.call_deferred()

func _move() -> void:
	if direction == 0.0: return
	motion_frame += 1
	var distance := step * (motion_frame if direction > 0.0 else frames_per_leg - motion_frame)
	hover.hover_position = start + forward * distance
	hover._update_camera()

func _capture(label: String) -> void:
	var error := root.get_texture().get_image().save_png(out.path_join(label + ".png"))
	if error != OK:
		push_error("Snapshot failed: " + label)
		quit(1)
		return
	captures.append({"file": label + ".png", "frame": motion_frame,
		"position": [hover.hover_position.x, hover.hover_position.y, hover.hover_position.z],
		"temporal_active": hover._clouds._lowres_material.get_shader_parameter("temporal_march"),
		"altitude_m": hover._last_altitude})
	print("CAPTURE ", label, " ", hover._view_state())

func _run() -> void:
	out = OS.get_environment("STORM_MOTION_OUTPUT")
	if out.is_empty() or DisplayServer.get_name() == "headless":
		push_error("STORM_MOTION_OUTPUT and a graphical display are required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	vertical = OS.get_environment("STORM_MOTION_VERTICAL") == "1"
	if vertical: start.y = 5760.0
	if OS.get_environment("STORM_MOTION_SWEEP") == "1":
		vertical = true
		start.y = 3500.0
		step = 25.0
		frames_per_leg = 500
		snapshots = [12, 20, 24, 28, 44, 60, 72, 100, 128, 140, 180, 260, 340, 460, 500]
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	hover = load("res://scenes/hover_preview.tscn").instantiate()
	root.add_child(hover)
	hover.set_process(false)
	hover.set_process_unhandled_input(false)
	hover.hover_hud.hide()
	hover.hover_time = 0.0
	hover.hover_yaw = 0.0
	hover.hover_pitch = 0.095
	hover.hover_position = start
	hover._clouds.weather_time = 24.1
	hover._clouds.time_scale = 0.0
	hover._clouds.temporal = OS.get_environment("STORM_MOTION_TEMPORAL") != "0"
	hover._update_camera()
	forward = -(Basis(Vector3.UP, hover.hover_yaw) * Basis(Vector3.RIGHT, hover.hover_pitch)).z
	if vertical: forward = Vector3.UP
	for i in range(120): await process_frame
	await RenderingServer.frame_post_draw
	_capture("start")
	process_frame.connect(_move)
	for d in [1.0, -1.0]:
		motion_frame = 0
		direction = d
		while motion_frame < frames_per_leg:
			await RenderingServer.frame_post_draw
			if motion_frame in snapshots:
				_capture(("forward" if d > 0.0 else "backward") + "_%03d" % motion_frame)
	direction = 0.0
	var manifest := {"time": 0.0, "yaw": 0.0, "pitch": 0.095, "weather": 24.1,
		"metres_per_frame": step, "frames_per_leg": frames_per_leg,
		"motion": "%g metres %s, then return without settling" % [step * frames_per_leg, "vertically" if vertical else "along view direction"],
		"temporal": hover._clouds.temporal, "captures": captures}
	var file := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	print("CAPTURE DONE ", out)
	quit(0)
