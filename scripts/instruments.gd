extends Control
## Compact attitude display and a live, projected orbital map.
signal throttle_changed(value: float)
signal sas_toggled
var sas_button: Button
var _sphere_shade: GradientTexture2D
var _dragging_throttle := false
var state: Dictionary = {}
var map_mode := false
var legend_only := false
const MINT := Color("7ce5c0")
const DIM := Color("78949b")
const Physics = preload("res://scripts/physics_math.gd")
const CENTER := Physics.PLANET_CENTER
const LEGEND := [
	["prograde", "PROGRADE"],
	["retrograde", "RETRO"],
	["normal", "NORMAL"],
	["antinormal", "ANTI-N"],
	["radial_out", "RAD OUT"],
	["radial_in", "RAD IN"],
	["target", "TARGET"],
	["anti_target", "ANTI-T"],
	["maneuver", "MANEUVER"],
]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "THROTTLE: drag the green left arc. Shift/Ctrl adjust; X cuts; Z sets full.\n\nORBITAL GUIDANCE\nGold split diamond: prograde / crossed: retrograde\nLilac pennant: normal / inverted, crossed: anti-normal\nCyan chevrons: radial out / inward: radial in\nCoral brackets: target / crossed: anti-target\nWhite lightning: maneuver burn direction\nDim markers with an outward tick are behind the craft.\nTarget and maneuver appear only when guidance is available."
	clip_contents = true
	if legend_only or map_mode: return
	tooltip_text += "\n\nATM: three blue bands show air density relative to this body's sea level.\nThe star-filled band represents vacuum; the white pointer shows the current level.\nSAS: click the rim button or press T to toggle stabilization."
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 0.75, 0.92, 1.0])
	gradient.colors = PackedColorArray([Color(0.7, 0.9, 1.0, 0.08), Color(0.02, 0.04, 0.08, 0.0), Color(0.02, 0.04, 0.08, 0.16), Color(0.02, 0.04, 0.08, 0.42), Color(0.02, 0.04, 0.08, 0.8)])
	_sphere_shade = GradientTexture2D.new()
	_sphere_shade.gradient = gradient
	_sphere_shade.width = 256
	_sphere_shade.height = 256
	_sphere_shade.fill = GradientTexture2D.FILL_RADIAL
	_sphere_shade.fill_from = Vector2(0.5, 0.5)
	_sphere_shade.fill_to = Vector2(1.0, 0.5)
	sas_button = Button.new()
	sas_button.name = "SAS"
	sas_button.text = "SAS"
	sas_button.toggle_mode = true
	sas_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sas_button.tooltip_text = "SAS · attitude stabilization\nClick or press T to toggle"
	sas_button.add_theme_font_size_override("font_size", 12)
	for style_name in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style := StyleBoxFlat.new()
		var active: bool = style_name in ["pressed", "hover_pressed"]
		style.bg_color = Color("123d35") if active else Color("0b141d")
		style.border_color = MINT if active or style_name in ["hover", "focus"] else DIM
		style.set_border_width_all(2 if style_name == "focus" else 1)
		style.set_corner_radius_all(23)
		style.set_content_margin_all(0)
		if style_name == "focus": style.bg_color = Color.TRANSPARENT
		sas_button.add_theme_stylebox_override(style_name, style)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		sas_button.add_theme_color_override(color_name, MINT)
	add_child(sas_button)
	sas_button.pressed.connect(func(): sas_toggled.emit())

# The left arc runs from lower-left (idle) to upper-left (full).
func throttle_at_point(point: Vector2) -> float:
	var relative := point - size * 0.5
	var angle := atan2(-relative.y, -relative.x)
	return clampf((angle + PI / 4.0) / (PI / 2.0), 0.0, 1.0)

func _on_throttle_arc(point: Vector2) -> bool:
	var relative := point - size * 0.5
	var radius := minf(size.x, size.y) * 0.30 + 59.0
	return relative.x < 0 and absf(relative.length() - radius) <= 15.0 and absf(atan2(-relative.y, -relative.x)) <= PI / 4.0 + 0.08

