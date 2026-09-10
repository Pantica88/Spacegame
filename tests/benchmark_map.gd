extends SceneTree
const World = preload("res://scripts/world_view.gd")
const Map = preload("res://scripts/orbital_map.gd")
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.disable_3d = true
	var world := World.new()
	root.add_child(world)
	world.hide()
	var map := Map.new()
	map.source_world = world
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(map)
	map.state = {"position":Vector3(0,30000,0),"velocity":Vector3(620,0,0),"time":100.0}
	map.zoom = 0.5
	for frame in range(60): await process_frame
	var started := Time.get_ticks_usec()
	for frame in range(240):
		map.yaw += 0.002
		await process_frame
	var milliseconds := float(Time.get_ticks_usec()-started)/240000.0
	print("MAP BENCHMARK: %.3f ms/frame (%.1f FPS), 240 orbiting frames, vsync off" % [milliseconds,1000.0/milliseconds])
	quit()
