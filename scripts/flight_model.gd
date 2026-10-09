extends RefCounted
## Deterministic spherical-planet flight simulation, independent of the scene tree.
## Position denotes the vehicle's contact point. The launch pad is on the home world equator.

const SolarBody = preload("res://scripts/solar_body.gd")
const Surface = preload("res://scripts/planet_surface.gd")
var terrain: RefCounted = Surface.home()
const BodyCollisions = preload("res://scripts/body_collisions.gd")
const Hydrostatics = preload("res://scripts/hydrostatics.gd")
const Parts = preload("res://scripts/parts.gd")
const Physics = preload("res://scripts/physics_math.gd")
const PLANET_RADIUS: float = Physics.PLANET_RADIUS
const PLANET_CENTER: Vector3 = Physics.PLANET_CENTER
const SURFACE_GRAVITY: float = Physics.SURFACE_GRAVITY
const MU: float = Physics.MU
const ATMOSPHERE_HEIGHT: float = Physics.ATMOSPHERE_HEIGHT
const MAX_STEP: float = 1.0 / 60.0
const SIDE_DRAG_RESPONSE_SECONDS := 0.5
const MIN_RAIL_WARP_ALTITUDE := 90000.0
const DEBRIS_DETAIL_DISTANCE := 2000.0
const BACKGROUND_DEBRIS_STEP := 0.25
const SAFE_LANDING_SPEED: float = 8.0
const DEBRIS_BREAKUP_SPEED := 20.0
const DEBRIS_RESTITUTION := 0.35
const DEBRIS_SETTLE_SECONDS := 2.0
const CHUTE_MAX_ALTITUDE: float = 2500.0
const CHUTE_MAX_SPEED: float = 180.0

var state: Dictionary = {}
var _design: Dictionary = {}
var _stats: Dictionary = {}
var _core_dry_mass: float = 0.0
var _chute_opening: float = 0.0
var _has_lifted: bool = false
var _prelaunch_time := 0.0
var _postflight_time := 0.0
var _debris_terrains: Dictionary = {}
var _radial_layout: Dictionary = {}
var _engines: Array = []
var _parts_by_id: Dictionary = {}
var _supplied_tanks: Dictionary = {}
var _stack_height := 0.0
var _mass_cache: Dictionary = {}
var _mass_cache_key: Array = []
var _mass_layout: Array = []
var _mass_layout_key: Array = []
var _water_hull: Dictionary = {}
var _water_hull_key: Array = []
var _rail_warp := false
var _stepping := false
var _has_local_debris := false
var _next_debris_id := 0
var _relaunching := false
var _relaunch_armed := false


func _init() -> void:
	reset(Parts.default_design())


func reset(design: Dictionary) -> void:
	_mass_cache.clear()
	_mass_cache_key.clear()
	_mass_layout.clear()
	_mass_layout_key.clear()
	_water_hull_key.clear()
	_design = Parts.normalize_design(design)
	_engines = Parts.Craft.engines(_design)
	_parts_by_id.clear()
	_supplied_tanks.clear()
	for part in _design.get("assembly", {}).get("parts", []):
		_parts_by_id[part.id] = part
	_radial_layout = {"boosters": Parts.Craft.radial_instances(_design, "boosters"), "separator": Parts.Craft.radial_instances(_design, "separator")}
	_stats = Parts.stats(_design)
	_stack_height = Parts.Craft.stack_top(_design)
	_core_dry_mass = float(_stats["core_dry_mass"])
	_next_debris_id = 0
	_chute_opening = 0.0
	_has_lifted = false
	_relaunching = false
	_relaunch_armed = false
	_prelaunch_time = 0.0
	_postflight_time = 0.0
	state = {
		"position": PLANET_CENTER + Surface.LAUNCH_RADIAL, "velocity": terrain.surface_velocity(Surface.LAUNCH_RADIAL), "orientation": Surface.LAUNCH_BASIS,
		"angular_velocity": Vector3.ZERO, "status": "ready", "engine_on": false, "active_engines": [], "removed_parts": [], "discarded_dry_mass": 0.0, "released_decouplers": [], "boosters_on": false, "stage_index": 0, "detached": [], "surface_impacts": [],
		"fuel": float(_stats["core_fuel_mass"]), "max_fuel": float(_stats["core_fuel_mass"]),
		"booster_fuel": float(_stats["booster_fuel_mass"]),
		"max_booster_fuel": float(_stats["booster_fuel_mass"]),
		"boosters_attached": bool(_design["boosters"]), "capsule_only": false,
		"chute_deployed": false, "chute_cut": false, "throttle": 1.0, "time": 0.0,
		"altitude": 0.0, "max_altitude": 0.0, "max_speed": 0.0,
		"mass": float(_stats["wet_mass"]), "vertical_speed": 0.0, "horizontal_speed": 0.0,
		"apoapsis": 0.0, "periapsis": -PLANET_RADIUS, "orbit_achieved": false,
		"in_stable_orbit": false, "speed": 0.0, "thrust": 0.0,
		"acceleration": 0.0, "acceleration_vector": Vector3.ZERO,
		"temperature": 288.0, "heating_rate": 0.0, "heat_glow": 0.0, "air_velocity": Vector3.ZERO,
		"air_density": 1.225, "dynamic_pressure": 0.0, "drag_acceleration": 0.0,
		"side_drag_exposure": 0.0,
		"gravity": SURFACE_GRAVITY, "fuel_fraction": 1.0,
		"booster_fraction": 1.0 if bool(_design["boosters"]) else 0.0,
		"mach": 0.0, "chute_safe": false, "flight_path_angle": 90.0,
		"destroyed": false, "impact_speed": 0.0, "max_g": 0.0, "sas": true
	}
	state["engine_fuel"] = {}
	if _engines.size() > 1 or _design.get("assembly",{}).get("parts",[]).any(func(part): return part.kind == "tank" and not Parts.Craft.radial_mount(_design.assembly,part.id).is_empty()):
		for engine in _engines:
			var parent: String = engine.parent
			var capacity := 0.0
			while not parent.is_empty():
				var part: Dictionary = _parts_by_id.get(parent, {})
				if part.is_empty() or part.kind != "tank": break
				capacity += Parts.TANK_FUEL_MASS
				_supplied_tanks[parent] = true
				parent = part.parent
			state.engine_fuel[engine.id] = capacity
	_refresh_telemetry()


func ignite() -> void:
	if _design.has("assembly"):
		execute_stage()
		return
	if str(state["status"]) == "ready":
		state["status"] = "flying"
		state["engine_on"] = not bool(_design["booster_first"])
		state["boosters_on"] = bool(state["boosters_attached"])
		state["stage_index"] = 1


func step(dt: float, input: Dictionary) -> void:
	if not is_finite(dt) or dt <= 0.0:
		return
	if _can_relaunch(input):
		state["settled"] = false
		state["settle_time"] = 0.0
		if state.chute_deployed:
			state.chute_deployed = false
			state.chute_cut = true
			_chute_opening = 0.0
		state["status"] = "flying"
		state["engine_on"] = true
		state["throttle"] = _finite_input(input, "throttle", float(state["throttle"]), 0.0, 1.0)
		_has_lifted = false
		_relaunching = true
	elif state.status in ["landed", "crashed"]:
		_advance_after_touchdown(minf(dt, 10.0))
		return
	if state.status != "flying":
		return
	state["throttle"] = _finite_input(input, "throttle", float(state["throttle"]), 0.0, 1.0)
	state["sas"] = bool(input.get("sas", true))
	var control: Vector3 = Vector3(
		_finite_input(input, "pitch", 0.0, -1.0, 1.0),
		_finite_input(input, "roll", 0.0, -1.0, 1.0),
		-_finite_input(input, "yaw", 0.0, -1.0, 1.0)
	)
	_mass_cache = {}
	_stepping = true
	var start_time := simulation_time()
	var frame_duration := minf(dt, 10.0)
	_classify_debris(frame_duration)
	# Substeps also support time acceleration without tunnelling through the surface.
	var remaining: float = minf(dt, 10.0)
	while remaining > 0.0000001 and str(state["status"]) == "flying":
		var substep: float = minf(remaining, MAX_STEP)
		if _has_local_debris:
			substep = BodyCollisions.step_limit(_collision_bodies(), substep)
		_integrate(substep, control)
		remaining -= substep
	# Distant debris remains on the simulation clock without running every
	# craft substep. Its trajectory is retained, so it can become local again.
	var background_time := start_time
	var finish_time := simulation_time()
	if state.detached.any(func(piece): return piece.get("background", false)):
		while finish_time - background_time > 0.0000001:
			var interval := minf(BACKGROUND_DEBRIS_STEP, finish_time - background_time)
			_integrate_detached(interval, true, background_time)
			background_time += interval
	_refresh_telemetry()
	_stepping = false


## Limits use each body's radius, atmosphere and terrain envelope in its own frame.
func warp_limit(throttle: float = 0.0) -> float:
	if throttle > 0.0 or (state.boosters_on and state.boosters_attached and state.booster_fuel > 0.0):
		return 1.0
	for piece in state.detached:
		if float(piece.get("fuel", 0.0)) > 0.0 and float(piece.get("thrust", 0.0)) > 0.0:
			return 1.0
	if state.status == "ready": return 100000.0
	if state.status in ["landed", "crashed"]:
		return 100000.0 if Vector3(state.get("settling_velocity", Vector3.ZERO)).length() < 0.01 and Vector3(state.angular_velocity).length() < 0.01 else 1.0
	var limit := 100000.0
	for body in _debris_surfaces(simulation_time()):
		var definition: Resource = body.terrain.definition
		var altitude := _body_radius_at(state.position, body.center) - float(definition.radius)
		var floor_height := maxf(float(definition.atmosphere_height), float(definition.relief) * 2.0 + 100.0)
		var factors := [0.0, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0]
		var speeds := [5.0, 10.0, 50.0, 100.0, 1000.0, 10000.0, 100000.0]
		var available := 1.0
		for i in range(speeds.size()):
			if altitude >= maxf(MIN_RAIL_WARP_ALTITUDE, floor_height + float(definition.radius) * factors[i]): available = speeds[i]
		limit = minf(limit, available)
	return limit


