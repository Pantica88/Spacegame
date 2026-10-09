extends SceneTree
const Flight = preload("res://scripts/flight_model.gd")
const World = preload("res://scripts/world_view.gd")

class DetailedFlight extends Flight:
	func _classify_debris(_duration: float) -> void:
		_has_local_debris = not state.detached.is_empty()
		for piece in state.detached: piece.background = false

func prepare(model) -> void:
	model.state.status = "flying"
	model.state.position = Vector3(0, Flight.ATMOSPHERE_HEIGHT + 30000.0, 0)
	model.state.velocity = Vector3(620, 0, 0)
	model.state.engine_on = false
	model._separate_core()
	var template: Dictionary = model.state.detached[0].duplicate(true)
	model.state.detached.clear()
	for index in range(8):
		var piece: Dictionary = template.duplicate(true)
		piece.id = index + 1
		piece.position = Vector3(model.state.position) + Vector3(5000 + 100 * index, 0, 0)
		piece.velocity = model.state.velocity
		piece.fuel = 0.0
		piece.thrust = 0.0
		piece.mass = piece.dry_mass
		model.state.detached.append(piece)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var model := Flight.new()
	var reference := DetailedFlight.new()
	prepare(model)
	prepare(reference)
	var elapsed: Array[float] = []
	for simulation in [reference, model]:
		simulation.step(1.0 / 60.0, {"throttle": 0.0})
		var started := Time.get_ticks_usec()
		for frame in range(16): simulation.step(128.0 / 60.0, {"throttle": 0.0})
		elapsed.append(float(Time.get_ticks_usec() - started) / 16000.0)
	assert(model.state.detached.size() == 8, "Background debris is retained")
	assert(model.state.detached.all(func(piece): return piece.background))
	assert(model._collision_bodies().size() == 1, "Distant debris skips detailed local collision pairs")
	for index in range(8):
		var difference: float = Vector3(model.state.detached[index].position).distance_to(reference.state.detached[index].position)
		assert(difference < 10.0, "Background trajectories stay within 10 m of detailed integration over 34 seconds")
	print("DISTANT DEBRIS: eight spent stages at 128x, detailed %.3f ms/tick, background %.3f ms/tick" % elapsed)
	var piece: Dictionary = model.state.detached[0]
	piece.position = Vector3(model.state.position) + Vector3(100, 0, 0)
	model._classify_debris(1.0)
	assert(not piece.background, "Approaching debris returns to detailed simulation")
	piece.position = Vector3(model.state.position) + Vector3(5000, 0, 0)
	piece.fuel = 1.0
	piece.thrust = 100.0
	model._classify_debris(1.0)
	assert(not piece.background, "Burning debris stays detailed")
	piece.fuel = 0.0
	piece.position = Vector3(0, 100, 0)
	model._classify_debris(1.0)
	assert(not piece.background, "Atmosphere and surface approaches stay detailed")

	var world := World.new()
	root.add_child(world)
	world._last_altitude = Flight.ATMOSPHERE_HEIGHT + 30000.0
	world.camera.position = Vector3(0, 0, 50)
	world.camera.look_at(Vector3.ZERO)
	var node := Node3D.new()
	var flame := Node3D.new()
	var flames: Array[Node3D] = [flame]
	node.add_child(flame)
	node.set_meta("debris_id", piece.id)
	node.set_meta("exhaust_nodes", flames)
	world.add_child(node)
	world._detached_nodes.append(node)
	piece.position = Vector3(10000, 0, 0)
	flame.scale = Vector3.ONE * 7.0
	world._sync_detached({"detached": [piece]}, Vector3.ZERO)
	assert(not node.visible and flame.scale == Vector3.ONE * 7.0, "Distant debris skips exhaust animation")
	piece.position = Vector3(0, 0, 500)
	world._sync_detached({"detached": [piece]}, Vector3.ZERO)
	assert(not node.visible, "Debris behind the camera is culled")
	piece.position = Vector3(0, 0, -1000)
	world._sync_detached({"detached": [piece]}, Vector3.ZERO)
	assert(not node.visible, "Spent stage disappears when its cross section is only a few pixels")
	world._last_altitude = 1000.0
	world._sync_detached({"detached": [piece]}, Vector3.ZERO)
	assert(node.visible, "Low-altitude stages remain visible even when small")
	assert(world.debris_markers.size() == 1 and is_equal_approx(float(world.debris_markers[0].distance), Vector3(piece.position).length()), "Tracking label measures distance from the vessel")
	world._last_altitude = Flight.ATMOSPHERE_HEIGHT + 30000.0
	piece.fuel = 1.0
	piece.thrust = 100.0
	world._sync_detached({"detached": [piece]}, Vector3.ZERO)
	assert(node.visible, "A burning stage retains its visible exhaust at the same distance")
	piece.fuel = 0.0
	piece.position = Vector3.ZERO
	piece.position_remainder = Vector3.ZERO
	world._sync_detached({"detached": [piece]}, Vector3.ZERO)
	assert(node.visible and node.position == Vector3.ZERO, "Debris becomes visible again when in view")
	piece.position = Vector3(0, 3000000, 0)
	piece.position_remainder = Vector3(0, 0.03, 0)
	world._sync_detached({"detached": [piece], "position_remainder": Vector3(0, 0.02, 0)}, Vector3(0, 3000000, 0))
	assert(is_equal_approx(node.position.y, 0.01), "Rendering preserves centimetre-scale relative motion at escape distances")
	var impact_state := {"detached": [], "surface_impacts": [{"position": Vector3(0, 2, 0), "radius": 4.0}]}
	world._sync_detached(impact_state, Vector3.ZERO)
	assert(world._detached_nodes.is_empty() and world.debris_markers.is_empty(), "Destroyed stages lose their meshes and tracking markers")
	assert(node.is_queued_for_deletion() and not node.visible, "Destroyed stage visual is freed")
	assert(world._impact_effects.size() == 1 and impact_state.surface_impacts.is_empty(), "Explosion event is consumed once")
	world._clock += 0.4
	world._sync_detached(impact_state, Vector3(0, 1, 0))
	assert(world._impact_effects[0].node.position == Vector3(0, 1, 0), "Explosion follows the rebased camera origin")
	world._clock += 0.5
	world._sync_detached(impact_state, Vector3.ZERO)
	assert(world._impact_effects.is_empty(), "Explosion expires without persistent debris")
	world.free()
	print("PASS: distant debris trajectories, local reactivation, powered/terrain safety and visual culling")
	quit()
