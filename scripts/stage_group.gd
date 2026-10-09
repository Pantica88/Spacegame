extends PanelContainer
## One activation block. Child controls forward drops to the entire block.
var game: Node
var index := 0
var flight_mode := false
var indicators: Array = []
var heading: Label
var _style: StyleBoxFlat

class Action extends Label:
	var game: Node
	var action := ""
	var members: Array = []
	func _get_drag_data(_position: Vector2) -> Variant:
		var preview := Label.new()
		var together := not Input.is_key_pressed(KEY_SHIFT)
		var count: int = members.size() if together else 1
		preview.text = text + (" · %d symmetry items" % count if count > 1 else "")
		set_drag_preview(preview)
		return {"stage_action": action, "together": together}
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		mouse_entered.connect(func(): game.highlight_action = action)
		mouse_exited.connect(func(): game.highlight_action = "")

func _ready() -> void:
	if flight_mode:
		size_flags_horizontal = Control.SIZE_SHRINK_END
	_style = StyleBoxFlat.new()
	_style.bg_color = Color("050811") if flight_mode else Color("203138")
	_style.border_color = Color("456166")
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(3 if flight_mode else 8)
	_style.set_content_margin_all(3 if flight_mode else 10)
	add_theme_stylebox_override("panel", _style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3 if flight_mode else 8)
	add_child(box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var title := Label.new()
	heading = title
	title.text = "STAGE %02d" % (index + 1)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_DRAG
	title.tooltip_text = "Drag this header onto another block to move this stage"
	if flight_mode and index < int(game.flight.state.stage_index):
		title.mouse_default_cursor_shape = Control.CURSOR_ARROW
		title.tooltip_text = "Activated stage — remaining attached parts"
	title.set_drag_forwarding(_get_drag_data, _can_drop_data, _drop_data)
	row.add_child(title)
	for step in ([] if flight_mode else [-1, 1]):
		var button := Button.new()
		button.text = "↑" if step == -1 else "↓"
		button.tooltip_text = "Activate earlier" if step == -1 else "Activate later"
		var destination: int = index + step
		if flight_mode:
			while destination >= 0 and destination < game.flight.staging_groups().size() and game.flight.attached_stage_actions(destination).is_empty(): destination += step
			button.disabled = not game.flight.can_reorder_stage(index, destination)
		else:
			button.disabled = destination < 0 or destination >= game.design.assembly.stages.size()
		button.pressed.connect(func(): game._move_stage(index, destination))
		button.set_drag_forwarding(Callable(), _can_drop_data, _drop_data)
		row.add_child(button)
	var actions: Array = game.flight.attached_stage_actions(index) if flight_mode else game.design.assembly.stages[index]
	var hint := Label.new()
	hint.text = "%d items · activate together" % actions.size()
	hint.add_theme_font_size_override("font_size", 12)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)
	hint.visible = not flight_mode
	for members in game._stage_display_groups(actions):
		var action: String = members[0]
		var card := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color("0c101c") if flight_mode else Color("15262e")
		card_style.set_corner_radius_all(5)
		card_style.set_content_margin_all(3 if flight_mode else 8)
		card.add_theme_stylebox_override("panel", card_style)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(card)
		var content := VBoxContainer.new()
		card.add_child(content)
		var item_row := HBoxContainer.new()
		content.add_child(item_row)
		var icon = preload("res://scripts/stage_icon.gd").new()
		icon.kind = "parachute" if action.begins_with("deploy:") else ("booster" if action == "ignite:boosters" else ("engine" if action.begins_with("ignite:") else ("radial_separator" if action.contains("separator") or action == "separate:boosters" else "separator")))
		item_row.add_child(icon)
		var count: int = members.size()
		if action.ends_with(":boosters"):
			count = game.Parts.Craft.radial_instances(game.design, "boosters").size()
		var badge := Label.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.text = "×%d" % count
		badge.visible = count > 1
		item_row.add_child(badge)
		var label := Action.new() if not flight_mode else Label.new()
		if not flight_mode:
			label.game = game
			label.action = action
			label.members = members
			label.set_drag_forwarding(label._get_drag_data, _can_drop_data, _drop_data)
			item_row.set_drag_forwarding(label._get_drag_data, _can_drop_data, _drop_data)
		label.text = game.Parts.Craft.action_label(action, game.design.assembly)
		if count > 1 and " (engine" in label.text: label.text = label.text.get_slice(" (engine", 0)
		label.tooltip_text = "\n".join(members) + ("\nDrag symmetry group · Shift-drag moves one item" if not flight_mode else "")
		label.add_theme_font_size_override("font_size", 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_row.add_child(label)
		label.visible = not flight_mode
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.tooltip_text = label.text
		if flight_mode: card.set_drag_forwarding(Callable(), _can_drop_data, _drop_data)
		var indicator := {"members": members, "icon": icon, "label": label, "name": label.text, "card": card}
		if action.begins_with("ignite:"):
			var bar := ProgressBar.new()
			bar.custom_minimum_size.y = 4 if flight_mode else 10
			bar.show_percentage = false
			bar.value = 100
			content.add_child(bar)
			var fuel := Label.new()
			fuel.add_theme_font_size_override("font_size", 11)
			fuel.clip_text = true
			content.add_child(fuel)
			fuel.visible = not flight_mode
			indicator["bar"] = bar
			indicator["fuel"] = fuel
		indicators.append(indicator)
	if flight_mode: return
	update_flight({})
	var target := Label.new()
	target.text = "+ Drop activation item here" if actions.size() < game.Parts.Craft.MAX_STAGE_ACTIONS else "Block full"
	target.custom_minimum_size.y = 36
	target.add_theme_font_size_override("font_size", 12)
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(target)

func _has_active_fuel(state: Dictionary) -> bool:
	for item in indicators:
		for action in item.members:
			if action == "ignite:boosters":
				if state.get("boosters_on", false) and state.get("boosters_attached", true) and float(state.get("booster_fuel", 0.0)) > 0.0:
					return true
			elif action.begins_with("ignite:"):
				var id: String = action.get_slice(":", 1)
				if state.get("engine_on", false) and id in state.get("active_engines", []) and id not in state.get("removed_parts", []) and float(state.get("engine_fuel", {}).get(id, state.get("fuel", 0.0))) > 0.0:
					return true
	return false

func update_flight(state: Dictionary) -> void:
	var current := int(state.get("stage_index", 0))
	var active := _has_active_fuel(state) or (current == 0 and index == 0)
	if flight_mode:
		custom_minimum_size.x = 216 if active else 72
		heading.text = "%s%02d" % ["✓" if index < current else ("▶" if index == current else ""), index + 1]
		_style.border_color = Color("00e75b") if active else Color("6255ad")
	for item in indicators:
		if flight_mode and item.has("bar"):
			item.bar.visible = active
			item.bar.custom_minimum_size.y = 8
			item.fuel.visible = active
		var action: String = item.members[0]
		if action.begins_with("deploy:"):
			var deployed := bool(state.get("chute_deployed", false))
			var unavailable: bool = not state.is_empty() and not deployed and (bool(state.get("chute_cut", false)) or (state.get("status", "ready") != "ready" and not state.get("chute_safe", false)))
			item.icon.tint = Color("8be0c5") if deployed else (Color("ef746f") if unavailable else Color("c4cece"))
			item.label.text = item.name + (" · Deployed" if deployed else (" · Unavailable" if unavailable else " · Idle"))
			item.card.tooltip_text = item.label.text
			item.icon.queue_redraw()
		if not item.has("bar"): continue
		var capacity := 0.0
		var remaining := 0.0
		var details: PackedStringArray = []
		if action == "ignite:boosters":
			capacity = game.Parts.BOOSTER_FUEL_MASS * game.Parts.Craft.radial_instances(game.design, "boosters").size() * 0.5
			remaining = float(state.get("booster_fuel", capacity)) if state.get("boosters_attached", true) else 0.0
		else:
			for member in item.members:
				var id: String = member.get_slice(":", 1)
				var total := 0.0
				if flight_mode: total = float(game.stage_fuel_capacity.get(id, 0.0))
				else:
					var cursor := id
					while true:
						var parts: Array = game.design.assembly.parts.filter(func(part): return part.id == cursor)
						if parts.is_empty(): break
						cursor = parts[0].parent
						var parents: Array = game.design.assembly.parts.filter(func(part): return part.id == cursor and part.kind == "tank")
						if parents.is_empty(): break
						total += game.Parts.TANK_FUEL_MASS
				var fuel := float(state.get("engine_fuel", {}).get(id, state.get("fuel", total)))
				if id in state.get("removed_parts", []) or state.get("capsule_only", false): fuel = 0.0
				capacity += total
				remaining += fuel
				details.append("%s: %.0f / %.0f kg" % [id, fuel, total])
		item.bar.value = remaining / capacity * 100.0 if capacity > 0 else 0.0
		item.fuel.text = "%s · %.0f%% · %.0f / %.0f kg" % ["Solid fuel" if action == "ignite:boosters" else "Fuel", item.bar.value, remaining, capacity]
		item.bar.tooltip_text = "\n".join(details)
		item.fuel.tooltip_text = item.fuel.text + "\n" + item.bar.tooltip_text
		item.card.tooltip_text = item.name + "\n" + item.fuel.tooltip_text

func _get_drag_data(_position: Vector2) -> Variant:
	if flight_mode and (index < int(game.flight.state.stage_index) or game.paused or game.flight.state.status not in ["ready", "flying"]): return null
	var preview := Label.new()
	preview.text = "Move stage %02d" % (index + 1)
	set_drag_preview(preview)
	return {"stage_group": index}

func _action_for_data(data: Variant) -> String:
	if not data is Dictionary: return ""
	if data.get("stage_action") is String: return data.stage_action
	if data.get("installed_part") is String:
		return game._stage_action_for_part(data.installed_part)
	return ""

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary: return false
	if flight_mode:
		return not game.paused and data.get("stage_group") is int and game.flight.can_reorder_stage(data.stage_group, index)
	if data.get("stage_group") is int:
		return data.stage_group != index and data.stage_group >= 0 and data.stage_group < game.design.assembly.stages.size()
	return game._can_move_action(_action_for_data(data), index, data.get("together", true))

func _drop_data(position: Vector2, data: Variant) -> void:
	if not _can_drop_data(position, data): return
	if data.has("stage_group"): game._move_stage(data.stage_group, index)
	else: game._move_action(_action_for_data(data), index, data.get("together", true))

func _process(_delta: float) -> void:
	if flight_mode: return
	var hovering := get_global_rect().has_point(get_global_mouse_position())
	var valid_drop := get_viewport().gui_is_dragging() and hovering and _can_drop_data(Vector2.ZERO, get_viewport().gui_get_drag_data())
	_style.border_color = Color("8be0c5") if valid_drop else Color("456166")

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_instance_valid(game):
		game.highlight_action = ""

class NewBlock extends PanelContainer:
	var game: Node
	func _ready() -> void:
		custom_minimum_size.y = 48
		var label := Label.new()
		label.text = "Drop item here for its own block"
		label.add_theme_font_size_override("font_size", 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		if not data is Dictionary or not data.get("stage_action") is String: return false
		return game._can_split_stage_action(data.stage_action, data.get("together", true))
	func _drop_data(position: Vector2, data: Variant) -> void:
		if _can_drop_data(position, data): game._split_stage_action(data.stage_action, data.get("together", true))
