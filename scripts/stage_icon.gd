extends Control
## Vector silhouettes stay sharp at every UI scale.
var kind := "engine"
var tint := Color("c4cece")
func _ready() -> void:
	custom_minimum_size = Vector2(32, 32)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	match kind:
		"parachute":
			draw_arc(Vector2(16, 15), 12, PI, TAU, 20, tint, 2, true)
			draw_line(Vector2(4, 15), Vector2(28, 15), tint, 2, true)
			for x in [4, 16, 28]: draw_line(Vector2(x, 15), Vector2(16, 28), tint, 1.5, true)
		"booster":
			draw_style_box(_box(), Rect2(11, 7, 10, 17))
			draw_colored_polygon(PackedVector2Array([Vector2(11, 7), Vector2(16, 1), Vector2(21, 7)]), tint)
			draw_line(Vector2(16, 25), Vector2(16, 31), tint, 3, true)
		"radial_separator":
			for x in [7, 23]: draw_line(Vector2(x, 5), Vector2(x, 27), tint, 3, true)
			draw_line(Vector2(11, 16), Vector2(21, 16), tint, 2, true)
			draw_line(Vector2(2, 16), Vector2(5, 12), tint, 2, true)
			draw_line(Vector2(30, 16), Vector2(27, 12), tint, 2, true)
		"separator":
			for y in [11, 21]: draw_line(Vector2(4, y), Vector2(28, y), tint, 4, true)
			draw_line(Vector2(16, 2), Vector2(16, 7), tint, 2, true)
			draw_line(Vector2(16, 25), Vector2(16, 30), tint, 2, true)
		_:
			draw_colored_polygon(PackedVector2Array([Vector2(11, 5), Vector2(21, 5), Vector2(21, 12), Vector2(27, 24), Vector2(5, 24), Vector2(11, 12)]), tint)
			for x in [11, 16, 21]: draw_line(Vector2(x, 27), Vector2(x, 31), tint, 2, true)
func _box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = tint
	return box
