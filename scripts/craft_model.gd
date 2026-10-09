extends RefCounted
## Serializable connected craft and stage actions. No rendering dependencies.
const MAX_PARTS := 256
const MAX_TANKS := 16
const MAX_STAGES := 80
const MAX_STAGE_ACTIONS := 80
const MAX_ROOT_HEIGHT := 44.0
const ENGINE_IDS := ["sparrow", "kestrel", "titan"]
# Retain only a few live assemblies: workshop previews and undo make temporary copies.
# The parts hash catches direct dictionary edits, which are part of the model API.
const GEOMETRY_CACHE_LIMIT := 8
static var _geometry_cache: Array[Dictionary] = []
const ACTION_LABELS := {"separate:engine_decoupler": "Separate lower stage", "ignite:engine": "Ignite core", "ignite:boosters": "Ignite boosters", "separate:boosters": "Separate boosters", "separate:decoupler": "Separate capsule", "deploy:capsule": "Deploy parachute"}

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
		craft.parts.append(node("separator", "separator", parent, "radial_pair"))
		craft.parts.append(node("boosters", "boosters", "separator", "radial_pair"))
	if design.get("fins", true):
		craft.parts.append(node("fins", "fins", parent, "radial_four"))
	if design.get("parachute", true): craft.parts.append(node("parachute", "parachute", "capsule", "top"))
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
	if design.get("parachute", true): stages.append(["deploy:capsule"])
	return stages

static func valid(raw: Variant) -> bool:
	if not raw is Dictionary or not raw.get("parts") is Array or not raw.get("stages") is Array:
		return false
	if raw.parts.size() > MAX_PARTS or raw.stages.size() > MAX_STAGES:
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
		elif not part.kind in ENGINE_IDS + ["capsule", "decoupler", "boosters", "separator", "fins", "parachute", "reaction_wheel"]:
			return false
		if part.kind == "reaction_wheel" and (not _numbered_id(part.id, "reaction_wheel_") or (part.parent not in ["capsule", "decoupler"] and ids.get(part.parent) != "reaction_wheel") or part.port != "bottom"): return false
		if part.kind in ENGINE_IDS and part.id != "engine" and not _numbered_id(part.id, "engine_"): return false
		if part.kind in ENGINE_IDS and (ids.get(part.parent) != "tank" or part.port != "bottom"): return false
		if part.kind in ["capsule", "decoupler", "fins", "parachute"] and part.id != part.kind and not (part.kind == "decoupler" and (part.id == "engine_decoupler" or _numbered_id(part.id, "decoupler_")) and ids.get(part.parent) in ENGINE_IDS + ["tank", "reaction_wheel"] and part.port == "bottom"): return false
		if not part.port in ["root", "top", "bottom", "radial_pair", "radial_four"] and not part.port.begins_with("surface:"): return false
		if part.id != "capsule" and not ids.has(part.parent):
			return false # Parent-before-child ordering rejects cycles and dangling connections.
		if part.kind == "parachute" and (part.parent != "capsule" or part.port != "top"): return false
		if part.port == "top" and part.kind != "parachute": return false
		if part.kind == "separator" and (ids.get(part.parent) != "tank" or not (part.port == "radial_pair" or part.port.begins_with("surface:"))):
			return false
		if part.kind == "boosters" and part.id != "boosters" and ids.get(part.parent) != "separator":
			return false
		if part.id == "capsule" and (part.kind != "capsule" or part.parent != ""):
			return false
		if part.kind in ["separator", "boosters"] and part.id != part.kind and not (part.id.begins_with(part.kind + "_") and part.id.trim_prefix(part.kind + "_").is_valid_int()): return false
		if part.has("rotation") and (typeof(part.rotation) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(part.rotation))): return false
		if part.has("surface_offset") and (typeof(part.surface_offset) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(part.surface_offset)) or absf(float(part.surface_offset)) > 2.0):
			return false
		var connection: String = part.parent + ":" + part.port
		if ports.has(connection):
			return false
		ports[connection] = true
		ids[part.id] = part.kind
	if ids.get("capsule") != "capsule":
		return false
	for count in _geometry(raw).tank_counts.values():
		if count > MAX_TANKS: return false
	var seen := {}
	for stage in raw.stages:
		if not stage is Array or stage.size() > MAX_STAGE_ACTIONS:
			return false
		for action in stage:
			if not action is String or not _valid_action(action, ids) or seen.has(action):
				return false
			if not ids.has(action.get_slice(":", 1)) and not (action.get_slice(":",1) == "boosters" and ids.values().has("boosters")):
				return false
			seen[action] = true
	for required in ["ignite:engine", "separate:decoupler", "separate:engine_decoupler"]:
		if ids.has(required.get_slice(":", 1)) and not seen.has(required):
			return false
	if ids.has("parachute") and not seen.has("deploy:capsule"): return false
	for id in ids:
		if ids[id] in ENGINE_IDS and not seen.has("ignite:" + id): return false
		if ids[id] == "decoupler" and not seen.has("separate:" + id): return false
	if ids.values().has("boosters") and (not seen.has("ignite:boosters") or not seen.has("separate:boosters")):
		return false
	return true

