extends RefCounted
## The original, fictional parts used by the flight prototype. SI units throughout.

const Craft = preload("res://scripts/craft_model.gd")

const Physics = preload("res://scripts/physics_math.gd")
const STANDARD_GRAVITY: float = Physics.STANDARD_GRAVITY
const CAPSULE_MASS: float = 380.0
const TANK_DRY_MASS: float = 70.0
const TANK_FUEL_MASS: float = 720.0
const FIN_MASS: float = 45.0
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
	normalized["tanks"] = clampi(int(design.get("tanks", 2)), 1, 4)
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
	var tank_count: int = int(clean["tanks"])
	var has_boosters: bool = bool(clean["boosters"])
	var core_dry: float = CAPSULE_MASS + TANK_DRY_MASS * tank_count + float(engine["mass"])
	if bool(clean["fins"]):
		core_dry += FIN_MASS
	var core_fuel: float = TANK_FUEL_MASS * tank_count
	var dry_mass: float = core_dry + (BOOSTER_DRY_MASS if has_boosters else 0.0)
	var fuel_mass: float = core_fuel + (BOOSTER_FUEL_MASS if has_boosters else 0.0)
	var wet_mass: float = dry_mass + fuel_mass
	var engine_thrust: float = float(engine["thrust"])
	var thrust: float = engine_thrust + (BOOSTER_THRUST if has_boosters else 0.0)
	var engine_isp: float = float(engine["isp"])
	var delta_v: float = (engine_isp * STANDARD_GRAVITY * log((core_dry + core_fuel) / core_dry) if engine_thrust > 0.0 else 0.0)
	if has_boosters:
		# Integrate each constant-Isp phase separately. Either propellant supply
		# can empty first; mixed Isp only applies while both engines are burning.
		var core_flow := engine_thrust / (engine_isp * STANDARD_GRAVITY)
		var booster_flow := BOOSTER_THRUST / (BOOSTER_ISP * STANDARD_GRAVITY)
		var booster_time := BOOSTER_FUEL_MASS / booster_flow
		var core_time := core_fuel / core_flow if core_flow > 0.0 else INF
		var mixed_time := minf(core_time, booster_time)
		var core_burn := core_flow * mixed_time
		var booster_burn := booster_flow * mixed_time
		var burnout_mass := wet_mass - core_burn - booster_burn
		var exhaust_velocity := thrust / (core_flow + booster_flow)
		delta_v = exhaust_velocity * log(wet_mass / burnout_mass)
		if core_time < booster_time:
			# Empty core remains attached while the solids finish burning.
			delta_v += BOOSTER_ISP * STANDARD_GRAVITY * log(burnout_mass / (core_dry + BOOSTER_DRY_MASS))
		elif engine_thrust > 0.0:
			# Estimate assumes immediate separation of depleted boosters.
			delta_v += engine_isp * STANDARD_GRAVITY * log((core_dry + core_fuel - core_burn) / core_dry)
	if has_boosters and bool(clean["booster_first"]):
		delta_v = BOOSTER_ISP * STANDARD_GRAVITY * log(wet_mass / (wet_mass - BOOSTER_FUEL_MASS))
		delta_v += (engine_isp * STANDARD_GRAVITY * log((core_dry + core_fuel) / core_dry) if engine_thrust > 0.0 else 0.0)
		thrust = BOOSTER_THRUST
	if clean.has("assembly") and not clean.assembly.stages.is_empty():
		var first: Array = clean.assembly.stages[0]
		thrust = (engine_thrust if first.has("ignite:engine") else 0.0) + (BOOSTER_THRUST if first.has("ignite:boosters") else 0.0)
	elif clean.has("assembly"):
		thrust = 0.0
	var cost: int = 1200 + tank_count * 550 + int(engine["cost"])
	cost += 350 if bool(clean["fins"]) else 0
	cost += 1600 if has_boosters else 0
	return {
		"dry_mass": dry_mass, "fuel_mass": fuel_mass, "wet_mass": wet_mass,
		"thrust": thrust, "isp": engine_isp, "twr": thrust / (wet_mass * Physics.SURFACE_GRAVITY),
		"delta_v": delta_v, "height": 4.2 + 2.2 * tank_count, "cost": cost,
		"core_dry_mass": core_dry, "core_fuel_mass": core_fuel,
		"engine_thrust": engine_thrust, "booster_fuel_mass": BOOSTER_FUEL_MASS if has_boosters else 0.0,
		"engine_name": str(engine["name"]), "tank_count": tank_count
	}


static func stage_plan(design: Dictionary) -> Array[String]:
	var clean := normalize_design(design)
	if clean.has("assembly"):
		var labels: Array[String] = []
		for group in clean.assembly.stages:
			var actions := PackedStringArray()
			for action in group: actions.append(Craft.ACTION_LABELS[action])
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
