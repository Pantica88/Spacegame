extends PanelContainer
## Catalogue entry with a locally drawn part illustration and native drag data.
var part_id := ""
var title := ""
var description := ""
var locked := false
var game: Node

class PartPicture extends Control:
	var part_id := ""
	func _draw() -> void:
		var white := Color("eef2e9")
		var teal := Color("279ba6")
		var metal := Color("617a85")
		var orange := Color("f3ab75")
		if part_id == "capsule":
			draw_colored_polygon(PackedVector2Array([Vector2(17,55),Vector2(36,8),Vector2(55,55)]), white)
			draw_rect(Rect2(17,51,38,9), teal)
			draw_circle(Vector2(36,35),5,Color("62d6e3"))
		elif part_id == "parachute":
			draw_colored_polygon(PackedVector2Array([Vector2(23,56),Vector2(35,20),Vector2(37,20),Vector2(49,56)]), white)
			draw_line(Vector2(33,29),Vector2(39,29),Color("dc943d"),2)
			draw_line(Vector2(25,50),Vector2(47,50),Color("dc943d"),3)
			draw_rect(Rect2(23,56,26,4),metal)
			draw_rect(Rect2(34,40,4,8),metal)
		elif part_id == "decoupler":
			draw_rect(Rect2(9, 29, 54, 20), orange)
			draw_rect(Rect2(9, 26, 54, 5), metal)
			draw_rect(Rect2(9, 48, 54, 5), metal)
		elif part_id == "reaction_wheel":
			draw_circle(Vector2(36,38),27,white)
			draw_circle(Vector2(36,38),23,Color("20272d"))
			draw_arc(Vector2(36,38),21,0,TAU,48,Color("ff8c19"),3,true)
			for index in range(8):
				var direction := Vector2.from_angle(index * TAU / 8)
				draw_line(Vector2(36,38)+direction*12,Vector2(36,38)+direction*19,metal,4,true)
			draw_circle(Vector2(36,38),11,metal)
			draw_arc(Vector2(36,38),8,0,TAU,32,Color("ff8c19"),2,true)
			draw_circle(Vector2(36,38),4,Color("20272d"))
		elif part_id == "tank":
			draw_style_box(_box(white), Rect2(16, 14, 40, 48))
			draw_rect(Rect2(16, 20, 40, 5), Color("dc943d"))
			draw_rect(Rect2(16, 51, 40, 5), Color("dc943d"))
			draw_rect(Rect2(16, 12, 40, 4), metal)
			draw_rect(Rect2(16, 60, 40, 4), metal)
			draw_line(Vector2(34, 16), Vector2(34, 60), metal, 1)
			draw_line(Vector2(52, 16), Vector2(52, 60), metal, 2)
			for y in [27, 45]: draw_rect(Rect2(49, y, 6, 6), metal)
		elif part_id == "boosters":
			for x in [12, 43]:
				draw_rect(Rect2(x, 24, 18, 38), white)
				draw_rect(Rect2(x, 16, 18, 8), metal)
				for y in [27,42,55]: draw_rect(Rect2(x,y,18,3),Color("e2b74c"))
				draw_rect(Rect2(x, 51, 18, 5), teal)
				draw_rect(Rect2(x+3, 62, 12, 7), metal)
		elif part_id == "separator":
			for x in [18,44]:
				draw_rect(Rect2(x,10,10,56),metal)
				for y in [16,28,40,52]: draw_line(Vector2(x+2,y+7),Vector2(x+8,y),Color("e2b74c"),3)
				for y in [9,61]: draw_rect(Rect2(x-3,y,16,7),metal)
		elif part_id == "fins":
			draw_colored_polygon(PackedVector2Array([Vector2(34,12),Vector2(12,64),Vector2(34,55)]), teal)
			draw_colored_polygon(PackedVector2Array([Vector2(40,12),Vector2(62,64),Vector2(40,55)]), teal)
		else:
			draw_rect(Rect2(19,12,36,12), teal)
			var bells := 2 if part_id == "titan" else 1
			for index in range(bells):
				var x := 12.0 + index*26.0 if bells == 2 else 19.0
				var width := 22.0 if bells == 2 else (36.0 if part_id == "kestrel" else 28.0)
				draw_colored_polygon(PackedVector2Array([Vector2(x+width*.25,24),Vector2(x+width*.75,24),Vector2(x+width,61),Vector2(x,61)]), metal)
				draw_line(Vector2(x,61),Vector2(x+width,61),orange,4)
	func _box(color: Color) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(6)
		return style

func _ready() -> void:
	custom_minimum_size = Vector2(0, 108)
	mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if locked else Control.CURSOR_DRAG
	tooltip_text = "Place the earlier parts first" if locked else "Drag into the assembly area"
	modulate = Color(0.42, 0.46, 0.47, 0.82) if locked else Color.WHITE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("203138")
	style.set_corner_radius_all(7)
	style.content_margin_left = 6
	style.content_margin_right = 8
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var picture := PartPicture.new()
	picture.part_id = part_id
	picture.custom_minimum_size = Vector2(72, 76)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(picture)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	for entry in [[title, 14, Color("eef2e9")], [description, 12, Color("91a8aa")]]:
		var label := Label.new()
		label.text = entry[0]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", entry[1])
		label.add_theme_color_override("font_color", entry[2])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(label)

func _get_drag_data(_position: Vector2) -> Variant:
	if locked:
		return null
	var preview := PanelContainer.new()
	var row := HBoxContainer.new()
	preview.add_child(row)
	var picture := PartPicture.new()
	picture.part_id = part_id
	picture.custom_minimum_size = Vector2(72, 76)
	row.add_child(picture)
	var label := Label.new()
	label.text = "  " + title + "  "
	row.add_child(label)
	set_drag_preview(preview)
	return {"rocket_part": part_id}

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("installed_part") is String

func _drop_data(_position: Vector2, data: Variant) -> void:
	if is_instance_valid(game) and data is Dictionary and data.get("installed_part") is String:
		game._remove_part_to_catalogue(str(data.installed_part))
