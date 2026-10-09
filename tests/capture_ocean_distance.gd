extends SceneTree
## Godot 4.5.1 graphical distance captures; validates ocean patch activation.
const World = preload("res://scripts/world_view.gd")
const Surface = preload("res://scripts/planet_surface.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1100,700)
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	var terrain = Surface.home()
	var direction := Vector3.UP
	for i in range(1, 1000):
		var d := Vector3(sin(i*2.4)*0.3, 1.0, cos(i*2.4)*0.3).normalized()
		if terrain.elevation(d) < -200.0:
			direction = d
			break
	var position := Vector3(0,-600000,0) + direction * 600003.0
	var output := OS.get_environment("OCEAN_CAPTURE_DIR")
	if output.is_empty(): output = "/tmp/aphelion-ocean-distance"
	DirAccess.make_dir_recursive_absolute(output)
	for view in ["low", "overhead", "mid", "high", "handoff", "orbit"]:
		world._pitch = 0.05 if view == "low" else 0.95
		var altitude: float = {"low": 3.0, "overhead": 3.0, "mid": 500.0, "high": 6000.0, "handoff": 22000.0, "orbit": 40000.0}[view]
		position = Vector3(0,-600000,0) + direction * (600000.0 + altitude)
		world._distance = 25.0 if view == "low" else 90.0
		world.sync_flight({"position":position,"altitude":altitude,"orientation":Basis(Quaternion(Vector3.UP,direction)),"engine_on":false,"fuel":0.0,"boosters_attached":false,"capsule_only":true,"chute_deployed":false},0.0)
		world.set_sun_direction(Vector3(0.5,0.65,0.55).normalized())
		world._rocket.hide()
		for frame in range(90): await process_frame
		if world._ocean.visible != (altitude < 25000.0):
			push_error("Ocean patch visibility does not match camera altitude at " + view)
			quit(1)
			return
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(output.path_join(view+".png")) != OK:
			quit(1)
			return
	print("PASS: full game ocean captured")
	quit(0)
