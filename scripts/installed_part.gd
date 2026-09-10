extends Control
var game: Node
var part_id := ""
var anchor := Vector3.ZERO
var hit_size := Vector2(96, 96)

func _ready() -> void:
	size = hit_size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Drag back to the parts list to remove · Delete removes · R rotates"

func _process(_delta: float) -> void:
	position = game.world.camera.unproject_position(game.world._rocket.to_global(anchor)) - size * 0.5

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		game.selected_part = part_id
		game.highlight_action = "part:" + part_id
		game.craft_caption.text = part_id.replace("_", " ") + "  ·  R rotate / Delete remove"
		accept_event()

func _get_drag_data(_position: Vector2) -> Variant:
	game._begin_return_drag(part_id)
	var native_preview := Control.new()
	native_preview.custom_minimum_size = Vector2.ONE
	native_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_drag_preview(native_preview)
	return {"installed_part": part_id}

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_instance_valid(game):
		game._end_return_drag()

func _can_drop_data(position: Vector2, data: Variant) -> bool:
	if data is Dictionary and data.get("installed_part") is String:
		game._update_return_drag(str(data.installed_part), global_position + position)
		return true
	if data is Dictionary and data.get("rocket_part") is String:
		game._update_build_drag(str(data.rocket_part), global_position + position)
		return true
	return false

func _drop_data(position: Vector2, data: Variant) -> void:
	if data is Dictionary and data.get("installed_part") is String:
		game._finish_return_drag(str(data.installed_part), global_position + position)
		return
	if data is Dictionary and data.get("rocket_part") is String:
		game._finish_build_drag(str(data.rocket_part), global_position + position)