## Returns actual elapsed time: a boundary stops the accelerated frame immediately.
func step_rails(dt: float, rate: float) -> float:
	if not is_finite(dt) or dt <= 0.0 or warp_limit(float(state.throttle)) < rate: return 0.0
	state.angular_velocity = Vector3.ZERO
	for piece in state.detached:
		piece.angular_momentum = Vector3.ZERO
		piece.angular_velocity = Vector3.ZERO
		piece.background = false
	var elapsed := 0.0
	_rail_warp = true
	_mass_cache = {}
	while elapsed < dt:
		if warp_limit(float(state.throttle)) < rate: break
		var interval := minf(dt - elapsed, 10.0)
		if state.status == "flying":
			# Resolve curved trajectories and approaching boundaries before large jumps.
			for body in _debris_surfaces(simulation_time()):
				var distance := _body_radius_at(state.position, body.center)
				var speed := maxf((Vector3(state.velocity) - Vector3(body.velocity)).length(), 1.0)
				interval = minf(interval, maxf(0.001, distance * 0.002 / speed))
				var rates := [5.0, 10.0, 50.0, 100.0, 1000.0, 10000.0, 100000.0]
				var factors := [0.0, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0]
				var definition: Resource = body.terrain.definition
				var floor_height := maxf(float(definition.atmosphere_height), float(definition.relief) * 2.0 + 100.0)
				var boundary := float(definition.radius) + maxf(MIN_RAIL_WARP_ALTITUDE, floor_height + float(definition.radius) * factors[maxi(rates.find(rate), 0)])
				interval = minf(interval, maxf(0.001, (distance - boundary) / speed))
		if not state.detached.is_empty():
			interval = BodyCollisions.step_limit(_collision_bodies(), interval)
		if state.status == "flying":
			_integrate(interval, Vector3.ZERO)
		elif state.status == "ready":
			_integrate_detached(interval)
			advance_prelaunch_time(interval)
		else:
			_integrate_detached(interval)
			_postflight_time += interval
			for body in _debris_surfaces(simulation_time()):
				if str(body.terrain.definition.planet_name) == state.get("landing_body", ""):
					var rotation: Basis = body.terrain.rotation_at(simulation_time())
					var radial: Vector3 = rotation * Vector3(state.landing_body_position)
					state.position = Vector3(body.center) + radial
					state.velocity = _body_surface_velocity(body, radial)
					state.orientation = rotation * Basis(state.landing_body_orientation)
		elapsed += interval
		state.angular_velocity = Vector3.ZERO
	_rail_warp = false
	_refresh_telemetry()
	return elapsed


func _can_relaunch(input: Dictionary) -> bool:
	var soft_touchdown: bool = state.status == "landed" or (state.status == "crashed" and float(state.get("impact_speed", INF)) <= DEBRIS_BREAKUP_SPEED)
	var requested_throttle := _finite_input(input, "throttle", 0.0, 0.0, 1.0)
	if soft_touchdown and requested_throttle == 0.0:
		_relaunch_armed = true
	return _relaunch_armed and not bool(state.get("destroyed", false)) and soft_touchdown and not bool(state["capsule_only"]) and float(state["fuel"]) > 0.0 and float(_stats.get("engine_thrust", 0.0)) > 0.0 and requested_throttle > 0.0


func _advance_after_touchdown(dt: float) -> void:
	var previous_velocity: Vector3 = state.velocity
	# Keep the world and released stages alive while preserving the flight report.
	_classify_debris(dt)
	var remaining := dt
	while remaining > 0.0000001:
		var interval := remaining if state.get("settled", false) and state.detached.is_empty() else minf(remaining, MAX_STEP)
		var start := simulation_time()
		_integrate_detached(interval, false, start)
		_integrate_detached(interval, true, start)
		_postflight_time += interval
		_settle_vessel(interval)
		remaining -= interval
	state.acceleration_vector = (Vector3(state.velocity)-previous_velocity)/maxf(dt,0.000001)
	state.acceleration = Vector3(state.acceleration_vector).length()
	_refresh_telemetry()


func _settle_vessel(dt: float) -> void:
	if state.get("destroyed", false): return
	var surfaces := _debris_surfaces(simulation_time())
	for body in surfaces:
		if str(body.terrain.definition.planet_name) != state.get("landing_body", ""):
			continue
		var rotation: Basis = body.terrain.rotation_at(simulation_time())
		var radial: Vector3 = rotation * Vector3(state.landing_body_position)
		if bool(state.get("landing_water", false)):
			_float_vessel(body, rotation, dt, surfaces)
			return
		# Settle in small body-frame offsets from the touchdown point. Absolute
		# planet-scale coordinates quantize to ~6 cm in float32, which turns
		# each contact correction into a hop and keeps the vessel rocking.
		if not state.has("landing_anchor"):
			state.landing_anchor = Vector3(state.landing_body_position)
			state.landing_offset = Vector3.ZERO
			state.landing_anchor_normal = rotation.transposed() * Vector3(body.terrain.contact(radial, simulation_time()).normal)
		var anchor: Vector3 = state.landing_anchor
		state.position = Vector3(body.center) + radial
		state.orientation = rotation * Basis(state.landing_body_orientation)
		if state.get("settled", false):
			state.velocity = _body_surface_velocity(body, radial)
			state.angular_velocity = Vector3.ZERO
			return
		var craft: Dictionary = _collision_bodies().back()
		craft.settle_time = float(state.get("settle_time", 0.0))
		craft.recoverable = true
		craft.fuel = 0.0
		craft.thrust = 0.0
		craft.orientation = Basis(state.landing_body_orientation)
		craft.position = Vector3(state.landing_offset) + Basis(craft.orientation) * Vector3(craft.local_center)
		craft.velocity = Vector3(state.get("settling_velocity", Vector3.ZERO))
		craft.angular_momentum = Basis(craft.orientation) * (Vector3(craft.inertia) * Vector3(state.angular_velocity))
		craft.velocity += rotation.transposed() * _debris_gravity(state.position, surfaces) * dt
		var omega: Vector3 = state.angular_velocity
		if omega.length() > 0.000001:
			craft.orientation = (Basis(craft.orientation) * Basis(omega.normalized(), omega.length() * dt)).orthonormalized()
		craft.position += Vector3(craft.velocity) * dt
		craft.angular_velocity = (Basis(craft.orientation).transposed() * Vector3(craft.angular_momentum)) / Vector3(craft.inertia)
		# The touchdown triangle's plane, through the anchor, in body coordinates.
		var normal: Vector3 = state.landing_anchor_normal
		var support := _debris_support(craft, normal)
		var gap := Vector3(craft.position).dot(normal) + support.dot(normal)
		if gap <= 0.02:
			_debris_contact(craft, {"normal": normal, "position": Vector3.ZERO}, dt, simulation_time(), {"terrain": body.terrain, "center": Vector3.ZERO, "velocity": Vector3.ZERO})
		else:
			craft.settle_time = 0.0
		state.settle_time = craft.settle_time
		if craft.settle_time >= DEBRIS_SETTLE_SECONDS:
			state["settled"] = true
			craft.velocity = Vector3.ZERO
			craft.angular_velocity = Vector3.ZERO
		state.landing_offset = Vector3(craft.position) - Basis(craft.orientation) * Vector3(craft.local_center)
		state.landing_body_orientation = Basis(craft.orientation)
		state.landing_body_position = anchor + Vector3(state.landing_offset)
		state.settling_velocity = craft.velocity
		radial = rotation * Vector3(state.landing_body_position)
		state.orientation = rotation * Basis(craft.orientation)
		state.position = Vector3(body.center) + radial
		state.velocity = _body_surface_velocity(body, radial) + rotation * Vector3(craft.velocity)
		state.angular_velocity = craft.angular_velocity
		break


## Rigid-body flotation in the rotating water frame. Entry momentum carries
## the hull under, displaced volume lifts it, and the righting moment of the
## real mass distribution decides whether it floats upright or on its side.
func _float_vessel(body: Dictionary, rotation: Basis, dt: float, surfaces: Array) -> void:
	# Accumulate small offsets from the splashdown point; planet-scale float32
	# coordinates would quantize each step's motion (see the land path).
	var anchor: Vector3 = state.get("water_anchor", state.landing_body_position)
	var up := anchor.normalized()
	var properties := _mass_properties()
	var center: Vector3 = properties.center
	var attitude: Basis = state.landing_body_orientation
	var float_body := {
		"position": Vector3(state.get("water_offset", Vector3.ZERO)) + attitude * center,
		"velocity": state.get("water_velocity", Vector3.ZERO), "orientation": attitude,
		"angular_velocity": state.angular_velocity, "mass": properties.mass,
		"inertia": properties.inertia, "center": center}
	if not state.get("settled", false):
		var gravity := _debris_gravity(Vector3(body.center) + rotation * anchor, surfaces).length()
		Hydrostatics.step(float_body, _water_hull_samples(), up, gravity, dt)
		var omega: Vector3 = float_body.angular_velocity
		if Vector3(float_body.velocity).length() < 0.05 and omega.length() < 0.03:
			state.settle_time = float(state.get("settle_time", 0.0)) + dt
		else:
			state.settle_time = 0.0
		if state.settle_time >= DEBRIS_SETTLE_SECONDS:
			state.settled = true
			float_body.velocity = Vector3.ZERO
			float_body.angular_velocity = Vector3.ZERO
		state.water_immersion = float_body.draft
		state.water_displaced_mass = float_body.displaced_mass
	attitude = float_body.orientation
	var water_velocity: Vector3 = float_body.velocity
	var omega_local: Vector3 = float_body.angular_velocity
	var origin_arm := attitude * -center
	state.water_offset = Vector3(float_body.position) + origin_arm
	state.water_velocity = water_velocity
	state.settling_velocity = water_velocity
	state.landing_body_orientation = attitude
	state.landing_body_position = anchor + Vector3(state.water_offset)
	# Height of the vessel origin above the water plane, from small offsets.
	# The absolute position rounds to ~6 cm at planet scale, differently each
	# tick as the planet turns; the renderer places the sea from this instead.
	state.water_height = Vector3(state.water_offset).dot(up)
	var radial: Vector3 = rotation * Vector3(state.landing_body_position)
	state.position = Vector3(body.center) + radial
	state.orientation = rotation * attitude
	var origin_velocity := water_velocity + (attitude * omega_local).cross(origin_arm)
	state.velocity = _body_surface_velocity(body, radial) + rotation * origin_velocity
	state.angular_velocity = omega_local


