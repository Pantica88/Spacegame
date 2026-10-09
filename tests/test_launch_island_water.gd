extends SceneTree

const Terrain = preload("res://scripts/planet_terrain.gd")
const Definition = preload("res://scripts/planet_definition.gd")

func _init() -> void:
	var ocean_samples := 0
	for seed_value in [73129, 591677, 591678]:
		var settings := Definition.new()
		settings.terrain_seed = seed_value
		var enabled := Terrain.new(settings)
		settings.launch_site = false
		var disabled := Terrain.new(settings)
		for latitude in range(1, 180):
			var angle := deg_to_rad(float(latitude))
			for longitude in range(0, 360, 5):
				var azimuth := deg_to_rad(float(longitude))
				var direction := Vector3(sin(angle)*sin(azimuth), cos(angle), sin(angle)*cos(azimuth))
				var local := Terrain.LAUNCH_BASIS.transposed() * direction
				if local.y > 0.0 and Vector2(local.x, local.z).length()*settings.radius < 3000.0:
					continue
				var original: float = disabled.elevation(direction)
				var actual: float = enabled.elevation(direction)
				if original != actual or not enabled.color_at(direction, actual).is_equal_approx(disabled.color_at(direction, original)):
					push_error("Launch island changed terrain or water outside its local footprint")
					quit(1)
					return
				if original < -120.0 and direction.y > 0.81:
					ocean_samples += 1
		if enabled.elevation(Terrain.LAUNCH_DIRECTION) != 0.0 or enabled.color_at(Terrain.LAUNCH_DIRECTION, enabled.elevation(Terrain.LAUNCH_DIRECTION)).a > 0.001:
			push_error("Launch island must retain a dry flat center at the building height")
			quit(1)
			return
	if ocean_samples == 0:
		push_error("Regression must cover northern ocean basins")
		quit(1)
		return
	print("PASS: launch island preserves surrounding terrain and water across three seeds (%d northern ocean samples)." % ocean_samples)
	quit(0)
