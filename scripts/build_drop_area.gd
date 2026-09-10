extends Control
## Invisible assembly canvas. The dragged mesh supplies all placement feedback.

var game: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not get_viewport().gui_is_dragging():
			game._deselect_part()
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_instance_valid(game):
		game._clear_build_drag()


func _can_drop_data(position: Vector2, data: Variant) -> bool:
	if data is Dictionary and data.get("installed_part") is String:
		game._update_return_drag(str(data.installed_part), global_position + position)
		return true
	if not data is Dictionary or not data.get("rocket_part") is String:
		return false
	game._update_build_drag(str(data.rocket_part), global_position + position)
	# Accept the canvas so the preview can turn red away from a connection.
	return true


func _drop_data(position: Vector2, data: Variant) -> void:
	if data is Dictionary and data.get("installed_part") is String:
		game._finish_return_drag(str(data.installed_part), global_position + position)
		return
	if data is Dictionary and data.get("rocket_part") is String:
		game._finish_build_drag(str(data.rocket_part), global_position + position)
