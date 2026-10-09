extends SceneTree
const World = preload("res://scripts/world_view.gd")
const Flight = preload("res://scripts/flight_model.gd")
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var flight := Flight.new()
	flight.reset({"boosters":true,"parachute":true})
	flight.state.status = "flying"
	flight.state.position = Vector3(0,1000,0)
	flight._separate_boosters()
	flight._separate_core()
	var world := World.new()
	world.set_design({"boosters":true,"parachute":true})
	root.add_child(world)
	world.set_mode("flight")
	world.sync_flight(flight.telemetry(),0.0)
	assert(world.debris_markers.size() == flight.state.detached.size(), "Every released booster and core receives a marker")
	for marker in world.debris_markers:
		assert(marker.has("basis") and marker.has("half_extents"), "Each marker fits its own rotating body")
	flight.state.chute_deployed = true
	for frame in range(90):
		world.sync_flight(flight.telemetry(),1.0/60.0)
	assert(world._parachute_module.cap_released)
	assert(world.debris_markers.size() == flight.state.detached.size(), "Tethered nose cap stays untracked near the vessel")
	world.set_design({"boosters":false})
	assert(world.debris_markers.is_empty(), "Reset removes old tracking squares")
	world.free()
	print("PASS: released stages receive fitted markers without tracking a nearby tethered nose cap")
	quit()
