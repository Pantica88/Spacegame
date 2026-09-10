extends RefCounted
## Deterministic spherical-planet flight simulation, independent of the scene tree.
## Position denotes the vehicle's contact point. The launch pad is world origin.

const Surface = preload("res://scripts/planet_surface.gd")
var terrain: RefCounted = Surface.home()
const Parts = preload("res://scripts/parts.gd")
const Physics = preload("res://scripts/physics_math.gd")
const PLANET_RADIUS: float = Physics.PLANET_RADIUS
const PLANET_CENTER: Vector3 = Physics.PLANET_CENTER
const SURFACE_GRAVITY: float = Physics.SURFACE_GRAVITY
const MU: float = Physics.MU
const ATMOSPHERE_HEIGHT: float = Physics.ATMOSPHERE_HEIGHT
const MAX_STEP: float = 1.0 / 60.0
const SAFE_LANDING_SPEED: float = 8.0
const CHUTE_MAX_ALTITUDE: float = 2500.0
const CHUTE_MAX_SPEED: float = 180.0

var state: Dictionary = {}
var _design: Dictionary = {}
var _stats: Dictionary = {}
var _core_dry_mass: float = 0.0
var _chute_opening: float = 0.0
var _has_lifted: bool = false


func _init() -> void:
	reset(Parts.default_design())


func reset(design: Dictionary) -> void:
	_design = Parts.normalize_design(design)
	_stats = Parts.stats(_design)
	_core_dry_mass = float(_stats["core_dry_mass"])
	_chute_opening = 0.0
	_has_lifted = false
	state = {
		"position": Vector3.ZERO, "velocity": Vector3.ZERO, "orientation": Basis.IDENTITY,
		"angular_velocity": Vector3.ZERO, "status": "ready", "engine_on": false, "boosters_on": false, "stage_index": 0, "detached": [],
		"fuel": float(_stats["core_fuel_mass"]), "max_fuel": float(_stats["core_fuel_mass"]),
		"booster_fuel": float(_stats["booster_fuel_mass"]),
		"max_booster_fuel": float(_stats["booster_fuel_mass"]),
		"boosters_attached": bool(_design["boosters"]), "capsule_only": false,
		"chute_deployed": false, "throttle": 1.0, "time": 0.0,
		"altitude": 0.0, "max_altitude": 0.0, "max_speed": 0.0,
		"mass": float(_stats["wet_mass"]), "vertical_speed": 0.0, "horizontal_speed": 0.0,
		"apoapsis": 0.0, "periapsis": -PLANET_RADIUS, "orbit_achieved": false,
		"in_stable_orbit": false, "speed": 0.0, "thrust": 0.0,
		"acceleration": 0.0, "acceleration_vector": Vector3.ZERO,
		"air_density": 1.225, "dynamic_pressure": 0.0, "drag_acceleration": 0.0,
		"gravity": SURFACE_GRAVITY, "fuel_fraction": 1.0,
		"booster_fraction": 1.0 if bool(_design["boosters"]) else 0.0,
		"mach": 0.0, "chute_safe": false, "flight_path_angle": 90.0,
		"impact_speed": 0.0, "max_g": 0.0, "sas": true
	}
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
	if not is_finite(dt) or dt <= 0.0 or str(state["status"]) != "flying":
		return
	state["throttle"] = _finite_input(input, "throttle", float(state["throttle"]), 0.0, 1.0)
	state["sas"] = bool(input.get("sas", true))
	var control: Vector3 = Vector3(
		_finite_input(input, "pitch", 0.0, -1.0, 1.0),
		_finite_input(input, "roll", 0.0, -1.0, 1.0),
		-_finite_input(input, "yaw", 0.0, -1.0, 1.0)
	)
	# Substeps also support time acceleration without tunnelling through the surface.
	var remaining: float = minf(dt, 10.0)
	while remaining > 0.0000001 and str(state["status"]) == "flying":
		var substep: float = minf(remaining, MAX_STEP)
		_integrate(substep, control)
		remaining -= substep
	_refresh_telemetry()


func stage() -> String:
	if _design.has("assembly"):
		return execute_stage()
	if str(state["status"]) != "flying":
		return "Launch before separating a stage."
	if bool(state["boosters_attached"]):
		state["stage_index"] += 1
		state["boosters_on"] = false
		state["engine_on"] = true
		state["boosters_attached"] = false
		state["booster_fuel"] = 0.0
		_refresh_telemetry()
		return "Side boosters separated. Core engine ignited." if _design.booster_first else "Side boosters separated."
	if not bool(state["capsule_only"]):
		state["stage_index"] += 1
		state["capsule_only"] = true
		state["fuel"] = 0.0
		state["engine_on"] = false
		state["thrust"] = 0.0
		state["throttle"] = 0.0
		_refresh_telemetry()
		return "Capsule separated. Deploy below 2.5 km and 180 m/s while descending."
	return "No stages remaining."


