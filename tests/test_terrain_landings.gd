extends SceneTree
const Surface = preload("res://scripts/planet_surface.gd")
const Terrain = preload("res://scripts/planet_terrain.gd")
const Flight = preload("res://scripts/flight_model.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _init() -> void:
	var terrain := Surface.home()
	var same := Terrain.new(Surface.HOME)
	var other_settings: Resource = Surface.HOME.duplicate()
	other_settings.terrain_seed += 1
	var different := Terrain.new(other_settings)
	var changes := 0
	for i in range(100):
		var p := Vector3(sin(i*2.4),sin(i*0.31),cos(i*2.4)).normalized()
		check(terrain.elevation(p) == same.elevation(p),"Same seed must reproduce terrain")
		if absf(terrain.elevation(p)-different.elevation(p)) > 10: changes += 1
	check(changes > 80,"Changing the seed generates a distinct planet")
	var mesh: ArrayMesh = terrain.build()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var samples := 0
	for offset in range(0,indices.size(),237):
		var a := vertices[indices[offset]]
		var b := vertices[indices[offset+1]]
		var c := vertices[indices[offset+2]]
		var point := (a+b+c)/3.0
		var normal := (c-a).cross(b-a).normalized()
		if point.y > 55000 or point.length() < 60200 or normal.dot(point.normalized()) < 0.93: continue
		for time in [0.0,360.0]:
			var rotation: Basis = terrain.rotation_at(time)
			var radial: Vector3 = rotation*point
			var hit: Dictionary = terrain.contact(radial,time)
			check(absf(float(hit.radius)-point.length()) < 0.05,"Contact must lie on the rendered triangle, including rotation")
			var flight := Flight.new()
			flight.ignite()
			flight.state.time = time
			flight.state.capsule_only = true
			flight.state.engine_on = false
			flight.state.position = Flight.PLANET_CENTER+radial+radial.normalized()*1.0
			flight.state.velocity = terrain.surface_velocity(radial)-radial.normalized()*2.0
			flight.step(1.0,{"throttle":0.0})
			check(flight.state.status == "landed","Slow capsule lands on elevated terrain")
			check(flight.state.terrain_clearance < 0.1,"Landed capsule touches visible ground")
			var landed_radial: Vector3 = flight.state.position-Flight.PLANET_CENTER
			var landed_hit: Dictionary = terrain.contact(landed_radial,flight.simulation_time())
			check(Vector3(flight.state.terrain_normal).dot(landed_hit.normal) > 0.9999,"Recovery telemetry uses the visible terrain normal")
			var plane_distance := (landed_radial.length()-float(landed_hit.radius))*landed_radial.normalized().dot(landed_hit.normal)
			check(absf(float(flight.state.terrain_plane_distance)-plane_distance) < 0.01,"Recovery plane follows the hillside")
			var previous_velocity: Vector3 = flight.state.velocity
			flight.step(1.0/60.0,{"throttle":0.0})
			var expected_acceleration: Vector3 = (Vector3(flight.state.velocity)-previous_velocity)*60.0
			check(Vector3(flight.state.acceleration_vector).is_equal_approx(expected_acceleration),"Touchdown refreshes acceleration for recovery visuals")
			check(flight.state.altitude > 150.0,"Mountain landing is above sea level")
			check(flight.state.impact_speed < 8.0,"Impact uses speed relative to spinning ground")
			var fast := Flight.new()
			fast.ignite()
			fast.state.time = time
			fast.state.position = Flight.PLANET_CENTER+radial+radial.normalized()*100.0
			fast.state.velocity = -radial.normalized()*20000.0
			fast.step(0.1,{"throttle":0.0})
			check(fast.state.status == "crashed","Fast descent cannot tunnel through elevated terrain")
		samples += 1
		if samples == 8: break
	check(samples == 8,"Landing tests cover eight distinct highland locations")
	var dry := Terrain.new(preload("res://assets/planets/ochre.tres"))
	check(dry.definition.radius != terrain.definition.radius,"Definitions support different world sizes")
	check(dry.build().get_surface_count() == 1,"Second planet generates physical geometry")
	check(dry.contact(Vector3.RIGHT).radius > dry.definition.radius,"Dry world's elevation is physical")
	if failures.is_empty():
		print("PASS: seeded worlds, triangle contact, 16 rotated highland landings and high-speed impacts")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)
