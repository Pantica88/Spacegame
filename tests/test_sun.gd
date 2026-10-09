extends SceneTree
const Sun = preload("res://scripts/solar_body.gd")
const Flight = preload("res://scripts/flight_model.gd")
const Map = preload("res://scripts/orbital_map.gd")
const World = preload("res://scripts/world_view.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# The sun spans about 0.53° from Verdant, like our Sun from Earth.
	assert(absf(rad_to_deg(2.0 * atan(Sun.RADIUS / Sun.DISTANCE)) - 0.53) < 0.01, "Sun spans about 0.53 degrees from the home planet")
	assert(is_equal_approx(Sun.segment_hit(Sun.POSITION + Vector3.LEFT * Sun.RADIUS * 2.0, Sun.POSITION + Vector3.RIGHT * Sun.RADIUS * 2.0), 0.25))
	assert(Sun.segment_hit(Vector3.ZERO, Vector3.UP * 1000.0) == -1.0)
	var flight := Flight.new()
	flight.state.position = Sun.POSITION + Vector3.LEFT * (Sun.RADIUS + 1.0)
	flight.state.velocity = Vector3.RIGHT * 1000.0
	flight.state.status = "flying"
	flight._integrate(1.0 / 60.0, Vector3.ZERO)
	assert(flight.state.status == "crashed")
	assert(flight.state.impact_body == "Sun")
	assert(absf(flight.state.position.distance_to(Sun.POSITION) - Sun.RADIUS) < 2.0)
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	# Test from the launchpad: a near-sun pose cannot catch far-plane clipping.
	world.sync_flight(Flight.new().telemetry(), 0.0)
	assert(world._sun_body.material_override is ShaderMaterial, "Sun uses the soft-rim shader")
	assert(world.camera.far > world.camera.position.distance_to(world._sun_body.position) + Sun.RADIUS * world._sun_body.scale.x)
	var physical_offset := world._sun_physical_position - world.camera.position
	var visual_offset := world._sun_body.position - world.camera.position
	assert(visual_offset.length() + Sun.RADIUS * world._sun_body.scale.x < 160001.0, "Distant sun stays within its scaled visual range independently of planet/moon clipping")
	assert(physical_offset.normalized().dot(visual_offset.normalized()) > 0.99999)
	assert(is_equal_approx(Sun.RADIUS * world._sun_body.scale.x / visual_offset.length(), Sun.RADIUS / physical_offset.length()))
	world.orbit_camera(Vector2(80.0, 20.0))
	world.zoom_camera(2.0)
	assert(world.camera.far > world.camera.position.distance_to(world._sun_body.position) + Sun.RADIUS * world._sun_body.scale.x)
	world.sync_flight(flight.telemetry(), 0.0)
	assert(world._sun_body.visible)
	assert(world._sun_physical_position.is_equal_approx(Sun.POSITION - flight.state.position))
	assert(world.camera.far > world._sun_body.position.length() + Sun.RADIUS * world._sun_body.scale.x)
	world.set_mode("workshop")
	assert(not world._sun_body.visible)
	assert(float(world._sky_material.get_shader_parameter("sun_glow_visibility")) == 0.0, "Workshop has no sun glow")
	var map := Map.new()
	map.source_world = world
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(map)
	# A flight camera near the sun must not rotate the map's daylight side.
	world._sun_direction = Vector3.DOWN
	map._update_camera()
	assert(is_equal_approx(map.local_sun.mesh.radius, Sun.RADIUS * 0.001))
	assert(map.local_sun.material_override is ShaderMaterial, "Map uses the flight sun surface")
	assert(map.local_sun.material_override.shader == world._sun_body.material_override.shader)
	assert(map.camera.position.distance_to(map.local_sun.position) > Sun.RADIUS * 0.001)
	var sun_screen_radius: float = map.local_sun.mesh.radius * map.local_sun.scale.x / map.camera.size
	var sun_position: Vector3 = map.local_sun.position
	map.zoom = 0.3
	map._update_camera()
	assert(is_equal_approx(map.local_sun.mesh.radius * map.local_sun.scale.x / map.camera.size, sun_screen_radius), "Sun screen size stays fixed when zooming onto the planet")
	assert(map.local_sun.position == sun_position, "Zoom preserves sun position")
	assert(is_equal_approx(map.local_sun.get_node("SunGlow").global_basis.get_scale().x, map.local_sun.scale.x), "Glow follows sun scale")
	map.zoom = 1.0
	map._update_camera()
	var expected := (map.local_sun.position-map.globe.position).normalized()
	var material: ShaderMaterial = map.globe.material_override
	assert(Vector3(material.get_shader_parameter("sun_direction")).is_equal_approx(expected))
	var before := map.camera.global_transform.affine_inverse() * map.local_sun.global_position
	map.yaw += 1.0
	map.pitch += 0.2
	map._update_camera()
	var after := map.camera.global_transform.affine_inverse() * map.local_sun.global_position
	assert(before.distance_to(after) > 100.0, "Sun moves with the orbiting map view")
	assert(Vector3(material.get_shader_parameter("sun_direction")).is_equal_approx(expected))
	# On the opposite side of the sun the planet lies directly in front of it.
	var away := -map.local_sun.position.normalized()
	map.yaw = atan2(away.x, away.z)
	map.pitch = asin(away.y)
	map._update_camera()
	assert(map.camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	var sun_view := map.camera.global_transform.affine_inverse() * map.local_sun.position
	var globe_view := map.camera.global_transform.affine_inverse() * map.globe.position
	assert(Vector2(sun_view.x-globe_view.x, sun_view.y-globe_view.y).length() < 0.01)
	assert(map._point_occluded(map.local_sun.position), "Planet terrain actually occludes the sun in the aligned view")
	assert(sun_view.z < globe_view.z, "Sun is behind the planet, not a foreground marker")
	map.system_focus = true
	map._update_camera()
	assert(map.local_sun.visible, "One sun remains visible at system framing")
	map.free()
	world.free()
	print("PASS: physical sun, swept impact, flight rebasing and visibility")
	quit()
