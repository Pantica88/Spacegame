extends SceneTree
## Three sloped highland landings: CPU cost of flight and visual synchronization.
const Parts = preload("res://scripts/parts.gd")
const Craft = preload("res://scripts/craft_model.gd")
const TimedCloth = preload("res://tests/benchmark_parachute.gd").TimedCloth
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var mesh: ArrayMesh = game.flight.terrain.build()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var sites: Array[Vector3] = []
	for offset in range(0,indices.size(),237):
		var a := vertices[indices[offset]]
		var b := vertices[indices[offset+1]]
		var c := vertices[indices[offset+2]]
		var p := (a+b+c)/3.0
		var normal := (c-a).cross(b-a).normalized()
		if p.y > game.flight.PLANET_RADIUS*0.92 or p.length() < game.flight.PLANET_RADIUS+200 or normal.dot(p.normalized()) > 0.999 or normal.dot(p.normalized()) < 0.8: continue
		sites.append(p)
		if sites.size() == 3: break
	assert(sites.size() == 3)
	for site in sites:
		var rate := 1.0
		var design := Parts.default_design()
		var assembly := Craft.migrate(design)
		Craft.add_part(assembly,"parachute")
		game.design = Craft.project(assembly,design)
		await game._roll_out()
		var module = game.world._parachute_module
		# Exercise live terrain draping; normal gameplay now fades a baked collapse.
		module.fade_after_landing = false
		module.canopy.free()
		module.canopy = TimedCloth.new()
		module.add_child(module.canopy)
		game.world._chute = module.canopy
		game._set_throttle(0.0)
		game.recorded = true
		game.flight.state.status = "flying"
		game.flight.state.capsule_only = true
		game.flight.state.chute_deployed = true
		game.flight.state.position = game.flight.PLANET_CENTER+site+site.normalized()*0.01
		game.flight.state.orientation = Basis(Quaternion(Vector3.UP,site.normalized()))
		game.flight.state.velocity = game.flight.terrain.surface_velocity(site)-site.normalized()*2.0
		game.flight._has_lifted = true
		game.flight.step(1.0/60.0,{"throttle":0.0})
		assert(game.flight.state.status in ["landed","crashed"])
		game.world.sync_flight(game.flight.telemetry(),3.0,0.0)
		game.warp = rate
		game.physical_warp = true
		for phase in ["touchdown","ground","rest","settled","asleep"]:
			module.canopy.solver_us = 0
			module.canopy.mesh_us = 0
			var start := Time.get_ticks_usec()
			var maximum := 0
			var physics_us := 0
			var visuals_us := 0
			for frame in range(600):
				var tick := Time.get_ticks_usec()
				game.flight.step(rate/60.0,{"throttle":0.0})
				var after_physics := Time.get_ticks_usec()
				game.world.sync_flight(game.flight.telemetry(),rate/60.0,1.0/60.0)
				var plane_normal: Vector3 = module.global_basis.orthonormalized()*module.surface_normal
				assert(plane_normal.dot(game.flight.state.terrain_normal) > 0.9999,"Recovery uses the terrain triangle plane")
				physics_us += after_physics-tick
				visuals_us += Time.get_ticks_usec()-after_physics
				maximum = maxi(maximum,Time.get_ticks_usec()-tick)
			print("RECOVERY %.0fx %s: %.3f ms/tick, max %.3f, cloth sleeping=%s" % [rate,phase,(Time.get_ticks_usec()-start)/600000.0,maximum/1000.0,game.world._parachute_module.canopy.sleeping])
			print("HILLSIDE ",site," physics ",physics_us/600000.0," visuals ",visuals_us/600000.0," solver ",module.canopy.solver_us/600000.0," mesh ",module.canopy.mesh_us/600000.0," settled ",game.flight.state.get("settled",false)," vertices ",game.world._parachute_module.canopy.fabric.mesh.surface_get_array_len(0)," cords ",game.world._parachute_module.canopy.cord_transforms.size())

		assert(game.flight.state.get("settled", false),"Hillside pod must stop rolling")
		assert(module.canopy.sleeping,"Settled hillside recovery must let cloth sleep")
		# Fabric spreads metres beyond the contact triangle; it must rest on the
		# sloped terrain itself, not sink below it toward the contact plane.
		var deepest := INF
		for p in module.canopy.points:
			var world: Vector3 = module.canopy.global_transform * p
			var radial: Vector3 = world + game.world._flight_position - game.flight.PLANET_CENTER
			var ground: float = game.flight.terrain.contact(radial,game.flight.simulation_time()).radius
			deepest = minf(deepest,radial.length()-ground)
		print("HILLSIDE canopy lowest point above terrain ",deepest)
		assert(deepest > -0.1,"Resting canopy must not sink into hillside terrain")
		module.canopy.solver_us = 0
		module.canopy.mesh_us = 0
		for frame in range(120):
			game.flight.step(1.0/60.0,{"throttle":0.0})
			game.world.sync_flight(game.flight.telemetry(),1.0/60.0,1.0/60.0)
		assert(module.canopy.sleeping and module.canopy.solver_us == 0 and module.canopy.mesh_us == 0,"Rotating terrain must not wake resting cloth or rebuild its mesh")
	print("PASS: three hillside pods stop rolling and their resting parachutes skip simulation and mesh rebuilds")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	quit()
