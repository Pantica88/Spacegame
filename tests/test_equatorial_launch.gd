extends SceneTree
const Flight = preload("res://scripts/flight_model.gd")
const Surface = preload("res://scripts/planet_surface.gd")
const World = preload("res://scripts/world_view.gd")
const Instruments = preload("res://scripts/instruments.gd")
var failures: Array[String] = []
func check(condition: bool, message: String):
 if not condition: failures.append(message)
func _initialize():
 run.call_deferred()
func run():
 var flight = Flight.new()
 var terrain = flight.terrain
 var period: float = terrain.definition.rotation_seconds
 check(terrain.spin_axis() == Vector3.UP, "Original planet axis is unchanged")
 check(terrain.rotation_at(period * 0.25).is_equal_approx(Basis(Vector3.UP, PI * 0.5)), "Planet still spins about +Y")
 check(Instruments.surface_frame(Vector3.BACK).z.is_equal_approx(Vector3.UP), "Navball north matches planet north at equator")
 var world = World.new()
 root.add_child(world)
 world.set_mode("flight")
 for interval in [0.0, 1.0, period * 0.25, period * 0.5]:
  var before: Vector3 = flight.state.position
  flight.advance_prelaunch_time(interval)
  var radial: Vector3 = flight.state.position - flight.PLANET_CENTER
  check(absf(radial.normalized().dot(Vector3.UP)) < 0.00001, "Base stays on equator")
  if interval > 0.0: check(before.distance_to(flight.state.position) > 100.0, "Parked craft moves with rotating planet")
  check(Vector3(flight.state.velocity).distance_to(terrain.surface_velocity(radial)) < 0.01, "Rocket inherits surface speed")
  check(absf(float(flight.telemetry().speed)) < 0.01, "Parked rocket has zero airspeed")
  world.sync_flight(flight.telemetry(), 0.0)
  check(world._landscape.position.length() < 0.1, "Rendered base stays under parked craft")
  check(world._landscape.basis.is_equal_approx(flight.state.orientation), "Rocket and base share launch orientation")
  check(world._planet.basis.is_equal_approx(terrain.rotation_at(flight.simulation_time())), "Rendered planet keeps original spin")
 for wait_time in [0.0, 10.0, period * 0.25]:
  flight.reset(preload("res://scripts/parts.gd").default_design())
  flight.advance_prelaunch_time(wait_time)
  var fuel: float = flight.state.fuel
  flight.ignite()
  for tick in range(180): flight.step(1.0 / 60.0, {"throttle":1.0, "sas":true})
  var state: Dictionary = flight.telemetry()
  print("Launch at ", wait_time, ": altitude=", state.altitude, " clearance=", state.terrain_clearance, " status=", state.status)
  check(state.status == "flying" and state.terrain_clearance > 1.0, "Rocket lifts off after wait of %s" % wait_time)
  check(state.fuel < fuel, "Engine burns fuel")
 world.free()
 var game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 await game._roll_out()
 var start_position: Vector3 = game.flight.state.position
 game._physics_process(1.0)
 check(is_equal_approx(game.flight.simulation_time(), 1.0), "Game loop advances world time")
 check(start_position.distance_to(game.flight.state.position) > 100.0, "Game loop moves the base")
 game._toggle_map()
 game._physics_process(1.0)
 game.map_instrument._process(0.01)
 check(game.map_instrument.globe.basis.is_equal_approx(game.world._planet.basis.scaled(Vector3.ONE * 0.001)), "Map and flight share the moving planet")
 game._set_throttle(0.0)
 game.warp = 1000.0
 game._physics_process(0.1)
 check(is_equal_approx(game.flight.simulation_time(), 102.0), "Time warp advances base and planet")
 game._toggle_map()
 check(game.world._landscape.position.length() < 0.1, "Returning from map keeps the base beneath the rocket")
 game.warp = 1.0
 game._set_throttle(1.0)
 game._stage()
 for tick in range(180): game._physics_process(1.0 / 60.0)
 check(game.flight.state.altitude > 1.0 and game.flight.state.status == "flying", "Game loop launches after map and time warp")
 game.sound.shutdown()
 game.free()
 if failures.is_empty():
  print("PASS: original axis, equatorial base, moving surface, navball, rendering and liftoff")
  quit(0)
 else:
  for message in failures: push_error(message)
  quit(1)
