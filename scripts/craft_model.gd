extends RefCounted
## Serializable connected craft and stage actions. No rendering dependencies.
const ENGINE_IDS := ["sparrow", "kestrel", "titan"]
const ACTION_LABELS := {"ignite:engine": "Ignite core", "ignite:boosters": "Ignite boosters", "separate:boosters": "Separate boosters", "separate:decoupler": "Separate capsule", "deploy:capsule": "Deploy parachute"}

static func node(id: String, kind: String, parent: String, port: String) -> Dictionary:
	return {"id": id, "kind": kind, "parent": parent, "port": port, "rotation": 0, "surface_offset": 0.0}

static func migrate(design: Dictionary) -> Dictionary:
	var craft := {"revision": 1, "parts": [], "stages": [], "next_id": 1, "root_height": 9.0}
	craft.parts.append(node("capsule", "capsule", "", "root"))
	craft.parts.append(node("decoupler", "decoupler", "capsule", "bottom"))
	var parent := "decoupler"
	for index in range(int(design.get("tanks", 2))):
		var id := "tank_%d" % craft.next_id
		craft.next_id += 1
		craft.parts.append(node(id, "tank", parent, "bottom"))
		parent = id
	craft.parts.append(node("engine", str(design.get("engine", "sparrow")), parent, "bottom"))
	if design.get("boosters", false):
		craft.parts.append(node("boosters", "boosters", parent, "radial_pair"))
	if design.get("fins", true):
		craft.parts.append(node("fins", "fins", parent, "radial_four"))
	craft.stages = default_stages(design)
	return craft

static func default_stages(design: Dictionary) -> Array:
	var stages: Array = []
	if design.get("boosters", false):
		if design.get("booster_first", false):
			stages = [["ignite:boosters"], ["separate:boosters", "ignite:engine"]]
		else:
			stages = [["ignite:engine", "ignite:boosters"], ["separate:boosters"]]
	else:
		stages = [["ignite:engine"]]
	stages.append(["separate:decoupler"])
	stages.append(["deploy:capsule"])
	return stages

static func valid(raw: Variant) -> bool:
	if not raw is Dictionary or not raw.get("parts") is Array or not raw.get("stages") is Array:
		return false
	if raw.parts.size() > 10 or raw.stages.size() > 12:
		return false
	if raw.parts.is_empty():
		return raw.stages.is_empty()
	var ids := {}
	var ports := {}
	var tanks := 0
	for part in raw.parts:
		if not part is Dictionary:
			return false
		for key in ["id", "kind", "parent", "port"]:
			if not part.get(key) is String or part[key].length() > 40:
				return false
		if part.id.is_empty() or ids.has(part.id):
			return false
		if part.kind == "tank":
			if not part.id.begins_with("tank_") or not part.id.trim_prefix("tank_").is_valid_int(): return false
			tanks += 1
		elif not part.kind in ENGINE_IDS + ["capsule", "decoupler", "boosters", "fins"]:
			return false
		if part.kind in ENGINE_IDS and part.id != "engine": return false
		if part.kind in ["capsule", "decoupler", "boosters", "fins"] and part.id != part.kind: return false
		if not part.port in ["root", "bottom", "radial_pair", "radial_four"]: return false
		if part.id != "capsule" and not ids.has(part.parent):
			return false # Parent-before-child ordering rejects cycles and dangling connections.
		if part.id == "capsule" and (part.kind != "capsule" or part.parent != ""):
			return false
		if part.has("surface_offset") and (typeof(part.surface_offset) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(part.surface_offset)) or absf(float(part.surface_offset)) > 2.0):
			return false
		var connection: String = part.parent + ":" + part.port
		if ports.has(connection):
			return false
		ports[connection] = true
		ids[part.id] = part.kind
	if tanks > 4 or ids.get("capsule") != "capsule":
		return false
	var seen := {}
	for stage in raw.stages:
		if not stage is Array or stage.size() > 5:
			return false
		for action in stage:
			if not action is String or not ACTION_LABELS.has(action) or seen.has(action):
				return false
			if not ids.has(action.get_slice(":", 1)):
				return false
			seen[action] = true
	for required in ["ignite:engine", "separate:decoupler", "deploy:capsule"]:
		if ids.has(required.get_slice(":", 1)) and not seen.has(required):
			return false
	if ids.has("boosters") and (not seen.has("ignite:boosters") or not seen.has("separate:boosters")):
		return false
	return true

static func load_craft(design: Dictionary) -> Dictionary:
	if valid(design.get("assembly")):
		var raw: Dictionary = design.assembly
		var saved_height := float(raw.get("root_height", 9.0)) if typeof(raw.get("root_height", 9.0)) in [TYPE_INT, TYPE_FLOAT] else 9.0
		var craft := {"revision": 1, "parts": [], "stages": raw.stages.duplicate(true), "next_id": 1, "root_height": clampf(saved_height, 3.5, 13.0)}
		for part in raw.parts:
			var clean_part := node(part.id, part.kind, part.parent, part.port)
			if typeof(part.get("rotation")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(part.rotation)):
				clean_part.rotation = int(fmod(float(part.rotation), 360.0))
			if typeof(part.get("surface_offset")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(part.surface_offset)):
				clean_part.surface_offset = clampf(float(part.surface_offset), -2.0, 2.0)
			craft.parts.append(clean_part)
			if part.id.begins_with("tank_"):
				craft.next_id = maxi(craft.next_id, int(part.id.trim_prefix("tank_")) + 1)
		return craft
	return migrate(design)