static func load_craft(design: Dictionary) -> Dictionary:
	if valid(design.get("assembly")):
		var raw: Dictionary = design.assembly
		var saved_height := float(raw.get("root_height", 9.0)) if typeof(raw.get("root_height", 9.0)) in [TYPE_INT, TYPE_FLOAT] else 9.0
		if not is_finite(saved_height):
			saved_height = 9.0
		var craft := {"revision": 1, "parts": [], "stages": raw.stages.duplicate(true), "next_id": 1, "root_height": clampf(saved_height, 3.5, MAX_ROOT_HEIGHT)}
		for part in raw.parts:
			var clean_part := node(part.id, part.kind, part.parent, part.port)
			if typeof(part.get("rotation")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(part.rotation)):
				clean_part.rotation = fmod(float(part.rotation), 360.0)
			if typeof(part.get("surface_offset")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(part.surface_offset)):
				clean_part.surface_offset = clampf(float(part.surface_offset), -2.0, 2.0)
			craft.parts.append(clean_part)
			for prefix in ["tank_", "separator_", "boosters_", "engine_", "decoupler_", "reaction_wheel_"]:
				if part.id.begins_with(prefix): craft.next_id = maxi(craft.next_id, int(part.id.trim_prefix(prefix)) + 1)
		_upgrade_booster_mounts(craft)
		_sync_parachute_stage(craft)
		return craft
	return migrate(design)

static func project(craft: Dictionary, design: Dictionary) -> Dictionary:
	craft.stages = craft.stages.filter(func(stage): return not stage.is_empty())
	_sync_parachute_stage(craft)
	var result := design.duplicate(true)
	result.tanks = 0
	result.engine = ""
	result.decoupler = false
	result.boosters = false
	result.separator = false
	result.fins = false
	result.parachute = false
	for part in craft.parts:
		if part.kind == "tank": result.tanks += 1
		elif part.id == "decoupler": result.decoupler = true
		elif part.kind in ENGINE_IDS and result.engine.is_empty(): result.engine = part.kind
		elif part.kind == "boosters": result.boosters = true
		elif part.kind == "separator": result.separator = true
		elif part.kind == "fins": result.fins = true
		elif part.kind == "parachute": result.parachute = true
	result.capsule = craft.parts.any(func(part): return part.kind == "capsule")
	result.booster_first = result.boosters and not craft.stages.is_empty() and not craft.stages[0].any(func(action): return action.begins_with("ignite:engine"))
	result.assembly = craft.duplicate(true)
	if result.tanks > 4:
		# Lift long stacks clear of the floor as the assembly grows downward.
		var clearance: float = stack_top(result) + 2.4
		result.assembly.root_height = maxf(float(result.assembly.get("root_height", 7.5)), clearance)
	return result

