extends RefCounted
## Place test vehicles in the current pad frame, with ground-relative velocity.
const Surface = preload("res://scripts/planet_surface.gd")

static func above_pad(flight: RefCounted, altitude: float, velocity := Vector3.ZERO, attitude := Basis.IDENTITY) -> void:
	var frame: Basis = flight.terrain.rotation_at(flight.simulation_time()) * Surface.LAUNCH_BASIS
	var radial: Vector3 = frame.y * (float(flight.terrain.definition.radius) + altitude)
	flight.state.position = flight.PLANET_CENTER + radial
	flight.state.position_remainder = Vector3.ZERO
	flight.state.velocity = flight.terrain.surface_velocity(radial) + frame * velocity
	flight.state.orientation = frame * attitude