static func project(craft: Dictionary, design: Dictionary) -> Dictionary:
	var result := design.duplicate(true)
	result.tanks = 0
	result.engine = ""
	result.decoupler = false
	result.boosters = false
	result.fins = false
	for part in craft.parts:
		if part.kind == "tank": result.tanks += 1
		elif part.kind == "decoupler": result.decoupler = true
		elif part.kind in ENGINE_IDS: result.engine = part.kind
		elif part.kind == "boosters": result.boosters = true
		elif part.kind == "fins": result.fins = true
	result.capsule = craft.parts.any(func(part): return part.kind == "capsule")
	result.booster_first = result.boosters and not craft.stages.is_empty() and not craft.stages[0].has("ignite:engine")
	result.assembly = craft.duplicate(true)
	return result

static func add_part(craft: Dictionary, kind: String, radial_parent: String = "") -> void:
	if kind == "capsule" and craft.parts.is_empty():
		craft.parts.append(node("capsule", "capsule", "", "root"))
		craft.stages.append(["deploy:capsule"])
		return
	if craft.parts.is_empty():
		return
	var tank: Dictionary = craft.parts[0]
	for part in craft.parts:
		if part.kind in ["decoupler", "tank"]: tank = part
	if kind == "tank" or kind == "decoupler":
		if kind == "decoupler": tank = craft.parts[0]
		var id := "tank_%d" % craft.next_id if kind == "tank" else "decoupler"
		if kind == "tank": craft.next_id += 1
		for part in craft.parts:
			if part.parent == tank.id: part.parent = id
		craft.parts.insert(craft.parts.find(tank) + 1, node(id, kind, tank.id, "bottom"))
		if kind == "decoupler": craft.stages.insert(maxi(0, craft.stages.size()-1), ["separate:decoupler"])
	elif kind in ENGINE_IDS:
		for part in craft.parts:
			if part.id == "engine":
				part.kind = kind
				return
		craft.parts.append(node("engine", kind, tank.id, "bottom"))
		craft.stages.insert(0, ["ignite:engine"])
	else:
		var parent_id: String = radial_parent if not radial_parent.is_empty() else tank.id
		craft.parts.append(node(kind, kind, parent_id, "radial_pair" if kind == "boosters" else "radial_four"))
		if kind == "boosters":
			craft.stages[0].append("ignite:boosters")
			craft.stages.insert(1, ["separate:boosters"])

static func remove_part(craft: Dictionary, id: String) -> void:
	var removed_ids := descendant_ids(craft, id)
	if removed_ids.is_empty(): return
	craft.parts = craft.parts.filter(func(part): return not part.id in removed_ids)
	for stage in craft.stages:
		for action in stage.duplicate():
			if action.get_slice(":", 1) in removed_ids: stage.erase(action)
	craft.stages = craft.stages.filter(func(stage): return not stage.is_empty())

static func descendant_ids(craft: Dictionary, root_id: String) -> Array[String]:
	var result: Array[String] = []
	if not craft.parts.any(func(part): return part.id == root_id): return result
	result.append(root_id)
	var changed := true
	while changed:
		changed = false
		for part in craft.parts:
			if part.parent in result and not part.id in result:
				result.append(part.id)
				changed = true
	return result

static func warnings(craft: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var core_removed := false
	var boosters_removed := false
	var core_active := false
	for index in range(craft.stages.size()):
		var stage: Array = craft.stages[index]
		var prefix := "Stage %d: " % (index + 1)
		if stage.has("separate:decoupler"):
			core_removed = true
			boosters_removed = true
			if core_active: result.append(prefix + "separates the core; cut throttle before firing.")
		if stage.has("separate:boosters"): boosters_removed = true
		if stage.has("ignite:engine") and core_removed: result.append(prefix + "cannot ignite the discarded core.")
		if stage.has("ignite:boosters") and boosters_removed: result.append(prefix + "cannot ignite discarded boosters.")
		if stage.has("ignite:engine"): core_active = true
		if stage.has("deploy:capsule") and (not core_removed or index == 0): result.append(prefix + "parachute requires capsule separation and safe descent.")
	return result


static func seed() -> Dictionary:
	return {"revision": 1, "parts": [], "stages": [], "next_id": 1, "root_height": 7.5}

static func blockers(craft: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	var kinds: Array = craft.parts.map(func(part): return part.kind)
	if not "capsule" in kinds: issues.append("Place a command capsule.")
	if not "tank" in kinds: issues.append("Attach a fuel tank.")
	if not kinds.any(func(kind): return kind in ENGINE_IDS): issues.append("Attach a core engine.")
	if not "decoupler" in kinds: issues.append("Attach the capsule decoupler for recovery.")
	for warning in warnings(craft):
		if "cannot ignite" in warning: issues.append(warning)
	return issues