static func add_part(craft: Dictionary, kind: String, radial_parent: String = "") -> void:
	var layout := _geometry(craft)
	if craft.parts.size() >= MAX_PARTS:
		# Replacing an engine consumes no additional part slot.
		if kind in ENGINE_IDS:
			var parent := radial_parent
			if parent.is_empty():
				for part in craft.parts:
					if part.kind == "tank" and str(layout.mount_ids.get(part.id, "")).is_empty(): parent = part.id
			for part in craft.parts:
				if part.parent == parent and part.port == "bottom" and part.kind in ENGINE_IDS:
					part.kind = kind
		return
	if kind == "tank" and not can_add_tank(craft,radial_parent): return
	if kind == "capsule" and craft.parts.is_empty():
		craft.parts.append(node("capsule", "capsule", "", "root"))
		return
	if craft.parts.is_empty():
		return
	if kind == "parachute":
		if not craft.parts.any(func(part): return part.kind == "parachute"):
			if craft.stages.size() >= MAX_STAGES: return
			craft.parts.append(node("parachute", "parachute", "capsule", "top"))
			craft.stages.append(["deploy:capsule"])
		return
	if kind == "reaction_wheel":
		var parent := reaction_wheel_parent(craft)
		var id := "reaction_wheel_%d" % craft.next_id
		craft.next_id += 1
		for child in craft.parts:
			if child.parent == parent.id and child.port == "bottom": child.parent = id
		craft.parts.insert(craft.parts.find(parent) + 1, node(id, kind, parent.id, "bottom"))
		return
	# Explicit side-stack connections preserve the selected branch.
	var selected: Array = craft.parts.filter(func(part): return part.id == radial_parent)
	if kind in ["tank", "decoupler"] and not selected.is_empty() and not str(layout.mount_ids.get(radial_parent, "")).is_empty() and selected[0].kind in ["tank", "decoupler"]:
		if kind == "decoupler" and (selected[0].kind != "tank" or craft.parts.any(func(part): return part.parent == radial_parent and part.port == "bottom")): return
		if kind == "decoupler" and craft.stages.size() >= MAX_STAGES: return
		var id := ("tank_" if kind == "tank" else "decoupler_") + str(craft.next_id)
		craft.next_id += 1
		for child in craft.parts:
			if child.parent == radial_parent and child.port == "bottom": child.parent = id
		craft.parts.insert(craft.parts.find(selected[0])+1,node(id,kind,radial_parent,"bottom"))
		if kind == "decoupler": craft.stages.insert(_stage_index(craft,"separate:"+str(layout.mount_ids[radial_parent])),["separate:"+id])
		return
	if kind == "decoupler" and not selected.is_empty() and selected[0].kind == "reaction_wheel":
		if craft.stages.size() >= MAX_STAGES: return
		if craft.parts.any(func(part): return part.parent == radial_parent and part.port == "bottom" and part.kind == "decoupler"): return
		var id := "decoupler_%d" % craft.next_id
		craft.next_id += 1
		for child in craft.parts:
			if child.parent == radial_parent and child.port == "bottom": child.parent = id
		craft.parts.insert(craft.parts.find(selected[0]) + 1, node(id,kind,radial_parent,"bottom"))
		craft.stages.insert(_stage_index(craft,"separate:decoupler"), ["separate:"+id])
		# Keep deployment after the new separation when there is no capsule ring.
		var chute_index := _stage_index(craft,"deploy:capsule")
		var separation_index := _stage_index(craft,"separate:"+id)
		if chute_index < separation_index:
			var group: Array = craft.stages.pop_at(separation_index)
			craft.stages.insert(chute_index,group)
		return
	if kind == "decoupler" and craft.parts.any(func(part): return part.id == radial_parent and part.kind in ENGINE_IDS):
		if craft.parts.any(func(part): return part.parent == radial_parent and part.port == "bottom"): return
		if craft.stages.size() >= MAX_STAGES: return
		var id := "engine_decoupler" if radial_parent == "engine" else "decoupler_%d" % craft.next_id
		if id != "engine_decoupler": craft.next_id += 1
		craft.parts.append(node(id, "decoupler", radial_parent, "bottom"))
		craft.stages.insert(_stage_index(craft,"ignite:" + radial_parent), ["separate:" + id])
		return
	var tank: Dictionary = craft.parts[0]
	for part in craft.parts:
		if (part.kind == "tank" or part.id == "decoupler") and str(layout.mount_ids.get(part.id, "")).is_empty(): tank = part
	if kind == "tank" and not radial_parent.is_empty():
		var mounts := free_mounts(craft).filter(func(part): return part.id == radial_parent)
		if mounts.is_empty() or mounts[0].port == "radial_pair" or craft.stages.size() >= MAX_STAGES: return
		var id := "tank_%d" % craft.next_id
		craft.next_id += 1
		craft.parts.append(node(id,"tank",radial_parent,"bottom"))
		craft.stages.insert(_stage_index(craft,"separate:decoupler"),["separate:"+radial_parent])
		return
	if kind == "tank":
		for part in craft.parts:
			if part.kind in ["tank", "decoupler", "reaction_wheel"] and str(layout.mount_ids.get(part.id, "")).is_empty(): tank = part
	if kind == "tank" or kind == "decoupler":
		if kind == "decoupler":
			if craft.stages.size() >= MAX_STAGES: return
			tank = craft.parts[0]
		var id := "tank_%d" % craft.next_id if kind == "tank" else "decoupler"
		if kind == "tank": craft.next_id += 1
		for part in craft.parts:
			if part.parent == tank.id and part.port != "top": part.parent = id
		craft.parts.insert(craft.parts.find(tank) + 1, node(id, kind, tank.id, "bottom"))
		if kind == "decoupler": craft.stages.insert(_stage_index(craft,"deploy:capsule"), ["separate:decoupler"])
	elif kind in ENGINE_IDS:
		if not radial_parent.is_empty():
			for part in craft.parts:
				if part.id == radial_parent and part.kind == "tank": tank = part
		if tank.kind != "tank": return
		for part in craft.parts:
			if part.parent == tank.id and part.port == "bottom":
				if part.kind in ENGINE_IDS: part.kind = kind
				return
		if craft.stages.size() >= MAX_STAGES: return
		var id := "engine" if not craft.parts.any(func(part): return part.id == "engine") else "engine_%d" % craft.next_id
		if id != "engine": craft.next_id += 1
		craft.parts.append(node(id, kind, tank.id, "bottom"))
		var ancestor: Dictionary = tank
		var before := "separate:decoupler"
		while not str(ancestor.parent).is_empty():
			if not layout.by_id.has(ancestor.parent): break
			ancestor = layout.by_id[ancestor.parent]
			if ancestor.kind in ["decoupler", "separator"]:
				before = "separate:" + str(ancestor.id)
				break
		var ignition_index := _stage_index(craft,before)
		if ignition_index == craft.stages.size(): ignition_index = _stage_index(craft,"deploy:capsule")
		if id == "engine": ignition_index = 0
		craft.stages.insert(ignition_index, ["ignite:" + id])
	else:
		if kind == "fins" and craft.parts.any(func(part): return part.id == kind): return
		if kind == "boosters" and not craft.parts.any(func(part): return part.kind == "separator"): return
		var parent_id: String = radial_parent if not radial_parent.is_empty() else tank.id
		if kind == "separator" and not craft.parts.any(func(part): return part.id == parent_id and part.kind == "tank"): return
		if kind == "boosters":
			if not craft.stages.any(func(stage): return stage.has("ignite:boosters")) and craft.stages.size() > MAX_STAGES - 2: return
			if radial_parent.is_empty():
				for item in craft.parts:
					if item.kind == "separator" and not craft.parts.any(func(child): return child.parent == item.id):
						parent_id = item.id
						break
			if not craft.parts.any(func(item): return item.kind == "separator" and item.id == parent_id): return
			if craft.parts.any(func(item): return item.parent == parent_id): return
		var id := kind
		var port := "radial_four"
		if kind in ["separator", "boosters"]:
			id = kind + "_%d" % craft.next_id
			craft.next_id += 1
			port = "surface:" + id if kind == "separator" else "bottom"
		craft.parts.append(node(id, kind, parent_id, port))
		if kind == "boosters" and not craft.stages.any(func(stage): return stage.has("ignite:boosters")):
			var ignition := -1
			for index in range(craft.stages.size()):
				if craft.stages[index].any(func(action): return action.begins_with("ignite:engine")):
					ignition = index
					break
			if ignition < 0:
				craft.stages.insert(0, ["ignite:boosters"])
				ignition = 0
			else:
				craft.stages.insert(ignition + 1, ["ignite:boosters"])
			craft.stages.insert(mini(ignition + 2, craft.stages.size()), ["separate:boosters"])

