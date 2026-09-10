extends Control
## Compact attitude display and a live, projected orbital map.
var state: Dictionary = {}
var map_mode := false
const MINT := Color("7ce5c0")
const DIM := Color("78949b")
const Physics = preload("res://scripts/physics_math.gd")
const CENTER := Physics.PLANET_CENTER

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _draw() -> void:
	if state.is_empty():
		return
	if map_mode:
		_draw_map()
	else:
		_draw_attitude()

func _draw_attitude() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.43
	draw_circle(center, radius + 7, Color("0b181f"))
	draw_circle(center, radius, Color("214d62"))
	var orientation: Basis = state.get("orientation", Basis.IDENTITY)
	var radial: Vector3 = (Vector3(state.get("position", Vector3.ZERO)) - CENTER).normalized()
	var elevation := asin(clampf(orientation.y.dot(radial), -1.0, 1.0))
	var offset := sin(elevation) * radius
	var ground := PackedVector2Array()
	for i in range(65):
		var angle := float(i) / 64.0 * TAU
		var point := Vector2(cos(angle), sin(angle)) * radius
		if point.y >= offset:
			ground.append(center + point)
	if ground.size() > 2:
		draw_colored_polygon(ground, Color("735542"))
	for deg in [-60, -30, 0, 30, 60]:
		var y := sin(elevation - deg_to_rad(deg)) * radius
		if absf(y) < radius * 0.92:
			var length := 30.0 if deg == 0 else 13.0
			draw_line(center + Vector2(-length, y), center + Vector2(length, y), Color(0.8, 0.87, 0.87, 0.4), 1)
	draw_arc(center, radius, 0, TAU, 90, Color("4f747f"), 2, true)
	draw_line(center + Vector2(-40, 0), center + Vector2(-12, 0), MINT, 3, true)
	draw_line(center + Vector2(12, 0), center + Vector2(40, 0), MINT, 3, true)
	draw_arc(center, 7, 0, PI, 16, MINT, 3, true)
	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-32, radius - 16), "%02d° UP" % roundi(rad_to_deg(elevation)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e8f1ed"))

func _draw_map() -> void:
	var font := ThemeDB.fallback_font
	var center := size * Vector2(0.5, 0.53)
	var pos: Vector3 = Vector3(state.get("position", Vector3.ZERO)) - CENTER
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var radial := pos.normalized()
	var tangent := velocity - radial * velocity.dot(radial)
	if tangent.length() < 0.01:
		tangent = Vector3.RIGHT - radial * radial.dot(Vector3.RIGHT)
		if tangent.length() < 0.01:
			tangent = Vector3.FORWARD
	tangent = tangent.normalized()
	var apo := float(state.get("apoapsis", 0.0))
	var extent := maxf(90000, minf(400000, Physics.PLANET_RADIUS + maxf(apo, pos.length() - Physics.PLANET_RADIUS)))
	var scale_factor := minf(size.x, size.y) * 0.39 / extent
	var planet_radius := Physics.PLANET_RADIUS * scale_factor
	draw_circle(center, planet_radius + Physics.ATMOSPHERE_HEIGHT * scale_factor, Color(0.1, 0.3, 0.42, 0.25))
	draw_circle(center, planet_radius, Color("205164"))
	draw_arc(center, planet_radius, 0, TAU, 128, Color("619295"), 2, true)
	var path := Physics.coast_path(pos, velocity, extent * 4.0)
	var previous := center + Vector2(0, -pos.length()) * scale_factor
	for index in range(1, path.size()):
		var point := center + Vector2(path[index].dot(tangent), -path[index].dot(radial)) * scale_factor
		if index % 3 != 0:
			draw_line(previous, point, Color(0.49, 0.9, 0.75, 0.65), 1.5, true)
		previous = point
	var period := float(state.get("orbital_period", INF))
	var period_text := "%.0f s" % period if is_finite(period) else "Open trajectory"
	draw_string(font, Vector2(24, 28), "e %.3f   /   %s" % [float(state.get("eccentricity", 0.0)), period_text], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	var ship := center + Vector2(0, -pos.length() * scale_factor)
	draw_circle(ship, 5, MINT)
	draw_arc(ship, 10, 0, TAU, 24, Color(MINT, 0.4), 1, true)
	draw_string(font, center + Vector2(-22, 5), "VERDANT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("b4d5d0"))
	draw_string(font, Vector2(24, size.y - 24), "Predicted coast • excludes thrust and atmosphere", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
