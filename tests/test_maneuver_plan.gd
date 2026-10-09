extends SceneTree
const Plan = preload("res://scripts/maneuver_plan.gd")
const Physics = preload("res://scripts/physics_math.gd")
const Flight = preload("res://scripts/flight_model.gd")
const Surface = preload("res://scripts/planet_surface.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	var mu := Physics.MU
	var radius := Physics.PLANET_RADIUS
	var r := Vector3(radius + Physics.ATMOSPHERE_HEIGHT + 40000.0, 0, 0)
	var v := Vector3(0, sqrt(mu / r.length()), 0)
	var period := TAU * sqrt(pow(r.length(), 3.0) / mu)
	var quarter := Plan.propagate(r, v, period / 4.0, mu, radius)
	check(Vector3(quarter.position).distance_to(Vector3(0, r.length(), 0)) < r.length() * 0.000002, "Circular quarter-period position matches analytic orbit")
	check(Vector3(quarter.velocity).distance_to(Vector3(-v.length(), 0, 0)) < 0.01, "Circular quarter-period velocity matches analytic orbit")
	check(absf(Plan.time_to_point(r, v, quarter.position, mu, radius) - period / 4.0) < 0.01, "Map point converts to its future burn time")
	var round_trip := Plan.propagate(r, v, period * 3.0, mu, radius)
	check(Vector3(round_trip.position).distance_to(r) < r.length() * 0.000005, "Multiple complete periods retain the original position")
	check(Plan.propagate(r, r.normalized() * 1000.0, 30.0, mu, radius).is_empty(), "Radial flight does not invent a maneuver plane")
	check(Plan.propagate(r, v.normalized() * sqrt(2.0 * mu / r.length()), 30.0, mu, radius).is_empty(), "Parabolic degeneracy fails explicitly")
	check(Plan.propagate(r, v, -1.0, mu, radius).is_empty(), "Past burn times are rejected")
	check(Plan.propagate(Vector3.INF, v, 30.0, mu, radius).is_empty(), "Non-finite state is rejected")
	var node := Plan.new()
	node.epoch = period / 4.0
	node.components = Vector3(100, 0, 0)
	var burn := node.evaluate(r, v, 0.0, mu, radius)
	check(Vector3(burn.burn).normalized().dot(Vector3.LEFT) > 0.9999, "Prograde is evaluated at node time, not at the current craft")
	check(float(burn.elements.apoapsis) > r.length() - radius, "Prograde burn raises apoapsis")
	node.components = Vector3(0, v.length() * 0.06, 0)
	burn = node.evaluate(r, v, 0.0, mu, radius)
	check(Vector3(burn.burn).normalized().dot(Vector3.BACK) > 0.9999, "Normal burn leaves the current orbital plane")
	check(absf(Vector3(burn.elements.normal).dot(Vector3.BACK)) < 0.999, "Normal burn changes the resulting orbital plane")
	node.components = Vector3(0, 0, 30)
	burn = node.evaluate(r, v, 0.0, mu, radius)
	check(Vector3(burn.burn).normalized().dot(Vector3.UP) > 0.9999, "Radial-out burn uses the node's orbital basis")
	# At elliptical apoapsis, the analytic circular-speed impulse circularizes.
	var apo_radius := radius + 80000.0
	var peri_radius := radius + 30000.0
	var apo_velocity := sqrt(mu * (2.0 / apo_radius - 2.0 / (apo_radius + peri_radius)))
	node.epoch = 0.0
	node.components = Vector3(sqrt(mu / apo_radius) - apo_velocity, 0, 0)
	burn = node.evaluate(Vector3(apo_radius, 0, 0), Vector3(0, apo_velocity, 0), 0.0, mu, radius)
	check(float(burn.elements.eccentricity) < 0.00001, "Known apoapsis circularization produces a circular orbit")
	check(absf(float(burn.elements.periapsis) - (apo_radius - radius)) < 1.0, "Circularization preview predicts the correct periapsis")
	# Compare elliptical and hyperbolic predictions with independent small-step Verlet.
	for multiplier in [1.15, 1.7]:
		var initial_v: Vector3 = v * float(multiplier)
		var position := r
		var velocity := initial_v
		for step in range(12000):
			var sample := Physics.coast_step(position, velocity, 0.01, mu)
			position = sample[0]
			velocity = sample[1]
		var prediction := Plan.propagate(r, initial_v, 120.0, mu, radius)
		check(Vector3(prediction.position).distance_to(position) < 15.0, "Conic propagation agrees with independent integration: %s" % multiplier)
		check(Vector3(prediction.velocity).distance_to(velocity) < 0.1, "Conic velocity agrees with independent integration: %s" % multiplier)
		check(absf(Plan.time_to_point(r, initial_v, prediction.position, mu, radius) - 120.0) < 0.01, "Conic picking recovers elapsed time: %s" % multiplier)
	var engine := {"thrust": 42000.0, "isp": 225.0, "fuel": 400.0}
	var exhaust := 225.0 * Physics.STANDARD_GRAVITY
	var estimate := Plan.burn_estimate(1000.0, [engine], 100.0)
	var expected_fuel := 1000.0 * (1.0 - exp(-100.0 / exhaust))
	check(absf(estimate.fuel - expected_fuel) < 0.001, "Burn fuel follows the rocket equation")
	check(absf(estimate.duration - expected_fuel * exhaust / 42000.0) < 0.001, "Burn duration uses mass flow")
	check(absf(estimate.available - exhaust * log(1000.0 / 600.0)) < 0.001, "Available delta-v accounts for dry mass")
	check(not Plan.burn_estimate(1000.0, [engine], 10000.0).sufficient, "Insufficient fuel is explicit")
	check(not Plan.burn_estimate(1000.0, [], 100.0).sufficient, "Missing engine has no fictional burn duration")
	check(Plan.burn_estimate(1000.0, [], 0.0).duration == 0.0, "Zero impulse needs no fuel or engine")
	var split := Plan.burn_estimate(1000.0, [{"thrust":21000.0,"isp":225.0,"fuel":100.0},{"thrust":21000.0,"isp":225.0,"fuel":300.0}], 800.0)
	check(absf(split.available - estimate.available) < 0.001, "Independent feeds retain remaining engine fuel after the first depletion")
	check(split.sufficient and split.duration > estimate.duration, "Burn can continue after one engine exhausts its feed")
	# Compare a planned impulse followed by a coast with the real flight model.
	var home: Resource = Surface.home().definition.duplicate(true)
	home.moons.clear()
	Surface.reset_home(home)
	var flight := Flight.new()
	flight.ignite()
	flight.state.position = Physics.PLANET_CENTER + r
	flight.state.velocity = v + Vector3(0, v.length() * 0.06, 0)
	flight.state.throttle = 0.0
	var expected := Plan.propagate(r, flight.state.velocity, 60.0, mu, radius)
	for step in range(600): flight.step(0.1, {"throttle":0.0,"sas":true})
	check((Vector3(flight.state.position) - Physics.PLANET_CENTER).distance_to(expected.position) < 20.0, "Post-impulse trajectory agrees with actual vacuum flight")
	check(not flight.maneuver_engines().is_empty(), "Ignited, fueled engine is available for burn estimates")
	flight.stage()
	check(flight.maneuver_engines().is_empty(), "Discarded propulsion cannot supply a planned burn")
	for failure in failures: push_error(failure)
	print("PASS: maneuver propagation, node frames, circularization, fuel and simulation comparisons" if failures.is_empty() else "FAIL: maneuver mathematics")
	quit(0 if failures.is_empty() else 1)