static func remove_part(craft: Dictionary, id: String) -> void:
	var removed_ids := descendant_ids(craft, id)
	if removed_ids.is_empty(): return
	craft.parts = craft.parts.filter(func(part): return not part.id in removed_ids)
	for stage in craft.stages:
		for action in stage.duplicate():
			if action.get_slice(":", 1) in removed_ids and action.get_slice(":",1) != "boosters": stage.erase(action)
			if action.get_slice(":",1) == "boosters" and not craft.parts.any(func(item): return item.kind == "boosters"): stage.erase(action)
	craft.stages = craft.stages.filter(func(stage): return not stage.is_empty())
	_sync_parachute_stage(craft)

static func _stage_index(craft: Dictionary, action: String) -> int:
	for index in range(craft.stages.size()):
		if action in craft.stages[index]: return index
	return craft.stages.size()

static func _sync_parachute_stage(craft: Dictionary) -> void:
	if craft.parts.any(func(part): return part.kind == "parachute"): return
	for index in range(craft.stages.size()-1,-1,-1):
		var stage: Array = craft.stages[index]
		if stage.has("deploy:capsule"):
			stage.erase("deploy:capsule")
			if stage.is_empty(): craft.stages.remove_at(index)

static func descendant_ids(craft: Dictionary, root_id: String) -> Array[String]:
	var result: Array[String] = []
	var data := _geometry(craft)
	if not data.by_id.has(root_id): return result
	var descendants := {root_id: true}
	var pending: Array[String] = [root_id]
	while not pending.is_empty():
		var id: String = pending.pop_back()
		for child_id in data.children.get(id, []):
			if descendants.has(child_id): continue
			descendants[child_id] = true
			pending.append(child_id)
	result.append(root_id)
	for part in craft.parts:
		if part.id != root_id and descendants.has(part.id): result.append(part.id)
	return result

