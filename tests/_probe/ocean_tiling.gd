extends SceneTree
## Low sea-level views for checking ripple tiling. OCEAN_CAPTURE_DIR, OCEAN_TAG.
const World = preload("res://scripts/world_view.gd")
const Surface = preload("res://scripts/planet_surface.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1600,900)
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	var terrain = Surface.home()
	var direction := Vector3.UP
	for i in range(1, 1000):
		var d := Vector3(sin(i*2.4)*0.3, 1.0, cos(i*2.4)*0.3).normalized()
		if terrain.elevation(d) < -200.0:
			direction = d
			break
	var output := OS.get_environment("OCEAN_CAPTURE_DIR")
	var tag := OS.get_environment("OCEAN_TAG")
	DirAccess.make_dir_recursive_absolute(output)
	var views := OS.get_environment("OCEAN_VIEWS").split(",") if OS.has_environment("OCEAN_VIEWS") else PackedStringArray(["low", "wide", "match"])
	for view in views:
		var altitude: float = {"low": 3.0, "wide": 30.0, "match": 0.5, "top": 2.0, "oblique": 40.0}[view]
		world._pitch = {"low": 0.12, "wide": 0.3, "match": 0.22, "top": 1.45, "oblique": 0.5}[view]
		world._distance = {"low": 25.0, "wide": 60.0, "match": 70.0, "top": 160.0, "oblique": 30.0}[view]
		var position := Vector3(0,-600000,0) + direction * (600000.0 + altitude)
		world.sync_flight({"position":position,"altitude":altitude,"orientation":Basis(Quaternion(Vector3.UP,direction)),"engine_on":false,"fuel":0.0,"boosters_attached":false,"capsule_only":true,"chute_deployed":false},0.0)
		world.set_sun_direction(Vector3(0.5,0.65,0.55).normalized())
		for frame in range(240): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(tag+"_"+view+".png"))
	print("done")
	quit(0)
