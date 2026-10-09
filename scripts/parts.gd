extends RefCounted
## The original, fictional parts used by the flight prototype. SI units throughout.

const Craft = preload("res://scripts/craft_model.gd")

const Physics = preload("res://scripts/physics_math.gd")
const STANDARD_GRAVITY: float = Physics.STANDARD_GRAVITY
const CAPSULE_MASS: float = 380.0
const PARACHUTE_MASS: float = 18.0
const TANK_DRY_MASS: float = 70.0
const TANK_FUEL_MASS: float = 720.0
const REACTION_WHEEL_MASS := 50.0
const REACTION_WHEEL_TORQUE := 12000.0 # N m on each local axis per installed ring.
const REACTION_WHEEL_COST := 650
const FIN_MASS: float = 45.0
const SEPARATOR_MASS: float = 12.0
const BOOSTER_DRY_MASS: float = 180.0
const BOOSTER_FUEL_MASS: float = 640.0
const BOOSTER_THRUST: float = 44000.0
const BOOSTER_ISP: float = 190.0

const ENGINES: Dictionary = {
	"sparrow": {
		"name": "Sparrow", "thrust": 42000.0, "isp": 225.0,
		"mass": 180.0, "cost": 1400, "description": "Light, dependable starter engine."
	},
	"kestrel": {
		"name": "Kestrel", "thrust": 64000.0, "isp": 255.0,
		"mass": 260.0, "cost": 2600, "description": "Efficient propulsion for orbital missions."
	},
	"titan": {
		"name": "Titan", "thrust": 98000.0, "isp": 210.0,
		"mass": 410.0, "cost": 3400, "description": "Heavy engine with plenty of lifting power."
	}
}


static func default_design() -> Dictionary:
	return {"name": "Pioneer 01", "tanks": 2, "engine": "sparrow", "boosters": false, "fins": true, "booster_first": false}


static func normalize_design(design: Dictionary) -> Dictionary:
	var normalized: Dictionary = default_design()
	normalized["name"] = str(design.get("name", normalized["name"])).strip_edges().left(40)
	if str(normalized["name"]).is_empty():
		normalized["name"] = "Pioneer 01"
	normalized["tanks"] = clampi(int(design.get("tanks", 2)), 1, Craft.MAX_TANKS)
	var engine_id: String = str(design.get("engine", "sparrow"))
	normalized["engine"] = engine_id if ENGINES.has(engine_id) else "sparrow"
	normalized["boosters"] = bool(design.get("boosters", false))
	normalized["fins"] = bool(design.get("fins", true))
	normalized["booster_first"] = bool(design.get("booster_first", false)) and normalized["boosters"]
	if Craft.valid(design.get("assembly")):
		return Craft.project(Craft.load_craft(design), normalized)
	return normalized