func _gui_input(event: InputEvent) -> void:
	if legend_only or map_mode: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _on_throttle_arc(event.position):
			_dragging_throttle = true
			throttle_changed.emit(throttle_at_point(event.position))
			accept_event()
		elif not event.pressed and _dragging_throttle:
			_dragging_throttle = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging_throttle:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_dragging_throttle = false
			return
		throttle_changed.emit(throttle_at_point(event.position))
		accept_event()

func _draw() -> void:
	if legend_only:
		_draw_legend(Rect2(Vector2.ZERO, size))
		return
	if state.is_empty():
		return
	if map_mode:
		_draw_map()
	else:
		_draw_attitude()

func _draw_attitude() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.30
	var orientation: Basis = state.get("orientation", Basis.IDENTITY)
	var radial: Vector3 = state.get("surface_up", (Vector3(state.get("position", Vector3.ZERO)) - CENTER).normalized())
	var elevation := asin(clampf(orientation.y.dot(radial), -1.0, 1.0))
	var frame := surface_frame(radial)
	var heading := fposmod(rad_to_deg(atan2(orientation.y.dot(frame.x), orientation.y.dot(frame.z))), 360.0)
	# Layered bezel and recessed glass surround the projected attitude sphere.
	draw_circle(center + Vector2(0, 3), radius + 47, Color(0, 0, 0, 0.45))
	draw_circle(center, radius + 44, Color("111b29"))
	draw_arc(center, radius + 44, 0, TAU, 160, Color("596387"), 1.5, true)
	draw_circle(center, radius + 39, Color("060c16"))
	draw_arc(center, radius + 38, 0, TAU, 160, Color("29354a"), 1, true)
	# Heading tape turns with the vessel; the fixed center index is its heading.
	for offset in range(-60, 61):
		var bearing := int(floorf(heading)) + offset
		if posmod(bearing, 5) != 0: continue
		var angle := deg_to_rad(-90.0 + float(bearing) - heading)
		var direction := Vector2.from_angle(angle)
		var major := posmod(bearing, 15) == 0
		draw_line(center + direction * (radius + 18), center + direction * (radius + (27 if major else 22)), Color("8d91cb"), 1, true)
		if major:
			var label := str(posmod(bearing, 360))
			if posmod(bearing, 90) == 0: label = ["N", "E", "S", "W"][posmod(bearing, 360) / 90]
			_centered_text(center + direction * (radius + 33), label, 9, Color("b5b7e5"))
	_draw_throttle(center, radius)
	_draw_environment_gauges(center, radius)
	draw_circle(center, radius + 9, Color("02050a"))
	draw_arc(center, radius + 7, 0, TAU, 144, Color("354e62"), 2, true)
	draw_circle(center, radius, Color("277b9b"))
	var local_up := orientation.orthonormalized().transposed() * radial
	var ground := attitude_ground_polygon(center, radius, local_up)
	if not ground.is_empty(): draw_colored_polygon(ground, Color("72513a"))
	_draw_sphere_grid(center, radius, orientation, radial)
	# Radial lighting shades the markings as well as the globe, with no viewport.
	if _sphere_shade:
		var face := PackedVector2Array()
		var uv := PackedVector2Array()
		for i in range(128):
			var direction := Vector2.from_angle(TAU * float(i) / 128.0)
			face.append(center + direction * radius)
			uv.append(Vector2.ONE * 0.5 + direction * 0.5)
		draw_polygon(face, PackedColorArray([Color.WHITE]), uv, _sphere_shade)
	draw_arc(center, radius, 0, TAU, 144, Color("78929a"), 1.5, true)
	_draw_guidance(center, radius, orientation)
	# Fixed aircraft reticle remains readable over the moving grid and markers.
	var reticle := PackedVector2Array([center + Vector2(-37, 0), center + Vector2(-15, 0), center + Vector2(-7, 9), center + Vector2(7, 9), center + Vector2(15, 0), center + Vector2(37, 0)])
	draw_polyline(reticle, Color("07131b"), 6, true)
	draw_polyline(reticle, Color("d9f6db"), 2.5, true)
	draw_circle(center, 3, Color("07131b"))
	draw_circle(center, 1.5, Color("d9f6db"))
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var tip := center + direction * (radius + 2)
		var side := Vector2(-direction.y, direction.x)
		draw_colored_polygon(PackedVector2Array([tip, tip + direction * 7 + side * 3, tip + direction * 7 - side * 3]), MINT)
	var speed := float(state.get("speed", Vector3(state.get("velocity", Vector3.ZERO)).length()))
	_readout(Rect2(5, center.y - 24, 78, 48), "SURFACE", "%.1f" % speed, "m/s", Color("dbbe48"))
	_readout(Rect2(size.x - 83, center.y - 24, 78, 48), "GROUND", "%.0f" % float(state.get("terrain_clearance", 0.0)), "m", Color("bf70d0"))
	_readout(Rect2(center.x - 33, center.y - radius - 62, 66, 32), "HEADING", "%03d°" % (roundi(heading) % 360), "", Color("aaa4eb"))
	_centered_text(center + Vector2(-30, radius + 22), "PITCH", 8, DIM)
	_centered_text(center + Vector2(-30, radius + 35), "%+.0f°" % rad_to_deg(elevation), 13, Color("d0e2e9"))
	if is_instance_valid(sas_button):
		sas_button.position = center + Vector2(27, radius + 8)
		sas_button.size = Vector2(46, 40)
		sas_button.set_pressed_no_signal(bool(state.get("sas", false)))
	_centered_text(Vector2(49, size.y - 13), "THR %03d%%" % roundi(float(state.get("throttle", 0.0)) * 100), 10, MINT)
	var density := atmosphere_fraction()
	var air_text := "VACUUM" if density <= 0.0 else ("ATM <1%" if density < 0.01 else "ATM %02d%%" % roundi(density * 100))
	_centered_text(Vector2(size.x - 50, size.y - 13), air_text, 10, Color("7ebcfa"))

