extends SceneTree
## Graphical regression: fresh atmospheric frames during storm-cap travel.
## Compares all four temporal phases against freshly marched half-resolution
## frames at the same poses. Uses generated weather, never the player's save.
const Clouds = preload("res://scripts/cloud_layer.gd")
const Definition = preload("res://scripts/planet_definition.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
const Tiles = preload("res://scripts/cloud_brush_library.gd")
const START := Vector3(0, 608166.1, 35000)
var camera: Camera3D
var clouds: Node3D
var definition: Resource
var direction := 0.0
var frame := 0
var failures: Array[String] = []
var legacy_mode := false

func _initialize() -> void:
	_run.call_deferred()

func _tick() -> void:
	if direction != 0.0: frame += 1
	camera.position = START + Vector3.UP * direction * frame * 8.0
	clouds.update_weather(definition, camera.position * 0.001, Vector3(0.3, 0.9, 0.3).normalized(), true)
	# Reproduce the former atmospheric reconstruction for the reference defect.
	if legacy_mode:
		clouds._fresh_atmospheric_storms = false
		clouds._sync_lowres()

func _error(a: Image, b: Image) -> float:
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var x := a.get_data()
	var y := b.get_data()
	var total := 0.0
	for i in x.size(): total += absi(x[i] - y[i])
	return total / (255.0 * x.size())

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Cloud motion regression requires a graphical display")
		quit(1)
		return
	root.size = Vector2i(960, 600)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("4686b6")
	scene.add_child(environment)
	camera = Camera3D.new()
	camera.near = 10.0
	camera.far = 2000000.0
	camera.fov = 40.0
	scene.add_child(camera)
	camera.position = START
	camera.look_at(Vector3(0, START.y, 0), Vector3.UP)
	camera.current = true
	definition = Definition.new()
	definition.cloud_weather = Weather.new()
	definition.cloud_weather.stamp(Vector3.UP, 0.025, Tiles.tile("mushroom"), 1.0)
	definition.cloud_wind_speed = 0.0
	definition.cloud_evolution = 0.0
	clouds = Clouds.new()
	scene.add_child(clouds)
	clouds.set_process(false)
	var noise: NoiseTexture3D = clouds.material_override.get_shader_parameter("cloud_noise")
	if noise.get_data().is_empty(): await noise.changed
	process_frame.connect(_tick)
	var production: Shader = clouds._resolve_materials[0].shader
	var legacy := Shader.new()
	legacy.code = production.code.replace("if (reprojection_storm_radius_km > reprojection_radius_km)", "if (false)")
	var out := "/tmp/aphelion-cloud-motion-regression"
	DirAccess.make_dir_recursive_absolute(out)
	for d in [1.0, -1.0]:
		var captures := {}
		for mode in ["legacy", "fixed", "reference"]:
			legacy_mode = mode == "legacy"
			direction = 0.0
			frame = 0
			clouds.temporal = mode != "reference"
			for material in clouds._resolve_materials:
				material.shader = legacy if mode == "legacy" else production
			for i in range(40): await process_frame
			await RenderingServer.frame_post_draw
			direction = d
			while frame < 64:
				await RenderingServer.frame_post_draw
				if frame >= 61:
					var shot := root.get_texture().get_image()
					captures[mode + str(frame)] = shot
					shot.save_png("%s/%s-%s-%d.png" % [out, "up" if d > 0 else "down", mode, frame])
			direction = 0.0
		var old_error := 0.0
		var new_error := 0.0
		for i in range(61, 65):
			old_error += _error(captures["legacy" + str(i)], captures["reference" + str(i)]) / 4.0
			new_error += _error(captures["fixed" + str(i)], captures["reference" + str(i)]) / 4.0
		print("MOTION direction=%+.0f legacy_error=%.6f fixed_error=%.6f" % [d, old_error, new_error])
		if old_error < 0.0001 or new_error >= old_error * 0.85:
			failures.append("Fresh atmospheric frames must reduce moving-frame error in both directions")
	process_frame.disconnect(_tick)
	scene.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: fresh atmospheric storm frames remove vertical-motion banding across all four phases")
	quit(0 if failures.is_empty() else 1)
