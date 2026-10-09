extends RefCounted
## One planet or moon: a stable id, physical properties read from its
## PlanetDefinition, its parent body and its terrain. Physical facts only; what a
## faction knows about a body lives in BodyKnowledge.
const Terrain = preload("res://scripts/planet_terrain.gd")
const SolarBody = preload("res://scripts/solar_body.gd")

var id: StringName
var definition: Resource
## The body this one orbits, or null for a planet (which orbits the sun).
## Held weakly: a parent holds its moons, so a strong back-reference would form a
## reference cycle that is never freed.
var parent: RefCounted:
	get: return _parent.get_ref() if _parent != null else null
var moons: Array[RefCounted] = []
var _parent: WeakRef
var _terrain: RefCounted

var display_name: String:
	get: return str(definition.planet_name)
var radius: float:
	get: return float(definition.radius)
var surface_gravity: float:
	get: return float(definition.surface_gravity)
## Standard gravitational parameter GM. Surface gravity is the single source of
## truth for a body's mass: mu = g r².
var mu: float:
	get: return surface_gravity * radius * radius
var atmosphere_height: float:
	get: return float(definition.atmosphere_height)
var rotation_seconds: float:
	get: return float(definition.rotation_seconds)
var terrain: RefCounted:
	get:
		if _terrain == null:
			_terrain = Terrain.new(definition)
		return _terrain

func _init(body_id: StringName, settings: Resource, parent_body: RefCounted = null, body_terrain: RefCounted = null) -> void:
	id = body_id
	_terrain = body_terrain
	# Share the terrain's definition so runtime edits to either stay consistent.
	definition = body_terrain.definition if body_terrain != null else settings
	_parent = weakref(parent_body) if parent_body != null else null

## Position relative to the parent body's centre, in metres. Planets do not
## move yet: heliocentric orbits arrive in roadmap step 3.
func offset_from_parent(time: float) -> Vector3:
	return SolarBody.moon_offset(definition, time) if parent != null else Vector3.ZERO
