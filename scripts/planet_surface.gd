extends RefCounted
## Shared home-world terrain: renderer, flight, debris and map query the same
## mesh. The home world itself is BodyRegistry.home(); this is its terrain view.
const Terrain = preload("res://scripts/planet_terrain.gd")
const Bodies = preload("res://scripts/body_registry.gd")
const HOME_PATH := Bodies.HOME_PATH
## The bundled definition, as shipped (ignores the player's saved override).
## Loaded, not preloaded: in Godot 4.5 a preloaded planet .tres loses its script
## variables if planet_definition.gd is preloaded afterwards (engine bug, fixed in
## 4.7; docs/FOUNDATION_REVIEW.md entry 13).
static var HOME: Resource:
	get: return load(HOME_PATH)
const LAUNCH_BASIS := Terrain.LAUNCH_BASIS
static var RADIUS: float:
	get: return Bodies.home().radius
static var LAUNCH_RADIAL: Vector3:
	get: return Terrain.LAUNCH_DIRECTION * RADIUS

static func home() -> RefCounted:
	return Bodies.home().terrain

## Rebuild the body registry, optionally with replacement home settings.
static func reset_home(settings: Resource = null) -> RefCounted:
	Bodies.rebuild(settings)
	return home()

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
