extends Control
## A drop target that follows an attachment point on the 3D rocket.
var game: Node
var slot := ""
var anchor := Vector3.ZERO
var caption := ""
var offset := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(46, 46)
	size = custom_minimum_size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = caption + " — drop a part here; right-click to remove."

func _process(_delta: float) -> void:
	var point: Vector3 = game.world._rocket.to_global(anchor)
	visible = game.mode == "workshop" and not game.world.camera.is_position_behind(point)
	if visible:
		position = game.world.camera.unproject_position(point) + offset - size * 0.5
		queue_redraw()

func _draw() -> void:
	var data: Variant = get_viewport().gui_get_drag_data()
	var dragging := get_viewport().gui_is_dragging()
	var valid := _can_drop_data(Vector2.ZERO, data)
	var tint := Color("7ce5c0") if valid else Color("91a8aa")
	if dragging and not valid:
		tint = Color("59676c")
	var center := size * 0.5
	draw_circle(center, 18.0, Color(0.03, 0.1, 0.12, 0.65))
	draw_arc(center, 18.0, 0, TAU, 32, tint, 2.5)
	draw_line(center - Vector2(7,0), center + Vector2(7,0), tint, 2)
	draw_line(center - Vector2(0,7), center + Vector2(0,7), tint, 2)

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("rocket_part") is String and game._can_attach(data.rocket_part, slot)

func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO, data):
		game._attach_part(data.rocket_part, slot)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		game._remove_attachment(slot)
		accept_event()
