extends PanelContainer
var game: Node
var index := 0

class Action extends Label:
	var game: Node
	var action := ""
	func _get_drag_data(_position: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = text
		set_drag_preview(preview)
		return {"stage_action": action}
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		mouse_entered.connect(func(): game.highlight_action = action)
		mouse_exited.connect(func(): game.highlight_action = "")

func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("203138")
	style.border_color = Color("456166")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var title := Label.new()
	title.text = "⋮ STAGE %02d" % (index + 1)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)
	for step in [-1, 1]:
		var button := Button.new()
		button.text = "↑" if step == -1 else "↓"
		button.disabled = index + step < 0 or index + step >= game.design.assembly.stages.size()
		button.pressed.connect(func(): game._move_stage(index, index + step))
		row.add_child(button)
	var actions: Array = game.design.assembly.stages[index]
	for action in actions:
		var label := Action.new()
		label.game = game
		label.action = action
		var symbol := "◆" if action.begins_with("separate") else ("◉" if action.begins_with("ignite") else "◠")
		label.text = symbol + " " + game.Parts.Craft.ACTION_LABELS[action]
		label.add_theme_font_size_override("font_size", 14)
		label.custom_minimum_size.y = 30
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
	if actions.is_empty():
		var remove := Button.new()
		remove.text = "Drop action here · × Remove"
		remove.add_theme_font_size_override("font_size", 12)
		remove.pressed.connect(func(): game._delete_stage(index))
		box.add_child(remove)

func _get_drag_data(_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = "Stage %d" % (index + 1)
	set_drag_preview(preview)
	return {"stage_group": index}

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data.has("stage_action") or data.has("stage_group"))

func _drop_data(_position: Vector2, data: Variant) -> void:
	if data.has("stage_action"): game._move_action(data.stage_action, index)
	elif data.has("stage_group"): game._move_stage(data.stage_group, index)