static func stats(design: Dictionary) -> Dictionary:
	var clean: Dictionary = normalize_design(design)
	var engine: Dictionary = ENGINES.get(str(clean["engine"]), {"mass": 0.0, "thrust": 0.0, "isp": 225.0, "cost": 0, "name": "No engine"})
	var installed_engines := Craft.engines(clean)
	var engine_mass := 0.0
	var engine_cost := 0
	var total_thrust := 0.0
	var total_flow := 0.0
	for installed in installed_engines:
		var spec: Dictionary = ENGINES[installed.kind]
		engine_mass += float(spec.mass)
		engine_cost += int(spec.cost)
		total_thrust += float(spec.thrust)
		total_flow += float(spec.thrust) / float(spec.isp)
	var tank_count: int = int(clean["tanks"])
	var has_boosters: bool = bool(clean["boosters"])
	var booster_count := Craft.radial_instances(clean,"boosters").size()
	var separator_count := Craft.radial_instances(clean,"separator").size() if clean.has("assembly") else 0
	var booster_dry := BOOSTER_DRY_MASS * booster_count * .5
	var booster_fuel := BOOSTER_FUEL_MASS * booster_count * .5
	var booster_thrust := BOOSTER_THRUST * booster_count * .5
	var wheel_count := reaction_wheels(clean).size()
	var core_dry: float = REACTION_WHEEL_MASS * wheel_count + recovery_mass(clean) + TANK_DRY_MASS * tank_count + engine_mass
	if bool(clean["fins"]):
		core_dry += FIN_MASS
	if bool(clean.get("separator", false)):
		core_dry += SEPARATOR_MASS * separator_count
	var core_fuel: float = TANK_FUEL_MASS * tank_count
	var dry_mass: float = core_dry + (booster_dry if has_boosters else 0.0)
	var fuel_mass: float = core_fuel + (booster_fuel if has_boosters else 0.0)
	var wet_mass: float = dry_mass + fuel_mass
	var engine_thrust: float = total_thrust
	var thrust: float = engine_thrust + (booster_thrust if has_boosters else 0.0)
	var engine_isp: float = total_thrust / total_flow if total_flow > 0.0 else float(engine["isp"])
	var delta_v: float = (engine_isp * STANDARD_GRAVITY * log((core_dry + core_fuel) / core_dry) if engine_thrust > 0.0 else 0.0)
	if has_boosters:
		# Integrate each constant-Isp phase separately. Either propellant supply
		# can empty first; mixed Isp only applies while both engines are burning.
		var core_flow := engine_thrust / (engine_isp * STANDARD_GRAVITY)
		var booster_flow := booster_thrust / (BOOSTER_ISP * STANDARD_GRAVITY)
		var booster_time := booster_fuel / booster_flow
		var core_time := core_fuel / core_flow if core_flow > 0.0 else INF
		var mixed_time := minf(core_time, booster_time)
		var core_burn := core_flow * mixed_time
		var booster_burn := booster_flow * mixed_time
		var burnout_mass := wet_mass - core_burn - booster_burn
		var exhaust_velocity := thrust / (core_flow + booster_flow)
		delta_v = exhaust_velocity * log(wet_mass / burnout_mass)
		if core_time < booster_time:
			# Empty core remains attached while the solids finish burning.
			delta_v += BOOSTER_ISP * STANDARD_GRAVITY * log(burnout_mass / (core_dry + booster_dry))
		elif engine_thrust > 0.0:
			# Estimate assumes immediate separation of depleted boosters.
			delta_v += engine_isp * STANDARD_GRAVITY * log((core_dry + core_fuel - core_burn) / core_dry)
	if has_boosters and bool(clean["booster_first"]):
		delta_v = BOOSTER_ISP * STANDARD_GRAVITY * log(wet_mass / (wet_mass - booster_fuel))
		delta_v += (engine_isp * STANDARD_GRAVITY * log((core_dry + core_fuel) / core_dry) if engine_thrust > 0.0 else 0.0)
		thrust = booster_thrust
	if clean.has("assembly") and not clean.assembly.stages.is_empty():
		var first: Array = clean.assembly.stages[0]
		thrust = booster_thrust if first.has("ignite:boosters") else 0.0
		for installed in installed_engines:
			if first.has("ignite:" + str(installed.id)): thrust += float(ENGINES[installed.kind].thrust)
	elif clean.has("assembly"):
		thrust = 0.0
	var cost: int = (1450 if clean.get("parachute", false) else 1200) + tank_count * 550 + engine_cost
	cost += REACTION_WHEEL_COST * wheel_count
	cost += 350 if bool(clean["fins"]) else 0
	cost += 800 * booster_count
	cost += 125 * separator_count
	return {
		"reaction_wheel_count": wheel_count, "reaction_wheel_torque": wheel_count * REACTION_WHEEL_TORQUE,
		"dry_mass": dry_mass, "fuel_mass": fuel_mass, "wet_mass": wet_mass,
		"thrust": thrust, "isp": engine_isp, "twr": thrust / (wet_mass * Physics.SURFACE_GRAVITY),
		"delta_v": delta_v, "height": Craft.stack_top(clean) + 2.2, "cost": cost,
		"core_dry_mass": core_dry, "core_fuel_mass": core_fuel,
		"engine_thrust": engine_thrust, "booster_fuel_mass": booster_fuel if has_boosters else 0.0,
		"engine_name": str(engine["name"]) if installed_engines.size() <= 1 else "%d engines" % installed_engines.size(), "tank_count": tank_count,
		"booster_count":booster_count,"separator_count":separator_count,"booster_dry_mass":booster_dry,"booster_thrust":booster_thrust
	}


static func stage_plan(design: Dictionary) -> Array[String]:
	var clean := normalize_design(design)
	if clean.has("assembly"):
		var labels: Array[String] = []
		for group in clean.assembly.stages:
			var actions := PackedStringArray()
			for action in group: actions.append(Craft.action_label(action, clean.assembly))
			labels.append(" + ".join(actions) if not actions.is_empty() else "Empty stage")
		return labels
	var stages: Array[String] = []
	if clean.boosters:
		stages.append("Ignite boosters" if clean.booster_first else "Ignite core + boosters")
		stages.append("Jettison boosters + ignite core" if clean.booster_first else "Jettison boosters")
	else:
		stages.append("Ignite core engine")
	stages.append("Separate recovery capsule")
	return stages


