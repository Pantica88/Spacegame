extends SceneTree
## Splashes the saved design's capsule (after real staging) and logs its depth.
const Flight = preload("res://scripts/flight_model.gd")

func _init() -> void:
	var profile = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("PROFILE_JSON")))
	var design: Dictionary = profile.design
	var model := Flight.new()
	model.reset(design)
	var terrain = model.terrain
	var direction := Vector3.ZERO
	for i in range(1000):
		var c := Vector3(sin(i * 2.4), sin(i * 0.31), cos(i * 2.4)).normalized()
		if terrain.elevation(c) < -200.0:
			direction = c
			break
	print("elevation ", terrain.elevation(direction), " contact-above-radius ", float(terrain.contact(direction).radius) - float(terrain.definition.radius))
	model.state.status = "flying"
	print("stage1 ", model.execute_stage())
	print("stage2 ", model.execute_stage())
	print("capsule_only ", model.state.capsule_only, " mass ", model._mass_properties())
	var radial: Vector3 = direction * float(terrain.contact(direction).radius)
	model.state.orientation = Basis(Quaternion(Vector3.UP, direction))
	model.state.position = Flight.PLANET_CENTER + radial + direction * 30.0
	model.state.velocity = terrain.surface_velocity(radial) - direction * 7.0
	model.state.max_altitude = 3000.0
	model._has_lifted = true
	model.state.terrain_clearance = 30.0
	model.state.speed = 7.0
	model.state.vertical_speed = -7.0
	print("stage3 ", model.execute_stage())
	for frame in range(60 * 40):
		model.step(1.0 / 60.0, {"throttle": 0.0})
		if frame % 120 == 0:
			var h: float = (Vector3(model.state.position) - Flight.PLANET_CENTER).length() - float(terrain.definition.radius)
			print("t=%5.1f status=%s water=%s above_sea=%.2f immersion=%.2f displaced=%.0f settled=%s clearance=%.2f" % [frame / 60.0, model.state.status, model.state.get("landing_water"), h, float(model.state.get("water_immersion", 0.0)), float(model.state.get("water_displaced_mass", 0.0)), model.state.get("settled"), float(model.state.get("terrain_clearance", -1.0))])
	quit(0)
