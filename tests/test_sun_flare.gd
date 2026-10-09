extends SceneTree

const World = preload("res://scripts/world_view.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	world._landscape.hide()
	world.camera.position = Vector3(0, 80000, 0)
	world.camera.look_at(world._sun_physical_position, Vector3.UP)
	world._update_atmosphere()
	var blocker := MeshInstance3D.new()
	blocker.mesh = BoxMesh.new()
	blocker.mesh.size = Vector3(10,10,10)
	world.add_child(blocker)
	blocker.global_position = world.camera.global_position + world._sun_direction * 100.0
	world._update_atmosphere()
	assert(float(world._sky_material.get_shader_parameter("sun_glow_visibility")) > 0.99, "Opaque object does not extinguish the surrounding sun glow")
	blocker.mesh.size = Vector3(1,1,1)
	world._update_atmosphere()
	assert(float(world._sky_material.get_shader_parameter("sun_glow_visibility")) > 0.99, "Partial obstruction keeps the glow steady")
	blocker.hide()
	world._update_atmosphere()
	assert(float(world._sky_material.get_shader_parameter("sun_glow_visibility")) > 0.99, "Glow stays steady when the occluder is hidden")
	blocker.free()
	world.camera.look_at(world._sun_physical_position, Vector3.UP)
	world._update_atmosphere()
	if DisplayServer.get_name() != "headless":
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		capture.save_png("/tmp/aphelion-sun-glow.png")
	world.camera.look_at(world.camera.position - world._sun_direction * 1000.0, Vector3.UP)
	world._update_atmosphere()
	assert(float(world._sky_material.get_shader_parameter("sun_glow_visibility")) == 0.0, "No glow when looking away")
	world.camera.position = Vector3(0, 7000, 0)
	world.camera.look_at(world._sun_physical_position, Vector3.UP)
	world._update_atmosphere()
	assert(float(world._sky_material.get_shader_parameter("sun_glow_visibility")) > 0.99, "Glow stays on during ascent")
	world.camera.position = Vector3(0, 10, 0)
	world.camera.look_at(world._sun_physical_position, Vector3.UP)
	world._update_atmosphere()
	assert(float(world._sky_material.get_shader_parameter("sun_glow_visibility")) > 0.99, "Unobstructed sun retains its halo near the ground")
	world.camera.position = Vector3(0, -200000, 0)
	world.set_sun_direction(Vector3.UP)
	world.camera.look_at(world._sun_body.position, Vector3.FORWARD)
	world._update_atmosphere()
	assert(float(world._sky_material.get_shader_parameter("sun_glow_visibility")) == 0.0, "Planet eclipse hides the glow")
	world.set_mode("workshop")
	assert(float(world._sky_material.get_shader_parameter("sun_glow_visibility")) == 0.0, "Workshop has no sun glow")
	world.free()
	print("PASS: steady sun glow through obstructions, looking away, ground, eclipse and workshop visibility.")
	quit(0)