func deploy_chute() -> String:
	_refresh_telemetry()
	if bool(state["chute_deployed"]):
		return "Parachute is already deployed."
	if str(state["status"]) != "flying":
		return "Parachute can only deploy in flight."
	if not bool(state["capsule_only"]):
		return "Separate the capsule before deploying its parachute."
	if float(state["terrain_clearance"]) > CHUTE_MAX_ALTITUDE:
		return "Too high. Deploy below 2.5 km."
	if float(state["speed"]) > CHUTE_MAX_SPEED:
		return "Too fast. Slow below 180 m/s before deployment."
	if float(state["vertical_speed"]) > 0.0:
		return "Still climbing. Deploy the parachute while descending."
	state["chute_deployed"] = true
	return "Parachute deployed."


func telemetry() -> Dictionary:
	_refresh_telemetry()
	return state.duplicate(true)


static func air_density_at(altitude: float) -> float:
	return _air_density_profile(altitude, 1.225, ATMOSPHERE_HEIGHT)


static func _air_density_profile(altitude: float, sea_level_density: float, atmosphere_height: float) -> float:
	if atmosphere_height <= 0.0 or sea_level_density <= 0.0 or altitude >= atmosphere_height:
		return 0.0
	var height: float = maxf(altitude, 0.0)
	# A smooth top avoids an abrupt drag discontinuity at the edge of space.
	var taper_start := atmosphere_height * 0.78
	var scale_height := maxf(1.0, atmosphere_height * 0.217)
	var taper: float = 1.0 - smoothstep(taper_start, atmosphere_height, height)
	return sea_level_density * exp(-height / scale_height) * taper


func _air_density_at(altitude: float) -> float:
	return _air_density_profile(altitude, float(terrain.definition.atmosphere_density), float(terrain.definition.atmosphere_height))


func _surface_gravity() -> float:
	return float(terrain.definition.surface_gravity)


func _mu() -> float:
	return _surface_gravity() * PLANET_RADIUS * PLANET_RADIUS


func _gravity(radial: Vector3) -> Vector3:
	var radius := maxf(radial.length(), 1.0)
	return -radial * (_mu() / (radius * radius * radius))


func _atmosphere_height() -> float:
	return float(terrain.definition.atmosphere_height)


