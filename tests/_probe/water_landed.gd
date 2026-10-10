extends SceneTree
## Probe: capsule on open ocean at 0, 3 and 30 m with a low camera, for renderer
## comparison. Run: PROBE_OUT=/some/dir tools/run.sh --rendering-method forward_plus \
##   --resolution 1280x720 --script res://tests/_probe/water_landed.gd (isolate XDG_*).
const World = preload("res://scripts/world_view.gd")
const Surface = preload("res://scripts/planet_surface.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	var terrain = Surface.home()
	var radius: float = Surface.RADIUS
	var direction := Vector3.UP
	for i in range(1, 2000):
		var d := Vector3(sin(i * 2.4) * 0.3, 1.0, cos(i * 2.4) * 0.3).normalized()
		if terrain.elevation(d) < -200.0:
			direction = d
			break
	var output := OS.get_environment("PROBE_OUT")
	DirAccess.make_dir_recursive_absolute(output)
	var renderer := RenderingServer.get_current_rendering_method()
	for altitude in [0.0, 3.0, 30.0]:
		var position: Vector3 = Vector3(0, -radius, 0) + direction * (radius + float(altitude))
		world._pitch = 0.18
		world._distance = 22.0
		world.sync_flight({"position": position, "altitude": altitude, "orientation": Basis(Quaternion(Vector3.UP, direction)), "engine_on": false, "fuel": 0.0, "boosters_attached": false, "capsule_only": true, "chute_deployed": altitude > 1.0, "status": "landed" if altitude == 0.0 else "flying"}, 0.0)
		world.set_sun_direction(Vector3(0.5, 0.65, 0.55).normalized())
		for frame in range(60): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%s-%03d.png" % [renderer, int(altitude)]))
	print("PROBE done ", renderer)
	quit(0)
