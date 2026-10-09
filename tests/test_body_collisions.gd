extends SceneTree
const Collision = preload("res://scripts/body_collisions.gd")
const Flight = preload("res://scripts/flight_model.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func body(position: Vector3, velocity: Vector3, mass: float = 100.0, length: float = 3.0) -> Dictionary:
	return {"position":position,"velocity":velocity,"mass":mass,"orientation":Basis.IDENTITY,
		"inertia":Vector3(1, .25, 1)*mass,"angular_momentum":Vector3.ZERO,"landed":false,"settle_time":0.0,
		"bound":length*.5,"min_radius":.5,"shapes":[{"offset":Vector3.ZERO,"radius":.5,"length":length}]}

func energy(a: Dictionary) -> float:
	return .5*float(a.mass)*Vector3(a.velocity).length_squared()+.5*Vector3(a.angular_momentum).dot(Collision.omega(a))

func momentum(a: Dictionary, b: Dictionary) -> Vector3:
	return a.velocity*a.mass+b.velocity*b.mass

func angular_momentum(a: Dictionary, b: Dictionary) -> Vector3:
	return a.angular_momentum+b.angular_momentum+Vector3(a.position).cross(a.velocity*a.mass)+Vector3(b.position).cross(b.velocity*b.mass)

func _initialize() -> void:
	var a := body(Vector3(-.49999,0,0),Vector3(10,0,0))
	var b := body(Vector3(.49999,0,0),Vector3(-2,0,0),200)
	var p := momentum(a,b)
	var e := energy(a)+energy(b)
	Collision.resolve(a,b)
	check(momentum(a,b).distance_to(p)<.001,"Head-on collision conserves total momentum")
	check(b.velocity.x>a.velocity.x,"Head-on collision reverses closing speed")
	check(energy(a)+energy(b)<=e+.001,"Collision does not create kinetic energy")
	check(Vector3(a.angular_momentum).length()<.001 and Vector3(b.angular_momentum).length()<.001,"Centered side impact does not create spurious spin")
	a = body(Vector3(-.49999,-.7,0),Vector3(10,2,0))
	b = body(Vector3(.49999,.7,0),Vector3(-2,-1,0),200)
	p = momentum(a,b)
	var angular := angular_momentum(a,b)
	e = energy(a)+energy(b)
	Collision.resolve(a,b)
	check(momentum(a,b).distance_to(p)<.001,"Glancing collision conserves linear momentum")
	check(angular_momentum(a,b).distance_to(angular)<.01,"Glancing collision conserves angular momentum")
	check(Vector3(a.angular_momentum).length()>1.0,"Off-center impact induces spin")
	check(energy(a)+energy(b)<=e+.01,"Friction removes energy in a glancing collision")
	# Deep pre-existing overlaps are separated without injecting energy.
	a = body(Vector3(-.2,0,0),Vector3.ZERO)
	b = body(Vector3(.2,0,0),Vector3.ZERO)
	Collision.resolve(a,b)
	check(Vector3(a.position).distance_to(b.position)>.999,"Overlapping parts are pushed apart")
	check(energy(a)+energy(b)<.0001,"Overlap correction does not launch stationary parts")
	b.landed = true
	a.position = Vector3(-.49999,0,0)
	b.position = Vector3(.49999,0,0)
	a.velocity = Vector3(10,0,0)
	Collision.resolve(a,b)
	check(not b.landed and b.velocity.x>0,"Impact wakes resting debris")
	# Adaptive stepping uses relative velocity: a shared orbital speed is harmless.
	a = body(Vector3(-3,0,0),Vector3(1500,0,0))
	b = body(Vector3(3,0,0),Vector3(-1500,0,0))
	check(Collision.step_limit([a,b],1.0/60.0)<.0001,"Fast nearby bodies force anti-tunneling substeps")
	b.velocity = a.velocity
	check(is_equal_approx(Collision.step_limit([a,b],1.0/60.0),1.0/60.0),"Co-moving orbital bodies do not force unnecessary tiny steps")
	# Full flight integration: two boosters would exchange sides in one old step.
	var model = Flight.new()
	model.reset({"boosters":true})
	model.state.status = "flying"
	model.state.position = Vector3(0,30000,0)
	model.state.velocity = Vector3.ZERO
	model.stage()
	var left: Dictionary = model.state.detached[0]
	var right: Dictionary = model.state.detached[1]
	for piece in [left,right]:
		piece.thrust = 0.0
		piece.angular_momentum = Vector3.ZERO
	left.position = Vector3(-3,30030,0)
	right.position = Vector3(3,30030,0)
	left.velocity = Vector3(1500,0,0)
	right.velocity = Vector3(-1500,0,0)
	model.step(1.0/60.0,{"throttle":0,"sas":false})
	check(left.position.x<right.position.x,"Fast detached bodies cannot pass through each other")
	check(left.velocity.x<0 and right.velocity.x>0,"Fast bodies bounce after the collision")
	# Debris hitting the controlled capsule transfers recoil to the craft too.
	model = Flight.new()
	model.state.status = "flying"
	model.state.position = Vector3(0,30000,0)
	model.stage()
	var core: Dictionary = model.state.detached[0]
	var craft_center: Vector3 = model.state.position+Vector3(0,1.3,0)
	core.position = craft_center+Vector3(-3,0,0)
	core.velocity = Vector3(1500,0,0)
	core.thrust = 0.0
	core.angular_momentum = Vector3.ZERO
	model.state.velocity = Vector3.ZERO
	model.step(1.0/60.0,{"throttle":0,"sas":false})
	check(model.state.velocity.x>10,"Debris impact gives the controlled capsule recoil")
	check(core.position.x<model.state.position.x,"Debris cannot pass through the controlled capsule")
	# A clean release does not receive an extra collision kick from oversized bounds.
	model = Flight.new()
	model.state.status = "flying"
	model.state.position = Vector3(0,30000,0)
	model.state.engine_on = true
	model.stage()
	var before: Vector3 = model.state.velocity
	check(model.state.detached[0].thrust > 0.0 and model.state.detached[0].fuel > 0.0,"Burning core retains thrust and fuel after decoupling")
	model._resolve_body_collisions()
	check(Vector3(model.state.velocity).distance_to(before)<.001,"Normal separation has no false collision impulse")
	var coasting = Flight.new()
	coasting.state = model.state.duplicate(true)
	coasting.state.detached[0].thrust = 0.0
	var initial_fuel: float = model.state.detached[0].fuel
	for frame in range(120):
		model.step(1.0/60.0, {"throttle":0,"sas":false})
		coasting.step(1.0/60.0, {"throttle":0,"sas":false})
	check(model.state.detached[0].fuel < initial_fuel, "Released engine burns fuel independently of capsule throttle")
	check(model.state.velocity.y > coasting.state.velocity.y + 1.0, "Powered core catches and pushes the capsule through contact")
	for throttle in [0.0, 0.4, 1.0]:
		var release = Flight.new()
		release.state.status = "flying"
		release.state.position = Vector3(0,30000,0)
		release.state.engine_on = true
		release.state.throttle = throttle
		release.stage()
		check(is_equal_approx(release.state.detached[0].thrust, release._stats.engine_thrust * throttle), "Released core preserves throttle %s" % throttle)
	var unlit = Flight.new()
	unlit.state.status = "flying"
	unlit.stage()
	check(unlit.state.detached[0].thrust == 0.0, "Separation does not ignite an unlit engine")
	if failures.is_empty():
		print("PASS: %d part collision checks" % checks)
		quit()
	else:
		for message in failures: push_error(message)
		quit(1)
