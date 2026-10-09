extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await game._roll_out()
	await process_frame
	await process_frame
	var clock_panel = game.warp_button.get_parent().get_parent().get_parent()
	var initial_clock_size: Vector2 = clock_panel.size
	game.warp_arrows[2].pressed.emit()
	await process_frame
	await process_frame
	assert(clock_panel.size == initial_clock_size, "First speed selection preserves panel size")
	for index in range(4):
		assert((game.warp_arrows[index].get_theme_color("font_color") == Color("00e75b")) == (index < 3), "3x lights exactly the first three arrows")
	game.warp_arrows[3].pressed.emit()
	assert(game.warp == 4.0 and game.physical_warp, "Fourth arrow selects 4x physical warp")
	assert(game.warp_arrows[3].get_theme_color("font_color") == Color("00e75b"), "Selected arrow is green")
	assert(game.warp_arrows[4].disabled and game.warp_arrows[4].modulate.a < 0.3, "Unavailable high-speed arrow is disabled and faded")
	game.warp_arrows[0].pressed.emit()
	assert(game.warp == 1.0 and not game.physical_warp, "First arrow jumps directly from 4x to 1x")
	var theme_changes := [0]
	for arrow in game.warp_arrows:
		arrow.theme_changed.connect(func(): theme_changes[0] += 1)
	for tick in range(100): game._enforce_warp_limit()
	assert(theme_changes[0] == 0, "Unchanged warp controls do not invalidate UI themes every tick")
	game._set_throttle(0.0)
	for index in range(game.WARP_STEPS.size()):
		assert(not game.warp_arrows[index].disabled, "Pad with zero throttle enables every arrow")
		game.warp_arrows[index].pressed.emit()
		assert(game.warp == game.WARP_STEPS[index], "Every arrow selects its own rate")
		await process_frame
		await process_frame
		assert(clock_panel.size == initial_clock_size, "Every speed preserves panel size")
	game.warp_arrows[0].pressed.emit()
	for speed in [5.0, 10.0, 50.0, 100.0, 1000.0, 10000.0, 100000.0, 1.0]:
		game._cycle_warp()
		assert(game.warp == speed, "Stationary pad permits all high-speed rates")
	game.flight.state.throttle = 0.0
	assert(is_equal_approx(game.flight.step_rails(100000.0 / 60.0, 100000.0), 100000.0 / 60.0), "Stationary surface warp advances the complete frame")
	var ground = game.flight.terrain
	var radial: Vector3 = game.flight.state.position - game.flight.PLANET_CENTER
	assert(absf(radial.normalized().dot(ground.spin_axis())) < 0.00001, "Launch base stays on the equator after time warp")
	assert(radial.distance_to(ground.rotation_at(game.flight.simulation_time()) * game.flight.Surface.LAUNCH_RADIAL) < 0.1, "Parked craft follows the rotating base")
	assert(Vector3(game.flight.state.velocity).distance_to(ground.surface_velocity(radial)) < 0.01, "Launch inherits eastward surface velocity")
	game._set_throttle(1.0)
	game._stage()
	for speed in [2.0, 3.0, 4.0, 1.0]:
		game._cycle_warp()
		assert(game.warp == speed and game.physical_warp)
	var fuel: float = game.flight.state.fuel
	game.flight.step(4.0 / 60.0, {"throttle": 1.0})
	assert(game.flight.state.fuel < fuel, "Physical warp retains fuel consumption")
	game._set_throttle(0.0)
	game.flight.state.position = game.flight.PLANET_CENTER + Vector3.UP * (game.flight.PLANET_RADIUS + 89999.0)
	game.flight.state.status = "flying"
	assert(game.flight.warp_limit() == 1.0, "Rail warp stays unavailable below 90000 m")
	game._enforce_warp_limit()
	assert(game.warp_arrows[4].disabled, "5x arrow stays disabled below 90000 m")
	game.flight.state.position = game.flight.PLANET_CENTER + Vector3.UP * (game.flight.PLANET_RADIUS + game.flight.ATMOSPHERE_HEIGHT)
	assert(game.flight.warp_limit() >= 5.0, "Rail warp is available at 90000 m")
	game._enforce_warp_limit()
	assert(not game.warp_arrows[4].disabled, "5x arrow enables at 90000 m")
	# The 100000x limit requires at least five body radii above the surface.
	# Keep this timing fixture in a circular orbit so it cannot enter a lower limit.
	var orbital_radius: float = game.flight.PLANET_RADIUS + 4000000.0
	game.flight.state.position = game.flight.PLANET_CENTER + Vector3.UP * orbital_radius
	game.flight.state.velocity = Vector3.RIGHT * sqrt(game.flight.MU / orbital_radius)
	game.flight.state.angular_velocity = Vector3.ONE
	game.flight.state.throttle = 0.0
	game.physical_warp = false
	game.warp = 1.0
	game._cycle_warp()
	assert(game.warp == 5.0 and game.flight.state.angular_velocity == Vector3.ZERO)
	var orientation: Basis = game.flight.state.orientation
	fuel = game.flight.state.fuel
	var start: float = game.flight.simulation_time()
	var elapsed: float = game.flight.step_rails(100000.0 / 60.0, 100000.0)
	assert(is_equal_approx(elapsed, 100000.0 / 60.0), "High-speed time is not capped at ten seconds")
	assert(is_equal_approx(game.flight.simulation_time() - start, elapsed))
	assert(game.flight.state.orientation.is_equal_approx(orientation))
	assert(game.flight.state.fuel == fuel)
	game.flight.state.position = Vector3(0, 19000, 0)
	game.flight.state.velocity = Vector3(0, -1000, 0)
	elapsed = game.flight.step_rails(100.0, 5.0)
	assert(elapsed < 2.0, "Atmosphere boundary stops the accelerated frame")
	assert(game.flight.warp_limit() == 1.0)
	game._enforce_warp_limit()
	assert(game.warp == 1.0)
	game._cycle_warp(true)
	assert(game.physical_warp and game.warp == 2.0)
	game.flight.state.boosters_on = true
	game.flight.state.boosters_attached = true
	game.flight.state.booster_fuel = 10.0
	assert(game.flight.warp_limit() == 1.0, "Burning solids prohibit high-speed warp")
	game.flight.state.booster_fuel = 0.0
	game.flight.state.detached = [{"fuel": 1.0, "thrust": 1.0}]
	assert(game.flight.warp_limit() == 1.0, "Burning debris prohibits high-speed warp")
	game.flight.state.detached = []
	game.flight.state.status = "landed"
	game.flight.state.angular_velocity = Vector3.ZERO
	game.flight.state.settling_velocity = Vector3(1, 0, 0)
	assert(game.flight.warp_limit() == 1.0, "Sliding surface craft cannot use high-speed warp")
	game.flight.state.settling_velocity = Vector3.ZERO
	assert(game.flight.warp_limit() == 100000.0)
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	print("PASS: high-speed rates, physical thrust, frozen attitude, elapsed time and atmosphere boundary")
	quit()