static func attitude_ground_polygon(center: Vector2, radius: float, local_up: Vector3) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	if not local_up.is_finite() or not is_finite(radius) or radius <= 0.0:
		return polygon
	var pitch := clampf(local_up.y, -1.0, 1.0)
	# Near straight-up flight the ground becomes a subpixel crescent.
	if radius * (1.0 - pitch) < 0.05:
		return polygon
	var down := -Vector2(local_up.x, local_up.z).normalized()
	if down.is_zero_approx(): down = Vector2.DOWN
	var right := Vector2(down.y, -down.x)
	# Both boundaries MUST use identical x samples. Independently sampled
	# circle/ellipse chords can cross when the horizon approaches the rim.
	var rim := PackedVector2Array()
	for i in range(97):
		var angle := PI * float(i) / 96.0
		var point := Vector2(cos(angle), sin(angle)) * radius
		if i == 0: point = Vector2(radius, 0)
		if i == 96: point = Vector2(-radius, 0)
		rim.append(point)
		polygon.append(center + right * point.x + down * point.y)
	for i in range(95, 0, -1):
		polygon.append(center + right * rim[i].x + down * (pitch * rim[i].y))
	return polygon


func _centered_text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at + Vector2(-width * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_throttle(center: Vector2, radius: float) -> void:
	var gauge_radius := radius + 59.0
	draw_arc(center, gauge_radius, deg_to_rad(133), deg_to_rad(227), 64, Color("080f19"), 20, true)
	for segment in range(24):
		var start := deg_to_rad(135.0 + segment * 3.75)
		var color := MINT if float(segment) / 24.0 < float(state.get("throttle", 0.0)) else Color("233a3f")
		draw_arc(center, gauge_radius, start, start + deg_to_rad(2.9), 5, color, 11, true)
	var pointer := Vector2.from_angle(deg_to_rad(135.0 + float(state.get("throttle", 0.0)) * 90.0))
	draw_line(center + pointer * (gauge_radius - 9), center + pointer * (gauge_radius + 9), Color("e4ffec"), 2, true)

# Density is relative to the current reference body, including airless moons.
func atmosphere_fraction() -> float:
	var sea_level := float(state.get("sea_level_air_density", 0.0))
	if sea_level <= 0.0 or float(state.get("atmosphere_height", 0.0)) <= 0.0: return 0.0
	return clampf(float(state.get("air_density", 0.0)) / sea_level, 0.0, 1.0)

func _draw_environment_gauges(center: Vector2, radius: float) -> void:
	var gauge_radius := radius + 59.0
	# Upper-right: signed vertical speed. Lower-right: atmospheric density.
	draw_arc(center, gauge_radius, deg_to_rad(-47), deg_to_rad(47), 64, Color("080f19"), 20, true)
	_draw_atmosphere_gauge(center, gauge_radius)
	# Logarithmic speed scale preserves sensitivity near zero on ascent/descent.
	var speed := float(state.get("vertical_speed", 0.0))
	var normalized := signf(speed) * clampf(log(1.0 + absf(speed) / 10.0) / log(101.0), 0.0, 1.0)
	for tick in range(9):
		var direction := Vector2.from_angle(deg_to_rad(-45.0 + tick * 5.0))
		draw_line(center + direction * (gauge_radius - 6), center + direction * (gauge_radius + (5 if tick % 4 == 0 else 1)), Color("9499cc"), 1, true)
	var needle := Vector2.from_angle(deg_to_rad(-25.0 - normalized * 20.0))
	draw_line(center + needle * (gauge_radius - 9), center + needle * (gauge_radius + 9), Color("f4edc9"), 2, true)
	_centered_text(center + Vector2(123, -122), "V/S", 8, DIM)
	_centered_text(center + Vector2(123, -111), "%+.0f" % speed, 11, Color("c4c9ed"))

func _draw_atmosphere_gauge(center: Vector2, gauge_radius: float) -> void:
	# Four permanent bands: space at the top, then thin through dense air.
	# A separate pointer preserves the reference's four-part silhouette in vacuum.
	var colors := [Color("090f20"), Color("284b9b"), Color("367dd1"), Color("75bdf4")]
	for section in range(4):
		var start := deg_to_rad(12.0 + section * 9.0)
		var end := start + deg_to_rad(7.5)
		draw_arc(center, gauge_radius, start, end, 12, Color("546a96"), 15, true)
		draw_arc(center, gauge_radius, start, end, 12, colors[section], 12, true)
	# Fixed stars stay still as telemetry changes, like markings on the gauge.
	for star: Vector2 in [Vector2(13.5, -2.5), Vector2(14.8, 3.0), Vector2(16.3, -0.5), Vector2(17.8, -3.0), Vector2(18.5, 2.5)]:
		var at := center + Vector2.from_angle(deg_to_rad(star.x)) * (gauge_radius + star.y)
		draw_circle(at, 0.7, Color("dce9ff"))
	var density := atmosphere_fraction()
	var angle := deg_to_rad(15.75 if density <= 0.0 else lerpf(21.0, 46.5, density))
	var direction := Vector2.from_angle(angle)
	var side := Vector2(-direction.y, direction.x)
	var tip := center + direction * (gauge_radius - 8)
	var base := center + direction * (gauge_radius - 16)
	var pointer := PackedVector2Array([tip, base + side * 4, base - side * 4])
	draw_colored_polygon(pointer, Color("f0f6ff"))
	draw_polyline(PackedVector2Array([pointer[0], pointer[1], pointer[2], pointer[0]]), Color("080f19"), 1, true)

# Geographic north follows the planet's +Y spin axis; use -Z at the poles.
static func surface_frame(up: Vector3) -> Basis:
	var north := Vector3.UP - up * Vector3.UP.dot(up)
	if north.length_squared() < 0.000001:
		north = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	north = north.normalized()
	return Basis(north.cross(up).normalized(), up, north)

static func sphere_direction(pitch: float, heading: float, frame: Basis) -> Vector3:
	return frame.y * sin(pitch) + (frame.z * cos(heading) + frame.x * sin(heading)) * cos(pitch)

func _sphere_line(points: Array[Vector3], center: Vector2, radius: float, inverse: Basis, color: Color, width: float = 1.0) -> void:
	var previous := Vector3.ZERO
	var has_previous := false
	for direction in points:
		var point := inverse * direction
		if has_previous and point.y >= 0 and previous.y >= 0:
			draw_line(center + Vector2(previous.x, previous.z) * radius, center + Vector2(point.x, point.z) * radius, color, width, true)
		previous = point
		has_previous = true

func _sphere_label(text: String, pitch: float, heading: float, frame: Basis, inverse: Basis, center: Vector2, radius: float) -> void:
	var local := inverse * sphere_direction(pitch, heading, frame)
	if local.y < 0.28: return
	var at := center + Vector2(local.x, local.z) * radius
	var upward := inverse * (sphere_direction(pitch + 0.01, heading, frame) - sphere_direction(pitch, heading, frame))
	var angle := Vector2(upward.x, upward.z).angle() + PI / 2
	draw_set_transform(at, angle)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, Vector2(-width / 2, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("d0e2e9"))
	draw_set_transform(Vector2.ZERO)

func _draw_sphere_grid(center: Vector2, radius: float, orientation: Basis, up: Vector3) -> void:
	var frame := surface_frame(up)
	var inverse := orientation.orthonormalized().transposed()
	for heading in range(0, 360, 45):
		var meridian: Array[Vector3] = []
		for pitch in range(-90, 91, 3):
			meridian.append(sphere_direction(deg_to_rad(pitch), deg_to_rad(heading), frame))
		_sphere_line(meridian, center, radius, inverse, Color("96b1bf"))
		for pitch in range(-80, 81, 5):
			if pitch == 0: continue
			var tick: Array[Vector3] = []
			var span := 4 if pitch % 10 == 0 else 2
			for offset in range(-span, span + 1):
				tick.append(sphere_direction(deg_to_rad(pitch), deg_to_rad(heading + offset), frame))
			_sphere_line(tick, center, radius, inverse, Color("e0ebed"))
			if pitch % 10 == 0 and absi(pitch) <= 60:
				_sphere_label(str(pitch), deg_to_rad(pitch), deg_to_rad(heading + 10), frame, inverse, center, radius)
		_sphere_label("%03d" % heading, deg_to_rad(3), deg_to_rad(heading + 20), frame, inverse, center, radius)
	var horizon: Array[Vector3] = []
	for heading in range(361):
		horizon.append(sphere_direction(0, deg_to_rad(heading), frame))
	_sphere_line(horizon, center, radius, inverse, Color("edf2dc"), 2.0)

func _readout(rect: Rect2, caption: String, value: String, unit: String, color: Color) -> void:
	draw_rect(rect, Color("050811"))
	draw_rect(rect, color, false, 1.5)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(5, 11), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)
	draw_string(font, rect.position + Vector2(5, 28), value, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 17, Color("e0def0"))
	if not unit.is_empty(): draw_string(font, rect.position + Vector2(rect.size.x - 23, 41), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)