func _integrate(dt: float, control: Vector3) -> void:
	_integrate_detached(dt)
	state["time"] = float(state["time"]) + dt
	var angular_velocity: Vector3 = state["angular_velocity"]
	var damping: float = 5.0 if bool(state["sas"]) else 0.65
	if bool(_design["fins"]) and not bool(state["capsule_only"]):
		var current_altitude: float = _radius_at(Vector3(state["position"])) - PLANET_RADIUS
		damping += 1.8 * _air_density_at(current_altitude) / 1.225
	var authority: float = 2.0 if bool(state["capsule_only"]) else 1.5
	angular_velocity += control * authority * dt
	angular_velocity *= exp(-damping * dt)
	angular_velocity = angular_velocity.limit_length(1.0)
	var orientation: Basis = state["orientation"]
	var angular_speed: float = angular_velocity.length()
	if angular_speed > 0.000001:
		orientation = (orientation * Basis(angular_velocity / angular_speed, angular_speed * dt)).orthonormalized()
	state["orientation"] = orientation
	state["angular_velocity"] = angular_velocity

	var position: Vector3 = state["position"]
	var velocity: Vector3 = state["velocity"]
	var radial_position: Vector3 = position - PLANET_CENTER
	var radius: float = maxf(_radius_at(position), 1.0)
	var up: Vector3 = radial_position / radius
	var altitude: float = maxf(radius - PLANET_RADIUS, 0.0)
	if _clearance(position,float(state.time)-dt) > 0.1:
		_has_lifted = true
	var density: float = _air_density_at(altitude)
	var gravity: Vector3 = -up * _mu() / (radius * radius)
	var thrust: float = 0.0
	var mass_before_burn: float = _current_mass()
	if bool(state["engine_on"]) and not bool(state["capsule_only"]):
		var desired_thrust: float = float(_stats["engine_thrust"]) * float(state["throttle"])
		var desired_fuel: float = desired_thrust * dt / (float(_stats["isp"]) * Physics.STANDARD_GRAVITY)
		var burned_fuel: float = minf(float(state["fuel"]), desired_fuel)
		if desired_fuel > 0.0:
			thrust += desired_thrust * burned_fuel / desired_fuel
		state["fuel"] = maxf(float(state["fuel"]) - burned_fuel, 0.0)
	# Solid boosters burn continuously after ignition, independently of throttle.
	if bool(state["boosters_on"]) and bool(state["boosters_attached"]) and float(state["booster_fuel"]) > 0.0:
		var wanted: float = Parts.BOOSTER_THRUST * dt / (Parts.BOOSTER_ISP * Physics.STANDARD_GRAVITY)
		var burned: float = minf(float(state["booster_fuel"]), wanted)
		thrust += Parts.BOOSTER_THRUST * burned / wanted
		state["booster_fuel"] = maxf(float(state["booster_fuel"]) - burned, 0.0)
	var mass: float = (mass_before_burn + _current_mass()) * 0.5
	var air_velocity: Vector3 = velocity-terrain.surface_velocity(radial_position)
	var speed: float = air_velocity.length()
	var drag_area: float = 0.40 if bool(state["capsule_only"]) else 0.52
	if bool(state["boosters_attached"]):
		drag_area += 0.22
	if not bool(state["capsule_only"]):
		# Sideways flight exposes the length of the rocket to the airstream.
		var alignment: float = absf(orientation.y.dot(air_velocity / speed)) if speed > 0.01 else 1.0
		drag_area += (1.0 - alignment) * float(_stats["height"]) * 0.75
	if bool(state["chute_deployed"]):
		_chute_opening = minf(_chute_opening + dt / 2.5, 1.0)
		drag_area += 203.0 * _chute_opening
	var drag_acceleration: float = 0.5 * density * speed * speed * drag_area / mass
	# Drag cannot reverse velocity within a substep, including during chute inflation.
	drag_acceleration = minf(drag_acceleration, speed / dt)
	var drag: Vector3 = -air_velocity.normalized() * drag_acceleration
	var acceleration: Vector3 = gravity + orientation.y * thrust / mass + drag
	var previous_position: Vector3 = position
	var previous_velocity: Vector3 = velocity
	# Symmetric gravity integration; thrust and aerodynamic forces are held
	# constant over this small substep. In vacuum this is velocity Verlet.
	var half_velocity := velocity + acceleration * (0.5 * dt)
	position += half_velocity * dt
	var next_gravity := _gravity(position - PLANET_CENTER)
	velocity = half_velocity + (acceleration - gravity + next_gravity) * (0.5 * dt)
	var next_radial: Vector3 = position - PLANET_CENTER
	var next_altitude: float = _radius_at(position) - PLANET_RADIUS
	var next_clearance := _clearance(position,float(state.time))
	if next_clearance > 1.0: _has_lifted = true
	var hit: Dictionary = terrain.segment_hit(previous_position-PLANET_CENTER,next_radial,float(state.time)-dt,float(state.time))
	if next_clearance <= 0.0 or not hit.is_empty():
		var contact: Dictionary = terrain.contact(next_radial,float(state.time))
		var contact_radial: Vector3 = next_radial.normalized()*float(contact.radius)
		var normal: Vector3 = contact.normal
		var contact_fraction := 1.0
		if not hit.is_empty():
			contact_radial = hit.position
			normal = hit.normal
			contact_fraction = hit.fraction
		if not _has_lifted and float(state["max_altitude"]) < 1.0:
			position = PLANET_CENTER+contact_radial
			velocity = terrain.surface_velocity(contact_radial)
		else:
			var impact_velocity: Vector3 = previous_velocity.lerp(velocity,contact_fraction)-terrain.surface_velocity(contact_radial)
			var impact_speed := impact_velocity.length()
			state["impact_speed"] = impact_speed
			var upright: bool = (bool(state["capsule_only"]) or orientation.y.dot(normal) > 0.8) and normal.dot(contact_radial.normalized()) > 0.70
			state["status"] = "landed" if impact_speed <= SAFE_LANDING_SPEED and upright else "crashed"
			if state["status"] == "landed":
				state["orientation"] = Basis(Quaternion(orientation.y,normal))*orientation
			state["landing_normal"] = normal
			state["landing_body_position"] = terrain.rotation_at(float(state.time)).transposed()*contact_radial
			state["engine_on"] = false
			state["boosters_on"] = false
			state["thrust"] = 0.0
			state["max_speed"] = maxf(float(state["max_speed"]),impact_speed)
			position = PLANET_CENTER+contact_radial
			velocity = terrain.surface_velocity(contact_radial)
	state["position"] = position
	state["velocity"] = velocity
	state["thrust"] = thrust if str(state["status"]) == "flying" else 0.0
	state["acceleration"] = acceleration.length()
	state["acceleration_vector"] = acceleration
	state["drag_acceleration"] = drag_acceleration
	state["max_g"] = maxf(float(state["max_g"]), (orientation.y * thrust / mass + drag).length() / Physics.STANDARD_GRAVITY)
	# Keep peaks correct even during an accelerated frame containing the whole apex.
	state["max_altitude"] = maxf(float(state["max_altitude"]), maxf(next_altitude, 0.0))
	state["max_speed"] = maxf(float(state["max_speed"]), velocity.length())


