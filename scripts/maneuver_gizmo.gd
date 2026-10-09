extends "res://scripts/instruments.gd"
## Screen-sized orbital handles; reuses the game's own navball glyphs.
signal component_changed(axis: int, value: float)
signal drag_started
const KEYS := ["prograde", "retrograde", "normal", "antinormal", "radial_out", "radial_in"]
const NAMES := ["Prograde", "Retrograde", "Normal", "Anti-normal", "Radial out", "Radial in"]
var handles: Array[Dictionary] = []
var center := Vector2.ZERO
var node_screen := Vector2.ZERO
var components := Vector3.ZERO
var dragging := -1
var hovered := -1
var _drag_value := 0.0
var _drag_start_value := 0.0
var _drag_direction := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func():
		if not is_visible_in_tree(): dragging = -1
	)

func set_frame(point: Vector3, directions: Array, camera: Camera3D, values: Vector3, bounds: Rect2) -> void:
	components = values
	if dragging >= 0:
		queue_redraw()
		return
	node_screen = camera.unproject_position(point)
	center = Vector2(clampf(node_screen.x, bounds.position.x + 105, bounds.end.x - 105), clampf(node_screen.y, bounds.position.y + 110, bounds.end.y - 130))
	handles.clear()
	var angles: Array[float] = []
	for axis in range(3):
		var projected := Vector2(Vector3(directions[axis]).dot(camera.basis.x), -Vector3(directions[axis]).dot(camera.basis.y))
		var angle := projected.angle() if projected.length() > 0.15 else float(axis) * PI / 3.0
		# Near edge-on, spread overlapping projected axes so all six remain usable.
		if axis > 0:
			var separation := PI
			for previous in angles: separation = minf(separation, acos(clampf(absf(cos(angle - previous)), 0.0, 1.0)))
			if separation < 0.42:
				var best := -1.0
				for offset in [PI/3.0, -PI/3.0, PI/2.0]:
					var candidate: float = angles[0] + offset
					var clearance := PI
					for previous in angles: clearance = minf(clearance, acos(clampf(absf(cos(candidate - previous)), 0.0, 1.0)))
					if clearance > best:
						best = clearance
						angle = candidate
		angles.append(angle)
		for sign_value in [1.0, -1.0]:
			var direction: Vector2 = Vector2.from_angle(angle) * float(sign_value)
			handles.append({"point": center + direction * 78.0, "direction": direction, "axis": axis, "sign": sign_value})
	queue_redraw()

func hit_test(point: Vector2) -> int:
	if not is_visible_in_tree(): return -1
	for index in range(handles.size()):
		if point.distance_to(handles[index].point) <= 20.0: return index
	return -1

func begin_drag(index: int) -> void:
	if index < 0 or index >= handles.size(): return
	dragging = index
	_drag_value = components[int(handles[index].axis)]
	_drag_start_value = _drag_value
	_drag_direction = handles[index].direction
	drag_started.emit()
	queue_redraw()

func drag_by(relative: Vector2, fine: bool = false) -> void:
	if dragging < 0: return
	var handle: Dictionary = handles[dragging]
	_drag_value = clampf(_drag_value + relative.dot(_drag_direction) * float(handle.sign) * (0.1 if fine else 1.0), -5000.0, 5000.0)
	components[int(handle.axis)] = _drag_value
	component_changed.emit(int(handle.axis), _drag_value)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if dragging < 0: return
	if event is InputEventMouseMotion:
		var local_event := make_input_local(event) as InputEventMouseMotion
		drag_by(local_event.relative, event.shift_pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = -1
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		component_changed.emit(int(handles[dragging].axis), _drag_start_value)
		dragging = -1
		queue_redraw()
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if handles.is_empty(): return
	if center.distance_to(node_screen) > 1.0: draw_line(node_screen, center, Color("d5a0ff"), 1.0, true)
	draw_circle(center, 23.0, Color("101c30"))
	draw_arc(center, 23, 0, TAU, 48, Color("d5a0ff"), 1.5, true)
	draw_circle(center, 4, Color("f3f8ff"))
	for index in range(handles.size()):
		var handle: Dictionary = handles[index]
		var color := marker_color(KEYS[index])
		var selected := dragging == index or hovered == index
		draw_line(center + Vector2(handle.direction) * 25, handle.point, Color(color, 0.85), 2.5 if selected else 1.5, true)
		draw_circle(handle.point, 19, Color("101c30"))
		draw_arc(handle.point, 19, 0, TAU, 32, color if selected else Color(color, 0.55), 2 if selected else 1, true)
		_draw_marker(KEYS[index], handle.point, color, 1.15)
	var active := dragging if dragging >= 0 else hovered
	var caption := "Drag a symbol · Shift: fine"
	if active >= 0:
		caption = "%s  %+.1f m/s" % [NAMES[active], components[int(handles[active].axis)] * float(handles[active].sign)]
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_rect(Rect2(center + Vector2(-width/2-6, 105), Vector2(width+12, 24)), Color(0.02,0.04,0.07,0.94))
	draw_string(font, center + Vector2(-width/2, 122), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("eef2e9"))
