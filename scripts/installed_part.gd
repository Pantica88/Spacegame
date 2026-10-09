extends Control
var game: Node
var part_id := ""
var anchor := Vector3.ZERO
var hit_size := Vector2(96, 96)

func _ready() -> void:
	size = hit_size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Drag into a stage to assign activation · Drag to parts list to remove symmetry group · Shift-drag removes one · Delete removes group · R rotates"

func _process(_delta: float) -> void:
	var camera: Camera3D = game.world.camera
	var point: Vector3 = game.world._rocket.to_global(anchor)
	var center := camera.unproject_position(point)
	if part_id.begins_with("tank_"):
		# Fit the picker to the tank at the current zoom so tall stacks do not
		# cover one another with the original fixed 128-pixel hit regions.
		var top := camera.unproject_position(game.world._rocket.to_global(anchor + Vector3(0, 1.025, 0)))
		var bottom := camera.unproject_position(game.world._rocket.to_global(anchor - Vector3(0, 1.025, 0)))
		var edge := camera.unproject_position(point + camera.global_basis.x * 0.95)
		size = Vector2(clampf(center.distance_to(edge) * 2.0, 12.0, hit_size.x), clampf(top.distance_to(bottom), 12.0, hit_size.y))
	position = center - size * 0.5

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
