extends SceneTree
## Render-order regression: the cloud composite must not slice nearby flames.
const World = preload("res://scripts/world_view.gd")
const Clouds = preload("res://scripts/cloud_layer.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	world.sync_flight({"position": Vector3(0, 12000, 0), "altitude": 12000.0,
		"status": "flying", "heat_glow": 0.8, "heating_rate": 180.0, "air_velocity": Vector3(1000, 0, 0)}, 0.05)
	var materials: Array[ShaderMaterial] = [world._heat_material, world._heat_halo_material,
		world._heat_outer_material, world._heat_trail.material_override]
	var flame: Node3D = world._engine_flames.values()[0][0]
	for child in flame.get_children():
		if child is MeshInstance3D: materials.append(child.material_override)
	var cloud_priority: int = world._clouds.material_override.render_priority
	for material in materials:
		assert(material.render_priority > cloud_priority, "Nearby flame and heat materials draw after clouds")
		assert(not material.shader.code.contains("depth_test_disabled"), "Effects remain occluded by the hull and terrain")
	if DisplayServer.get_name() != "headless":
		world.hide()
		world._environment.background_mode = Environment.BG_COLOR
		world._environment.background_color = Color.BLACK
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(0, 0, 5)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 4.0
		camera.current = true
		var cloud := Clouds.new()
		root.add_child(cloud)
		# Isolate compositing from weather/noise: a black cloud covers the upper
		# half of the frame, exactly where the reported flame cut occurs.
		var composite := Shader.new()
		composite.code = "shader_type spatial; render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled; void vertex(){POSITION=vec4(VERTEX.xy,1.0,1.0);} void fragment(){if(SCREEN_UV.y>0.5){discard;} ALBEDO=vec3(0.0); ALPHA=1.0;}"
		cloud.material_override.shader = composite
		var effect := MeshInstance3D.new()
		effect.mesh = QuadMesh.new()
		effect.mesh.size = Vector2(2, 2)
		root.add_child(effect)
		var diagnostic := Shader.new()
		diagnostic.code = "shader_type spatial; render_mode unshaded, blend_add, depth_draw_never; void fragment(){ALBEDO=vec3(0.0,1.0,0.0); ALPHA=1.0;}"
		for source in materials:
			var material := source.duplicate() as ShaderMaterial
			material.next_pass = null
			material.shader = diagnostic
			effect.material_override = material
			cloud.show()
			var frame := await _capture()
			var upper := frame.get_pixel(frame.get_width() / 2, int(frame.get_height() * 0.4))
			var lower := frame.get_pixel(frame.get_width() / 2, int(frame.get_height() * 0.6))
			assert(upper.g > 0.5 and absf(upper.g - lower.g) < 0.01, "Cloud boundary cannot cut the foreground effect")
			frame.save_png("/tmp/aphelion-flame-cloud-overlap.png")
		# Raising transparent priority must not turn off normal solid occlusion.
		cloud.hide()
		var blocker := MeshInstance3D.new()
		blocker.mesh = QuadMesh.new()
		blocker.mesh.size = Vector2(2, 2)
		blocker.position.z = 1.0
		var solid := StandardMaterial3D.new()
		solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		solid.albedo_color = Color.RED
		blocker.material_override = solid
		root.add_child(blocker)
		var blocked := await _capture()
		assert(blocked.get_pixel(blocked.get_width() / 2, blocked.get_height() / 2).g < 0.01, "Opaque geometry still hides effects")
		blocker.queue_free()
		effect.queue_free()
		cloud.queue_free()
		camera.queue_free()
	world.queue_free()
	await process_frame
	print("PASS: exhaust, nozzle glow, hull heat, halos and wake composite after clouds with solid depth occlusion")
	quit()

func _capture() -> Image:
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