func _water_hull_samples() -> Dictionary:
	var key := [bool(state.capsule_only), bool(state.boosters_attached), state.removed_parts.duplicate(), float(state.get("stack_bottom", 0.0))]
	if not _water_hull.is_empty() and key == _water_hull_key:
		return _water_hull
	# Same envelope as the collision shapes, but the capsule uses its lathed
	# outline: its wide heat-shield base is what keeps it floating upright.
	var top := 0.0 if state.capsule_only else _stack_top()
	var shapes: Array = [{"bottom": top, "top": top + Hydrostatics.RecoveryHull.TOP - Hydrostatics.RecoveryHull.BOTTOM, "radius": 0.98, "profile": true}]
	if not state.capsule_only:
		shapes.append({"bottom": float(state.get("stack_bottom", 0.0)), "top": top, "radius": .95})
		if state.boosters_attached:
			for booster in _radial_layout.boosters:
				var mount: Vector3 = booster.position
				shapes.append({"bottom": mount.y - 2.64, "top": mount.y + 2.64, "radius": .72, "lateral": Vector3(mount.x, 0.0, mount.z)})
	_water_hull = Hydrostatics.hull(shapes)
	_water_hull_key = key
	return _water_hull


func stage() -> String:
	if _design.has("assembly"):
		return execute_stage()
	if str(state["status"]) != "flying":
		return "Launch before separating a stage."
	if bool(state["boosters_attached"]):
		state["stage_index"] += 1
		_separate_boosters()
		state["engine_on"] = true
		_refresh_telemetry()
		return "Side boosters separated. Core engine ignited." if _design.booster_first else "Side boosters separated."
	if not bool(state["capsule_only"]):
		state["stage_index"] += 1
		_separate_core()
		_refresh_telemetry()
		return "Capsule separated. Deploy below 2.5 km and 180 m/s while descending."
	return "No stages remaining."


func deploy_chute() -> String:
	if not _design.get("parachute", true): return "No parachute installed."
	_refresh_telemetry()
	if bool(state.get("chute_cut", false)):
		return "Parachute was cut away and cannot be redeployed."
	if bool(state["chute_deployed"]):
		return "Parachute is already deployed."
	if str(state["status"]) != "flying":
		return "Parachute can only deploy in flight."
	if float(state["terrain_clearance"]) > CHUTE_MAX_ALTITUDE:
		return "Too high. Deploy below 2.5 km."
	if float(state["speed"]) > CHUTE_MAX_SPEED:
		return "Too fast. Slow below 180 m/s before deployment."
	if float(state["vertical_speed"]) > 0.0:
		return "Still climbing. Deploy the parachute while descending."
	state["chute_deployed"] = true
	return "Parachute deployed."


func simulation_time() -> float:
	return _postflight_time + _prelaunch_time + float(state.get("time", 0.0))


func advance_prelaunch_time(dt: float) -> void:
	if state.get("status") == "ready" and is_finite(dt) and dt > 0.0:
		_prelaunch_time += dt
		# A vehicle resting on the pad belongs to the rotating surface frame.
		# Carry that attitude into ignition so time acceleration cannot rotate the
		# launch site underneath a stationary rocket or make the craft snap back.
		var rotation: Basis = terrain.rotation_at(_prelaunch_time)
		var radial: Vector3 = rotation * Surface.LAUNCH_RADIAL
		state["position"] = PLANET_CENTER + radial
		state["velocity"] = terrain.surface_velocity(radial)
		state["orientation"] = rotation * Surface.LAUNCH_BASIS


func telemetry() -> Dictionary:
	_refresh_telemetry()
	var result := state.duplicate(true)
	result["maneuver_engines"] = maneuver_engines()
	# One-shot visual events share their queue so rendering acknowledges them.
	result["surface_impacts"] = state.surface_impacts
	result["simulation_time"] = simulation_time()
	return result


## Currently ignited liquid engines and their usable feed, for burn estimates.
func maneuver_engines() -> Array:
	var result: Array = []
	if state.capsule_only or not state.engine_on: return result
	for engine in _engines:
		if engine.id in state.removed_parts: continue
		if not state.active_engines.is_empty() and engine.id not in state.active_engines: continue
		var fuel := float(state.engine_fuel.get(engine.id, 0.0)) if not state.engine_fuel.is_empty() else float(state.fuel)
		if fuel <= 0.0: continue
		var spec: Dictionary = Parts.ENGINES[engine.kind]
		result.append({"thrust": float(spec.thrust), "isp": float(spec.isp), "fuel": fuel})
	return result


static func air_density_at(altitude: float) -> float:
	return _air_density_profile(altitude, 1.225, ATMOSPHERE_HEIGHT)


static func _air_density_profile(altitude: float, sea_level_density: float, atmosphere_height: float) -> float:
	if atmosphere_height <= 0.0 or sea_level_density <= 0.0 or altitude >= atmosphere_height:
		return 0.0
	var height: float = maxf(altitude, 0.0)
	# Earth-like hydrostatic layers: troposphere, stratosphere and mesosphere.
	# Stretch the reference column for custom planets; surface density remains
	# independently configurable. Height is in metres, temperature in kelvin.
	var reference_height := height * ATMOSPHERE_HEIGHT / atmosphere_height
	var boundaries := [11000.0, 20000.0, 32000.0, 47000.0, 51000.0, 71000.0, 90000.0]
	var lapse_rates := [-0.0065, 0.0, 0.001, 0.0028, 0.0, -0.0028, -0.002]
	var temperature := 288.15
	var pressure_ratio := 1.0
	var base_height := 0.0
	const GAS_CONSTANT := 287.05287 # Specific gas constant for dry air, J/(kg K).
	for layer in range(boundaries.size()):
		var thickness := minf(reference_height, float(boundaries[layer])) - base_height
		var lapse: float = lapse_rates[layer]
		var next_temperature := temperature + lapse * thickness
		if lapse == 0.0:
			pressure_ratio *= exp(-Physics.STANDARD_GRAVITY * thickness / (GAS_CONSTANT * temperature))
		else:
			pressure_ratio *= pow(temperature / next_temperature, Physics.STANDARD_GRAVITY / (GAS_CONSTANT * lapse))
		temperature = next_temperature
		if reference_height <= float(boundaries[layer]): break
		base_height = float(boundaries[layer])
	# Only taper the very thin last 5 km to meet the simulation's vacuum boundary.
	var taper := 1.0 - smoothstep(85000.0, ATMOSPHERE_HEIGHT, reference_height)
	return sea_level_density * pressure_ratio * (288.15 / temperature) * taper


func _air_density_at(altitude: float) -> float:
	return _air_density_profile(altitude, float(terrain.definition.atmosphere_density), float(terrain.definition.atmosphere_height))


func _surface_gravity() -> float:
	return float(terrain.definition.surface_gravity)


func _mu() -> float:
	var radius := float(terrain.definition.radius)
	return _surface_gravity() * radius * radius


func _gravity(radial: Vector3) -> Vector3:
	var radius := maxf(radial.length(), 1.0)
	return -radial * (_mu() / (radius * radius * radius))


func _body_radius_at(position: Vector3, center: Vector3) -> float:
	var x: float = float(position.x) - float(center.x)
	var y: float = float(position.y) - float(center.y)
	var z: float = float(position.z) - float(center.z)
	return sqrt(x * x + y * y + z * z)


func _body_surface_velocity(body: Dictionary, radial: Vector3) -> Vector3:
	return Vector3(body.velocity) + body.terrain.surface_velocity(radial)


func _nearest_body(position: Vector3, bodies: Array) -> Dictionary:
	var nearest: Dictionary = bodies[0]
	var nearest_clearance := INF
	for body: Dictionary in bodies:
		var clearance := _body_radius_at(position, body.center) - float(body.terrain.definition.radius)
		if clearance < nearest_clearance:
			nearest = body
			nearest_clearance = clearance
	return nearest


func _atmosphere_height() -> float:
	return float(terrain.definition.atmosphere_height)


static func _advance_position(body: Dictionary, position: Vector3, displacement: Vector3) -> Vector3:
	# Vector3 uses float32 even though scalar floats use float64. Carry the
	# rounding remainder so small relative velocities survive escape distances.
	var remainder: Vector3 = body.get("position_remainder", Vector3.ZERO)
	var result := Vector3.ZERO
	for axis in range(3):
		var exact := float(position[axis]) + float(remainder[axis]) + float(displacement[axis])
		result[axis] = exact
		remainder[axis] = exact - float(result[axis])
	body.position_remainder = remainder
	return result


