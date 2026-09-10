extends SceneTree
## Run: godot --headless --path . --script tests/test_flight.gd

const Parts = preload("res://scripts/parts.gd")
const Physics = preload("res://scripts/physics_math.gd")
const Flight = preload("res://scripts/flight_model.gd")
const PlanetSurface = preload("res://scripts/planet_surface.gd")
const PlanetTerrain = preload("res://scripts/planet_terrain.gd")
var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	_test_designs()
	_test_launch_and_fuel()
	_test_staging()
	_test_booster_first()
	_test_controls_and_inputs()
	_test_impact()
	_test_parachute_recovery()
	_test_gravity_and_orbit()
	_test_orbit_mission()
	_test_frame_rates()
	_test_orbital_math()
	_test_propulsion_math()
	if _failures.is_empty():
		print("PASS: %d flight simulation checks." % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		print("FAIL: %d of %d flight simulation checks." % [_failures.size(), _checks])
		quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _test_designs() -> void:
	for engine: String in Parts.ENGINES:
		for tanks: int in range(1, 5):
			for boosters: bool in [false, true]:
				var design: Dictionary = {"engine": engine, "tanks": tanks, "boosters": boosters}
				var stats: Dictionary = Parts.stats(design)
				_check(float(stats["twr"]) > 1.0, "%s / %d tanks must lift from pad" % [engine, tanks])
				_check(float(stats["wet_mass"]) > float(stats["dry_mass"]), "Fuel contributes to launch mass")
				_check(float(stats["delta_v"]) > 900.0, "Every build has a useful flight budget")
				var model = Flight.new()
				model.reset(design)
				model.ignite()
				model.step(2.0, {"throttle": 1.0})
				_check(float(model.state["altitude"]) > 1.0, "%s / %d tanks / boosters %s actually leaves terrain" % [engine, tanks, boosters])
	var normalized: Dictionary = Parts.normalize_design({"engine": "missing", "tanks": 100, "name": "  "})
	_check(normalized["engine"] == "sparrow" and normalized["tanks"] == 4, "Invalid designs safely normalize")
	_check(not str(normalized["name"]).is_empty(), "Design always has a display name")
	_check(Parts.default_design() == Parts.default_design(), "Default designs are deterministic")
	var independent: Dictionary = Parts.default_design()
	independent["tanks"] = 4
	_check(Parts.default_design()["tanks"] == 2, "Default designs do not share mutable state")


func _test_launch_and_fuel() -> void:
	var model = Flight.new()
	var initial_fuel: float = float(model.state["fuel"])
	model.step(1.0, {"throttle": 1.0})
	_check(float(model.state["fuel"]) == initial_fuel and model.state["status"] == "ready", "Ready craft cannot burn fuel")
	model.ignite()
	model.step(1.0, {"throttle": 0.0})
	_check(float(model.state["altitude"]) < 0.1 and model.state["status"] == "flying", "Zero throttle remains supported on launch pad")
	model.step(1.0, {"throttle": 1.0})
	var expected_burn: float = float(Parts.ENGINES["sparrow"]["thrust"]) / (float(Parts.ENGINES["sparrow"]["isp"]) * Parts.STANDARD_GRAVITY)
	_check(absf(initial_fuel - float(model.state["fuel"]) - expected_burn) < 0.001, "Fuel burn follows thrust / exhaust velocity")
	_check(float(model.state["altitude"]) > 2.0, "Default rocket lifts off")
	_check(float(model.state["vertical_speed"]) > 0.0, "Launch has upward velocity")
	for index: int in range(50):
		model.step(1.0, {"throttle": 1.0})
	_check(float(model.state["max_altitude"]) > 12000.0, "Starter rocket can reach the 12 km milestone")
	for index: int in range(70):
		model.step(1.0, {"throttle": 1.0})
	_check(float(model.state["fuel"]) == 0.0, "Fuel never becomes negative after burnout")
	_check(float(model.state["thrust"]) == 0.0, "Empty engines produce no thrust")
	_check(float(model.state["mass"]) >= Parts.CAPSULE_MASS, "Vehicle mass stays positive")
	var copy: Dictionary = model.telemetry()
	copy["fuel"] = 200000.0
	_check(float(model.state["fuel"]) == 0.0, "Telemetry snapshots cannot mutate simulation")
	model.reset(Parts.default_design())
	_check(model.state["status"] == "ready" and not bool(model.state["orbit_achieved"]), "Reset clears flight progress")


func _test_staging() -> void:
	var model = Flight.new()
	model.reset({"boosters": true})
	var initial_mass: float = float(model.state["mass"])
	model.stage()
	_check(bool(model.state["boosters_attached"]), "Stages cannot separate before launch")
	model.ignite()
	model.step(1.0, {"throttle": 0.0})
	_check(float(model.state["booster_fuel"]) < Parts.BOOSTER_FUEL_MASS, "Solid boosters burn independently of throttle")
	_check(float(model.state["fuel"]) == float(model.state["max_fuel"]), "Core cutoff preserves core fuel")
	_check(float(model.state["mass"]) < initial_mass, "Burned propellant reduces mass")
	var before_stage: float = float(model.state["mass"])
	var discarded_mass: float = Parts.BOOSTER_DRY_MASS + float(model.state["booster_fuel"])
	model.stage()
	_check(not bool(model.state["boosters_attached"]) and not bool(model.state["capsule_only"]), "First stage ejects only attached boosters")
	_check(absf(before_stage - float(model.state["mass"]) - discarded_mass) < 0.001, "Booster separation discards exactly remaining booster mass")
	model.stage()
	_check(bool(model.state["capsule_only"]), "Second stage separates capsule")
	_check(float(model.state["mass"]) == Parts.CAPSULE_MASS and float(model.state["fuel"]) == 0.0, "Capsule has correct mass and no propulsion fuel")
	model.step(0.1, {"throttle": 1.0})
	_check(float(model.state["thrust"]) == 0.0, "Capsule cannot restart discarded engine")
	_check(model.stage() == "No stages remaining.", "Repeated staging is safe")


func _test_controls_and_inputs() -> void:
	var model = Flight.new()
	model.ignite()
	model.state["position"] = Vector3(0.0, 30000.0, 0.0)
	model.step(-1.0, {"throttle": 1.0})
	model.step(INF, {})
	_check(float(model.state["time"]) == 0.0, "Invalid timesteps cannot corrupt simulation")
	model.step(1.0, {"pitch": 1.0, "throttle": 3.0, "sas": true})
	_check(float(model.state["throttle"]) == 1.0, "Throttle input is clamped")
	var orientation: Basis = model.state["orientation"]
	_check(orientation.y.z > 0.1, "Pitch input changes rocket orientation")
	model.step(2.0, {"pitch": 0.0, "throttle": -1.0, "sas": true})
	var angular_velocity: Vector3 = model.state["angular_velocity"]
	_check(angular_velocity.length() < 0.001, "SAS arrests rotation when controls are released")
	_check(float(model.state["throttle"]) == 0.0, "Negative throttle is clamped")
	model.step(0.1, {"throttle": NAN, "pitch": NAN})
	_check(is_finite(float(model.state["altitude"])) and is_finite(float(model.state["fuel"])), "Non-finite controls cannot poison state")
	_check(absf(orientation.determinant() - 1.0) < 0.0001, "Attitude basis remains orthonormal")


func _test_impact() -> void:
	var model = Flight.new()
	model.ignite()
	model.state["position"] = Vector3(0.0, 100.0, 0.0)
	model.state["velocity"] = Vector3(0.0, -100.0, 0.0)
	model.step(2.0, {"throttle": 0.0})
	_check(model.state["status"] == "crashed", "High-speed terrain collision crashes the vessel")
	_check(float(model.state["impact_speed"]) > Flight.SAFE_LANDING_SPEED, "Crash records pre-impact speed")
	_check(float(model.state["altitude"]) < 0.1, "Collision is resolved at terrain surface")
	var stopped_position: Vector3 = model.state["position"]
	model.step(1.0, {"throttle": 1.0})
	_check(model.state["position"] == stopped_position, "Crashed craft remain stopped")
	# Verify that terrain collision uses radius, including far from the original pad.
	model.reset(Parts.default_design())
	model.ignite()
	model.state["position"] = Flight.PLANET_CENTER + Vector3(Flight.PLANET_RADIUS + 100.0, 0.0, 0.0)
	model.state["velocity"] = Vector3(-100.0, 0.0, 0.0)
	model.step(2.0, {"throttle": 0.0})
	_check(model.state["status"] == "crashed", "Terrain collision works around the curved planet")
	var distance: float = (Vector3(model.state["position"]) - Flight.PLANET_CENTER).length()
	_check(absf(distance-float(model.terrain.contact(Vector3(model.state.position)-Flight.PLANET_CENTER,float(model.state.time)).radius)) < 0.1, "Off-pad impact stays on planetary surface")
	model.reset(Parts.default_design())
	model.ignite()
	model.state["position"] = Vector3(0.0, 100.0, 0.0)
	model.state["velocity"] = Vector3(0.0, -10000.0, 0.0)
	model.step(0.1, {"throttle": 0.0})
	_check(model.state["status"] == "crashed", "A fast first frame cannot tunnel through terrain")


func _test_parachute_recovery() -> void:
	var model = Flight.new()
	model.ignite()
	model.state["position"] = Vector3(0.0, 1000.0, 0.0)
	model.deploy_chute()
	_check(not bool(model.state["chute_deployed"]), "Parachute requires capsule separation")
	model.stage()
	model.state["position"] = Vector3(0.0, 8000.0, 0.0)
	model.deploy_chute()
	_check(not bool(model.state["chute_deployed"]), "Parachute rejects thin air")
	model.state["position"] = Vector3(0.0, 1200.0, 0.0)
	model.state["velocity"] = Vector3(0.0, 50.0, 0.0)
	model.deploy_chute()
	_check(not bool(model.state["chute_deployed"]), "Parachute waits until the capsule is descending")
	model.state["velocity"] = Vector3(0.0, -181.0, 0.0)
	model.deploy_chute()
	_check(not bool(model.state["chute_deployed"]), "Parachute rejects excessive airspeed")
	model.state["velocity"] = Vector3(0.0, -100.0, 0.0)
	model.deploy_chute()
	_check(bool(model.state["chute_deployed"]), "Parachute opens inside safe envelope")
	for index: int in range(300):
		model.step(1.0, {"throttle": 0.0})
		if model.state["status"] != "flying":
			break
	_check(model.state["status"] == "landed", "Parachute recovers capsule safely from descent")
	_check(float(model.state["impact_speed"]) < 7.0, "Chute has a survivable terminal descent speed")
	_check(float(model.state["altitude"]) < 0.1, "Recovered capsule rests at surface")
	# End-to-end player mission: build, launch past 1 km, separate, deploy, recover.
	model.reset(Parts.default_design())
	model.ignite()
	for index: int in range(1800):
		model.step(1.0 / 60.0, {"throttle": 1.0})
		if float(model.state["altitude"]) >= 1200.0:
			break
	model.stage()
	for index: int in range(400):
		if bool(model.telemetry()["chute_safe"]):
			model.deploy_chute()
		model.step(1.0, {"throttle": 0.0})
		if model.state["status"] != "flying":
			break
	_check(float(model.state["max_altitude"]) >= 1000.0 and model.state["status"] == "landed", "Playable 1 km launch-and-recover loop succeeds")
	model.reset(Parts.default_design())
	model.ignite()
	model.stage()
	model.state["position"] = Vector3(0.0, 45000.0, 0.0)
	for index: int in range(600):
		if bool(model.telemetry()["chute_safe"]):
			model.deploy_chute()
		model.step(1.0, {"throttle": 0.0})
		if model.state["status"] != "flying":
			break
	_check(model.state["status"] == "landed", "Atmospheric drag permits safe chute deployment and recovery from 45 km")


func _test_gravity_and_orbit() -> void:
	_check(Flight.air_density_at(0.0) > Flight.air_density_at(10000.0), "Atmosphere thins with altitude")
	_check(Flight.air_density_at(Flight.ATMOSPHERE_HEIGHT) == 0.0, "There is no atmospheric drag in space")
	var model = Flight.new()
	model.ignite()
	model.state["position"] = Vector3(0.0, Flight.PLANET_RADIUS, 0.0)
	var before: Dictionary = model.telemetry()
	_check(absf(float(before["gravity"]) - Flight.SURFACE_GRAVITY / 4.0) < 0.00001, "Gravity obeys inverse square law")
	model.step(0.1, {"throttle": 0.0})
	_check(absf(float(model.state["vertical_speed"]) + Flight.SURFACE_GRAVITY / 4.0 * 0.1) < 0.001, "Coasting vessel accelerates under central gravity")
	model.reset(Parts.default_design())
	model.ignite()
	var altitude: float = 25000.0
	var radius: float = Flight.PLANET_RADIUS + altitude
	model.state["position"] = Vector3(0.0, altitude, 0.0)
	model.state["velocity"] = Vector3(sqrt(Flight.MU / radius), 0.0, 0.0)
	var orbital: Dictionary = model.telemetry()
	_check(absf(float(orbital["apoapsis"]) - altitude) < 0.1, "Circular orbit has correct apoapsis")
	_check(absf(float(orbital["periapsis"]) - altitude) < 0.1, "Circular orbit has correct periapsis")
	_check(bool(orbital["in_stable_orbit"]), "Stable orbit is recognized above atmosphere")
	var initial_speed: float = Vector3(orbital["velocity"]).length()
	for index: int in range(150):
		model.step(2.0, {"throttle": 0.0})
	_check(model.state["status"] == "flying", "Orbital coasting does not collide with ground")
	_check(absf(float(model.state["altitude"]) - altitude) < 100.0, "Circular orbit remains stable during 300 seconds of coasting")
	_check(absf(Vector3(model.state["velocity"]).length() - initial_speed) < 1.0, "Orbital integrator approximately conserves energy")
	_check(bool(model.state["orbit_achieved"]), "Orbital achievement persists")
	model.state["velocity"] = Vector3.ZERO
	model.telemetry()
	_check(not bool(model.state["in_stable_orbit"]) and bool(model.state["orbit_achieved"]), "Current orbit and earned milestone are distinct")
	model.state["velocity"] = Vector3(sqrt(2.0 * Flight.MU / radius) * 1.1, 0.0, 0.0)
	model.telemetry()
	_check(is_inf(float(model.state["apoapsis"])) and not bool(model.state["in_stable_orbit"]), "Escape trajectories are not mistaken for closed orbits")
	var custom = PlanetSurface.HOME.duplicate(true)
	custom.surface_gravity = 3.0
	custom.atmosphere_density = 2.4
	custom.atmosphere_height = 9000.0
	model = Flight.new()
	model.terrain = PlanetTerrain.new(custom)
	model.ignite()
	before = model.telemetry()
	_check(absf(float(before["air_density"]) - 2.4) < 0.00001, "Custom planet air density feeds drag telemetry")
	model.state["position"] = Vector3(0.0, Flight.PLANET_RADIUS, 0.0)
	before = model.telemetry()
	_check(absf(float(before["gravity"]) - 0.75) < 0.00001, "Custom planet gravity feeds flight telemetry")
	model.state["position"] = Vector3(0.0, 10000.0, 0.0)
	before = model.telemetry()
	_check(float(before["air_density"]) == 0.0, "Custom atmosphere height controls drag cutoff")


func _test_frame_rates() -> void:
	var fast = Flight.new()
	var slow = Flight.new()
	fast.ignite()
	slow.ignite()
	for index: int in range(600):
		fast.step(1.0 / 60.0, {"throttle": 1.0})
	for index: int in range(100):
		slow.step(0.1, {"throttle": 1.0})
	_check(absf(float(fast.state["altitude"]) - float(slow.state["altitude"])) < 0.1, "Flight is consistent across frame rates")
	_check(absf(float(fast.state["fuel"]) - float(slow.state["fuel"])) < 0.0001, "Fuel usage is consistent across frame rates")


func _test_orbit_mission() -> void:
	# Exercise the same throttle and attitude controls available to the player.
	# Coast upright through dense air, then circularize with a horizontal burn.
	var model = Flight.new()
	model.ignite()
	var phase: int = 0
	for index: int in range(15000):
		var data: Dictionary = model.telemetry()
		if bool(data["in_stable_orbit"]):
			break
		var throttle: float = 1.0
		var desired_angle: float = 0.0
		if phase == 0 and float(data["apoapsis"]) >= 45000.0:
			phase = 1
		if phase >= 1:
			desired_angle = PI * 0.5 if float(data["altitude"]) > Flight.ATMOSPHERE_HEIGHT else 0.0
			throttle = 0.0
			if float(data["vertical_speed"]) < 70.0:
				phase = 2
		if phase == 2:
			throttle = 1.0
		var attitude: Basis = data["orientation"]
		var radial: Vector3 = (Vector3(data["position"]) - Flight.PLANET_CENTER).normalized()
		var tangent: Vector3 = Vector3(radial.y, -radial.x, 0.0)
		var desired_up: Vector3 = radial * cos(desired_angle) + tangent * sin(desired_angle)
		var angle_error: float = atan2(desired_up.x, desired_up.y) - atan2(attitude.y.x, attitude.y.y)
		model.step(1.0 / 60.0, {"throttle": throttle, "yaw": clampf(angle_error * 8.0, -1.0, 1.0), "sas": true})
	_check(bool(model.state["in_stable_orbit"]), "Default rocket can launch into a stable orbit using player controls")
	_check(float(model.state["fuel"]) > 200.0, "Orbital mission leaves fuel for an eventual deorbit burn")
	model.step(120.0 / 60.0, {"throttle": 0.0})
	_check(bool(model.state["in_stable_orbit"]), "Achieved orbit persists after engine cutoff")


func _test_booster_first() -> void:
	var design := Parts.default_design()
	design.boosters = true
	design.booster_first = true
	var model = Flight.new()
	model.reset(design)
	var fuel := float(model.state.fuel)
	model.ignite()
	_check(not model.state.engine_on and model.state.boosters_on, "Booster-first launch holds the core unlit")
	for frame in range(1800):
		model.step(1.0 / 60.0, {"throttle": 1.0})
	_check(is_equal_approx(model.state.fuel, fuel), "Booster-first preserves all core fuel before staging")
	_check(model.state.booster_fuel == 0.0, "Solids burn out independently of core ignition")
	_check(model.state.altitude > 1000.0, "Booster-first lifts the starter craft")
	model.stage()
	_check(model.state.engine_on and not model.state.boosters_attached, "Second stage jettisons boosters and ignites core")
	model.step(1.0, {"throttle": 1.0})
	_check(model.state.fuel < fuel and model.state.thrust > 0.0, "Core burns after delayed ignition")
	model.stage()
	_check(model.state.capsule_only and model.state.stage_index == 3, "Planned capsule separation completes the sequence")
	_check(Parts.stage_plan(design).size() == 3, "Booster plan has three Space actions")
	design.boosters = false
	_check(not Parts.normalize_design(design).booster_first, "Removing boosters restores core ignition")


func _test_orbital_math() -> void:
	var radius := 85000.0
	var circular := sqrt(Physics.MU / radius)
	var rotation := Basis(Vector3.RIGHT, 0.61)
	var radial := rotation * Vector3(0, radius, 0)
	var velocity := rotation * Vector3(circular, 0, 0)
	var orbit := Physics.orbital_elements(radial, velocity)
	_check(absf(orbit.eccentricity) < 1e-6, "Inclined circular orbit has zero eccentricity")
	_check(absf(orbit.semi_major_axis - radius) < 0.1, "Circular semimajor axis is radius from planet center")
	_check(absf(orbit.orbital_period - TAU * radius / circular) < 0.01, "Orbital period follows Kepler's third law")
	_check(absf(orbit.escape_speed / orbit.circular_speed - sqrt(2.0)) < 1e-6, "Escape speed is sqrt(2) times circular speed")
	_check(absf(Vector3(orbit.normal).dot(radial.normalized())) < 1e-6 and absf(Vector3(orbit.normal).dot(velocity.normalized())) < 1e-6, "Orbit normal is perpendicular to position and velocity")
	_check(Vector3(orbit.prograde).is_equal_approx(-Vector3(orbit.retrograde)), "Retrograde opposes prograde")
	_check(Vector3(orbit.radial_out).dot(radial.normalized()) > 0.99999, "Radial-out points outward in a circular orbit")
	var prograde_burn := Physics.orbital_elements(radial, velocity + Vector3(orbit.prograde) * 20.0)
	_check(prograde_burn.apoapsis > orbit.apoapsis + 1000.0 and absf(prograde_burn.periapsis - orbit.periapsis) < 0.1, "Prograde burn raises the opposite apsis")
	var retrograde_burn := Physics.orbital_elements(radial, velocity + Vector3(orbit.retrograde) * 20.0)
	_check(retrograde_burn.periapsis < orbit.periapsis - 1000.0 and absf(retrograde_burn.apoapsis - orbit.apoapsis) < 0.1, "Retrograde burn lowers the opposite apsis")
	var normal_burn := Physics.orbital_elements(radial, velocity + Vector3(orbit.normal) * 20.0)
	_check(Vector3(normal_burn.normal).angle_to(orbit.normal) > 0.02, "Normal burn changes the orbital plane")
	var stationary := Physics.orbital_elements(radial, Vector3.ZERO)
	_check(not stationary.orbit_plane_defined and stationary.normal == Vector3.ZERO and stationary.prograde == Vector3.ZERO, "Stationary craft does not invent an orbit plane or velocity direction")
	var climbing := Physics.orbital_elements(radial, radial.normalized() * 100.0)
	_check(not climbing.orbit_plane_defined and is_finite(climbing.apoapsis), "Pure radial ascent has a finite ballistic apex and no orbit plane")
	var escape := Physics.orbital_elements(Vector3(0, radius, 0), Vector3(sqrt(2.0 * Physics.MU / radius), 0, 0))
	_check(not escape.bound_orbit and is_inf(escape.apoapsis) and is_inf(escape.orbital_period), "Parabolic escape has no apoapsis or period")
	var hyperbolic := Physics.orbital_elements(radial, velocity * 1.6)
	_check(hyperbolic.eccentricity > 1.0 and hyperbolic.semi_major_axis < 0.0 and not hyperbolic.bound_orbit, "Hyperbolic orbit has eccentricity above one and negative semimajor axis")
	# Known ellipse, initialized at periapsis with speed from vis-viva.
	var peri_radius := 85000.0
	var apo_radius := 175000.0
	var semimajor := (peri_radius + apo_radius) * 0.5
	var peri_velocity := Vector3(sqrt(Physics.MU * (2.0 / peri_radius - 1.0 / semimajor)), 0, 0)
	var ellipse := Physics.orbital_elements(Vector3(0, peri_radius, 0), peri_velocity)
	_check(absf(ellipse.periapsis + Physics.PLANET_RADIUS - peri_radius) < 0.1, "Ellipse periapsis agrees with vis-viva")
	_check(absf(ellipse.apoapsis + Physics.PLANET_RADIUS - apo_radius) < 0.1, "Ellipse apoapsis agrees with vis-viva")
	var path := Physics.coast_path(Vector3(0, peri_radius, 0), peri_velocity, 400000.0)
	var minimum := INF
	var maximum := 0.0
	for point in path:
		minimum = minf(minimum, point.length())
		maximum = maxf(maximum, point.length())
	_check(absf(minimum - peri_radius) < 0.1 and absf(maximum - apo_radius) < 0.1, "Map conic reaches the same apsides as flight telemetry")
	_check(path[0].distance_to(path[-1]) < 0.1, "Elliptical map path closes without numerical drift")
	var open_path := Physics.coast_path(radial, velocity * 1.6, 400000.0)
	_check(open_path.size() > 2 and open_path[-1].distance_to(open_path[0]) > 1000.0, "Hyperbolic map trajectory remains open")
	for point in open_path:
		_check(point.is_finite() and point.length() <= 400000.1, "Open conic samples remain finite and within map bounds")
	var fallen := Physics.coast_path(Vector3(0, 61000, 0), Vector3(0, -100, 0), 400000)
	_check(fallen[-1].length() <= Physics.PLANET_RADIUS, "Radial map prediction terminates at the surface")
	var near_radial := Physics.coast_path(Vector3(0, 70000, 0), Vector3(0.1, 100, 0), 400000)
	_check(near_radial.size() > 10 and near_radial[1].length() > 70000, "Almost-vertical map arc preserves the climb before falling")
	# Multiple complete orbits expose secular drift hidden by a short arc.
	var position := radial
	var speed := velocity
	for index in range(2500):
		var next := Physics.coast_step(position, speed, 1.0)
		position = next[0]
		speed = next[1]
	var after := Physics.orbital_elements(position, speed)
	_check(absf((after.specific_energy - orbit.specific_energy) / orbit.specific_energy) < 0.0001, "Gravity coast conserves specific energy over three orbits")
	_check(Vector3(after.specific_angular_momentum).distance_to(orbit.specific_angular_momentum) / Vector3(orbit.specific_angular_momentum).length() < 0.0001, "Gravity coast conserves angular momentum over three orbits")
	var reverse := Physics.coast_step(position, speed, -1.0)
	var forward := Physics.coast_step(reverse[0], reverse[1], 1.0)
	_check(forward[0].distance_to(position) < 0.02 and forward[1].distance_to(speed) < 0.001, "Gravity integration is time symmetric")


func _test_propulsion_math() -> void:
	_check(Parts.STANDARD_GRAVITY == 9.80665, "Specific impulse uses standard gravity in SI")
	# Independently integrate thrust/mass as propellant is exhausted, covering
	# both core-first and booster-first burnout at simultaneous ignition.
	for engine: String in ["sparrow", "titan"]:
		var design := {"engine": engine, "tanks": 1, "boosters": true, "booster_first": false}
		var stats := Parts.stats(design)
		var fuel := Parts.TANK_FUEL_MASS
		var solid := Parts.BOOSTER_FUEL_MASS
		var integrated_delta_v := 0.0
		var core_flow: float = Parts.ENGINES[engine].thrust / (Parts.ENGINES[engine].isp * Parts.STANDARD_GRAVITY)
		var booster_flow := Parts.BOOSTER_THRUST / (Parts.BOOSTER_ISP * Parts.STANDARD_GRAVITY)
		while fuel > 0.0 or solid > 0.0:
			var core_burn := minf(fuel, core_flow * 0.001)
			var solid_burn := minf(solid, booster_flow * 0.001)
			var mass: float = stats.core_dry_mass + fuel + solid + (Parts.BOOSTER_DRY_MASS if solid > 0.0 else 0.0)
			var impulse: float = Parts.STANDARD_GRAVITY * (core_burn * Parts.ENGINES[engine].isp + solid_burn * Parts.BOOSTER_ISP)
			integrated_delta_v += impulse / (mass - (core_burn + solid_burn) * 0.5)
			fuel = maxf(0.0, fuel - core_burn)
			solid = maxf(0.0, solid - solid_burn)
		_check(absf(integrated_delta_v - stats.delta_v) < 0.1, engine + " staged delta-v agrees with independently integrated impulse")
		_check(absf(stats.twr - stats.thrust / (stats.wet_mass * Physics.SURFACE_GRAVITY)) < 1e-9, "Launch TWR uses planet gravity rather than Isp's reference gravity")