# World-space vectors use the vessel's +Y nose, +X right and -Z screen-up.
# Back-hemisphere markers stay on the rim instead of mirroring onto the face.
static func project_direction(direction: Vector3, orientation: Basis) -> Dictionary:
	if not direction.is_finite() or direction.length_squared() < 1e-12:
		return {}
	var local := orientation.orthonormalized().transposed() * direction.normalized()
	var point := Vector2(local.x, local.z)
	var behind := local.y < -0.00001
	if behind:
		point = point.normalized() if point.length_squared() > 1e-10 else Vector2.DOWN
	return {"point": point, "behind": behind}

func guidance_directions() -> Dictionary:
	var directions := {}
	for key in ["prograde", "retrograde", "normal", "antinormal", "radial_out", "radial_in"]:
		directions[key] = Vector3(state.get(key, Vector3.ZERO))
	# Optional guidance contract: absolute world target position, world burn vector.
	var target := Vector3.ZERO
	if state.has("target_position"):
		target = Vector3(state.target_position) - Vector3(state.get("position", Vector3.ZERO))
	directions["target"] = target
	directions["anti_target"] = -target
	directions["maneuver"] = Vector3(state.get("maneuver_direction", Vector3.ZERO))
	return directions

func _draw_guidance(center: Vector2, radius: float, orientation: Basis) -> void:
	var directions := guidance_directions()
	# Rear cues first; front-facing symbols remain legible when cues overlap.
	for rear in [true, false]:
		for key in directions:
			var projected := project_direction(directions[key], orientation)
			if projected.is_empty() or projected.behind != rear:
				continue
			var point: Vector2 = projected.point
			var location := center + point * (radius - 12.0)
			var color := marker_color(key)
			if rear:
				color.a = 0.48
				draw_line(location + point * 8, location + point * 12, color, 1.5, true)
			_draw_marker(key, location, color, 0.75 if rear else 1.0)

