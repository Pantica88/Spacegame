extends SceneTree
## Graphical regression: terrain must not draw through the launch deck.
const Flight = preload("res://scripts/flight_model.gd")
const World = preload("res://scripts/world_view.gd")

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Launch deck rendering check requires a graphical display")
		quit(1)
		return
	run.call_deferred()

func capture() -> Image:
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func run() -> void:
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	var failures := 0
	for pose in [Vector3(45,0.65,0), Vector3(60,0.4,144), Vector3(80,0.85,360), Vector3(150,0.85,0), Vector3(100,0.4,144), Vector3(180,1.2,360)]:
		world._distance = pose.x
		world._pitch = pose.y
		var flight := Flight.new()
		flight.advance_prelaunch_time(pose.z)
		world.sync_flight(flight.telemetry(), 0)
		world._rocket.hide()
		world._planet.show()
		var terrain_visible := await capture()
		world._planet.hide()
		var deck_only := await capture()
		var image_scale := Vector2(terrain_visible.get_size()) / world.camera.get_viewport().get_visible_rect().size
		var overlaps := 0
		var samples := 0
		# Sample well inside the slab boundary, including the thin concrete
		# finish. Props are identical in both images and need no special mask.
		for x in range(-55,56):
			for z in range(-55,56):
				var point: Vector3 = world._landscape.global_transform * Vector3(x,0.015,z)
				if world.camera.is_position_behind(point): continue
				var pixel := Vector2i(world.camera.unproject_position(point) * image_scale)
				if not Rect2i(Vector2i.ZERO, terrain_visible.get_size()).has_point(pixel): continue
				var a := terrain_visible.get_pixelv(pixel)
				var b := deck_only.get_pixelv(pixel)
				if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length() > 0.15: overlaps += 1
				samples += 1
		print("DECK pitch=%.2f rotation=%.0f: %d overlaps / %d samples" % [pose.y,pose.z,overlaps,samples])
		if samples < 1000 or overlaps > 0:
			failures += 1
			terrain_visible.save_png("/tmp/launch-deck-overlap-%.0f.png" % pose.z)
	world.queue_free()
	await process_frame
	if failures == 0: print("PASS: terrain stays beneath launch deck at close and wide camera angles and planet rotations")
	else: push_error("Terrain overlaps the launch deck in %d views" % failures)
	quit(0 if failures == 0 else 1)
