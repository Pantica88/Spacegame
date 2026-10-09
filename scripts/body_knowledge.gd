extends RefCounted
## What one faction knows about each body, separate from the physical facts in
## BodyRegistry, so a body can be fully simulated while still hidden from a
## faction's map. Discovery gameplay (telescopes, probes) comes later; until then
## every faction knows every registered body, which preserves current behaviour.
const BodyRegistry = preload("res://scripts/body_registry.gd")

enum Discovery { UNDISCOVERED, DETECTED, OBSERVED, SURVEYED, EXPLORED }

## Bodies without an explicit entry report this level.
var default_level: Discovery = Discovery.EXPLORED
var _levels: Dictionary = {}

func level(id: StringName) -> Discovery:
	return _levels.get(id, default_level)

## Knowledge only grows: observing a body never makes a faction forget it.
func raise(id: StringName, new_level: Discovery) -> void:
	if new_level > level(id):
		_levels[id] = new_level

func is_known(id: StringName) -> bool:
	return level(id) >= Discovery.DETECTED

## Ids this faction can see, in registry order.
func known_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id in BodyRegistry.ids():
		if is_known(id):
			result.append(id)
	return result

func to_dict() -> Dictionary:
	var levels := {}
	for id: StringName in _levels:
		levels[String(id)] = int(_levels[id])
	return {"default": int(default_level), "levels": levels}

static func from_dict(data: Dictionary) -> RefCounted:
	var knowledge := new()
	knowledge.default_level = clampi(int(data.get("default", Discovery.EXPLORED)), Discovery.UNDISCOVERED, Discovery.EXPLORED)
	var levels: Dictionary = data.get("levels", {})
	for key in levels:
		knowledge._levels[StringName(str(key))] = clampi(int(levels[key]), Discovery.UNDISCOVERED, Discovery.EXPLORED)
	return knowledge
