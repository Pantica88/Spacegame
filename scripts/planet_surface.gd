extends RefCounted
## Shared home-world instance: renderer, flight, debris and map query the same mesh.
const Terrain = preload("res://scripts/planet_terrain.gd")
const PlanetList = preload("res://scripts/planet_list.gd")
const HOME_PATH := "res://assets/planets/verdant.tres"
const HOME = preload("res://assets/planets/verdant.tres")
const RADIUS := 600000.0
const LAUNCH_BASIS := Terrain.LAUNCH_BASIS
const LAUNCH_RADIAL := Terrain.LAUNCH_DIRECTION * RADIUS
static var _home: RefCounted

static func home() -> RefCounted:
	if _home == null:
		var saved := PlanetList.load_planet(HOME_PATH)
		_home = Terrain.new(saved if saved != null else HOME)
	return _home

static func reset_home(settings: Resource = null) -> RefCounted:
	var selected := settings if settings != null else PlanetList.load_planet(HOME_PATH)
	_home = Terrain.new(selected if selected != null else HOME)
	return _home

static func build_mesh() -> ArrayMesh:
	return home().build()

static func render_mesh_for_altitude(altitude: float, current_lod: int = -1) -> ArrayMesh:
	var terrain := home()
	return terrain.render_mesh_for_lod(terrain.render_lod_for_altitude(altitude, current_lod))

static func render_lod_for_altitude(altitude: float, current_lod: int = -1) -> int:
	return home().render_lod_for_altitude(altitude, current_lod)

static func terrain_height(point: Vector2) -> float:
	var direction := Vector3(point.x,sqrt(maxf(0.0,RADIUS*RADIUS-point.length_squared())),point.y).normalized()
	return home().elevation(LAUNCH_BASIS * direction)
