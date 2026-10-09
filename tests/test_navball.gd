extends SceneTree
const Instruments = preload("res://scripts/instruments.gd")
const Physics = preload("res://scripts/physics_math.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(Instruments.project_direction(Vector3.ZERO, Basis.IDENTITY).is_empty())
	assert(Instruments.project_direction(Vector3(INF, 0, 0), Basis.IDENTITY).is_empty())
	assert(Instruments.project_direction(Vector3.UP, Basis.IDENTITY).point == Vector2.ZERO)
	assert(Instruments.project_direction(Vector3.RIGHT, Basis.IDENTITY).point == Vector2.RIGHT)
	assert(Instruments.project_direction(Vector3.FORWARD, Basis.IDENTITY).point == Vector2.UP)
	var rear := Instruments.project_direction(Vector3.DOWN, Basis.IDENTITY)
	assert(rear.behind and rear.point.length() == 1.0)
	var turn := Basis(Vector3.FORWARD, PI / 2)
	assert(Instruments.project_direction(turn.y, turn).point.is_zero_approx())
	assert(Instruments.project_direction(turn.x, turn).point.is_equal_approx(Vector2.RIGHT))
	# Sphere markings share the same vessel projection as guidance markers.
	for up in [Vector3.UP, Vector3.FORWARD, Vector3(1, 2, 3).normalized()]:
		var frame := Instruments.surface_frame(up)
		assert(frame.x.is_normalized() and frame.z.is_normalized())
		assert(absf(frame.x.dot(up)) < 0.00001)
		assert(Instruments.sphere_direction(PI / 2, 0, frame).is_equal_approx(up))
		assert(absf(Instruments.sphere_direction(0, 1.2, frame).dot(up)) < 0.00001)
		var level := Basis(frame.x, frame.z, -up)
		assert(Instruments.project_direction(up, level).point.is_equal_approx(Vector2.UP))
		var rolled := level * Basis(Vector3.UP, PI / 2)
		assert(absf(Instruments.project_direction(up, rolled).point.x) > 0.999)
	# Nearly coincident rim/horizon chords used to cross during upright ascent.
	for radius in [48.0, 96.0, 180.0]:
		for pitch in [-1.0, -0.9999, -0.5, 0.0, 0.5, 0.98, 0.999, 0.9998, 0.9999, 1.0]:
			for roll in range(0, 360, 7):
				var angle := deg_to_rad(float(roll))
				var lateral := sqrt(maxf(0.0, 1.0 - pitch * pitch))
				var up := Vector3(cos(angle)*lateral, pitch, sin(angle)*lateral)
				var polygon := Instruments.attitude_ground_polygon(Vector2(180,160), radius, up)
				if polygon.is_empty():
					assert(radius * (1.0 - pitch) < 0.05)
				else:
					assert(not Geometry2D.triangulate_polygon(polygon).is_empty(), "Attitude ground must triangulate at every pitch and roll")
	var ball := Instruments.new()
	ball.size = Vector2(360, 320)
	root.add_child(ball)
	assert(ball.sas_button.get_parent() == ball, "SAS belongs to the navball")
	var toggles: Array[bool] = []
	ball.sas_toggled.connect(func(): toggles.append(true))
	ball.sas_button.pressed.emit()
	assert(toggles.size() == 1)
	# Exercise the gauge using simulation telemetry, including the atmospheric edge.
	var flight = preload("res://scripts/flight_model.gd").new()
	var previous_density := 1.0
	for altitude in [0.0, 4000.0, 12000.0, 18000.0, 100000.0]:
		flight.state.position = Vector3(0, altitude, 0)
		ball.state = flight.telemetry()
		var density := ball.atmosphere_fraction()
		assert(density >= 0.0 and density <= previous_density)
		if altitude == 0.0: assert(is_equal_approx(density, 1.0))
		if altitude >= float(ball.state.atmosphere_height): assert(is_zero_approx(density))
		previous_density = density
	ball.state = {"air_density": 0.0, "sea_level_air_density": 0.0, "atmosphere_height": 0.0}
	assert(is_zero_approx(ball.atmosphere_fraction()), "Airless bodies select the vacuum band")
	ball.state = {"air_density": 0.4, "sea_level_air_density": 0.8, "atmosphere_height": 30000.0}
	assert(is_equal_approx(ball.atmosphere_fraction(), 0.5), "Gauge uses the local body's density")
	var received: Array[float] = []
	ball.throttle_changed.connect(func(value: float): received.append(value))
	var arc_radius := minf(ball.size.x, ball.size.y) * 0.30 + 59.0
	var center := ball.size * 0.5
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center + Vector2.from_angle(deg_to_rad(135)) * arc_radius
	ball._gui_input(press)
	assert(received.size() == 1 and is_zero_approx(received[-1]))
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.position = center + Vector2.LEFT * arc_radius
	ball._gui_input(drag)
	assert(is_equal_approx(received[-1], 0.5))
	drag.position = center + Vector2.from_angle(deg_to_rad(225)) * arc_radius
	ball._gui_input(drag)
	assert(is_equal_approx(received[-1], 1.0))
	press.pressed = false
	ball._gui_input(press)
	var count := received.size()
	ball._gui_input(drag)
	assert(received.size() == count)
	press.pressed = true
	press.position = center
	ball._gui_input(press)
	assert(received.size() == count)

	ball.state = Physics.orbital_elements(Vector3.UP * 60000, Vector3.RIGHT * 700)
	ball.state.position = Vector3(12, 34, 56)
	var directions := ball.guidance_directions()
	assert(directions.target == Vector3.ZERO and directions.maneuver == Vector3.ZERO)
	ball.state.target_position = ball.state.position + Vector3.FORWARD * 100
	ball.state.maneuver_direction = Vector3.UP * 20
	directions = ball.guidance_directions()
	assert(directions.target == -directions.anti_target)
	assert(directions.target == Vector3.FORWARD * 100)
	assert(directions.radial_out.is_equal_approx(Vector3.UP))
	# Draw every glyph on the face and exercise opposite-hemisphere cues.
	for key in directions:
		var nose: Vector3 = directions[key].normalized()
		var side := nose.cross(Vector3.ONE).normalized()
		ball.state.orientation = Basis(side, nose, side.cross(nose))
		ball.queue_redraw()
		await process_frame
		await process_frame
	ball.free()
	print("PASS: navball projection, rolled attitude, guidance markers, SAS signal, throttle drag and atmosphere telemetry")
	quit()
