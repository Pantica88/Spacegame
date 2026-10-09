extends SceneTree
const Flight = preload("res://scripts/flight_model.gd")
const Parts = preload("res://scripts/parts.gd")
var failures: Array[String] = []
var count := 0

func check(ok: bool, message: String) -> void:
	count += 1
	if not ok: failures.append(message)

func flying(boosters: bool = false):
	var model = Flight.new()
	model.reset({"boosters": boosters})
	model.state.status = "flying"
	model.state.position = Vector3(0,30000,0)
	model.state.velocity = Vector3(120,30,-15)
	model.state.angular_velocity = Vector3(.2,.1,-.15)
	model.state.orientation = Basis(Vector3(1,2,3).normalized(),.5)
	model.telemetry()
	return model

func momentum(model) -> Vector3:
	var result: Vector3 = model.state.velocity * model._current_mass()
	for piece in model.state.detached: result += piece.velocity * piece.mass
	return result

func _initialize() -> void:
	# Decoupling must not create overlapping colliders and positional kicks.
	for boosters in [false, true]:
		for tanks in [1, 3, 8]:
			var release = Flight.new()
			release.reset({"boosters":boosters,"tanks":tanks})
			release.state.status = "flying"
			release.state.position = Vector3(0,30000,0)
			release.state.orientation = Basis(Vector3.RIGHT,0.4)
			release._separate_core()
			var released: Dictionary = release.state.detached[0]
			var core_position: Vector3 = released.position
			var capsule_position: Vector3 = release.state.position
			release._resolve_body_collisions()
			check(Vector3(released.position).distance_to(core_position) < 0.001,"Core has no collision-induced displacement at release")
			check(Vector3(release.state.position).distance_to(capsule_position) < 0.001,"Capsule has no collision-induced displacement at release")
	var model = flying(true)
	var initial_momentum := momentum(model)
	var orientation: Basis = model.state.orientation
	var position: Vector3 = model.state.position
	model.stage()
	check(model.state.detached.size() == 2,"Boosters become two independent bodies")
	check(momentum(model).distance_to(initial_momentum) < .08,"Booster release conserves linear momentum including spin")
	var left: Dictionary = model.state.detached[0]
	var right: Dictionary = model.state.detached[1]
	check(left.source_index == 0 and right.source_index == 1,"Each body identifies exactly one rendered booster")
	check((right.position-left.position).distance_to(orientation.x*3.92) < .003,"Boosters release at their actual mounting positions")
	var initial_gap: float = left.position.distance_to(right.position)
	var angular_momentum: Vector3 = left.angular_momentum
	var before_orientation: Basis = left.orientation
	model._integrate_detached(.016)
	check(left.position.distance_to(right.position) > initial_gap,"Booster springs move the pair apart")
	check(not left.orientation.is_equal_approx(before_orientation),"Detached parts inherit rotation and tumble")
	check(Vector3(left.angular_momentum).distance_to(angular_momentum) < .001,"Vacuum preserves angular momentum")
	model = flying()
	initial_momentum = momentum(model)
	position = model.state.position
	orientation = model.state.orientation
	var top: float = model._stack_top()
	var total_mass: float = model._current_mass()
	var expected_core_center: Vector3 = (model._stack_center()*total_mass-Vector3(0,top+1.3,0)*Parts.CAPSULE_MASS)/(total_mass-Parts.CAPSULE_MASS)
	model.stage()
	check(momentum(model).distance_to(initial_momentum) < .08,"Core release conserves momentum with capsule recoil")
	check(Vector3(model.state.position).distance_to(position+orientation.y*top) < .003,"Capsule reference shifts without a visual teleport")
	var core: Dictionary = model.state.detached[0]
	check(Vector3(core.position).distance_to(position+orientation*expected_core_center) < .003,"Core rotates about its own center")
	core.velocity = Vector3.ZERO
	core.angular_momentum = Vector3.ZERO
	core.thrust = 0.0
	var expected: Vector3 = model._debris_gravity(core.position, model._debris_surfaces(model.simulation_time()))*.1
	model._integrate_detached(.1)
	check(Vector3(core.velocity).distance_to(expected)<.001,"Detached vacuum acceleration matches gravity")
	# No drag on debris comoving with the rotating atmosphere.
	core.position = Vector3(0,1000,0)
	core.velocity = model.terrain.surface_velocity(core.position-Flight.PLANET_CENTER)
	var before_velocity: Vector3 = core.velocity
	expected = model._debris_gravity(core.position, model._debris_surfaces(model.simulation_time()))*.01
	model._integrate_detached(.01)
	check((Vector3(core.velocity)-before_velocity).distance_to(expected)<.001,"Drag is relative to the rotating air")
	# Broadside debris has a larger drag area than end-on debris.
	var a = flying()
	var b = flying()
	a.stage()
	b.stage()
	var pa: Dictionary = a.state.detached[0]
	var pb: Dictionary = b.state.detached[0]
	for piece in [pa,pb]:
		piece.position = Vector3(0,1000,0)
		piece.velocity = Vector3(0,0,200)
		piece.thrust = 0.0
		piece.angular_momentum = Vector3.ZERO
	pa.orientation = Basis.IDENTITY
	pb.orientation = Basis(Vector3.RIGHT,PI*.5)
	a._integrate_detached(.01)
	b._integrate_detached(.01)
	check(pa.velocity.z < pb.velocity.z,"Broadside stages experience more drag")
	# Live solids keep burning after release, individually accounting for fuel.
	model = flying(true)
	model.state.boosters_on = true
	model.stage()
	left = model.state.detached[0]
	var fuel: float = left.fuel
	model._integrate_detached(.02)
	check(left.fuel < fuel and is_equal_approx(left.mass,left.dry_mass+left.fuel),"Released live boosters continue burning with correct mass")
	# Fast impact sweeps the body's lowest extent, not only its center.
	model = flying()
	model.state.orientation = Basis.IDENTITY
	model.stage()
	core = model.state.detached[0]
	core.position = Vector3(0,20,0)
	core.velocity = Vector3(0,-1500,0)
	core.angular_momentum = Vector3.ZERO
	core.thrust = 0.0
	model._integrate_detached(.02)
	check(model.state.detached.is_empty(), "Surface impact removes debris from simulation")
	check(model.state.surface_impacts.size() == 1, "Surface impact emits one explosion")
	model._integrate_detached(.1)
	check(model.state.surface_impacts.size() == 1, "Destroyed debris cannot explode again")
	# Removing the first stage preserves the identity of the surviving one.
	model = flying(true)
	model.stage()
	left = model.state.detached[0]
	right = model.state.detached[1]
	left.position = Vector3(0, 20, 0)
	left.velocity = Vector3(0, -1500, 0)
	left.angular_momentum = Vector3.ZERO
	left.thrust = 0.0
	model._integrate_detached(.02)
	check(model.state.detached.size() == 1 and model.state.detached[0].id == right.id, "Surviving stage keeps its stable identity")
	# Background integration uses the same surface destruction path.
	right.background = true
	right.position = Vector3(0, 20, 0)
	right.velocity = Vector3(0, -1500, 0)
	right.angular_momentum = Vector3.ZERO
	right.thrust = 0.0
	model._integrate_detached(.02, true)
	check(model.state.detached.is_empty(), "Background surface impacts also remove debris")
	model = flying()
	model.stage()
	core = model.state.detached[0]
	var bodies: Array = model._debris_surfaces(model.simulation_time())
	if bodies.size() > 1:
		var body: Dictionary = bodies[1]
		var surface: Dictionary = body.terrain.contact(Vector3.UP, model.simulation_time())
		var normal: Vector3 = surface.normal
		core.orientation = Basis.IDENTITY
		core.angular_momentum = Vector3.ZERO
		core.thrust = 0.0
		core.position = Vector3(body.center) + Vector3.UP * float(surface.radius) - model._debris_support(core, normal) + normal * 20.0
		core.velocity = Vector3(body.velocity) - normal * 1500.0
		model._integrate_detached(.02)
		check(model.state.detached.is_empty() and model.state.surface_impacts.size() == 1, "Moon impacts destroy debris and emit an explosion")
	model = flying()
	model.stage()
	core = model.state.detached[0]
	core.position = Vector3(0, 20, 0)
	core.velocity = Vector3(0, -1500, 0)
	core.thrust = 0.0
	core.angular_momentum = Vector3.ZERO
	model.state.status = "crashed"
	var flight_time: float = model.state.time
	model.step(.1, {})
	check(model.state.detached.is_empty(), "Debris still hits the ground after the active craft crashes")
	check(model.simulation_time() > flight_time and model.state.time == flight_time, "Postflight world time advances without changing flight duration")
	var snapshot: Dictionary = model.telemetry()
	snapshot.surface_impacts.clear()
	check(model.telemetry().surface_impacts.is_empty(), "Rendered explosion events do not replay on later telemetry snapshots")
	# Gentle impacts bounce; the limit measures normal contact speed, not orbit speed.
	model = flying()
	model.state.orientation = Basis.IDENTITY
	model.stage()
	core = model.state.detached[0]
	core.orientation = Basis.IDENTITY
	core.angular_momentum = Vector3.ZERO
	core.thrust = 0.0
	core.position = Vector3(0, float(core.length) * .5, 0)
	var home_body: Dictionary = model._debris_surfaces(0.0)[0]
	var ground_velocity: Vector3 = model.terrain.surface_velocity(Vector3(0, Flight.PLANET_RADIUS, 0))
	var template: Dictionary = core.duplicate(true)
	core.velocity = ground_velocity + Vector3(0, -5, 0)
	model._debris_contact(core, {"position": Vector3(0, Flight.PLANET_RADIUS, 0), "normal": Vector3.UP}, .016, 0.0, home_body)
	check(not core.get("destroyed", false) and (Vector3(core.velocity) - ground_velocity).y > 1.0, "Gentle surface impact rebounds without exploding")
	check(model.state.surface_impacts.is_empty(), "Bounces do not emit explosions")
	for speed_at_contact in [Flight.DEBRIS_BREAKUP_SPEED, Flight.DEBRIS_BREAKUP_SPEED + .1]:
		var sample: Dictionary = template.duplicate(true)
		sample.velocity = ground_velocity + Vector3(0, -speed_at_contact, 0)
		model._debris_contact(sample, {"position": Vector3(0, Flight.PLANET_RADIUS, 0), "normal": Vector3.UP}, .016, 0.0, home_body)
		check(bool(sample.get("destroyed", false)) == (speed_at_contact > Flight.DEBRIS_BREAKUP_SPEED), "Breakup speed boundary is strict")
	var sliding: Dictionary = template.duplicate(true)
	sliding.velocity = ground_velocity + Vector3(80, -1, 0)
	model._debris_contact(sliding, {}, .016, 0.0, home_body)
	check(not sliding.get("destroyed", false), "Fast tangential motion slides instead of triggering normal-impact breakup")
	model.state.surface_impacts.clear()
	model.state.detached = [template]
	template.velocity = ground_velocity
	for tick in range(1800):
		model._integrate_detached(1.0 / 60.0)
		model.state.time += 1.0 / 60.0
	check(model.state.detached.is_empty() and model.state.surface_impacts.is_empty(), "Settled debris retires without exploding")
	# Low-gravity moon contacts retain their bounce and continue moving afterward.
	model = flying()
	model.state.orientation = Basis.IDENTITY
	model.stage()
	core = model.state.detached[0]
	bodies = model._debris_surfaces(0.0)
	if bodies.size() > 1:
		var moon: Dictionary = bodies[1]
		var contact: Dictionary = moon.terrain.contact(Vector3.UP, 0.0)
		var normal: Vector3 = contact.normal
		var point := Vector3.UP * float(contact.radius)
		core.angular_momentum = Vector3.ZERO
		core.thrust = 0.0
		core.position = Vector3(moon.center) + point - model._debris_support(core, normal)
		var moon_velocity: Vector3 = Vector3(moon.velocity) + moon.terrain.surface_velocity(point)
		core.velocity = moon_velocity - normal * 5.0
		model._debris_contact(core, {"position": point, "normal": normal}, .016, 0.0, moon)
		check(not core.get("destroyed", false) and (Vector3(core.velocity) - moon_velocity).dot(normal) > 0.0, "Moon impact bounces relative to its moving surface")
		model._integrate_detached(.05)
		check(model.state.detached.size() == 1 and model.state.surface_impacts.is_empty(), "Moon bounce stays simulated instead of disappearing on contact")
	if failures.is_empty():
		print("PASS: %d detached-body physics checks" % count)
		quit()
	else:
		for message in failures: push_error(message)
		quit(1)
