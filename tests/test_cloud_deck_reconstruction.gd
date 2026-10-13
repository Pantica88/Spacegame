extends SceneTree
## Atmospheric storm views render fresh frames and reset history at orbit.
const Clouds = preload("res://scripts/cloud_layer.gd")
const Definition = preload("res://scripts/planet_definition.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	root.size = Vector2i(800, 600)
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	var clouds := Clouds.new()
	scene.add_child(clouds)
	clouds.set_process(false)
	var definition := Definition.new()
	definition.cloud_weather = Weather.new()
	var painted := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	painted.fill(Color(0, 0, 0, 1))
	definition.cloud_weather.restore(painted)
	var was_fresh := false
	# Include the reported heights, both sides of the former band, and orbit.
	for altitude in [100000.0, 89999.0, 16000.0, 8000.0, 6701.0, 6001.0, 6000.0, 5885.0, 5299.0, 4100.0, 3500.0, 30.0, 4100.0, 6000.0, 16000.0, 89999.0, 90001.0, 100000.0]:
		await process_frame
		camera.position = Vector3(0, definition.radius + altitude, 0)
		clouds.update_weather(definition, camera.position * 0.001, Vector3.UP, true)
		clouds._sync_lowres()
		var fresh: bool = altitude <= 90000.0
		_check(clouds._lowres_material.get_shader_parameter("temporal_march") == not fresh,
			"Fresh atmospheric storm samples at %.0f m" % altitude)
		_check(clouds._lowres.size == (Vector2i(400, 300) if fresh else Vector2i(200, 150)),
			"Fresh mode retains half-resolution detail instead of enlarging quarter-frame samples")
		if fresh:
			for target in clouds._resolve:
				_check(target.render_target_update_mode == SubViewport.UPDATE_DISABLED, "No stale reconstruction pass in atmospheric storm views")
		elif was_fresh:
			var material: ShaderMaterial = clouds._resolve_materials[clouds._temporal_frame % 2]
			_check(not material.get_shader_parameter("history_valid"), "Leaving the atmosphere must start new history")
		was_fresh = fresh
	# The guard follows each world's atmosphere, not a fixed home-world height.
	definition.atmosphere_height = 30000.0
	await process_frame
	camera.position = Vector3(0, definition.radius + 35000.0, 0)
	clouds.update_weather(definition, camera.position * 0.001, Vector3.UP, true)
	clouds._sync_lowres()
	_check(clouds._lowres_material.get_shader_parameter("temporal_march"), "Reconstruction resumes above a shorter atmosphere")
	# Ordinary low clouds still have a representative low-deck depth.
	painted.fill(Color(1, 0, 0, 0))
	definition.cloud_weather.restore(painted)
	await process_frame
	camera.position = Vector3(0, definition.radius + 6000.0, 0)
	clouds.update_weather(definition, camera.position * 0.001, Vector3.UP, true)
	clouds._sync_lowres()
	_check(clouds._lowres_material.get_shader_parameter("temporal_march"), "Storm-free weather retains reconstruction inside the deck")
	clouds.temporal = false
	await process_frame
	clouds._sync_lowres()
	_check(not clouds._lowres_material.get_shader_parameter("temporal_march"), "Explicit temporal disable still works for storm-free weather")
	scene.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: fresh atmospheric storm frames preserve resolution, orbital history and storm-free reconstruction")
	quit(0 if failures.is_empty() else 1)
