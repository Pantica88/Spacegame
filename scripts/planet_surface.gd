extends RefCounted
## Shared home-world instance: renderer, flight, debris and map query the same mesh.
const Terrain = preload("res://scripts/planet_terrain.gd")
const HOME = preload("res://assets/planets/verdant.tres")
const RADIUS := 60000.0
static var _home: RefCounted

static func home() -> RefCounted:
	if _home == null: _home = Terrain.new(HOME)
	return _home

static func reset_home(settings: Resource = null) -> RefCounted:
	_home = Terrain.new(settings if settings != null else HOME)
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
	return home().elevation(direction)