func _integrate(dt: float, control: Vector3) -> void:
	_integrate_detached(dt)
	if _rail_warp: _integrate_detached(dt, true)
	state["time"] = float(state["time"]) + dt
	var current_time := simulation_time()
	var previous_bodies := _debris_surfaces(current_time - dt)
	var bodies := _debris_surfaces(current_time)
	var angular_velocity: Vector3 = state["angular_velocity"]
	var damping: float = 5.0 if bool(state["sas"]) else 0.65
	if bool(_design["fins"]) and not bool(state["capsule_only"]):
		var current_altitude: float = _radius_at(Vector3(state["position"])) - PLANET_RADIUS
		damping += 1.8 * _air_density_at(current_altitude) / 1.225
	var authority: float = 2.0 if bool(state["capsule_only"]) else 1.5
	var moment := Vector3(8000,600,8000) if not state.capsule_only else Vector3(450,200,450)
	# Attached wheels add torque independently of baseline capsule/engine authority.
	var wheel_count := 0 if state.capsule_only else Parts.reaction_wheels(_design).size()
	var wheel_torque := float(wheel_count) * Parts.REACTION_WHEEL_TORQUE
	angular_velocity += control * (authority * moment + Vector3.ONE * wheel_torque) / Vector3(_mass_properties().inertia) * dt
	angular_velocity *= exp(-damping * dt)
	# Preserve the original limit for legacy craft; wheels also allow faster turns.
	angular_velocity = angular_velocity.limit_length(1.0 + 0.5 * wheel_count)
	var orientation: Basis = state["orientation"]
	var previous_orientation := orientation
	if _rail_warp: angular_velocity = Vector3.ZERO
	var angular_speed: float = angular_velocity.length()
	if angular_speed > 0.000001:
		orientation = (orientation * Basis(angular_velocity / angular_speed, angular_speed * dt)).orthonormalized()
	# Keep the mass centroid fixed during pure rotation; position tracks the base.
	if angular_speed > 0.000001:
		var center: Vector3 = _mass_properties().center
		state.position = _advance_position(state, state.position, previous_orientation*center-orientation*center)
	state["orientation"] = orientation
	state["angular_velocity"] = angular_velocity

	var position: Vector3 = state["position"]
	var velocity: Vector3 = state["velocity"]
	var local_body := _nearest_body(position, previous_bodies)
	var local_terrain: RefCounted = local_body.terrain
	var local_definition: Resource = local_terrain.definition
	var radial_position: Vector3 = position - Vector3(local_body.center)
	var radius: float = maxf(_body_radius_at(position, local_body.center), 1.0)
	var up: Vector3 = radial_position / radius
	var altitude: float = maxf(radius - float(local_definition.radius), 0.0)
	if _clearance(position,simulation_time()-dt) > 0.1:
		_has_lifted = true
		_relaunching = false
	var density := _air_density_profile(altitude, float(local_definition.atmosphere_density), float(local_definition.atmosphere_height))
	var gravity := _debris_gravity(position, previous_bodies)
	var thrust: float = 0.0
	var core_thrust := 0.0
	var booster_thrust := 0.0
	var mass_before_burn: float = _current_mass()
	if not _rail_warp and bool(state["engine_on"]) and not bool(state["capsule_only"]):
		if not state.get("engine_fuel", {}).is_empty():
			for engine in _engines:
				if not engine.id in state.active_engines or engine.id in state.removed_parts: continue
				var spec: Dictionary = Parts.ENGINES[engine.kind]
				var wanted_thrust := float(spec.thrust) * float(state.throttle)
				var wanted_fuel := wanted_thrust * dt / (float(spec.isp) * Physics.STANDARD_GRAVITY)
				var burned := minf(float(state.engine_fuel.get(engine.id,0.0)),wanted_fuel)
				if wanted_fuel > 0.0: core_thrust += wanted_thrust * burned / wanted_fuel
				state.engine_fuel[engine.id] = maxf(float(state.engine_fuel.get(engine.id,0.0))-burned,0.0)
				state.fuel = maxf(float(state.fuel)-burned,0.0)
			thrust = core_thrust
		else:
			var propulsion := _active_propulsion()
			var desired_thrust: float = float(propulsion.thrust) * float(state["throttle"])
			var desired_fuel: float = float(propulsion.flow) * float(state["throttle"]) * dt
			var burned_fuel: float = minf(float(state["fuel"]), desired_fuel)
			if desired_fuel > 0.0:
				core_thrust = desired_thrust * burned_fuel / desired_fuel
				thrust += core_thrust
			state["fuel"] = maxf(float(state["fuel"]) - burned_fuel, 0.0)
	# Solid boosters burn continuously after ignition, independently of throttle.
	if not _rail_warp and bool(state["boosters_on"]) and bool(state["boosters_attached"]) and float(state["booster_fuel"]) > 0.0:
		var wanted: float = float(_stats.booster_thrust) * dt / (Parts.BOOSTER_ISP * Physics.STANDARD_GRAVITY)
		var burned: float = minf(float(state["booster_fuel"]), wanted)
		booster_thrust = float(_stats.booster_thrust) * burned / wanted
		thrust += booster_thrust
		state["booster_fuel"] = maxf(float(state["booster_fuel"]) - burned, 0.0)
	if not state.capsule_only:
		var properties := _mass_properties()
		var center: Vector3 = properties.center
		var torque := (Vector3(0,.2,0)-center).cross(Vector3.UP*core_thrust)
		var boosters: Array = _radial_layout.boosters
		if state.boosters_attached:
			for booster in boosters:
				torque += (Vector3(booster.position)-center).cross(Vector3.UP*booster_thrust/maxi(boosters.size(),1))
		state.angular_velocity += torque / Vector3(properties.inertia) * dt
	var mass: float = (mass_before_burn + _current_mass()) * 0.5
	var air_velocity: Vector3 = velocity - _body_surface_velocity(local_body, radial_position)
	var speed: float = air_velocity.length()
	state.air_velocity = air_velocity
	_update_aerothermal(dt, density, speed)
	var drag_area: float = 0.40 if bool(state["capsule_only"]) else 0.52
	if bool(state["boosters_attached"]):
		drag_area += 0.11 * float(_stats.booster_count)
	# Crossflow loads resist sideways motion across the hull, rather than
	# applying the whole broadside area as a brake along the flight path.
	var side_area := 0.0 if state.capsule_only else (_stack_top() + 2.2) * 0.75
	var side_exposure := _advance_side_drag(air_velocity, orientation.y, density, dt)
	var canopy_area := 0.0
	if not _rail_warp and bool(state["chute_deployed"]):
		_chute_opening = minf(_chute_opening + dt / 2.5, 1.0)
		canopy_area = 203.0 * _chute_opening
	var drag := Physics.body_drag_acceleration(air_velocity, orientation.y, density, mass, drag_area + canopy_area, side_area, dt, side_exposure)
	if _rail_warp: drag = Vector3.ZERO
	var drag_acceleration := drag.length()
	if bool(state["chute_deployed"]) and speed > 0.01:
		# Apply the canopy's share of drag at its top attachment, not at the centroid.
		var properties := _mass_properties()
		var attachment := Vector3(0, (0.0 if state.capsule_only else _stack_top()) + 3.05, 0)
		var arm := attachment - Vector3(properties.center)
		# Only canopy drag acts at the parachute attachment, not hull crossflow.
		var canopy_drag := Physics.body_drag_acceleration(air_velocity, orientation.y, density, mass, canopy_area, 0.0, dt)
		var chute_force := orientation.transposed() * canopy_drag * mass
		var torque := arm.cross(chute_force)
		state.angular_velocity += torque / Vector3(properties.inertia) * dt
	var acceleration: Vector3 = gravity + orientation.y * thrust / mass + drag
	var previous_position: Vector3 = position
	var previous_velocity: Vector3 = velocity
	# Symmetric gravity integration; thrust and aerodynamic forces are held
	# constant over this small substep. In vacuum this is velocity Verlet.
	var half_velocity := velocity + acceleration * (0.5 * dt)
	position = _advance_position(state, position, half_velocity * dt)
	var next_gravity := _debris_gravity(position, bodies)
	velocity = half_velocity + (acceleration - gravity + next_gravity) * (0.5 * dt)
	var next_radial: Vector3 = position - PLANET_CENTER
	var next_local_body := _nearest_body(position, bodies)
	var next_altitude: float = _body_radius_at(position, next_local_body.center) - float(next_local_body.terrain.definition.radius)
	var next_clearance := _clearance(position,simulation_time())
	if next_clearance > 1.0: _has_lifted = true
	var landing_body: Dictionary = {}
	var landing_hit: Dictionary = {}
	var landing_radial := Vector3.ZERO
	for index in range(bodies.size()):
		var body: Dictionary = bodies[index]
		var old_body: Dictionary = previous_bodies[index]
		var body_terrain: RefCounted = body.terrain
		var radial_end: Vector3 = position - Vector3(body.center)
		var body_hit: Dictionary = body_terrain.segment_hit(previous_position - Vector3(old_body.center), radial_end, current_time - dt, current_time)
		var sea_hit := _sea_hit(body_terrain, previous_position - Vector3(old_body.center), radial_end, current_time)
		if not sea_hit.is_empty() and float(sea_hit.fraction) < float(body_hit.get("fraction", INF)): body_hit = sea_hit
		var close_enough := _body_radius_at(position, body.center) <= float(body_terrain.definition.radius) + float(body_terrain.definition.relief) * 2.0 + 0.05
		# The home launch point needs scalar-double clearance so the first
		# millimetres of liftoff are not rounded back into the ground.
		var penetrating: bool = next_clearance <= 0.0 if index == 0 else (close_enough and body_terrain.clearance(radial_end, current_time) <= 0.0)
		if body_hit.is_empty() and not penetrating:
			continue
		if landing_body.is_empty() or float(body_hit.get("fraction", 1.0)) < float(landing_hit.get("fraction", 1.0)):
			landing_body = body
			landing_hit = body_hit
			landing_radial = radial_end
	if not landing_body.is_empty():
		var landing_terrain: RefCounted = landing_body.terrain
		var contact: Dictionary = landing_terrain.contact(landing_radial,current_time)
		var contact_radial: Vector3 = landing_radial.normalized()*float(contact.radius)
		var normal: Vector3 = contact.normal
		var contact_fraction := 1.0
		if not landing_hit.is_empty():
			contact_radial = landing_hit.position
			normal = landing_hit.normal
			contact_fraction = landing_hit.fraction
		if not _has_lifted and (_relaunching or float(state["max_altitude"]) < 1.0):
			position = Vector3(landing_body.center)+contact_radial
			velocity = _body_surface_velocity(landing_body, contact_radial)
		else:
			var impact_velocity: Vector3 = previous_velocity.lerp(velocity,contact_fraction)-_body_surface_velocity(landing_body, contact_radial)
			var impact_speed := impact_velocity.length()
			state["impact_speed"] = impact_speed
			var water_direction: Vector3 = landing_terrain.rotation_at(current_time).transposed() * contact_radial.normalized()
			var on_water: bool = bool(landing_terrain.definition.has_ocean) and landing_terrain.color_at(water_direction, landing_terrain.elevation(water_direction)).a > 0.5
			if -impact_velocity.dot(normal) > DEBRIS_BREAKUP_SPEED and not on_water:
				state["destroyed"] = true
				_queue_surface_explosion(Vector3(landing_body.center) + contact_radial, 2.6 if state.capsule_only else _stack_top() + 2.6)
			var upright: bool = (bool(state["capsule_only"]) or orientation.y.dot(normal) > 0.8) and normal.dot(contact_radial.normalized()) > 0.70
			state["status"] = "landed" if (impact_speed <= SAFE_LANDING_SPEED and (upright or on_water)) else "crashed"
			state["landing_water"] = on_water
			if on_water:
				state["water_velocity"] = landing_terrain.rotation_at(current_time).transposed() * impact_velocity
				state["water_immersion"] = 0.0
				state["water_offset"] = Vector3.ZERO
				state["water_anchor"] = landing_terrain.rotation_at(current_time).transposed() * contact_radial
				# Swell never meets a hull perfectly level. Without this nudge a
				# vertical splashdown balances a tall stack on an unstable
				# equilibrium indefinitely instead of letting it capsize.
				state["angular_velocity"] = Vector3(state.angular_velocity) + Vector3(0.02, 0.0, 0.01)
			state["landing_normal"] = normal
			state["settling_velocity"] = Vector3.ZERO
			state["settled"] = false
			state["settle_time"] = 0.0
			state["landing_body_position"] = landing_terrain.rotation_at(current_time).transposed()*contact_radial
			state["landing_anchor"] = state["landing_body_position"]
			state["landing_offset"] = Vector3.ZERO
			state["landing_anchor_normal"] = landing_terrain.rotation_at(current_time).transposed() * normal
			state["landing_body"] = str(landing_terrain.definition.planet_name)
			state["landing_body_orientation"] = landing_terrain.rotation_at(current_time).transposed() * Basis(state.orientation)
			state["impact_body"] = str(landing_terrain.definition.planet_name)
			state["engine_on"] = false
			# A held throttle must not undo the touchdown shutdown next frame.
			# Cut throttle before requesting a deliberate restart.
			_relaunch_armed = float(state["throttle"]) == 0.0
			state["boosters_on"] = false
			state["thrust"] = 0.0
			state["max_speed"] = maxf(float(state["max_speed"]),impact_speed)
			position = Vector3(landing_body.center)+contact_radial
			velocity = _body_surface_velocity(landing_body, contact_radial) + (impact_velocity if on_water else Vector3.ZERO)
	var solar_hit := SolarBody.segment_hit(previous_position, position)
	if solar_hit >= 0.0:
		position = previous_position.lerp(position, solar_hit)
		state["status"] = "crashed"
		state["impact_body"] = "Sun"
		state["impact_speed"] = velocity.length()
		state["engine_on"] = false
		state["boosters_on"] = false
		velocity = Vector3.ZERO
	state["position"] = position
	if str(state["status"]) != "flying": state.position_remainder = Vector3.ZERO
	state["velocity"] = velocity
	_resolve_body_collisions()
	state["thrust"] = thrust if str(state["status"]) == "flying" else 0.0
	state["acceleration_vector"] = acceleration if state.status == "flying" else Vector3.ZERO
	state["acceleration"] = Vector3(state["acceleration_vector"]).length()
	state["drag_acceleration"] = drag_acceleration
	state["max_g"] = maxf(float(state["max_g"]), (orientation.y * thrust / mass + drag).length() / Physics.STANDARD_GRAVITY)
	# Keep peaks correct even during an accelerated frame containing the whole apex.
	state["max_altitude"] = maxf(float(state["max_altitude"]), maxf(next_altitude, 0.0))
	state["max_speed"] = maxf(float(state["max_speed"]), velocity.length())


