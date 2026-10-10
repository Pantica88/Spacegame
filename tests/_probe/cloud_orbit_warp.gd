extends SceneTree
## Cloud renderer rebuild: a camera on a circular orbit through an owner-chosen
## hover view, at every time-warp step 1x to 100000x. This is a rendering stress
## test, not gameplay: the orbit is far below where the game permits warp
## (FlightModel.warp_limit). The camera flies at orbital speed along its view
## heading, keeping its angle to the ground; warp scales the distance per frame
## and the planet's spin and sunlight. Snapshots are taken mid-flight, each
## followed by a reference that marches every pixel of the same pose.
## Saves to $COMPARE_OUT; cloud_compare_metrics.gd scores them.
## Cloud modes: "reduced" (the game's clouds) and "reference" (every pixel
## integrated at full resolution).
const FlightModel = preload("res://scripts/flight_model.gd")
const START := Vector3(28925.7, 22594.4, -23024.9)
const YAW := -0.415
const PITCH := -0.347
const WEATHER := 27.4
const WARPS := [1, 2, 3, 4, 5, 10, 50, 100, 1000, 10000, 100000]
const STEP := 1.0 / 60.0

## The hover preview with its camera turned to follow the orbit.
class OrbitHover extends "res://scripts/hover_preview.gd":
	## Camera basis in the planet's own frame; null leaves the hover camera.
	var orbit_basis: Variant = null

	func _update_camera() -> void:
		super._update_camera()
		if orbit_basis != null and is_instance_valid(camera):
			camera.basis = PlanetSurface.home().rotation_at(hover_time) * orbit_basis
			# Clouds and sky read the camera there; refresh them for the new pose.
			_update_atmosphere()

var hover: OrbitHover
var clouds: Node
var _start: Vector3
var _start_basis: Basis
var _axis: Vector3
var _angular_speed: float
var _angle := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _mode(mode: String) -> void:
	clouds.resolution_scale = 1.0 if mode == "reference" else 0.5
	clouds.altitude_scaling = mode != "reference"

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_environment("COMPARE_OUT"), name])

## Places the camera after flying `angle` radians around the planet.
func _place(angle: float, time: float) -> void:
	var turn := Basis(_axis, angle)
	var launch: Basis = hover.PlanetSurface.LAUNCH_BASIS
	hover.hover_position = launch.inverse() * (turn * _start - hover.PlanetSurface.LAUNCH_RADIAL)
	hover.orbit_basis = turn * _start_basis
	hover.hover_time = time

## Flies one frame at the given warp.
func _advance(warp: int) -> void:
	_angle += _angular_speed * STEP * warp
	_place(_angle, hover.hover_time + STEP * warp)
	await process_frame

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var modes: Array = ["reduced"]
	hover = OrbitHover.new()
	root.add_child(hover)
	# Ignore the desktop's mouse wheel and keys while capturing.
	hover.set_process_unhandled_input(false)
	hover.hover_hud.visible = false
	clouds = hover._clouds
	clouds.weather_time = WEATHER
	clouds.time_scale = 0.0
	var launch: Basis = hover.PlanetSurface.LAUNCH_BASIS
	_start = hover.PlanetSurface.LAUNCH_RADIAL + launch * START
	_start_basis = launch * Basis(Vector3.UP, YAW) * Basis(Vector3.RIGHT, PITCH)
	var up := _start.normalized()
	# Orbit along the view's heading; rotating about up x heading moves toward it.
	var heading := (_start_basis * Vector3.FORWARD).slide(up).normalized()
	_axis = up.cross(heading).normalized()
	_angular_speed = sqrt(FlightModel.MU / _start.length()) / _start.length()
	print("ORBIT altitude %.1f km, %.0f m/s" % [(_start.length() - hover.PlanetSurface.RADIUS) / 1000.0, _angular_speed * _start.length()])
	_place(0.0, 0.0)
	_mode("reference")
	for i in range(200): await process_frame
	for warp in WARPS:
		# The highest warps cross a large share of the planet each frame.
		var snapshots := 2 if warp >= 10000 else 3
		var warm := 30 if warp >= 10000 else 45
		for mode in modes:
			_angle = 0.0
			_place(0.0, 0.0)
			_mode(mode)
			for i in range(warm): await _advance(warp)
			for snapshot in range(snapshots):
				var name := "w%06dx_s%d_%s" % [warp, snapshot + 1, mode]
				# Captured while flying; the reference then holds this pose.
				await _shot("%s-%s" % [name, mode])
				_mode("reference")
				for i in range(8): await process_frame
				await _shot("%s-reference" % name)
				_mode(mode)
				for i in range(warm): await _advance(warp)
		print("ORBIT %dx done" % warp)
	print("ORBIT done")
	quit(0)
