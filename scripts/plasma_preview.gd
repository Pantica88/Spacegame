extends Node3D
## A visual wind tunnel using the same hull plasma and wake as normal flight.
const World = preload("res://scripts/world_view.gd")
var world: Node3D
var orientation := Basis.IDENTITY
var airspeed := 2000.0
var travel_heading := 0.0
var heat := 1.0
var turn_rate := 35.0
var auto_turn := true
var paused := false
var craft_index := 0
var speed_slider: HSlider
var heading_slider: HSlider
var heat_slider: HSlider
var turn_slider: HSlider
var auto_check: CheckBox
var pause_button: Button
var craft_picker: OptionButton
var readout: Label
var _camera_drag := false

func _ready() -> void:
	world = World.new()
	add_child(world)
	world.set_mode("flight")
	_build_ui()
	_reset()

func _process(delta: float) -> void:
	var dt := 0.0 if paused else minf(delta, 0.05)
	if dt > 0.0:
		var steering := Vector3(float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)), float(Input.is_physical_key_pressed(KEY_A)) - float(Input.is_physical_key_pressed(KEY_D)), float(Input.is_physical_key_pressed(KEY_Q)) - float(Input.is_physical_key_pressed(KEY_E)))
		if steering.length_squared() > 0.0:
			auto_check.button_pressed = false
			orientation = orientation * Basis(steering.normalized(), deg_to_rad(turn_rate) * dt)
		elif auto_turn:
			orientation = Basis(Vector3(0.16, 0.20, 1.0).normalized(), deg_to_rad(turn_rate) * dt) * orientation
		orientation = orientation.orthonormalized()
	var travel_velocity := Vector3.RIGHT.rotated(Vector3.BACK, deg_to_rad(travel_heading)) * airspeed
	world.sync_flight({"position": Vector3(0, 12000, 0), "altitude": 12000.0,
		"orientation": orientation, "status": "flying", "simulation_time": 0.0,
		"engine_on": false, "fuel": 0.0, "boosters_attached": craft_index == 2,
		"capsule_only": craft_index == 1, "chute_deployed": false,
		"heat_glow": heat, "plasma_glow": heat, "heating_rate": 180.0 if airspeed > 0.0 else 0.0,
		"air_velocity": travel_velocity, "velocity": travel_velocity}, dt)
	readout.text = "%s  •  %.0f m/s\nHeat %.0f%%  •  Turn %.0f°/s\nTravel heading %+.0f°" % ["PAUSED" if paused else "RUNNING", airspeed, heat * 100.0, turn_rate, travel_heading]

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size.x = 290
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.075, 0.93)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	_label(column, "PLASMA FLIGHT TEST", 22)
	_label(column, "Visual preview • heat held steady\nNo launch or landing required.", 14)
	readout = _label(column, "", 17)
	_label(column, "Airspeed", 15)
	speed_slider = _slider(column, 0, 2000, 25, airspeed)
	speed_slider.value_changed.connect(func(value): airspeed = value)
	_label(column, "Travel direction (independent of nose)", 14)
	heading_slider = _slider(column, -180, 180, 1, travel_heading)
	heading_slider.value_changed.connect(func(value): travel_heading = value)
	_label(column, "Heat glow", 15)
	heat_slider = _slider(column, 0, 1, 0.05, heat)
	heat_slider.value_changed.connect(func(value): heat = value)
	_label(column, "Turning speed", 15)
	turn_slider = _slider(column, 5, 120, 5, turn_rate)
	turn_slider.value_changed.connect(func(value): turn_rate = value)
	auto_check = CheckBox.new()
	auto_check.text = "Automatic tumble  [T]"
	auto_check.focus_mode = Control.FOCUS_NONE
	auto_check.toggled.connect(func(enabled): auto_turn = enabled)
	column.add_child(auto_check)
	craft_picker = OptionButton.new()
	for title in ["Rocket", "Recovery capsule", "Rocket with boosters"]: craft_picker.add_item(title)
	craft_picker.focus_mode = Control.FOCUS_NONE
	craft_picker.item_selected.connect(_set_craft)
	column.add_child(craft_picker)
	var poses := HBoxContainer.new()
	column.add_child(poses)
	_button(poses, "Nose first", func(): _set_pose(-PI / 2.0))
	_button(poses, "Sideways", func(): _set_pose(0.0))
	_button(poses, "Tail first", func(): _set_pose(PI / 2.0))
	pause_button = _button(column, "Pause  [SPACE]", _toggle_pause)
	_button(column, "Reset  [R]", _reset)
	_label(column, "W / S  pitch     A / D  yaw\nQ / E  roll\nManual steering stops auto tumble.\n\nRight drag  orbit camera\nScroll  zoom     Esc  exit", 14)

func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _slider(parent: Node, minimum: float, maximum: float, step_size: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.value = value
	slider.focus_mode = Control.FOCUS_NONE
	parent.add_child(slider)
	return slider

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _set_craft(index: int) -> void:
	craft_index = index
	world.set_design({"tanks": 2, "engine": "kestrel", "boosters": index == 2, "fins": true})
	world._distance = 21.0 if index == 1 else 29.0

func _set_pose(angle: float) -> void:
	auto_check.button_pressed = false
	orientation = Basis(Vector3.BACK, angle + deg_to_rad(travel_heading))

func _toggle_pause() -> void:
	paused = not paused
	pause_button.text = "Resume  [SPACE]" if paused else "Pause  [SPACE]"

func _reset() -> void:
	paused = false
	pause_button.text = "Pause  [SPACE]"
	heading_slider.value = 0.0
	speed_slider.value = speed_slider.max_value
	heat_slider.value = heat_slider.max_value
	turn_slider.value = 35.0
	auto_check.button_pressed = true
	craft_picker.select(0)
	_set_craft(0)
	orientation = Basis(Vector3.BACK, -PI / 2.0)
	world._yaw = 0.62
	world._pitch = 0.10

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: _toggle_pause()
			KEY_T: auto_check.button_pressed = not auto_check.button_pressed
			KEY_R: _reset()
			KEY_ESCAPE: get_tree().quit()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: _camera_drag = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: world.zoom_camera(-1.0)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: world.zoom_camera(1.0)
	if event is InputEventMouseMotion and _camera_drag:
		world.orbit_camera(event.relative)