## Gameplay thermal model: aerodynamic heating scales with sqrt(density) * speed³.
## Temperature retains heat between steps; no heating occurs in vacuum.
func _update_aerothermal(dt: float, density: float, speed: float) -> void:
	var heating := 110.0 * sqrt(maxf(density, 0.0) / 1.225) * pow(maxf(speed, 0.0) / 700.0, 3.0)
	var cooling := 0.10
	var equilibrium := 288.0 + heating / cooling
	state.temperature = clampf(equilibrium + (float(state.temperature) - equilibrium) * exp(-cooling * dt), 288.0, 4000.0)
	state.heating_rate = heating
	state.heat_glow = smoothstep(700.0, 1400.0, float(state.temperature))


func _advance_side_drag(air_velocity: Vector3, axis: Vector3, density: float, dt: float) -> float:
	# Relax the crossflow coefficient, never velocity or the force direction.
	# Forces always use current airflow, so a turn cannot create a velocity
	# impulse or leave an old force accelerating the vessel after flow reverses.
	if density <= 0.0 or air_velocity.is_zero_approx() or _rail_warp or state.capsule_only:
		state.side_drag_exposure = 0.0
		return 0.0
	var alignment := clampf(axis.dot(air_velocity.normalized()), -1.0, 1.0)
	var target := sqrt(maxf(0.0, 1.0 - alignment * alignment))
	var previous := float(state.side_drag_exposure)
	var decay := exp(-dt / SIDE_DRAG_RESPONSE_SECONDS)
	state.side_drag_exposure = target + (previous - target) * decay
	# Mean exposure over the substep keeps the response independent of rate.
	return target + (previous - target) * SIDE_DRAG_RESPONSE_SECONDS * (1.0 - decay) / dt


func _current_mass() -> float:
	if bool(state["capsule_only"]):
		return Parts.recovery_mass(_design)
	var mass: float = _core_dry_mass - float(state.get("discarded_dry_mass",0.0)) + float(state["fuel"])
	if bool(state["boosters_attached"]):
		mass += float(_stats.booster_dry_mass) + float(state["booster_fuel"])
	return mass


func _refresh_telemetry() -> void:
	var properties := _mass_properties()
	state.center_of_mass = properties.center
	state.moment_of_inertia = properties.inertia
	var position: Vector3 = state["position"]
	var velocity: Vector3 = state["velocity"]
	var bodies := _debris_surfaces(simulation_time())
	var local_body := _nearest_body(position, bodies)
	var local_terrain: RefCounted = local_body.terrain
	var definition: Resource = local_terrain.definition
	var radial: Vector3 = position - Vector3(local_body.center)
	var radius: float = maxf(_body_radius_at(position, local_body.center), 1.0)
	var up: Vector3 = radial / radius
	var body_radius := float(definition.radius)
	var altitude: float = maxf(radius - body_radius, 0.0)
	var relative_velocity := velocity - Vector3(local_body.velocity)
	var surface_velocity: Vector3 = velocity-_body_surface_velocity(local_body, radial)
	# Rendering needs the final velocity after forces, collisions, and staging.
	state.air_velocity = surface_velocity
	var speed: float = surface_velocity.length()
	var vertical_speed: float = surface_velocity.dot(up)
	var horizontal_speed: float = (surface_velocity - up * vertical_speed).length()
	var local_mu: float = float(definition.surface_gravity) * body_radius * body_radius
	var elements := Physics.orbital_elements(radial, relative_velocity, local_mu, body_radius)
	state.merge(elements, true)
	var periapsis: float = elements.periapsis
	var apoapsis: float = elements.apoapsis
	state["altitude"] = altitude
	var ground_contact: Dictionary = local_terrain.contact(radial,simulation_time())
	# Over open water the surface is the sea-level sphere, not the sagging
	# mesh below it (see _sea_hit): the readout and parachute cloth use it.
	if bool(definition.has_ocean) and float(ground_contact.radius) < body_radius:
		var local_up: Vector3 = local_terrain.rotation_at(simulation_time()).transposed() * up
		if local_terrain.color_at(local_up, local_terrain.elevation(local_up)).a > 0.5:
			ground_contact = {"radius": body_radius, "normal": up}
	state["terrain_clearance"] = maxf(0.0,radius-float(ground_contact.radius))
	state["terrain_normal"] = Vector3(ground_contact.normal).normalized()
	# Signed distance to the actual terrain triangle, rather than a radial plane.
	state["terrain_plane_distance"] = (radius-float(ground_contact.radius))*up.dot(state["terrain_normal"])
	state["reference_body"] = str(definition.planet_name)
	state["speed"] = speed
	state["vertical_speed"] = vertical_speed
	state["horizontal_speed"] = horizontal_speed
	state["mass"] = _current_mass()
	state["apoapsis"] = maxf(apoapsis, altitude)
	state["periapsis"] = periapsis
	state["in_stable_orbit"] = periapsis >= float(definition.atmosphere_height) and is_finite(apoapsis)
	state["orbit_achieved"] = bool(state["orbit_achieved"]) or bool(state["in_stable_orbit"])
	state["max_altitude"] = maxf(float(state["max_altitude"]), altitude)
	state["max_speed"] = maxf(float(state["max_speed"]), speed)
	state["fuel_fraction"] = float(state["fuel"]) / maxf(float(state["max_fuel"]), 1.0)
	state["booster_fraction"] = float(state["booster_fuel"]) / maxf(float(state["max_booster_fuel"]), 1.0)
	state["air_density"] = _air_density_profile(altitude, float(definition.atmosphere_density), float(definition.atmosphere_height))
	state["sea_level_air_density"] = float(definition.atmosphere_density)
	state["atmosphere_height"] = float(definition.atmosphere_height)
	state["dynamic_pressure"] = 0.5 * float(state["air_density"]) * speed * speed
	state["gravity"] = local_mu / (radius * radius)
	state["mach"] = speed / 340.0
	state["chute_safe"] = bool(_design.get("parachute", true)) and str(state["status"]) == "flying" and not bool(state["chute_deployed"]) and not bool(state.get("chute_cut", false)) and float(state["terrain_clearance"]) <= CHUTE_MAX_ALTITUDE and speed <= CHUTE_MAX_SPEED and vertical_speed <= 0.0
	state["flight_path_angle"] = rad_to_deg(atan2(vertical_speed, horizontal_speed)) if speed > 0.01 else 90.0