func _current_mass() -> float:
	if bool(state["capsule_only"]):
		return Parts.CAPSULE_MASS
	var mass: float = _core_dry_mass + float(state["fuel"])
	if bool(state["boosters_attached"]):
		mass += Parts.BOOSTER_DRY_MASS + float(state["booster_fuel"])
	return mass


func _refresh_telemetry() -> void:
	var position: Vector3 = state["position"]
	var velocity: Vector3 = state["velocity"]
	var radial: Vector3 = position - PLANET_CENTER
	var radius: float = maxf(_radius_at(position), 1.0)
	var up: Vector3 = radial / radius
	var altitude: float = maxf(radius - PLANET_RADIUS, 0.0)
	var surface_velocity: Vector3 = velocity-terrain.surface_velocity(radial)
	var speed: float = surface_velocity.length()
	var vertical_speed: float = surface_velocity.dot(up)
	var horizontal_speed: float = (surface_velocity - up * vertical_speed).length()
	var elements := Physics.orbital_elements(radial, velocity, _mu(), PLANET_RADIUS)
	state.merge(elements, true)
	var periapsis: float = elements.periapsis
	var apoapsis: float = elements.apoapsis
	state["altitude"] = altitude
	state["terrain_clearance"] = maxf(0.0,_radius_at(position)-float(terrain.contact(radial,float(state.time)).radius))
	state["speed"] = speed
	state["vertical_speed"] = vertical_speed
	state["horizontal_speed"] = horizontal_speed
	state["mass"] = _current_mass()
	state["apoapsis"] = maxf(apoapsis, altitude)
	state["periapsis"] = periapsis
	state["in_stable_orbit"] = periapsis >= _atmosphere_height() and is_finite(apoapsis)
	state["orbit_achieved"] = bool(state["orbit_achieved"]) or bool(state["in_stable_orbit"])
	state["max_altitude"] = maxf(float(state["max_altitude"]), altitude)
	state["max_speed"] = maxf(float(state["max_speed"]), speed)
	state["fuel_fraction"] = float(state["fuel"]) / maxf(float(state["max_fuel"]), 1.0)
	state["booster_fraction"] = float(state["booster_fuel"]) / maxf(float(state["max_booster_fuel"]), 1.0)
	state["air_density"] = _air_density_at(altitude)
	state["dynamic_pressure"] = 0.5 * float(state["air_density"]) * speed * speed
	state["gravity"] = _mu() / (radius * radius)
	state["mach"] = speed / 340.0
	state["chute_safe"] = str(state["status"]) == "flying" and bool(state["capsule_only"]) and not bool(state["chute_deployed"]) and float(state["terrain_clearance"]) <= CHUTE_MAX_ALTITUDE and speed <= CHUTE_MAX_SPEED and vertical_speed <= 0.0
	state["flight_path_angle"] = rad_to_deg(atan2(vertical_speed, horizontal_speed)) if speed > 0.01 else 90.0