static func warnings(craft: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var core_removed := false
	var boosters_removed := false
	var core_active := false
	var discarded: Array[String] = []
	for index in range(craft.stages.size()):
		var stage: Array = craft.stages[index]
		var prefix := "Stage %d: " % (index + 1)
		if stage.has("separate:decoupler"):
			core_removed = true
			boosters_removed = true
			if core_active: result.append(prefix + "separates the core; cut throttle before firing.")
		for action in stage:
			if action.begins_with("separate:") and action != "separate:boosters":
				discarded.append_array(descendant_ids(craft,action.get_slice(":",1)))
		for action in stage:
			if action.begins_with("ignite:engine") and action.get_slice(":",1) in discarded and not core_removed:
				result.append(prefix + "cannot ignite the discarded engine.")
		if stage.has("separate:boosters"): boosters_removed = true
		if stage.any(func(action): return action.begins_with("ignite:engine")) and core_removed: result.append(prefix + "cannot ignite the discarded core.")
		if stage.has("ignite:boosters") and boosters_removed: result.append(prefix + "cannot ignite discarded boosters.")
		if stage.has("ignite:engine"): core_active = true
		if stage.has("deploy:capsule") and index == 0: result.append(prefix + "parachute requires safe descent after launch.")
	return result


static func seed() -> Dictionary:
	return {"revision": 1, "parts": [], "stages": [], "next_id": 1, "root_height": 7.5}

static func can_roll_out(craft: Dictionary) -> bool:
	return craft.parts.any(func(part): return part.kind == "capsule")


static func blockers(craft: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	var kinds: Array = craft.parts.map(func(part): return part.kind)
	if not "capsule" in kinds: issues.append("Place a command capsule.")
	if not "tank" in kinds: issues.append("Attach a fuel tank.")
	if not kinds.any(func(kind): return kind in ENGINE_IDS): issues.append("Attach a core engine.")
	for warning in warnings(craft):
		if "cannot ignite" in warning: issues.append(warning)
	return issues


static func _upgrade_booster_mounts(craft: Dictionary) -> void:
	# Preserve old combined booster assemblies and their saved stage actions.
	for index in range(craft.parts.size()):
		var part: Dictionary = craft.parts[index]
		if part.kind == "boosters" and part.id == "boosters" and not craft.parts.any(func(item): return item.kind == "separator" and item.id == part.parent):
			if not craft.parts.any(func(item): return item.id == "separator"):
				craft.parts.insert(index, node("separator", "separator", part.parent, "radial_pair"))
			part.parent = "separator"
			return

static func radial_height(design: Dictionary) -> float:
	if not design.has("assembly"): return 3.075
	var parent_id := ""
	for part in design.assembly.parts:
		if part.kind == "separator": parent_id = part.parent
	var tanks: Array = design.assembly.parts.filter(func(part): return part.kind == "tank")
	var base := 2.0 if not str(design.get("engine", "")).is_empty() else 0.0
	for index in range(tanks.size()):
		if tanks[index].id == parent_id:
			return tank_center(design, tanks[index].id)
	return base + 1.075


static func engines(design: Dictionary) -> Array:
	if design.has("assembly"):
		return design.assembly.parts.filter(func(part): return part.kind in ENGINE_IDS)
	var kind := str(design.get("engine", ""))
	return [node("engine", kind, "", "bottom")] if kind in ENGINE_IDS else []

static func stack_top(design: Dictionary) -> float:
	if not design.has("assembly"): return engines(design).size() * 2.0 + int(design.get("tanks", 0)) * 2.15
	return part_base(design,"capsule")

# Read-only geometry shared by batch callers. No cache data is written into saved crafts.
static func geometry(design: Dictionary) -> Dictionary:
	return _geometry(design.get("assembly", {}))

static func _geometry(craft: Dictionary) -> Dictionary:
	var parts: Array = craft.get("parts", [])
	var signature := parts.hash()
	for cached in _geometry_cache:
		if is_same(cached.parts, parts) and cached.signature == signature:
			return cached.data
	var data := {"by_id": {}, "children": {}, "mount_ids": {}, "bases": {}, "lateral": {}, "tank_counts": {}}
	for part in parts:
		data.by_id[part.id] = part
		if not data.children.has(part.parent): data.children[part.parent] = []
		data.children[part.parent].append(part.id)
	var visiting := {}
	for id in data.by_id:
		_geometry_branch(data, id, visiting)
	for id in data.by_id:
		_geometry_base(data, id, visiting)
		if data.by_id[id].kind == "tank":
			var mount_id: String = data.mount_ids[id]
			var branch := "core" if mount_id.is_empty() else mount_id
			data.tank_counts[branch] = int(data.tank_counts.get(branch, 0)) + 1
	# Assembly slots include empty space below the engine bell. Ground contact
	# uses Y=0, so translate the entire assembly to its lowest physical part.
	# Apply once after resolving all branches to preserve attachment spacing.
	var bottom := INF
	for part in parts:
		var base := float(data.bases[part.id])
		match str(part.kind):
			"sparrow": bottom = minf(bottom, base + 2.0 - 2.0 * (1.80 / 2.69))
			"kestrel": bottom = minf(bottom, base + 0.20)
			"titan": bottom = minf(bottom, base + 0.3285)
			"tank", "capsule", "decoupler", "reaction_wheel": bottom = minf(bottom, base)
			"boosters":
				var mount: Dictionary = data.by_id.get(part.parent, part)
				var center := float(data.bases.get(mount.parent, 0.0)) + 1.075 + float(mount.get("surface_offset", 0.0))
				bottom = minf(bottom, center - 2.63)
	if is_finite(bottom):
		for id in data.bases:
			data.bases[id] = float(data.bases[id]) - bottom
	# Replace an obsolete entry for an assembly before retaining another version.
	for index in range(_geometry_cache.size() - 1, -1, -1):
		if is_same(_geometry_cache[index].parts, parts): _geometry_cache.remove_at(index)
	_geometry_cache.append({"parts": parts, "signature": signature, "data": data})
	if _geometry_cache.size() > GEOMETRY_CACHE_LIMIT: _geometry_cache.pop_front()
	return data

static func _geometry_branch(data: Dictionary, id: String, visiting: Dictionary) -> void:
	if data.mount_ids.has(id) or not data.by_id.has(id) or visiting.has(id): return
	visiting[id] = true
	var part: Dictionary = data.by_id[id]
	_geometry_branch(data, part.parent, visiting)
	var mount_id: String = str(data.mount_ids.get(part.parent, ""))
	var lateral: Vector3 = data.lateral.get(part.parent, Vector3.ZERO)
	if part.kind == "separator":
		mount_id = id
		var angle := deg_to_rad(float(part.get("rotation", 0.0)))
		lateral += Vector3(sin(angle) * 2.2, 0, cos(angle) * 2.2)
	data.mount_ids[id] = mount_id
	data.lateral[id] = lateral
	visiting.erase(id)

static func _geometry_base(data: Dictionary, id: String, visiting: Dictionary) -> float:
	if data.bases.has(id): return float(data.bases[id])
	if not data.by_id.has(id) or visiting.has(id): return 0.0
	visiting[id] = true
	var part: Dictionary = data.by_id[id]
	var mount_id: String = data.mount_ids[id]
	var height := 0.0
	if not mount_id.is_empty():
		var mount: Dictionary = data.by_id[mount_id]
		if part.parent == mount_id:
			height = _geometry_base(data, mount.parent, visiting) + float(mount.get("surface_offset", 0.0))
		else:
			height = _geometry_base(data, part.parent, visiting) - _installed_height(data, part)
	else:
		# Core bases are the total height of the non-radial descendants below them.
		for child_id in data.children.get(id, []):
			if not str(data.mount_ids[child_id]).is_empty(): continue
			height += _installed_height(data, data.by_id[child_id]) + _geometry_base(data, child_id, visiting)
	data.bases[id] = height
	visiting.erase(id)
	return height

static func reaction_wheel_parent(craft: Dictionary) -> Dictionary:
	var parent: Dictionary = craft.parts[0]
	for part in craft.parts:
		if part.id == "decoupler" or part.kind == "reaction_wheel": parent = part
	return parent

static func _installed_height(data: Dictionary, part: Dictionary) -> float:
	# Unlike the legacy capsule collar, a gyro-mounted ring occupies its own slot.
	if part.kind == "decoupler" and data.by_id.get(part.parent, {}).get("kind") == "reaction_wheel": return .2
	return _part_height(part.kind)

static func _part_height(kind: String) -> float:
	if kind == "reaction_wheel": return 0.2
	if kind == "tank": return 2.15
	return 2.0 if kind in ENGINE_IDS else 0.0

static func part_base(design: Dictionary, id: String) -> float:
	return float(geometry(design).bases.get(id, 0.0))

static func engine_base(design: Dictionary, id: String = "engine") -> float:
	return part_base(design, id)

static func tank_center(design: Dictionary, id: String) -> float:
	return part_base(design, id) + 1.075

static func _numbered_id(id: String, prefix: String) -> bool:
	return id.begins_with(prefix) and id.trim_prefix(prefix).is_valid_int()

static func _valid_action(action: String, ids: Dictionary) -> bool:
	if ACTION_LABELS.has(action): return true
	if action.get_slice_count(":") != 2: return false
	var kind: String = str(ids.get(action.get_slice(":", 1), ""))
	return (action.begins_with("ignite:") and kind in ENGINE_IDS) or (action.begins_with("separate:") and kind in ["decoupler", "separator"])

static func action_label(action: String, craft: Dictionary = {}) -> String:
	var installed: Array = craft.get("parts", []).filter(func(part): return part.kind in ENGINE_IDS)
	if action.begins_with("ignite:") and installed.size() > 1:
		for index in range(installed.size()):
			if installed[index].id == action.get_slice(":",1):
				return "Ignite %s (engine %d)" % [str(installed[index].kind).capitalize(),index+1]
	if action.begins_with("separate:"):
		var parts: Dictionary = _geometry(craft).by_id
		var ring: Dictionary = parts.get(action.get_slice(":",1), {})
		if parts.get(ring.get("parent", ""), {}).get("kind") == "reaction_wheel": return "Separate below gyro"
	if ACTION_LABELS.has(action): return ACTION_LABELS[action]
	var id := action.get_slice(":", 1)
	if id.begins_with("separator_"): return "Separate side tank " + id.get_slice("_",1)
	return ("Ignite engine " if action.begins_with("ignite:") else "Separate lower stage ") + id.get_slice("_", 1)

static func radial_instances(design: Dictionary, kind: String) -> Array:
	var parts: Array = design.get("assembly",{}).get("parts",[])
	if parts.is_empty():
		if not design.get("boosters",false): return []
		return [{"id":kind,"position":Vector3(-1.96 if kind == "boosters" else -1.17,3.075,0),"angle":-PI/2}, {"id":kind,"position":Vector3(1.96 if kind == "boosters" else 1.17,3.075,0),"angle":PI/2}]
	var data := geometry(design)
	var result: Array = []
	for part in parts:
		if part.kind != kind: continue
		var mount: Dictionary = part
		if kind == "boosters": mount = data.by_id.get(part.parent, part)
		var angles: Array = [-PI/2,PI/2] if mount.port == "radial_pair" else [deg_to_rad(float(mount.get("rotation",0.0)))]
		for angle in angles:
			var r := 1.96 if kind == "boosters" else 1.17
			var y := float(data.bases.get(mount.parent, 0.0)) + 1.075 + float(mount.get("surface_offset",0.0))
			var lateral: Vector3 = data.lateral.get(mount.parent, Vector3.ZERO)
			result.append({"id":part.id,"mount":mount.id,"angle":angle,"position":lateral+Vector3(sin(angle)*r,y,cos(angle)*r)})
	return result

static func free_mounts(craft: Dictionary) -> Array:
	var data := _geometry(craft)
	return craft.parts.filter(func(item): return item.kind == "separator" and not data.children.has(item.id))

static func surface_clear(design: Dictionary, parent: String, angle: float, offset: float, ignore: String = "") -> bool:
	var position := lateral_position(design,parent)+Vector3(sin(angle)*1.17,tank_center(design,parent)+offset,cos(angle)*1.17)
	for existing in radial_instances(design,"separator"):
		if existing.id == ignore: continue
		var delta: Vector3 = existing.position-position
		if Vector2(delta.x,delta.z).length() < .38 and absf(delta.y) < 1.42: return false
	return absf(offset) <= .37

# Find the side mount owning a tank/engine branch.
static func radial_mount(craft: Dictionary, id: String) -> Dictionary:
	var data := _geometry(craft)
	return data.by_id.get(data.mount_ids.get(id, ""), {})

static func lateral_position(design: Dictionary, id: String) -> Vector3:
	return geometry(design).lateral.get(id, Vector3.ZERO)

# The tank limit applies to each stack; the assembly still has an MAX_PARTS cap.
static func can_add_tank(craft: Dictionary, parent: String = "") -> bool:
	if craft.parts.size() >= MAX_PARTS: return false
	var data := _geometry(craft)
	var mount_id: String = str(data.mount_ids.get(parent, ""))
	return int(data.tank_counts.get("core" if mount_id.is_empty() else mount_id, 0)) < MAX_TANKS
