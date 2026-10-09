extends RefCounted
## Every planet and moon, by stable id. A planet's id is its bundled .tres file
## name ("verdant", "ochre"); a moon's is "<planet id>/moon-<index>". Planets load
## through PlanetList, so the player's saved overrides in user://planets win over
## the bundled files, exactly as the planet editor and map see them.
##
## The home planet and its moons load immediately. Other planets load on first
## lookup, because each one brings its terrain bake.
const CelestialBody = preload("res://scripts/celestial_body.gd")
const PlanetList = preload("res://scripts/planet_list.gd")
const Terrain = preload("res://scripts/planet_terrain.gd")
const HOME_ID := &"verdant"
const HOME_PATH := "res://assets/planets/verdant.tres"

static var _home: RefCounted
static var _bodies: Dictionary = {}
static var _planet_paths: Dictionary = {}

static func home() -> RefCounted:
	if _home == null:
		rebuild()
	return _home

## The body with this id, or null. Loads its planet on first lookup.
static func get_body(id: StringName) -> RefCounted:
	if _home == null:
		rebuild()
	if not _bodies.has(id):
		var planet_id := StringName(String(id).get_slice("/", 0))
		if _planet_paths.has(planet_id) and not _bodies.has(planet_id):
			var settings := PlanetList.load_planet(_planet_paths[planet_id])
			if settings != null:
				_add_planet(planet_id, settings)
	return _bodies.get(id)

## Ids of every known planet and moon, home system first.
static func ids() -> Array[StringName]:
	if _home == null:
		rebuild()
	var result: Array[StringName] = []
	for planet_id: StringName in _planet_paths:
		var planet := get_body(planet_id)
		if planet == null:
			continue
		result.append(planet_id)
		for moon: RefCounted in planet.moons:
			result.append(moon.id)
	return result

## Rebuild from disk. `home_settings` replaces the home planet's definition, as
## the planet editor's preview and tests do.
static func rebuild(home_settings: Resource = null) -> void:
	_bodies.clear()
	_planet_paths.clear()
	_planet_paths[HOME_ID] = HOME_PATH
	for path in PlanetList.paths():
		var planet_id := StringName(path.get_file().get_basename())
		if not _planet_paths.has(planet_id):
			_planet_paths[planet_id] = path
	var settings := home_settings if home_settings != null else PlanetList.load_planet(HOME_PATH)
	if settings == null:
		# Loaded, not preloaded: preloading planet .tres files early can leave them
		# with a stale script (see docs/FOUNDATION_REVIEW.md, resource loading).
		settings = load(HOME_PATH)
	_home = _add_planet(HOME_ID, settings, Terrain.new(settings))

static func _add_planet(planet_id: StringName, settings: Resource, terrain: RefCounted = null) -> RefCounted:
	var planet := CelestialBody.new(planet_id, settings, null, terrain)
	_bodies[planet_id] = planet
	for index in range(planet.definition.moons.size()):
		var moon := CelestialBody.new(StringName("%s/moon-%d" % [planet_id, index]), planet.definition.moons[index], planet)
		planet.moons.append(moon)
		_bodies[moon.id] = moon
	return planet