static func _finite_input(input: Dictionary, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value: float = float(input.get(key, fallback))
	return clampf(value, minimum, maximum) if is_finite(value) else fallback


## Where a substep crosses open water's sea-level sphere. The collision mesh's
## flat ocean triangles sag below that sphere (about 12 m mid-face on the
## home planet), while the drawn water follows it, so splashing down on the
## mesh left vessels floating metres underwater.
func _sea_hit(body_terrain: RefCounted, start: Vector3, finish: Vector3, time: float) -> Dictionary:
	if not bool(body_terrain.definition.has_ocean): return {}
	var radius := float(body_terrain.definition.radius)
	var start_radius := start.length()
	var finish_radius := finish.length()
	if start_radius < radius or finish_radius >= radius: return {}
	var fraction := (start_radius - radius) / maxf(start_radius - finish_radius, 0.000001)
	var direction := start.lerp(finish, fraction).normalized()
	var local: Vector3 = body_terrain.rotation_at(time).transposed() * direction
	if body_terrain.color_at(local, body_terrain.elevation(local)).a <= 0.5: return {}
	return {"position": direction * radius, "normal": direction, "fraction": fraction}

func _clearance(position: Vector3, time: float) -> float:
	var radial := position-PLANET_CENTER
	if _radius_at(position) > PLANET_RADIUS+float(terrain.definition.relief)*2.0:
		# Above every possible peak, a conservative bound is enough for contact rejection.
		return _radius_at(position)-PLANET_RADIUS-float(terrain.definition.relief)*2.0
	return _radius_at(position)-float(terrain.contact(radial,time).radius)

static func _radius_at(position: Vector3) -> float:
	# Vector3 uses float32 in standard Godot builds. Adding the planet's 60 km
	# radius in a Vector3 can erase the first millimetres of a heavy rocket's
	# liftoff, causing the terrain constraint to pin it permanently to the pad.
	# Scalar floats use doubles, preserving the local position for contact tests.
	var x: float = float(position.x)
	var y: float = float(position.y) + PLANET_RADIUS
	var z: float = float(position.z)
	return sqrt(x * x + y * y + z * z)


func staging_groups() -> Array:
	return _design.assembly.stages

func attached_stage_actions(index: int) -> Array:
	var result: Array = []
	for action in staging_groups()[index]:
		var id: String = action.get_slice(":", 1)
		if id == "boosters":
			if not state.boosters_attached: continue
		elif id == "capsule":
			if not _design.get("parachute", false): continue
		elif state.capsule_only or id in state.get("removed_parts", []): continue
		result.append(action)
	return result

func skip_detached_stages() -> void:
	while int(state.stage_index) < staging_groups().size() and attached_stage_actions(int(state.stage_index)).is_empty():
		state.stage_index += 1

func can_reorder_stage(source: int, destination: int) -> bool:
	return state.status in ["ready", "flying"] and source != destination and source >= int(state.stage_index) and destination >= int(state.stage_index) and source < staging_groups().size() and destination < staging_groups().size() and not attached_stage_actions(source).is_empty() and not attached_stage_actions(destination).is_empty()

func reorder_stage(source: int, destination: int) -> bool:
	if not can_reorder_stage(source, destination): return false
	var groups := staging_groups()
	var group: Array = groups.pop_at(source)
	groups.insert(destination, group)
	return true

func execute_stage() -> String:
	if not state.status in ["ready", "flying"]:
		return "Staging unavailable after flight ends."
	skip_detached_stages()
	var groups: Array = _design.assembly.stages
	var index := int(state.stage_index)
	if index >= groups.size(): return "No stages remaining."
	var actions: Array = attached_stage_actions(index)
	var capsule_separates := actions.has("separate:decoupler")
	# Validate the complete group first: unsafe actions never partly fire a stage.
	if actions.any(func(action): return action.begins_with("ignite:engine")) and (state.capsule_only or capsule_separates):
		return "Stage blocked: core engine would be detached."
	var discarded: Array = state.get("removed_parts", []).duplicate()
	for action in actions:
		if action.begins_with("separate:") and action != "separate:boosters":
			discarded.append_array(Parts.Craft.descendant_ids(_design.assembly, action.get_slice(":", 1)))
	for action in actions:
		if action.begins_with("ignite:") and action.get_slice(":", 1) in discarded:
			return "Stage blocked: engine would be detached."
	if actions.has("ignite:boosters") and (not state.boosters_attached or capsule_separates or actions.has("separate:boosters")):
		return "Stage blocked: boosters would be detached."
	if actions.has("deploy:capsule") and not _design.get("parachute", true): return "Stage blocked: no parachute installed."
	if actions.has("deploy:capsule") and not state.chute_deployed:
		if bool(state.get("chute_cut", false)):
			return "Stage blocked: parachute was cut away."
		if state.status != "flying" or state.terrain_clearance > CHUTE_MAX_ALTITUDE or state.speed > CHUTE_MAX_SPEED or state.vertical_speed > 0.0:
			return "Stage held: parachute needs descent below 2.5 km and 180 m/s."
	if state.status == "ready": state.status = "flying"
	if actions.has("separate:boosters") and state.boosters_attached:
		_separate_boosters()
	if capsule_separates and not state.capsule_only:
		_separate_core()
	for action in actions:
		var id: String = action.get_slice(":", 1)
		if action.begins_with("separate:") and id not in ["boosters", "decoupler"]: _separate_engine_stage(id)
		if action.begins_with("ignite:") and id != "boosters":
			if not id in state.active_engines: state.active_engines.append(id)
			state.engine_on = true
	if actions.has("ignite:boosters"): state.boosters_on = true
	if actions.has("deploy:capsule"): state.chute_deployed = true
	state.stage_index += 1
	_refresh_telemetry()
	return "Stage %d complete." % (index + 1)


# Detached bodies use their center of mass; the controlled vehicle retains its
# contact-point position convention. Cylinder dimensions approximate assemblies.
func _active_propulsion() -> Dictionary:
	var thrust := 0.0
	var flow := 0.0
	for engine in _engines:
		if engine.id in state.get("removed_parts", []): continue
		if not state.get("active_engines", []).is_empty() and not engine.id in state.active_engines: continue
		var spec: Dictionary = Parts.ENGINES[engine.kind]
		thrust += float(spec.thrust)
		flow += float(spec.thrust) / (float(spec.isp) * Physics.STANDARD_GRAVITY)
	return {"thrust":thrust,"flow":flow}

func _separate_engine_stage(id: String) -> void:
	if id in state.released_decouplers: return
	var removed := Parts.Craft.descendant_ids(_design.assembly,id)
	var running_engines: Array[Dictionary] = []
	for engine in _engines:
		if engine.id not in removed or engine.id in state.removed_parts: continue
		if not state.engine_on or engine.id not in state.active_engines: continue
		var spec: Dictionary = Parts.ENGINES[engine.kind]
		running_engines.append({"id": engine.id, "fuel": float(state.engine_fuel.get(engine.id, state.fuel)),
			"thrust": float(spec.thrust) * float(state.throttle), "isp": float(spec.isp)})
	var dry := 0.0
	var tanks := 0
	var remaining_tanks := 0
	var bottom := float(state.get("stack_bottom",0.0))
	for part in _design.assembly.parts:
		if part.id in state.removed_parts: continue
		if part.kind == "tank": remaining_tanks += 1
		if not part.id in removed: continue
		if part.kind == "tank":
			dry += Parts.TANK_DRY_MASS
			tanks += 1
		elif part.kind in Parts.Craft.ENGINE_IDS: dry += float(Parts.ENGINES[part.kind].mass)
		elif part.kind == "reaction_wheel": dry += Parts.REACTION_WHEEL_MASS
		elif part.kind == "fins": dry += Parts.FIN_MASS
		elif part.kind == "separator":
			dry += Parts.SEPARATOR_MASS * _radial_layout.separator.filter(func(mount): return mount.id == part.id).size()
	var fuel := float(state.fuel) * tanks / maxi(remaining_tanks,1)
	if not state.get("engine_fuel", {}).is_empty():
		fuel = 0.0
		for part in _design.assembly.parts:
			if part.kind == "tank" and part.id in removed and not part.id in state.removed_parts and not _supplied_tanks.has(part.id):
				fuel += Parts.TANK_FUEL_MASS
		for engine_id in state.engine_fuel:
			if engine_id in removed and not engine_id in state.removed_parts:
				fuel += float(state.engine_fuel[engine_id])
				state.engine_fuel[engine_id] = 0.0
	var geometry := Parts.Craft.geometry(_design)
	var top: float = geometry.bases.get(id, 0.0)
	var side_mount: Dictionary = geometry.by_id.get(geometry.mount_ids.get(id, ""), {})
	var lateral := Vector3.ZERO
	if not side_mount.is_empty():
		lateral = geometry.lateral.get(id, Vector3.ZERO)
		if id == side_mount.id: top = float(geometry.bases.get(side_mount.parent, 0.0)) + float(side_mount.get("surface_offset",0.0)) + 2.15
		bottom = top
		for part in _design.assembly.parts:
			if part.id in removed and part.kind in Parts.Craft.ENGINE_IDS + ["tank"]:
				bottom = minf(bottom,geometry.bases.get(part.id, 0.0))
	if dry > 0.0:
		var center := lateral + Vector3(0,(top+bottom)*.5,0)
		var orientation: Basis = state.orientation
		var velocity: Vector3 = state.velocity + (orientation * Vector3(state.angular_velocity)).cross(orientation * (center-_stack_center()))
		var thrust := 0.0
		var flow := 0.0
		for engine in running_engines:
			engine.fuel = minf(engine.fuel, fuel)
			if engine.fuel <= 0.0: continue
			thrust += engine.thrust
			flow += engine.thrust / engine.isp
		_new_debris("stack",center,dry,fuel,thrust,thrust / flow if flow > 0.0 else 225.0,1.05,maxf(top-bottom,.2),velocity)
		state.detached.back()["engines"] = running_engines
		state.detached.back()["throttle"] = float(state.throttle)
		state.detached.back()["part_ids"] = removed.duplicate()
		if side_mount.is_empty(): state.stack_bottom = maxf(bottom,top)
	state.fuel -= fuel
	state.discarded_dry_mass += dry
	for part_id in removed:
		if not part_id in state.removed_parts: state.removed_parts.append(part_id)
		state.active_engines.erase(part_id)
	state.released_decouplers.append(id)
	state.engine_shell_jettisoned = "engine_decoupler" in state.released_decouplers
	state.engine_on = not state.active_engines.is_empty()
	_design["removed_parts"] = state.removed_parts
	_mass_cache.clear()

func _stack_top() -> float:
	# Staging marks removed parts without moving the original stack geometry.
	# Contacts and parachute torque read this several times per physics substep.
	return _stack_height


func _mass_properties() -> Dictionary:
	if state.capsule_only: return {"mass":Parts.recovery_mass(_design),"center":Vector3(0,1.3,0),"inertia":Vector3(300,170,300)}
	# HUD telemetry reads this outside step(), too. Keep geometry available to
	# every caller and invalidate on staging/reset, never merely on fuel burn.
	var layout_key := [bool(state.boosters_attached), state.removed_parts]
	if _mass_layout.is_empty() or layout_key != _mass_layout_key:
		_mass_layout = Parts.mass_layout(_design, state.boosters_attached, _radial_layout)
		_mass_layout_key = layout_key.duplicate(true)
		_mass_cache.clear()
	var key := [float(state.fuel), float(state.booster_fuel)]
	if not _mass_cache.is_empty() and key == _mass_cache_key:
		return _mass_cache
	var properties := Parts.mass_properties(_design,float(state.fuel),float(state.booster_fuel),state.boosters_attached,_radial_layout,_mass_layout)
	_mass_cache_key = key
	_mass_cache = properties
	return properties

func _stack_center() -> Vector3:
	return _mass_properties().center


func _new_debris(kind: String, center: Vector3, dry: float, fuel: float, thrust: float, isp: float, radius: float, length: float, velocity: Vector3, side: int = -1) -> void:
	var orientation: Basis = state.orientation
	var mass := dry + fuel
	var inertia := Vector3(mass * (3.0 * radius * radius + length * length) / 12.0, mass * radius * radius * 0.5, mass * (3.0 * radius * radius + length * length) / 12.0)
	_next_debris_id += 1
	state.detached.append({"id": _next_debris_id, "kind": kind, "source_index": side, "local_center": center,
		"position_remainder": state.get("position_remainder", Vector3.ZERO),
		"dry_mass": dry, "fuel": fuel, "mass": mass,
		"position": Vector3(state.position) + orientation * center, "velocity": velocity,
		"orientation": orientation, "angular_velocity": Vector3(state.angular_velocity),
		"angular_momentum": orientation * (inertia * Vector3(state.angular_velocity)),
		"radius": radius, "length": length, "thrust": thrust, "isp": isp,
		"landed": false, "settle_time": 0.0})
	var piece: Dictionary = state.detached.back()
	piece.position = _advance_position(piece, state.position, orientation * center)


func _separate_boosters() -> void:
	var center := _stack_center()
	var orientation: Basis = state.orientation
	var omega: Vector3 = orientation * Vector3(state.angular_velocity)
	var velocity: Vector3 = state.velocity
	var total_mass := _current_mass()
	var boosters: Array = _radial_layout.boosters
	var piece_mass := Parts.BOOSTER_DRY_MASS*.5 + float(state.booster_fuel)/maxi(boosters.size(),1)
	var momentum := velocity * total_mass
	for index in range(boosters.size()):
		var local_center: Vector3 = boosters[index].position
		var outward := Vector3(local_center.x,0,local_center.z).normalized()
		var inherited := velocity + omega.cross(orientation * (local_center-center))
		var release_velocity := inherited + orientation*outward*.8
		momentum -= release_velocity*piece_mass
		_new_debris("boosters",local_center,Parts.BOOSTER_DRY_MASS*.5,float(state.booster_fuel)/boosters.size(),
			Parts.BOOSTER_THRUST*.5 if state.boosters_on else 0.0,Parts.BOOSTER_ISP,.72,5.28,release_velocity,index)
	state.boosters_attached = false
	state.boosters_on = false
	state.booster_fuel = 0.0
	state.velocity = momentum / _current_mass()
	_refresh_telemetry()


func _separate_core() -> void:
	var center := _stack_center()
	var top := _stack_top()
	var orientation: Basis = state.orientation
	var omega: Vector3 = orientation * Vector3(state.angular_velocity)
	var dry := _core_dry_mass - float(state.get("discarded_dry_mass",0.0)) - Parts.recovery_mass(_design)
	var carries_boosters := bool(state.boosters_attached)
	var fuel := float(state.fuel)
	var radius := 0.95
	if carries_boosters:
		dry += float(_stats.booster_dry_mass)
		fuel += float(state.booster_fuel)
		for mount in _radial_layout.boosters:
			radius = maxf(radius, Vector2(mount.position.x, mount.position.z).length() + 0.72)
	var engines: Array[Dictionary] = []
	for engine in _engines:
		if engine.id in state.removed_parts: continue
		var spec: Dictionary = Parts.ENGINES[engine.kind]
		engines.append({"id": engine.id, "fuel": float(state.engine_fuel.get(engine.id, state.fuel)),
			"thrust": float(spec.thrust) * float(state.throttle) if state.engine_on and (state.active_engines.is_empty() or engine.id in state.active_engines) else 0.0, "isp": float(spec.isp)})
	if carries_boosters:
		engines.append({"id": "boosters", "fuel": float(state.booster_fuel),
			"thrust": float(_stats.booster_thrust) if state.boosters_on else 0.0, "isp": Parts.BOOSTER_ISP})
	var thrust := 0.0
	var flow := 0.0
	for engine in engines:
		if engine.fuel <= 0.0: continue
		thrust += engine.thrust
		flow += engine.thrust / engine.isp
	var mass := dry + fuel
	var local_center := (center*_current_mass()-Vector3(0,top+1.3,0)*Parts.recovery_mass(_design))/maxf(mass,1.0)
	# Spring impulse gives 0.8 m/s relative release speed, conserving momentum.
	var impulse := -orientation.y * (0.8 / (1.0 / maxf(mass,1.0) + 1.0 / Parts.recovery_mass(_design)))
	var inherited := Vector3(state.velocity) + omega.cross(orientation * (local_center - center))
	# The released engine retains its current throttle until its fuel runs out.
	_new_debris("core", local_center, dry, fuel, thrust,
		thrust / flow if flow > 0.0 else _stats.isp, radius, maxf(top,0.22), inherited + impulse / maxf(mass,1.0))
	# Collision geometry stays at its original location even when fuel and
	# engine mass put the released body's center of mass off-center.
	var bottom := float(state.get("stack_bottom", 0.0))
	var shapes: Array = [{"offset": Vector3(0,(top+bottom)*0.5,0)-local_center,
		"radius": 0.95, "length": maxf(top-bottom,0.22)}]
	if carries_boosters:
		for mount in _radial_layout.boosters:
			shapes.append({"offset": Vector3(mount.position)-local_center,"radius":0.72,"length":5.28})
	state.detached.back()["collision_shapes"] = shapes
	state.detached.back()["carries_boosters"] = carries_boosters
	state.detached.back()["engines"] = engines
	state.detached.back()["throttle"] = float(state.throttle)
	state.velocity += omega.cross(orientation * (Vector3(0,top + 1.3,0) - center)) - impulse / Parts.recovery_mass(_design)
	# Rebase without making the capsule teleport down to the old stack's origin.
	state.position = _advance_position(state, state.position, orientation * Vector3(0,top,0))
	state.capsule_only = true
	state.boosters_attached = false
	state.boosters_on = false
	state.booster_fuel = 0.0
	state.active_engines.clear()
	state.fuel = 0.0
	state.engine_on = false
	state.thrust = 0.0
	state.throttle = 0.0


func _debris_inertia(piece: Dictionary) -> Vector3:
	var mass := maxf(float(piece.mass),1.0)
	var r2: float = piece.radius * piece.radius
	var transverse: float = mass * (3.0 * r2 + piece.length * piece.length) / 12.0
	return Vector3(transverse, mass * r2 * 0.5, transverse)


func _debris_support(piece: Dictionary, normal: Vector3) -> Vector3:
	if piece.has("shapes"):
		var lowest := Vector3.ZERO
		var depth := INF
		for shape in piece.shapes:
			var support := Basis(piece.orientation) * Vector3(shape.offset) + _debris_support({"orientation": piece.orientation, "length": shape.length, "radius": shape.radius}, normal)
			if support.dot(normal) < depth:
				lowest = support
				depth = support.dot(normal)
		return lowest
	var axis: Vector3 = piece.orientation.y
	var dot := axis.dot(normal)
	var radial := normal - axis * dot
	var axial_support := -axis * signf(dot) * float(piece.length) * 0.5 if absf(dot) > 0.00001 else Vector3.ZERO
	# A near-level flat end rests on its centre; picking a rim point from a
	# tiny tilt flips sides each step and rocks a landed vessel indefinitely.
	var radial_support := -radial.normalized() * float(piece.radius) * clampf(radial.length() / 0.05, 0.0, 1.0) if radial.length_squared() > 0.0000000001 else Vector3.ZERO
	return axial_support + radial_support


# Use the same recursive moon orbits and terrain resources as the renderer.
func _debris_surfaces(time: float) -> Array:
	var bodies: Array = [{"terrain": terrain, "center": PLANET_CENTER, "velocity": Vector3.ZERO}]
	_append_debris_moons(bodies, terrain.definition, PLANET_CENTER, Vector3.ZERO, time)
	return bodies


func _append_debris_moons(bodies: Array, parent: Resource, center: Vector3, velocity: Vector3, time: float) -> void:
	for definition in parent.moons:
		if not _debris_terrains.has(definition):
			_debris_terrains[definition] = Surface.Terrain.new(definition)
		var offset: Vector3 = SolarBody.moon_offset(definition, time)
		var orbit_velocity: Vector3 = (SolarBody.moon_offset(definition, time + 1.0) - SolarBody.moon_offset(definition, time - 1.0)) * 0.5
		bodies.append({"terrain": _debris_terrains[definition], "center": center + offset, "velocity": velocity + orbit_velocity})
		_append_debris_moons(bodies, definition, center + offset, velocity + orbit_velocity, time)


func _debris_gravity(position: Vector3, bodies: Array) -> Vector3:
	var result := _gravity(position - PLANET_CENTER)
	for index in range(1, bodies.size()):
		var body: Dictionary = bodies[index]
		var radial: Vector3 = position - Vector3(body.center)
		var definition: Resource = body.terrain.definition
		var radius: float = definition.radius
		result -= radial.normalized() * float(definition.surface_gravity) * radius * radius / maxf(radial.length_squared(), radius * radius)
	return result


func _classify_debris(duration: float) -> void:
	_has_local_debris = false
	if state.detached.is_empty(): return
	var surfaces := _debris_surfaces(simulation_time())
	for piece in state.detached:
		# Include possible closing travel before the next classification. The
		# generous margin restores detailed contacts before a craft rendezvous.
		var travel := (Vector3(piece.velocity) - Vector3(state.velocity)).length() * duration
		var distant := Vector3(piece.position).distance_to(state.position) > DEBRIS_DETAIL_DISTANCE + travel
		var background: bool = distant and not (piece.thrust > 0.0 and piece.fuel > 0.0)
		if background and not piece.landed:
			for body in surfaces:
				var definition: Resource = body.terrain.definition
				var clearance := Vector3(piece.position).distance_to(body.center) - float(definition.radius)
				var approach := (Vector3(piece.velocity) - Vector3(body.velocity)).length() * duration
				if clearance < maxf(float(definition.atmosphere_height), float(definition.relief) * 2.0) + 2000.0 + approach:
					background = false
					break
		piece.background = background
		_has_local_debris = _has_local_debris or not background


func _integrate_detached(dt: float, background: bool = false, start_time: float = -1.0) -> void:
	if state.detached.is_empty() or (not background and not _has_local_debris and _stepping): return
	if start_time < 0.0: start_time = simulation_time()
	var next_time := start_time + dt
	var bodies := _debris_surfaces(next_time)
	var previous_bodies := _debris_surfaces(start_time)
	for piece in state.detached:
		if bool(piece.get("background", false)) != background: continue
		if piece.landed:
			piece["destroyed"] = true
			continue
		var previous: Vector3 = piece.position
		var radial: Vector3 = previous - PLANET_CENTER
		var previous_piece: Dictionary = piece.duplicate()
		var gravity := _debris_gravity(previous, previous_bodies)
		var density := _air_density_at(_radius_at(previous) - PLANET_RADIUS)
		var air_velocity: Vector3 = piece.velocity - terrain.surface_velocity(radial)
		var speed := air_velocity.length()
		var alignment := absf(Vector3(piece.orientation.y).dot(air_velocity.normalized()))
		var area: float = 0.5 * PI * piece.radius * piece.radius * alignment + 1.1 * 2.0 * piece.radius * piece.length * sqrt(maxf(0.0,1.0-alignment*alignment))
		if piece.has("engines"):
			var thrust := 0.0
			var flow := 0.0
			for engine in piece.engines:
				var wanted: float = engine.thrust * dt / (engine.isp * Physics.STANDARD_GRAVITY)
				var used := minf(engine.fuel, wanted) if not _rail_warp else 0.0
				engine.fuel -= used
				if wanted > 0.0:
					thrust += engine.thrust * used / wanted
					flow += used / dt
			piece.thrust = thrust
			if flow > 0.0: piece.isp = thrust / (flow * Physics.STANDARD_GRAVITY)
		var burn := minf(piece.fuel, piece.thrust * dt / (maxf(piece.isp,1.0) * Physics.STANDARD_GRAVITY))
		if _rail_warp: burn = 0.0
		var mass := maxf(float(piece.mass) - burn * 0.5,1.0)
		var drag := minf(speed / dt,0.5 * density * speed * speed * area / mass)
		if _rail_warp:
			drag = 0.0
			density = 0.0
			piece.angular_momentum = Vector3.ZERO
		var acceleration := gravity - air_velocity.normalized() * drag
		if burn > 0.0:
			acceleration += piece.orientation.y * burn * piece.isp * Physics.STANDARD_GRAVITY / (dt * mass)
		# Approximate aerodynamic rotational damping; no artificial damping in vacuum.
		# Escaping propellant carries its share of the body's rotational momentum.
		piece.angular_momentum *= (float(piece.mass)-burn) / maxf(float(piece.mass),1.0)
		piece.fuel -= burn
		piece.mass = piece.dry_mass + piece.fuel
		piece.angular_momentum *= exp(-density * (speed + 1.0) * area * 0.12 * dt / mass)
		var inertia := _debris_inertia(piece)
		var omega_local: Vector3 = (Basis(piece.orientation).transposed() * Vector3(piece.angular_momentum)) / inertia
		var angular_speed := omega_local.length()
		if angular_speed > 0.000001:
			piece.orientation = (Basis(piece.orientation) * Basis(omega_local/angular_speed,angular_speed*dt)).orthonormalized()
		piece.angular_velocity = (Basis(piece.orientation).transposed() * Vector3(piece.angular_momentum)) / inertia
		var half_velocity: Vector3 = piece.velocity + acceleration * (0.5 * dt)
		piece.position = _advance_position(piece, piece.position, half_velocity * dt)
		piece.velocity = half_velocity + (acceleration - gravity + _debris_gravity(piece.position, bodies)) * (0.5 * dt)
		var touched := false
		for index in range(bodies.size()):
			var body: Dictionary = bodies[index]
			var ground: RefCounted = body.terrain
			var center: Vector3 = body.center
			var old_center: Vector3 = previous_bodies[index].center
			var support := _debris_support(piece, (Vector3(piece.position) - center).normalized())
			var previous_support := _debris_support(previous_piece, (previous - old_center).normalized())
			var hit: Dictionary = ground.segment_hit(previous + previous_support - old_center, Vector3(piece.position) + support - center, start_time, next_time)
			var radial_end: Vector3 = Vector3(piece.position) + support - center
			if hit.is_empty() and radial_end.length() > float(ground.definition.radius) + float(ground.definition.relief) * 2.0 + 0.05:
				continue
			if not hit.is_empty() or ground.clearance(radial_end, next_time) <= 0.02:
				piece.surface_index = index
				_debris_contact(piece, hit, dt, next_time, body)
				touched = true
				break
		if not touched:
			piece.settle_time = 0.0
		else:
			piece.position_remainder = Vector3.ZERO

	state.detached = state.detached.filter(func(piece): return not piece.get("destroyed", false))


func _queue_surface_explosion(position: Vector3, size: float) -> void:
	state.surface_impacts.append({"position": position, "radius": clampf(size, 2.0, 12.0)})
	if state.surface_impacts.size() > 64: state.surface_impacts.pop_front()


func _debris_contact(piece: Dictionary, hit: Dictionary, dt: float, time: float, body: Dictionary) -> void:
	var ground: RefCounted = body.terrain
	var center: Vector3 = body.center
	var radial: Vector3 = piece.position - center
	var contact: Dictionary = ground.contact(radial, time)
	var normal: Vector3 = hit.normal if not hit.is_empty() else contact.normal
	var point: Vector3 = hit.position if not hit.is_empty() else radial.normalized() * float(contact.radius)
	var arm := _debris_support(piece, normal)
	piece.position += normal * maxf(0.0, (point - radial - arm).dot(normal) + 0.005)
	var basis: Basis = piece.orientation
	var inertia: Vector3 = piece.inertia if piece.get("recoverable", false) else _debris_inertia(piece)
	var omega: Vector3 = basis * ((basis.transposed() * Vector3(piece.angular_momentum)) / inertia)
	var surface_velocity: Vector3 = Vector3(body.velocity) + ground.surface_velocity(point)
	var relative: Vector3 = piece.velocity - surface_velocity
	var contact_velocity := relative + omega.cross(arm)
	var incoming := contact_velocity.dot(normal)
	# Only closing speed into the surface breaks a part. Tangential motion
	# slides/rolls, and surface rotation/orbital velocity is not impact energy.
	if -incoming > DEBRIS_BREAKUP_SPEED and not piece.get("recoverable", false):
		_queue_surface_explosion(center + point, float(piece.length))
		piece["destroyed"] = true
		return
	if incoming < 0.0:
		var cross_arm := arm.cross(normal)
		var inverse_rot: Vector3 = basis * ((basis.transposed() * cross_arm) / inertia)
		var effective_inverse_mass := 1.0 / maxf(piece.mass, 1.0) + normal.dot(inverse_rot.cross(arm))
		# The recoverable vessel lands; only loose debris bounces.
		var restitution := 0.0 if piece.get("recoverable", false) else (DEBRIS_RESTITUTION if incoming < -1.0 else 0.0)
		var impulse_size := -(1.0 + restitution) * incoming / effective_inverse_mass
		var tangent := contact_velocity - normal * incoming
		var tangent_dir := tangent.normalized()
		var tangent_arm := arm.cross(tangent_dir)
		var tangent_inverse: Vector3 = basis * ((basis.transposed() * tangent_arm) / inertia)
		var tangent_mass := 1.0 / maxf(piece.mass, 1.0) + tangent_dir.dot(tangent_inverse.cross(arm))
		var friction := minf(0.6 * impulse_size, tangent.length() / maxf(tangent_mass, 0.000001))
		var impulse := normal * impulse_size - tangent_dir * friction
		piece.velocity += impulse / maxf(piece.mass, 1.0)
		piece.angular_momentum += arm.cross(impulse)
	# Finite contact patches resist rolling and residual twisting on recovery.
	if piece.get("recoverable", false) or (Vector3(piece.velocity) - surface_velocity).length() < 0.4:
		piece.angular_momentum *= exp(-2.0 * dt)
	piece.angular_velocity = (basis.transposed() * Vector3(piece.angular_momentum)) / inertia
	if (Vector3(piece.velocity) - surface_velocity).length() < 0.4 and Vector3(piece.angular_velocity).length() < 0.35 and (piece.fuel <= 0.0 or piece.thrust <= 0.0):
		piece.settle_time += dt
	elif piece.get("recoverable", false) and (Vector3(piece.velocity) - surface_velocity).length() < 0.8 and Vector3(piece.angular_velocity).length() < 0.7:
		# A single contact-edge wobble must not erase all quiet time.
		piece.settle_time = maxf(0.0, float(piece.settle_time) - dt)
	else:
		piece.settle_time = 0.0
	# Quiet debris retires without an explosion; airborne/bouncing parts stay live.
	if piece.settle_time >= DEBRIS_SETTLE_SECONDS and not piece.get("recoverable", false):
		piece.landed = true
		piece["destroyed"] = true


func _collision_bodies() -> Array:
	var bodies: Array = []
	for piece in state.detached:
		if piece.get("background", false): continue
		piece.inertia = _debris_inertia(piece)
		piece.shapes = piece.get("collision_shapes", [{"offset":Vector3.ZERO,"radius":piece.radius,"length":piece.length}])
		piece.bound = 0.0
		piece.min_radius = piece.radius
		for shape in piece.shapes:
			piece.bound = maxf(piece.bound,Vector3(shape.offset).length()+maxf(float(shape.length)*.5,float(shape.radius)))
			piece.min_radius = minf(piece.min_radius,shape.radius)
		bodies.append(piece)
	if state.get("destroyed", false): return bodies
	var center := Vector3(0,1.3,0) if state.capsule_only else _stack_center()
	var top := 0.0 if state.capsule_only else _stack_top()
	var shapes: Array = [{"offset":Vector3(0,top+1.35,0)-center,"radius":.94,"length":2.3}]
	if not state.capsule_only:
		var bottom := float(state.get("stack_bottom",0.0))
		shapes.append({"offset":Vector3(0,(top+bottom)*.5,0)-center,"radius":.95,"length":maxf(top-bottom,.22)})
		if state.boosters_attached:
			for booster in _radial_layout.boosters:
				shapes.append({"offset":Vector3(booster.position)-center,"radius":.72,"length":5.28})
	var body := {"position":Vector3(state.position)+Basis(state.orientation)*center,
		"orientation":state.orientation,"velocity":state.velocity,"mass":maxf(_current_mass(),1.0),
		"radius":.94,"length":top+2.6,"shapes":shapes,"local_center":center,
		"landed":false,"settle_time":0.0,"bound":0.0,"min_radius":.94}
	body.inertia = _mass_properties().inertia
	body.angular_momentum = Basis(state.orientation)*(Vector3(body.inertia)*Vector3(state.angular_velocity))
	for shape in shapes:
		body.bound = maxf(body.bound,Vector3(shape.offset).length()+maxf(float(shape.length)*.5,float(shape.radius)))
		body.min_radius = minf(body.min_radius,shape.radius)
	bodies.append(body)
	return bodies


func _resolve_body_collisions() -> void:
	if state.get("destroyed", false): return
	if state.detached.is_empty() or (_stepping and not _has_local_debris): return
	var bodies := _collision_bodies()
	var initial_craft_center: Vector3 = bodies.back().position
	# A few contact iterations handle simultaneous contacts in a compact pile.
	for iteration in range(4):
		for i in range(bodies.size()):
			for j in range(i+1,bodies.size()):
				BodyCollisions.resolve(bodies[i],bodies[j])
	for piece in state.detached:
		if piece.get("background", false): continue
		piece.angular_velocity = (Basis(piece.orientation).transposed()*Vector3(piece.angular_momentum))/Vector3(piece.inertia)
	var craft: Dictionary = bodies.back()
	# Apply only the correction: avoid losing sub-millimetre launch motion by
	# repeatedly converting the contact-point position to/from a float32 COM.
	state.position += Vector3(craft.position)-initial_craft_center
	state.velocity = craft.velocity
	state.angular_velocity = (Basis(state.orientation).transposed()*Vector3(craft.angular_momentum))/Vector3(craft.inertia)
