extends SceneTree
const Parts = preload("res://scripts/parts.gd")
const Flight = preload("res://scripts/flight_model.gd")
const World = preload("res://scripts/world_view.gd")

func _initialize() -> void:
	var design := Parts.default_design()
	var assembly := Parts.Craft.migrate(design)
	for index in range(8):
		var mount := Parts.Craft.node("separator_%d" % (10 + index), "separator", "tank_2", "surface:%d" % index)
		mount.rotation = float(index) * 45.0
		assembly.parts.append(mount)
		assembly.parts.append(Parts.Craft.node("boosters_%d" % (20 + index), "boosters", mount.id, "bottom"))
	assembly.stages = Parts.Craft.default_stages({"boosters": true})
	assembly.next_id = 30
	assert(Parts.Craft.valid(assembly))
	design.assembly = assembly
	var flight := Flight.new()
	flight.reset(design)
	assert(flight._radial_layout.boosters.size() == 8)
	var expected := Parts.mass_properties(flight._design, flight.state.fuel, flight.state.booster_fuel, true)
	assert(flight._mass_properties() == expected, "Cached booster layout preserves mass and inertia")
	flight.ignite()
	flight.state.position = Vector3(0, 30000, 0)
	flight.state.velocity = Vector3(620, 0, 0)
	flight.step(1.0 / 60.0, {"throttle": 1.0})
	var start := Time.get_ticks_usec()
	for frame in range(120):
		flight.step(1.0 / 60.0, {"throttle": 1.0})
	assert(flight.state.status == "flying")
	print("EIGHT BOOSTERS: powered physics %.3f ms/tick" % (float(Time.get_ticks_usec() - start) / 120000.0))
	var world := World.new()
	var flames: Array[Node3D] = []
	var boosters: Array[Node3D] = []
	start = Time.get_ticks_usec()
	for index in range(8):
		boosters.append(world._make_booster(1.0, flames))
	assert(flames.size() == 32)
	var mesh: ArrayMesh = flames[0].get_child(0).mesh
	for flame in flames:
		assert(flame.get_child(0).mesh == mesh, "All 32 booster nozzles share one mesh")
	var vertices := mesh.surface_get_array_len(0)
	var indices := mesh.surface_get_array_index_len(0)
	assert(vertices < 1200 and indices == 4608)
	print("EIGHT BOOSTERS: 32 plumes, %d shared vertices, %d triangles/plume, %.2f ms build" % [vertices, indices / 3, float(Time.get_ticks_usec() - start) / 1000.0])
	for booster in boosters: booster.free()
	world.free()
	print("PASS: eight-booster physics, mass properties and shared exhaust geometry")
	quit()