static func _finite_input(input: Dictionary, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value: float = float(input.get(key, fallback))
	return clampf(value, minimum, maximum) if is_finite(value) else fallback


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


func execute_stage() -> String:
	if not state.status in ["ready", "flying"]:
		return "Staging unavailable after flight ends."
	var groups: Array = _design.assembly.stages
	var index := int(state.stage_index)
	if index >= groups.size(): return "No stages remaining."
	var actions: Array = groups[index]
	var capsule_separates := actions.has("separate:decoupler")
	# Validate the complete group first: unsafe actions never partly fire a stage.
	if actions.has("ignite:engine") and (state.capsule_only or capsule_separates):
		return "Stage blocked: core engine would be detached."
	if actions.has("ignite:boosters") and (not state.boosters_attached or capsule_separates or actions.has("separate:boosters")):
		return "Stage blocked: boosters would be detached."
	if actions.has("deploy:capsule") and not state.chute_deployed:
		if not state.capsule_only and not capsule_separates:
			return "Stage blocked: separate the capsule first."
		if state.status != "flying" or state.terrain_clearance > CHUTE_MAX_ALTITUDE or state.speed > CHUTE_MAX_SPEED or state.vertical_speed > 0.0:
			return "Stage held: parachute needs descent below 2.5 km and 180 m/s."
	if state.status == "ready": state.status = "flying"
	if (actions.has("separate:boosters") or capsule_separates) and state.boosters_attached:
		_detach("boosters", Parts.BOOSTER_DRY_MASS, state.booster_fuel, Parts.BOOSTER_THRUST if state.boosters_on else 0.0, Parts.BOOSTER_ISP)
	if capsule_separates and not state.capsule_only:
		_detach("core", _core_dry_mass - Parts.CAPSULE_MASS, state.fuel, _stats.engine_thrust * state.throttle if state.engine_on else 0.0, _stats.isp)
	if actions.has("separate:boosters") or capsule_separates:
		state.boosters_attached = false
		state.boosters_on = false
		state.booster_fuel = 0.0
	if capsule_separates:
		state.capsule_only = true
		state.fuel = 0.0
		state.engine_on = false
		state.thrust = 0.0
		state.throttle = 0.0
	if actions.has("ignite:engine"): state.engine_on = true
	if actions.has("ignite:boosters"): state.boosters_on = true
	if actions.has("deploy:capsule"): state.chute_deployed = true
	state.stage_index += 1
	_refresh_telemetry()
	return "Stage %d complete." % (index + 1)


func _detach(kind: String, dry_mass: float, fuel: float, thrust: float, isp: float) -> void:
	state.detached.append({"kind": kind, "dry_mass": dry_mass, "fuel": fuel,
		"mass": dry_mass + fuel, "position": state.position,
		"velocity": state.velocity + state.orientation.x * (2.0 if kind == "boosters" else -1.0),
		"orientation": state.orientation, "thrust": thrust, "isp": isp, "landed": false})

func _integrate_detached(dt: float) -> void:
	for piece in state.detached:
		if piece.landed:
			if piece.has("body_position"):
				piece.position = PLANET_CENTER+terrain.rotation_at(float(state.time)+dt)*Vector3(piece.body_position)
			continue
		var radial: Vector3 = piece.position - PLANET_CENTER
		var radius := maxf(radial.length(), PLANET_RADIUS)
		var gravity := _gravity(radial)
		var acceleration := gravity
		var burn := minf(piece.fuel, piece.thrust * dt / (piece.isp * Physics.STANDARD_GRAVITY))
		if burn > 0.0:
			acceleration += piece.orientation.y * burn * piece.isp * Physics.STANDARD_GRAVITY / (dt * piece.mass)
		piece.fuel -= burn
		piece.mass = piece.dry_mass + piece.fuel
		var speed: float = piece.velocity.length()
		var drag := minf(speed / dt, 0.5 * _air_density_at(radius - PLANET_RADIUS) * speed * speed * 0.6 / maxf(piece.mass, 1.0))
		acceleration -= piece.velocity.normalized() * drag
		var half_velocity: Vector3 = piece.velocity + acceleration * (0.5 * dt)
		var previous: Vector3 = piece.position
		piece.position += half_velocity * dt
		piece.velocity = half_velocity + (acceleration - gravity + _gravity(piece.position - PLANET_CENTER)) * (0.5 * dt)
		var hit: Dictionary = terrain.segment_hit(previous-PLANET_CENTER,piece.position-PLANET_CENTER,float(state.time),float(state.time)+dt)
		if not hit.is_empty() or _clearance(piece.position,float(state.time)+dt) <= 0.0:
			var radial_end: Vector3 = piece.position-PLANET_CENTER
			var contact: Dictionary = terrain.contact(radial_end,float(state.time)+dt)
			var point: Vector3 = hit.position if not hit.is_empty() else radial_end.normalized()*float(contact.radius)
			piece.position = PLANET_CENTER+point
			piece.body_position = terrain.rotation_at(float(state.time)+dt).transposed()*point
			piece.velocity = terrain.surface_velocity(point)
			piece.landed = true