func _draw_legend(bounds: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var margin := 5.0
	var column_width := floorf((bounds.size.x - margin * 2.0) / 3.0)
	var row_height := 15.0
	var top := bounds.position.y + 10.0
	var left := bounds.position.x + margin
	var panel := bounds.grow(-1.0)
	draw_rect(panel, Color(0.03, 0.07, 0.09, 0.78), true)
	draw_rect(panel, Color(0.32, 0.45, 0.48, 0.55), false, 1.0)
	for index in range(LEGEND.size()):
		var key: String = LEGEND[index][0]
		var label: String = LEGEND[index][1]
		var column := index % 3
		var row := index / 3
		var origin := Vector2(left + column * column_width, top + row * row_height)
		_draw_marker(key, origin + Vector2(6, 0), marker_color(key), 0.47)
		draw_string(font, origin + Vector2(15, 4), label, HORIZONTAL_ALIGNMENT_LEFT, column_width - 15, 8, Color("d7e7e4"))

static func marker_color(key: String) -> Color:
	match key:
		"prograde", "retrograde": return Color("ffda76")
		"normal", "antinormal": return Color("c4a2ff")
		"radial_out", "radial_in": return Color("69ddf5")
		"target", "anti_target": return Color("ff9c91")
	return Color("f3f8ff")

func _marker_stroke(points: Array, at: Vector2, color: Color, scale_factor: float) -> void:
	var line := PackedVector2Array()
	for point in points:
		line.append(at + Vector2(point) * scale_factor)
	draw_polyline(line, Color(0.02, 0.05, 0.08, color.a), 5.0 * scale_factor, true)
	draw_polyline(line, color, 2.0 * scale_factor, true)

func _draw_marker(key: String, at: Vector2, color: Color, scale_factor: float = 1.0) -> void:
	match key:
		"prograde", "retrograde":
			_marker_stroke([Vector2(-2,-8),Vector2(-9,0),Vector2(-2,8)], at, color, scale_factor)
			_marker_stroke([Vector2(2,-8),Vector2(9,0),Vector2(2,8)], at, color, scale_factor)
			if key == "prograde":
				draw_circle(at, 2 * scale_factor, color)
		"normal", "antinormal":
			var sign_y := -1.0 if key == "antinormal" else 1.0
			_marker_stroke([Vector2(-8,5)*sign_y,Vector2(0,-9)*sign_y,Vector2(8,5)*sign_y,Vector2(0,1)*sign_y,Vector2(-8,5)*sign_y], at, color, scale_factor)
		"radial_out", "radial_in":
			var sign_x := -1.0 if key == "radial_in" else 1.0
			for side in [-1.0, 1.0]:
				_marker_stroke([Vector2(5-3*sign_x,-6)*Vector2(side,1),Vector2(5+3*sign_x,0)*Vector2(side,1),Vector2(5-3*sign_x,6)*Vector2(side,1)], at, color, scale_factor)
		"target", "anti_target":
			for side in [-1.0, 1.0]:
				_marker_stroke([Vector2(3,-7)*side,Vector2(8,-7)*side,Vector2(8,7)*side,Vector2(3,7)*side], at, color, scale_factor)
			if key == "target":
				draw_circle(at, 2 * scale_factor, color)
		"maneuver":
			_marker_stroke([Vector2(2,-10),Vector2(-6,1),Vector2(1,1),Vector2(-2,10),Vector2(7,-2),Vector2(0,-2),Vector2(2,-10)], at, color, scale_factor)
	if key in ["retrograde", "antinormal", "anti_target"]:
		_marker_stroke([Vector2(-3,-3),Vector2(3,3)], at, color, scale_factor)
		_marker_stroke([Vector2(-3,3),Vector2(3,-3)], at, color, scale_factor)

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
	var extent := maxf(Physics.PLANET_RADIUS * 1.5, minf(Physics.PLANET_RADIUS * (20.0 / 3.0), Physics.PLANET_RADIUS + maxf(apo, pos.length() - Physics.PLANET_RADIUS)))
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