static func mass_layout(design: Dictionary, boosters_attached: bool, radial_layout: Dictionary = {}) -> Array:
	# Geometry stays fixed during a burn. Last two columns are fuel mass weights.
	var components: Array = []
	var tanks := int(design.get("tanks",0))
	var base := 2.0 if not str(design.get("engine","")).is_empty() else 0.0
	var geometry := Craft.geometry(design)
	var top := Craft.stack_top(design)
	components.append([recovery_mass(design),Vector3(0,top+1.3,0),.94,2.6])
	var removed: Array = design.get("removed_parts", [])
	for wheel in reaction_wheels(design):
		components.append([REACTION_WHEEL_MASS,Vector3(0,float(geometry.bases[wheel.id])+.1,0),.948,.2])
	for installed in Craft.engines(design):
		if installed.id in removed: continue
		var lateral: Vector3 = geometry.lateral.get(installed.id, Vector3.ZERO)
		var engine_base: float = geometry.bases.get(installed.id, 0.0)
		components.append([float(ENGINES[installed.kind].mass),lateral+Vector3(0,engine_base+.8,0),.9,1.8])
	var tank_parts: Array = design.get("assembly", {}).get("parts", []).filter(func(part): return part.kind == "tank")
	var retained_tanks := tank_parts.filter(func(part): return not part.id in removed).size() if not tank_parts.is_empty() else tanks
	for index in range(tanks):
		if index < tank_parts.size() and tank_parts[index].id in removed: continue
		var y: float = float(geometry.bases.get(tank_parts[index].id, 0.0)) + 1.075 if index < tank_parts.size() else base+index*2.15+1.075
		var lateral: Vector3 = geometry.lateral.get(tank_parts[index].id, Vector3.ZERO) if index < tank_parts.size() else Vector3.ZERO
		components.append([TANK_DRY_MASS,lateral+Vector3(0,y,0),.94,2.15,1.0/maxi(retained_tanks,1),0.0])
	if design.get("fins",false) and not "fins" in removed: components.append([FIN_MASS,Vector3(0,1.5,0),1.2,1.0])
	if design.has("assembly"):
		for mount in (radial_layout.separator if radial_layout.has("separator") else Craft.radial_instances(design,"separator")):
			if not mount.id in removed: components.append([SEPARATOR_MASS,mount.position,.20,1.40])
	var boosters: Array = radial_layout.boosters if radial_layout.has("boosters") else Craft.radial_instances(design,"boosters")
	if boosters_attached:
		for booster in boosters: components.append([BOOSTER_DRY_MASS*.5,booster.position,.72,5.28,0.0,1.0/maxi(boosters.size(),1)])
	return components


static func mass_properties(design: Dictionary, fuel: float, booster_fuel: float, boosters_attached: bool, radial_layout: Dictionary = {}, layout: Array = []) -> Dictionary:
	var components := layout if not layout.is_empty() else mass_layout(design, boosters_attached, radial_layout)
	var mass := 0.0
	var center := Vector3.ZERO
	for item in components:
		var m: float = float(item[0]) + (fuel * item[4] + booster_fuel * item[5] if item.size() > 4 else 0.0)
		mass += m
		center += item[1]*m
	center /= maxf(mass,1.0)
	var inertia := Vector3.ZERO
	for item in components:
		var m: float = float(item[0]) + (fuel * item[4] + booster_fuel * item[5] if item.size() > 4 else 0.0)
		var delta: Vector3 = item[1]-center
		var radius: float = item[2]
		var length: float = item[3]
		var transverse := m*(3*radius*radius+length*length)/12.0
		inertia += Vector3(transverse,m*radius*radius*.5,transverse)
		inertia += m*Vector3(delta.y*delta.y+delta.z*delta.z,delta.x*delta.x+delta.z*delta.z,delta.x*delta.x+delta.y*delta.y)
	return {"mass":mass,"center":center,"inertia":inertia.max(Vector3.ONE)}


static func reaction_wheels(design: Dictionary) -> Array:
	var removed: Array = design.get("removed_parts", [])
	return design.get("assembly", {}).get("parts", []).filter(func(part): return part.kind == "reaction_wheel" and part.id not in removed)


static func recovery_mass(design: Dictionary) -> float:
	return CAPSULE_MASS + (PARACHUTE_MASS if design.get("parachute", false) else 0.0)
