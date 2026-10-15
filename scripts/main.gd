extends Node

const Parts = preload("res://scripts/parts.gd")
const FlightModel = preload("res://scripts/flight_model.gd")
const WorldView = preload("res://scripts/world_view.gd")
const PlanetSurface = preload("res://scripts/planet_surface.gd")
const Profile = preload("res://scripts/profile.gd")
const FlightAudio = preload("res://scripts/flight_audio.gd")
const Instruments = preload("res://scripts/instruments.gd")
const INK := Color("101e25")
const MINT := Color("7ce5c0")
const PAPER := Color("eef2e9")
const MUTED := Color("91a8aa")
const ORANGE := Color("f3ab75")
const MISSIONS := [
	{"id": "hop", "name": "A little altitude", "tag": "01  /  FIRST FLIGHT", "description": "Reach 1 km and bring the capsule home safely.", "target": 1000.0},
	{"id": "sky", "name": "The sky gets quiet", "tag": "02  /  HIGH FLIGHT", "description": "Reach 12 km and recover the capsule in one piece.", "target": 12000.0},
	{"id": "orbit", "name": "Around we go", "tag": "03  /  ORBITAL FLIGHT", "description": "Raise both ends of your orbit above the 18 km atmosphere.", "target": 18000.0}
]

var profile = Profile.new()
var design: Dictionary
var flight = FlightModel.new()
var world: Node3D
var sound: Node
var ui: Control
var workshop: Control
var workshop_side_panels: Array[Control] = []
var workshop_expanded := false
var workshop_expand_button: Button
var workshop_orbit_drag := false
var workshop_pan_drag := false
var flight_ui: Control
var asset_viewer
var modal: Control
var toast_label: Label
var toast_time := 0.0
var mode := "workshop"
var paused := false
var _preparing_launch := false
var hud_hidden := false
var header: Control
var mission_index := 0
var throttle := 1.0
var sas := true
var warp := 1.0
var physical_warp := false
var warp_target_time := -1.0
var warp_target_body := ""
var recorded := false
var flight_completed := false
var stats_labels: Dictionary = {}
var tank_label: Label
var craft_name: LineEdit
var craft_caption: Label
var mission_description: Label
var mission_tag: Label
var mission_hint: Label
var stage_fuel_capacity: Dictionary = {}
const WARP_STEPS := [1, 2, 3, 4, 5, 10, 50, 100, 1000, 10000, 100000]
var warp_arrows: Array[Button] = []
var _last_warp_ui_state := Vector3(-1, -1, -1)
var warp_button: Button
var stage_button: Button
var navball: Control
var map_panel: PanelContainer
var map_instrument: Control
var launch_button: Button
var engine_buttons: Dictionary = {}
var attachment_layer: Control
var build_drop_area: Control
var radial_symmetry := 2
var radial_snap: Dictionary = {}
var drag_snap_slot := ""
var drag_root_height := 7.5
var highlight_action := ""
var selected_part := ""
var hovered_part := ""
var return_drag_single := false
var return_drag_id := ""
var return_drag_kind := ""
var return_drag_snap_slot := ""
var drag_fin_offset := 0.0
var flight_stage_list: VBoxContainer
var _last_stage_display := ""
var _flight_stage_plan: Array[String] = []
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var assembly_list: VBoxContainer
var stage_preview: VBoxContainer
var terrain_settings: Resource
var terrain_controls: Dictionary = {}
var terrain_labels: Dictionary = {}

func _ready() -> void:
	DisplayServer.window_set_title("Aphelion — Flight Works · v%s" % ProjectSettings.get_setting("application/config/version", "dev"))
	design = profile.data.design.duplicate(true)
	design = Parts.Craft.project(Parts.Craft.load_craft(design), design)
	world = WorldView.new()
	# Disable body heating visuals for the flight performance comparison.
	world.aerothermal_effects_enabled = false
	world.set_design(design)
	world.set_atmosphere_quality(profile.data.atmosphere_quality)
	add_child(world)
	var cost_overlay := preload("res://scripts/render_cost_overlay.gd").new()
	cost_overlay.world = world
	add_child(cost_overlay)
	terrain_settings = PlanetSurface.home().definition.duplicate()
	sound = FlightAudio.new()
	add_child(sound)
	sound.enabled = profile.data.sound
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _theme()
	layer.add_child(ui)
	_build_header()
	_build_workshop()
	_build_flight_ui()
	var debris_overlay := preload("res://scripts/debris_markers.gd").new()
	debris_overlay.world = world
	flight_ui.add_child(debris_overlay)
	flight_ui.move_child(debris_overlay, 0)
	toast_label = _label(ui, "", 16, MINT)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_rect_offsets(toast_label, Rect2(-340, 150, 680, 36))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh_design(false, false)
	if not profile.last_error.is_empty():
		_toast(profile.last_error)
	get_tree().auto_accept_quit = false
	if "--smoke-test" in OS.get_cmdline_user_args():
		_smoke_test.call_deferred()

func _theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_hover_color", "Button", MINT)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", MINT)
	theme.set_stylebox("normal", "Button", _style(Color("203138"), Color("3c5056"), 6, 12))
	theme.set_stylebox("hover", "Button", _style(Color("30474b"), MINT, 6, 12))
	theme.set_stylebox("pressed", "Button", _style(MINT, MINT, 6, 12))
	theme.set_stylebox("focus", "Button", _style(Color(0, 0, 0, 0), MINT, 6, 2))
	theme.set_stylebox("disabled", "Button", _style(Color("17262c"), Color("283b42"), 6, 12))
	theme.set_color("font_disabled_color", "Button", Color("61777e"))
	theme.set_stylebox("normal", "LineEdit", _style(Color("101d25"), Color("3b5158"), 6, 12))
	theme.set_color("font_color", "LineEdit", PAPER)
	theme.set_color("caret_color", "LineEdit", MINT)
	theme.set_stylebox("background", "ProgressBar", _style(Color("26383e"), Color.TRANSPARENT, 3, 0))
	theme.set_stylebox("fill", "ProgressBar", _style(MINT, Color.TRANSPARENT, 3, 0))
	theme.set_constant("separation", "VBoxContainer", 12)
	theme.set_constant("separation", "HBoxContainer", 10)
	return theme

func _style(bg: Color, border: Color, radius: int = 8, margin: int = 20) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box

func _label(parent: Node, text: String, font_size: int = 16, color: Color = PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _wrap(parent: Node, text: String, font_size: int = 15, color: Color = MUTED) -> Label:
	var label := _label(parent, text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(parent: Node, text: String, callback: Callable, accent: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if accent:
		button.add_theme_stylebox_override("normal", _style(MINT, MINT, 6, 12))
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", PAPER)
	button.pressed.connect(func():
		sound.ping()
		callback.call()
	)
	parent.add_child(button)
	return button

func _panel(parent: Control, rect: Rect2, right: bool = false, bottom: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	if right:
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
	if bottom:
		panel.anchor_top = 1.0
		panel.anchor_bottom = 1.0
	_rect_offsets(panel, rect)
	panel.add_theme_stylebox_override("panel", _style(Color(0.055, 0.094, 0.118, 0.96), Color("31454a")))
	var box := VBoxContainer.new()
	panel.add_child(box)
	return box

func _rect_offsets(control: Control, rect: Rect2) -> void:
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y

func _spacer(parent: Node, height: float = 6) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)

func _rule(parent: Node) -> void:
	var line := HSeparator.new()
	line.add_theme_color_override("separator", Color("31454a"))
	parent.add_child(line)

func _build_header() -> void:
	var bar := Panel.new()
	header = bar
	ui.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 90
	bar.add_theme_stylebox_override("panel", _style(Color(0.035, 0.064, 0.081, 0.98), Color("31454a"), 0, 0))
	var icon := TextureRect.new()
	icon.texture = preload("res://assets/icon.svg")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.position = Vector2(26, 20)
	icon.size = Vector2(48, 48)
	bar.add_child(icon)
	_label(bar, "A P H E L I O N", 26).position = Vector2(88, 18)
	_label(bar, "B L U F F T O N   F L I G H T   W O R K S", 10, MUTED).position = Vector2(90, 53)
	_label(bar, "v%s" % ProjectSettings.get_setting("application/config/version", "dev"), 12, MINT).position = Vector2(370, 34)
	var assets_button := _button(bar, "ASSET VIEWER", _show_asset_viewer)
	assets_button.position = Vector2(530, 23)
	var menu := _button(bar, "ESC   /   MENU", _toggle_pause)
	menu.anchor_left = 1
	menu.anchor_right = 1
	_rect_offsets(menu, Rect2(-188, 23, 164, 42))

func _build_workshop() -> void:
	workshop = Control.new()
	workshop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workshop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(workshop)
	var left := _panel(workshop, Rect2(24, 122, 294, 585))
	workshop_side_panels.append(left.get_parent())
	left.add_theme_constant_override("separation", 7)
	_label(left, "VEHICLE ASSEMBLY", 11, MINT)
	_label(left, "Make it fly.", 28)
	tank_label = _label(left, "", 13, MUTED)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 460)
	left.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.name = "Parts"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	assembly_list = preload("res://scripts/parts_catalogue.gd").new()
	assembly_list.game = self
	assembly_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assembly_list.add_theme_constant_override("separation", 7)
	scroll.add_child(assembly_list)
	attachment_layer = Control.new()
	attachment_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	attachment_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	workshop.add_child(attachment_layer)
	build_drop_area = preload("res://scripts/build_drop_area.gd").new()
	build_drop_area.game = self
	build_drop_area.anchor_right = 1.0
	build_drop_area.anchor_bottom = 1.0
	build_drop_area.offset_left = 330
	build_drop_area.offset_top = 92
	build_drop_area.offset_right = -330
	build_drop_area.offset_bottom = -110
	workshop.add_child(build_drop_area)
	# Installed-part handles must sit above the assembly canvas so they can begin
	# a return-to-inventory drag. Each handle forwards catalogue drops below.
	attachment_layer.move_to_front()
	var right_panel := _panel(workshop, Rect2(-318, 122, 294, 580), true)
	workshop_side_panels.append(right_panel.get_parent())
	var right_tabs := TabContainer.new()
	right_tabs.custom_minimum_size = Vector2(0, 530)
	right_panel.add_child(right_tabs)
	var stage_scroll := ScrollContainer.new()
	stage_scroll.name = "Stages"
	stage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_tabs.add_child(stage_scroll)
	stage_preview = VBoxContainer.new()
	stage_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_preview.add_theme_constant_override("separation", 9)
	stage_scroll.add_child(stage_preview)
	var report_scroll := ScrollContainer.new()
	report_scroll.name = "Flight checks"
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_tabs.add_child(report_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 7)
	report_scroll.add_child(right)
	mission_tag = _label(right, "", 11, MINT)
	var chooser := OptionButton.new()
	for mission in MISSIONS:
		chooser.add_item(mission.name)
	chooser.custom_minimum_size.y = 42
	chooser.item_selected.connect(func(index: int):
		mission_index = index
		_refresh_mission()
	)
	right.add_child(chooser)
	mission_description = _wrap(right, "", 16, PAPER)
	mission_hint = _wrap(right, "", 13)
	_spacer(right)
	_rule(right)
	_label(right, "ENGINEERING REPORT", 11, MUTED)
	for entry in [["wet_mass", "Launch mass"], ["thrust", "Thrust"], ["twr", "Thrust / weight"], ["delta_v", "Estimated Δv"], ["fuel_mass", "Liquid fuel"]]:
		var stats_row := HBoxContainer.new()
		right.add_child(stats_row)
		_label(stats_row, entry[1], 14, MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_labels[entry[0]] = _label(stats_row, "", 15)
	_rule(right)
	stats_labels["readiness"] = _wrap(right, "", 14, MINT)
	_spacer(right)
	_label(right, "YOUR FLIGHT PROGRAM", 11, MUTED)
	stats_labels["records"] = _wrap(right, "", 13)
	craft_caption = _label(workshop, "", 23)
	craft_caption.anchor_left = 0.5
	craft_caption.anchor_right = 0.5
	craft_caption.anchor_top = 1
	craft_caption.anchor_bottom = 1
	_rect_offsets(craft_caption, Rect2(-235, -165, 470, 36))
	craft_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var orbit_hint := _label(workshop, "RMB  orbit    ·    MMB  pan    ·    SCROLL  zoom", 12, MUTED)
	orbit_hint.anchor_left = 0.5
	orbit_hint.anchor_right = 0.5
	orbit_hint.anchor_top = 1
	orbit_hint.anchor_bottom = 1
	_rect_offsets(orbit_hint, Rect2(-220, -130, 440, 24))
	orbit_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var camera_tools := HBoxContainer.new()
	workshop.add_child(camera_tools)
	camera_tools.anchor_left = 0.5
	camera_tools.anchor_right = 0.5
	_rect_offsets(camera_tools, Rect2(-300, 100, 600, 42))
	camera_tools.add_theme_constant_override("separation", 8)
	workshop_expand_button = _button(camera_tools, "Expand workshop", _toggle_workshop_expanded)
	var views := OptionButton.new()
	views.add_item("View rocket…")
	for view in ["Front", "Back", "Left", "Right", "Top", "Bottom"]:
		views.add_item(view)
	views.item_selected.connect(func(index: int):
		if index > 0: world.workshop_camera_view(views.get_item_text(index))
		views.select(0)
	)
	camera_tools.add_child(views)
	_button(camera_tools, "Fit rocket", func(): world.fit_workshop_camera())
	_button(camera_tools, "Reset view", func(): world.workshop_camera_view("Reset"))

	var footer := _panel(workshop, Rect2(24, -98, 1392, 74), false, true)
	footer.get_parent().anchor_right = 1
	footer.get_parent().offset_right = -24
	var footer_row := HBoxContainer.new()
	footer.add_child(footer_row)
	_label(footer_row, "CRAFT", 11, MUTED).custom_minimum_size.x = 56
	craft_name = LineEdit.new()
	craft_name.text = design.name
	craft_name.max_length = 28
	craft_name.custom_minimum_size = Vector2(190, 40)
	craft_name.text_changed.connect(func(value: String):
		design.name = value
		craft_caption.text = value if not value.strip_edges().is_empty() else "Untitled craft"
	)
	craft_name.focus_exited.connect(_save_design)
	footer_row.add_child(craft_name)
	_button(footer_row, "Save design", _save_design)
	_button(footer_row, "New", _new_craft)
	_button(footer_row, "Undo", _undo_edit)
	_button(footer_row, "Redo", _redo_edit)
	_button(footer_row, "Map editor", _show_terrain_editor)
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(filler)
	_label(footer_row, "ASSEMBLY BAY  /  01", 11, MUTED).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	launch_button = _button(footer_row, "ROLL OUT TO PAD   →", _roll_out, true)
	launch_button.custom_minimum_size.x = 246

func _toggle_workshop_expanded() -> void:
	workshop_expanded = not workshop_expanded
	for panel in workshop_side_panels:
		panel.visible = not workshop_expanded
	build_drop_area.offset_left = 24 if workshop_expanded else 330
	build_drop_area.offset_right = -24 if workshop_expanded else -330
	workshop_expand_button.text = "Show panels" if workshop_expanded else "Expand workshop"


func _workshop_camera_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		workshop_orbit_drag = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		workshop_pan_drag = false
	if mode != "workshop" or paused or is_instance_valid(asset_viewer):
		workshop_orbit_drag = false
		workshop_pan_drag = false
		return false
	if event is InputEventMouseMotion and workshop_pan_drag:
		world.pan_workshop_camera(event.relative)
		return true
	if event is InputEventMouseMotion and workshop_orbit_drag:
		world.orbit_camera(event.relative)
		return true
	if not event is InputEventMouseButton or not event.pressed: return false
	if not build_drop_area.get_global_rect().has_point(event.position): return false
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != build_drop_area and hovered.get_script() != preload("res://scripts/installed_part.gd"):
		return false
	match event.button_index:
		MOUSE_BUTTON_RIGHT: workshop_orbit_drag = true
		MOUSE_BUTTON_MIDDLE: workshop_pan_drag = true
		MOUSE_BUTTON_WHEEL_UP: world.zoom_camera(-1)
		MOUSE_BUTTON_WHEEL_DOWN: world.zoom_camera(1)
		_: return false
	return true


var resource_bars: Dictionary = {}
var resource_labels: Dictionary = {}
var mission_clock: Label
var fps_label: Label

func _flight_panel(rect: Rect2, right: bool = false, bottom: bool = false) -> VBoxContainer:
	var box := _panel(flight_ui, rect, right, bottom)
	box.get_parent().add_theme_stylebox_override("panel", _style(Color("050811"), Color("6255ad"), 4, 8))
	box.add_theme_constant_override("separation", 4)
	return box

func _build_flight_ui() -> void:
	flight_ui = Control.new()
	flight_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flight_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(flight_ui)
	flight_ui.hide()
	var hud_theme := ui.theme.duplicate() as Theme
	hud_theme.set_stylebox("background", "ProgressBar", _style(Color("44485c"), Color.TRANSPARENT, 0, 0))
	hud_theme.set_stylebox("fill", "ProgressBar", _style(Color("00e75b"), Color.TRANSPARENT, 0, 0))
	for kind in ["normal", "hover", "pressed"]:
		hud_theme.set_stylebox(kind, "Button", _style(Color("080b16") if kind == "normal" else Color("252448"), Color("6255ad"), 3, 5))
	flight_ui.theme = hud_theme
	fps_label = _label(flight_ui, "FPS: %d" % Engine.get_frames_per_second(), 14, Color("c8d0ef"))
	fps_label.position = Vector2(20, 20)
	fps_label.add_theme_color_override("font_outline_color", Color("050811"))
	fps_label.add_theme_constant_override("outline_size", 4)
	var resources := _flight_panel(Rect2(-252, 20, 232, 100), true)
	_label(resources, "VESSEL RESOURCES", 11, Color("9391c9"))
	for key in ["fuel", "booster_fuel"]:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		resources.add_child(row)
		resource_labels[key] = _label(row, "", 11)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 9
		row.add_child(bar)
		resource_bars[key] = bar
	var sequence_panel := _flight_panel(Rect2(-252, 132, 232, 360), true)
	sequence_panel.get_parent().add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	sequence_panel.get_parent().mouse_filter = Control.MOUSE_FILTER_IGNORE
	sequence_panel.get_parent().anchor_bottom = 1.0
	sequence_panel.get_parent().offset_bottom = -118
	var sequence_scroll := ScrollContainer.new()
	sequence_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sequence_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sequence_panel.add_child(sequence_scroll)
	flight_stage_list = VBoxContainer.new()
	flight_stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sequence_scroll.add_child(flight_stage_list)
	var actions := _flight_panel(Rect2(-252, -106, 232, 86), true, true)
	stage_button = _button(actions, "SPACE  /  GO", _stage)
	stage_button.clip_text = true
	stage_button.add_theme_font_size_override("font_size", 14)
	stage_button.add_theme_stylebox_override("normal", _style(Color("00d858"), Color("6255ad"), 3, 6))
	stage_button.add_theme_color_override("font_color", Color("002c19"))
	_button(actions, "M  Orbital map", _toggle_map).custom_minimum_size.y = 28
	var ball_root := Control.new()
	flight_ui.add_child(ball_root)
	ball_root.anchor_top = 1
	ball_root.anchor_bottom = 1
	_rect_offsets(ball_root, Rect2(16, -340, 360, 320))
	ball_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	navball = Instruments.new()
	navball.size = Vector2(360, 320)
	ball_root.add_child(navball)
	navball.throttle_changed.connect(func(value: float):
		if mode == "flight" and not paused: _set_throttle(value)
	)
	navball.sas_toggled.connect(func():
		if mode == "flight" and not paused: _toggle_sas()
		_update_controls()
	)
	var clock_panel := _flight_panel(Rect2(-165, -83, 330, 63), false, true)
	clock_panel.get_parent().anchor_left = 0.5
	clock_panel.get_parent().anchor_right = 0.5
	var clock_row := HBoxContainer.new()
	clock_panel.add_child(clock_row)
	_button(clock_row, "Ⅱ", _toggle_pause).custom_minimum_size = Vector2(32, 26)
	mission_clock = _label(clock_row, "T+ 00:00:00", 16, Color("c8d0ef"))
	warp_button = _button(clock_row, "1× time", _cycle_warp)
	warp_button.custom_minimum_size = Vector2(104, 26)
	warp_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warp_button.clip_text = true
	warp_button.add_theme_font_size_override("font_size", 12)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 3)
	clock_panel.add_child(speeds)
	for speed in WARP_STEPS:
		var button := _button(speeds, "▶", func(): _select_warp_step(speed))
		button.custom_minimum_size = Vector2(24, 19)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 10)
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
		warp_arrows.append(button)
	map_panel = PanelContainer.new()
	flight_ui.add_child(map_panel)
	map_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_panel.offset_top = 90
	map_panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.07, 0.1, 0.97), Color("51727a"), 12, 0))
	map_instrument = preload("res://scripts/orbital_map.gd").new()
	map_instrument.source_world = world
	map_panel.add_child(map_instrument)
	map_instrument.warp_to_requested.connect(_warp_to_location)
	map_instrument.cancel_warp_requested.connect(_cancel_warp_to)
	map_instrument.plan_edit_started.connect(_cancel_warp_to)
	map_panel.hide()
	map_panel.visibility_changed.connect(_sync_map_rendering)
	_sync_map_rendering()

func _refresh_design(save: bool = true, refresh_world: bool = true) -> void:
	design = Parts.Craft.project(Parts.Craft.load_craft(design), design)
	if refresh_world:
		world.set_design(design)
	var stats: Dictionary = Parts.stats(design)
	tank_label.text = "%d tanks · %s" % [design.tanks, "no engine" if design.engine.is_empty() else "%s engine" % stats.engine_name]
	_refresh_assembly()
	craft_caption.text = design.name
	stats_labels.wet_mass.text = "%.2f t" % (stats.wet_mass / 1000)
	var mass_properties := Parts.mass_properties(design,stats.core_fuel_mass,stats.booster_fuel_mass,design.boosters)
	stats_labels.wet_mass.tooltip_text = "%d separators · %d boosters\nDry mass: %.0f kg\nLateral center-of-mass offset: %.3f m" % [stats.separator_count,stats.booster_count,stats.dry_mass,Vector2(mass_properties.center.x,mass_properties.center.z).length()]
	stats_labels.thrust.text = "%d kN" % (stats.thrust / 1000)
	stats_labels.twr.text = "%.2f" % stats.twr
	stats_labels.delta_v.text = "%s m/s" % str(roundi(stats.delta_v))
	stats_labels.fuel_mass.text = "%.2f t" % (stats.core_fuel_mass / 1000)
	var can_roll_out := Parts.Craft.can_roll_out(design.assembly)
	launch_button.disabled = not can_roll_out
	var advisories := Parts.Craft.blockers(design.assembly)
	if stats.twr <= 1.05 and not design.engine.is_empty():
		advisories.append("Low thrust: use a stronger engine or fewer tanks.")
	stats_labels.readiness.text = "Ready for rollout." if can_roll_out else "Place a command capsule to roll out."
	if can_roll_out and not advisories.is_empty():
		stats_labels.readiness.text += "\nFlight advisories:\n" + "\n".join(advisories)
	stats_labels.readiness.add_theme_color_override("font_color", MINT if can_roll_out and advisories.is_empty() else ORANGE)
	stats_labels.records.text = "%d flights  ·  %d recovered\nBest altitude: %s" % [profile.data.flights, profile.data.recoveries, _distance(profile.data.best_altitude)]
	for key in engine_buttons:
		engine_buttons[key].add_theme_stylebox_override("normal", _style(Color("284e49") if key == design.engine else Color("203138"), MINT if key == design.engine else Color("3c5056"), 6, 12))
	_refresh_mission()
	if save:
		profile.data.design = design.duplicate(true)
		if not profile.save():
			_toast(profile.last_error)

func _refresh_mission() -> void:
	var mission: Dictionary = MISSIONS[mission_index]
	mission_tag.text = mission.tag
	mission_description.text = mission.description
	var hints := ["Start small. Cut the engine at 1 km, coast, separate the capsule, and deploy your chute on descent.", "More fuel means more altitude. Separate the capsule after the climb; deploy the chute below 2.5 km.", "Climb until apoapsis reaches 45 km, cut thrust, turn sideways above 18 km, then burn near the top."]
	mission_hint.text = "✓ Completed — fly it again." if mission.id in profile.data.completed else hints[mission_index]

func _build_terrain_editor(parent: VBoxContainer) -> void:
	terrain_controls = {}
	terrain_labels = {}
	terrain_settings = PlanetSurface.home().definition.duplicate()
	_label(parent, "MAP EDITOR", 11, MINT)
	_label(parent, "Procedural world", 24)
	terrain_labels.seed = _label(parent, "", 13, MUTED)
	terrain_controls.seed = SpinBox.new()
	terrain_controls.seed.min_value = 1
	terrain_controls.seed.max_value = 999999
	terrain_controls.seed.step = 1
	terrain_controls.seed.rounded = true
	terrain_controls.seed.custom_minimum_size.y = 38
	terrain_controls.seed.value_changed.connect(func(value: float):
		terrain_settings.terrain_seed = int(value)
		_refresh_terrain_editor()
	)
	parent.add_child(terrain_controls.seed)
	_terrain_slider(parent, "sea_threshold", "Sea level", -0.35, 0.25, 0.01)
	_terrain_slider(parent, "continent_frequency", "Continents", 0.6, 6.0, 0.05)
	_terrain_slider(parent, "continent_edge_smoothness", "Continent edge", 0.02, 0.35, 0.01)
	_terrain_slider(parent, "relief", "Relief", 600.0, 5200.0, 50.0)
	_terrain_slider(parent, "mountain_frequency", "Mountains", 2.0, 18.0, 0.1)
	_terrain_slider(parent, "ridge_roundness", "Ridge roundness", 0.02, 0.5, 0.01)
	terrain_controls.ocean = CheckBox.new()
	terrain_controls.ocean.text = "Ocean"
	terrain_controls.ocean.toggled.connect(func(value: bool): terrain_settings.has_ocean = value)
	parent.add_child(terrain_controls.ocean)
	terrain_controls.launch_site = CheckBox.new()
	terrain_controls.launch_site.text = "Launch island"
	terrain_controls.launch_site.toggled.connect(func(value: bool): terrain_settings.launch_site = value)
	parent.add_child(terrain_controls.launch_site)
	terrain_controls.launch_central_hill = CheckBox.new()
	terrain_controls.launch_central_hill.text = "Launch central hill"
	terrain_controls.launch_central_hill.toggled.connect(func(value: bool): terrain_settings.launch_central_hill = value)
	parent.add_child(terrain_controls.launch_central_hill)
	terrain_controls.launch_apron = CheckBox.new()
	terrain_controls.launch_apron.text = "Launch apron"
	terrain_controls.launch_apron.toggled.connect(func(value: bool): terrain_settings.launch_apron = value)
	parent.add_child(terrain_controls.launch_apron)
	terrain_controls.launch_coast = CheckBox.new()
	terrain_controls.launch_coast.text = "Launch coast"
	terrain_controls.launch_coast.toggled.connect(func(value: bool): terrain_settings.launch_coast = value)
	parent.add_child(terrain_controls.launch_coast)
	terrain_controls.launch_rings = CheckBox.new()
	terrain_controls.launch_rings.text = "Launch rings"
	terrain_controls.launch_rings.toggled.connect(func(value: bool): terrain_settings.launch_rings = value)
	parent.add_child(terrain_controls.launch_rings)
	var row := HBoxContainer.new()
	parent.add_child(row)
	_button(row, "Apply", _apply_terrain_settings, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "Random", _randomize_terrain_seed).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(parent, "Reset Verdant", _reset_terrain_settings)
	_refresh_terrain_editor()

func _show_terrain_editor() -> void:
	get_tree().change_scene_to_file("res://scenes/planet_editor.tscn")

func _terrain_slider(parent: VBoxContainer, key: String, title: String, minimum: float, maximum: float, step: float) -> void:
	var label := _label(parent, "", 13, MUTED)
	terrain_labels[key] = label
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size.y = 26
	slider.value_changed.connect(func(value: float):
		terrain_settings.set(key, value)
		terrain_labels[key].text = "%s: %s" % [title, _terrain_value_text(key, value)]
	)
	terrain_controls[key] = slider
	parent.add_child(slider)

func _refresh_terrain_editor() -> void:
	if terrain_settings == null or terrain_controls.is_empty():
		return
	terrain_labels.seed.text = "Seed: %d" % int(terrain_settings.terrain_seed)
	terrain_controls.seed.set_value_no_signal(int(terrain_settings.terrain_seed))
	for key in ["sea_threshold", "continent_frequency", "continent_edge_smoothness", "relief", "mountain_frequency", "ridge_roundness"]:
		var value := float(terrain_settings.get(key))
		terrain_controls[key].set_value_no_signal(value)
		var titles := {"sea_threshold": "Sea level", "continent_frequency": "Continents", "continent_edge_smoothness": "Continent edge", "relief": "Relief", "mountain_frequency": "Mountains", "ridge_roundness": "Ridge roundness"}
		terrain_labels[key].text = "%s: %s" % [titles[key], _terrain_value_text(key, value)]
	terrain_controls.ocean.button_pressed = bool(terrain_settings.has_ocean)
	terrain_controls.launch_site.button_pressed = bool(terrain_settings.launch_site)
	terrain_controls.launch_central_hill.button_pressed = bool(terrain_settings.launch_central_hill)
	terrain_controls.launch_apron.button_pressed = bool(terrain_settings.launch_apron)
	terrain_controls.launch_coast.button_pressed = bool(terrain_settings.launch_coast)
	terrain_controls.launch_rings.button_pressed = bool(terrain_settings.launch_rings)

func _terrain_value_text(key: String, value: float) -> String:
	if key == "relief":
		return _distance(value)
	if key in ["continent_frequency", "mountain_frequency"]:
		return "%.2f" % value
	return "%.2f" % value

func _apply_terrain_settings() -> void:
	PlanetSurface.reset_home(terrain_settings)
	flight.terrain = PlanetSurface.home()
	world.reload_planet()
	if map_instrument != null and map_instrument.globe != null:
		map_instrument.globe.mesh = world._planet.mesh
	_toast("Terrain rebuilt from editor settings.")

func _randomize_terrain_seed() -> void:
	terrain_settings.terrain_seed = randi_range(1, 999999)
	_refresh_terrain_editor()
	_apply_terrain_settings()

func _reset_terrain_settings() -> void:
	terrain_settings = PlanetSurface.HOME.duplicate()
	_refresh_terrain_editor()
	_apply_terrain_settings()

func _change_tanks(amount: int) -> void:
	if amount > 0 and Parts.Craft.can_add_tank(design.assembly):
		_attach_part("tank", "tank")
	elif amount < 0:
		_remove_attachment("tank")
	_refresh_design()

func _save_design() -> void:
	if design.name.strip_edges().is_empty():
		design.name = "Untitled craft"
		craft_name.text = design.name
	profile.data.design = design.duplicate(true)
	_toast("Design saved to this computer." if profile.save() else profile.last_error)

func _roll_out() -> void:
	if _preparing_launch: return
	_cancel_warp_to()
	design = Parts.Craft.project(Parts.Craft.load_craft(design), design)
	if not Parts.Craft.can_roll_out(Parts.Craft.load_craft(design)):
		_toast("Place a command capsule before rollout.")
		return
	_close_modal()
	_preparing_launch = true
	var cover := ColorRect.new()
	cover.name = "LaunchLoadingCover"
	cover.color = INK
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := _label(cover, "Preparing launch…", 18, MINT)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	ui.add_child(cover)
	var was_tree_paused := get_tree().paused
	get_tree().paused = true
	# Present the cover before rebuilding the craft or sampling its wake hull.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	_save_design()
	mode = "flight"
	workshop.hide()
	hud_hidden = false
	flight.reset(design)
	sound.reset_for_launch()
	stage_fuel_capacity = flight.state.engine_fuel.duplicate()
	if stage_fuel_capacity.is_empty():
		for engine in Parts.Craft.engines(design): stage_fuel_capacity[engine.id] = flight.state.max_fuel
	_last_stage_display = ""
	# The launch design is fixed for this flight; only the stage index changes.
	_flight_stage_plan = Parts.stage_plan(design)
	map_instrument.reset_history(Vector3(flight.state.position))
	world.set_design(design)
	world.set_mode("flight")
	world.sync_flight(flight.telemetry(), 0)
	map_panel.hide()
	_update_hud_visibility()
	throttle = 1
	sas = true
	warp = 1
	physical_warp = false
	recorded = false
	flight_completed = false
	_update_controls()
	_update_flight_ui()
	await _prewarm_flight_effects()
	cover.free()
	get_tree().paused = was_tree_paused
	_preparing_launch = false
	_toast("Launchpad clear. SPACE to ignite · H to hide HUD.")

## Prepare CPU resources and draw each rendering path under the launch cover.
## The caller keeps simulation paused until all viewports have been restored.
func _prewarm_flight_effects() -> void:
	flight.prepare_terrain_contacts()
	world.prepare_impact_pool()
	var terrain = PlanetSurface.home()
	var launch_mesh: Mesh = world._planet.mesh
	world.prewarm_effects(true)
	for lod in terrain.RENDER_LODS.size():
		world._planet.mesh = terrain.render_mesh_for_lod(lod)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	# The opaque chute variant is a separate shader from the faded one.
	world.prewarm_effects(true, true)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	world._planet.mesh = launch_mesh
	world.prewarm_effects(false)
	world.sync_flight(flight.telemetry(), 0)
	if DisplayServer.get_name() != "headless":
		await world._clouds.prewarm()
		map_panel.show()
		await map_instrument.prewarm_views()
		map_panel.hide()
		# Let the flight view and its clouds draw again before uncovering the launchpad.
		await RenderingServer.frame_post_draw

func _return_workshop() -> void:
	_cancel_warp_to()
	if mode == "flight" and flight.state.get("status") != "ready" and not recorded:
		_record_flight()
	_close_modal()
	mode = "workshop"
	hud_hidden = false
	_update_hud_visibility()
	workshop.show()
	map_panel.hide()
	world.set_design(design)
	world.set_mode("workshop")
	_refresh_design(false)

func _physics_process(delta: float) -> void:
	if mode != "flight" or paused:
		return
	world.begin_flight_tick()
	_enforce_warp_limit()
	_prepare_warp_to()
	var start_time: float = flight.simulation_time()
	if flight.state.status == "ready":
		flight.state.throttle = throttle
		if warp > 1.0 and not physical_warp:
			flight.step_rails(delta * warp, warp)
		else:
			flight.advance_prelaunch_time(delta * warp)
	var before: String = flight.state.get("status", "ready")
	if before == "ready":
		world.sync_flight(flight.telemetry(), delta)
	if before in ["flying", "landed", "crashed"]:
		var editing_maneuver: bool = map_panel.visible and (get_viewport().gui_get_focus_owner() is LineEdit or map_instrument.maneuver_gizmo.dragging >= 0)
		var adjustment := float(Input.is_physical_key_pressed(KEY_SHIFT)) - float(Input.is_physical_key_pressed(KEY_CTRL))
		if not editing_maneuver: _set_throttle(throttle + adjustment * delta * 0.5)
		var controls := {"pitch": float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)), "yaw": float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), "roll": float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)), "throttle": throttle, "sas": sas}
		if editing_maneuver:
			controls.pitch = 0.0
			controls.yaw = 0.0
			controls.roll = 0.0
		flight.state.throttle = throttle
		var simulation_delta := delta * warp
		if warp_target_time >= 0.0:
			simulation_delta = minf(simulation_delta, maxf(0.0, warp_target_time - flight.simulation_time()))
		if warp > 1.0 and not physical_warp:
			flight.step_rails(simulation_delta, warp)
		else:
			flight.step(simulation_delta, controls)
		var state: Dictionary = flight.telemetry()
		map_instrument.record_flight(state)
		world.sync_flight(state, 0.0 if warp > 1.0 and not physical_warp else simulation_delta, delta)
		if mission_index == 2 and state.get("orbit_achieved", false):
			_complete_mission()
		if state.status in ["landed", "crashed"] and not recorded:
			_record_flight()
			warp = 1
			_toast("Touchdown. The world keeps running. ESC for the flight report or workshop.")
	world.advance_solar_time(flight.simulation_time() - start_time)
	world.set_planet_time(flight.simulation_time())
	world.end_flight_tick(warp <= 1.0 or physical_warp)
	_enforce_warp_limit()
	if warp_target_time >= 0.0:
		if flight.simulation_time() >= warp_target_time - 0.00001:
			_cancel_warp_to("Reached the selected orbit point. Time is back to 1×.")
		elif flight.state.status != "flying" or flight.warp_limit(throttle) <= 1.0:
			_cancel_warp_to("Warp stopped at a safety limit before the selected point.")
	_update_flight_ui()

func _process(delta: float) -> void:
	if mode == "flight":
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
		world.present_flight_frame(Engine.get_physics_interpolation_fraction(), paused)
	# Keep the current outline while orbiting/panning; passing parts under the
	# stationary pointer is camera navigation, not a new selection.
	if mode == "workshop" and not workshop_orbit_drag and not workshop_pan_drag:
		if not get_viewport().gui_is_dragging(): _update_part_hover()
		if not return_drag_kind.is_empty() and get_viewport().gui_is_dragging():
			var mouse := get_viewport().get_mouse_position()
			var over_catalogue: bool = assembly_list.get_parent().get_global_rect().has_point(mouse)
			if over_catalogue:
				return_drag_snap_slot = "inventory"
				if is_instance_valid(world):
					world.preview_subassembly_drag(_affected_part_ids(return_drag_id), return_drag_id, mouse, true)
			else:
				_update_return_drag(return_drag_id, mouse)
		else:
			var preview := selected_part
			if not get_viewport().gui_is_dragging() and not highlight_action.is_empty():
				preview = highlight_action.get_slice(":", 1)
				if preview == "decoupler": preview = "separation"
			if not get_viewport().gui_is_dragging():
				if is_instance_valid(world):
					if not selected_part.is_empty(): world.preview_subassembly(_affected_part_ids(selected_part), true)
					elif not hovered_part.is_empty(): world.preview_subassembly(_affected_part_ids(hovered_part), false)
					else: world.preview_part(preview)
	if toast_time > 0:
		toast_time -= delta
		toast_label.modulate.a = minf(1.0, maxf(0.0, toast_time))
	sound.update_engines(flight.state if mode == "flight" else {}, flight._engines,
		throttle, delta, paused and mode == "flight")

func _update_part_hover() -> void:
	if not is_instance_valid(attachment_layer):
		hovered_part = ""
		return
	hovered_part = _part_at(get_viewport().get_mouse_position())

func _part_at(mouse: Vector2) -> String:
	if not is_instance_valid(attachment_layer):
		return ""
	var best_id := ""
	var best_score := INF
	for picker in attachment_layer.get_children():
		if not picker is Control or not picker.get_global_rect().has_point(mouse): continue
		var half_size: Vector2 = picker.size * 0.5
		var delta: Vector2 = mouse - picker.get_global_rect().get_center()
		var score: float = Vector2(delta.x / maxf(1.0, half_size.x), delta.y / maxf(1.0, half_size.y)).length_squared()
		# At distant zoom, neighboring stack targets overlap heavily. The thin
		# decoupler owns the pointer near its ring rather than losing to a tank.
		if picker.part_id in ["decoupler", "engine_decoupler"] or picker.part_id.begins_with("reaction_wheel_"): score *= 0.35
		if score < best_score:
			best_score = score
			best_id = picker.part_id
	return best_id

func _deselect_part() -> void:
	if selected_part.is_empty(): return
	selected_part = ""
	hovered_part = ""
	if highlight_action.begins_with("part:"): highlight_action = ""
	craft_caption.text = str(design.get("name", "New craft"))

func _update_flight_ui() -> void:
	_enforce_warp_limit()
	flight.skip_detached_stages()
	var state: Dictionary = flight.telemetry()
	var plan: Array = flight.staging_groups()
	var next_stage := int(state.get("stage_index", 0))
	stage_button.text = "SPACE   Activate stage %02d" % (next_stage + 1) if next_stage < plan.size() else "Staging complete"
	var display_key := str(plan) + str(next_stage) + str(state.get("removed_parts", [])) + str(state.capsule_only) + str(state.boosters_attached) + str(state.status)
	if display_key != _last_stage_display:
		_last_stage_display = display_key
		for child in flight_stage_list.get_children():
			flight_stage_list.remove_child(child)
			child.queue_free()
		for index in range(plan.size()):
			if flight.attached_stage_actions(index).is_empty(): continue
			var group = preload("res://scripts/stage_group.gd").new()
			group.game = self
			group.index = index
			group.flight_mode = true
			flight_stage_list.add_child(group)
	for group in flight_stage_list.get_children(): group.update_flight(state)
	stage_button.tooltip_text = stage_button.text
	stage_button.disabled = next_stage >= plan.size() or state.status in ["landed", "crashed"]
	state["throttle"] = throttle
	state["warp_limit"] = flight.warp_limit(throttle)
	map_instrument.warp_destination = warp_target_time
	map_instrument.set_flight_state(state)
	var maneuver_direction: Vector3 = map_instrument.maneuver_direction()
	if not maneuver_direction.is_zero_approx(): state["maneuver_direction"] = maneuver_direction
	for key in resource_bars:
		var remaining := float(state.get(key, 0.0))
		var capacity := float(state.get("max_" + key, 0.0))
		resource_bars[key].value = 100.0 * remaining / capacity if capacity > 0 else 0.0
		resource_labels[key].text = "%s    %.2f / %.2f t" % ["LF" if key == "fuel" else "SF", remaining / 1000, capacity / 1000]
	var seconds := int(state.get("time", 0.0))
	mission_clock.text = "T+ %02d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]
	state["throttle"] = throttle
	state["sas"] = sas
	navball.state = state
	navball.queue_redraw()
	if map_panel.visible:
		map_instrument.state = state
		map_instrument.queue_redraw()

func _flight_advice(state: Dictionary) -> String:
	if state.status in ["landed", "crashed"]:
		return "Flight recorded. Watch the remaining stages, or press ESC for the flight report and workshop."
	if state.status == "ready":
		return "Press SPACE to ignite. Start with a straight climb, then experiment with your design."
	if float(state.get("heat_glow", 0.0)) > 0.05:
		return "ATMOSPHERIC HEATING — %.0f K. Reduce speed in dense air; throttle down during ascent." % float(state.temperature)
	if state.boosters_attached and design.get("booster_first", false):
		return "Boosters spent. Press SPACE to jettison them and ignite the core." if state.booster_fuel <= 0.0 else "Flying on solid boosters. The core fuel is reserved. Wait for booster burnout, then press SPACE."
	if state.chute_deployed:
		return "Canopy open. Let the capsule descend. Use time acceleration to speed up the return."
	if state.get("chute_cut", false) and (state.capsule_only or state.vertical_speed < -2):
		return "Parachute cut away. It cannot be deployed again."
	if state.capsule_only and not design.get("parachute", true):
		return "Capsule separated. No parachute is installed."
	var stage_plan := _flight_stage_plan
	var stage_index := int(state.get("stage_index",0))
	if stage_index < stage_plan.size():
		var active_fuel := 0.0
		for id in state.get("active_engines", []): active_fuel += float(state.get("engine_fuel", {}).get(id,state.fuel))
		if not state.engine_on or active_fuel <= 0.0:
			return "Press SPACE to " + stage_plan[stage_index] + "."
	if state.capsule_only:
		return "Activate the parachute stage with SPACE below 2.5 km, while descending under 180 m/s."
	if state.vertical_speed < -2 and design.get("parachute", true):
		return "Coming down. Activate the parachute stage with SPACE below 2.5 km and under 180 m/s."
	if mission_index < 2 and state.max_altitude >= MISSIONS[mission_index].target:
		return "Target altitude reached! Press X to cut thrust. Separate the capsule, then recover safely."
	if state.fuel <= 0:
		return "Liquid fuel depleted. Separate the capsule for recovery, or check your trajectory with M."
	if mission_index == 2:
		return "Turn gently with W A S D. An orbit needs sideways speed; use M to watch both ends rise."
	return "Climb to %s, cut thrust with X, and bring the capsule home." % _distance(MISSIONS[mission_index].target)

func _set_throttle(value: float) -> void:
	if value > 0.0 and warp_target_time >= 0.0: _cancel_warp_to("Warp cancelled by throttle input.")
	throttle = clampf(value, 0, 1)
	if is_instance_valid(navball):
		navball.state["throttle"] = throttle
		navball.queue_redraw()
	_enforce_warp_limit()

func _stage() -> void:
	if mode != "flight" or paused:
		return
	_cancel_warp_to()
	if design.has("assembly"):
		_toast(flight.execute_stage())
	elif flight.state.status == "ready":
		flight.ignite()
		_toast("Ignition. Your flight begins.")
	else:
		_toast(flight.stage())
	_enforce_warp_limit()
	world.sync_flight(flight.telemetry(), 0)
	_update_flight_ui()

func _chute() -> void:
	if mode == "flight" and not paused:
		_cancel_warp_to()
		_toast(flight.deploy_chute())
		world.sync_flight(flight.telemetry(), 0)

func _toggle_sas() -> void:
	sas = not sas
	_update_controls()

func _engines_running() -> bool:
	var state: Dictionary = flight.state
	if mode != "flight" or state.get("status", "ready") != "flying":
		return false
	if state.get("engine_on", false) and not state.get("capsule_only", false) and float(state.get("fuel", 0.0)) > 0.0 and throttle > 0.0:
		return true
	if state.get("boosters_on", false) and state.get("boosters_attached", false) and float(state.get("booster_fuel", 0.0)) > 0.0:
		return true
	for piece in state.get("detached", []):
		if float(piece.get("fuel", 0.0)) > 0.0 and float(piece.get("thrust", 0.0)) > 0.0:
			return true
	return false

func _enforce_warp_limit() -> void:
	var limit := flight.warp_limit(throttle)
	if physical_warp:
		warp = minf(warp, 4.0)
	else:
		warp = minf(warp, limit)
	# Theme overrides invalidate control layout; refresh only when the UI changes.
	var ui_state := Vector3(warp, limit, 1.0 if physical_warp else 0.0)
	if ui_state == _last_warp_ui_state:
		return
	_last_warp_ui_state = ui_state
	if is_instance_valid(warp_button):
		warp_button.disabled = false
		warp_button.text = "%d× %s" % [warp, "physics" if physical_warp else "time"]
		warp_button.tooltip_text = "Period: cycle warp. Alt+Period: physical warp (1–4×). High-speed warp requires zero throttle and sufficient altitude, or a stationary surface vessel."

	for index in range(warp_arrows.size()):
		var arrow := warp_arrows[index]
		var speed: int = WARP_STEPS[index]
		var available := speed <= 4 or speed <= limit
		var selected := float(speed) <= warp
		# Landed vessels flip availability as they settle; touch only what
		# changed, because each theme override invalidates the HUD layout.
		if arrow.disabled != not available:
			arrow.disabled = not available
			arrow.modulate.a = 1.0 if available else 0.2
		var tint := Color("00e75b") if selected else Color("9397a3")
		if not arrow.has_theme_color_override("font_color") or arrow.get_theme_color("font_color") != tint:
			for state_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
				arrow.add_theme_color_override(state_name, tint)
		arrow.tooltip_text = "%d× %s%s" % [speed, "physics" if speed > 1 and speed <= 4 else "time", " — unavailable under current flight conditions" if not available else ""]

func _select_warp_step(speed: int) -> void:
	if mode != "flight" or speed not in WARP_STEPS:
		return
	if speed > 4 and speed > flight.warp_limit(throttle):
		return
	_cancel_warp_to()
	physical_warp = speed > 1 and speed <= 4
	warp = float(speed)
	if not physical_warp and warp > 1.0:
		flight.state.angular_velocity = Vector3.ZERO
	_update_controls()

func _cycle_warp(physical: bool = false) -> void:
	_cancel_warp_to()
	_enforce_warp_limit()
	var limit: float = flight.warp_limit(throttle)
	var use_physics := physical or limit == 1.0
	if use_physics != physical_warp:
		warp = 1.0
	physical_warp = use_physics
	var speeds := [1.0, 2.0, 3.0, 4.0] if physical_warp else [1.0, 5.0, 10.0, 50.0, 100.0, 1000.0, 10000.0, 100000.0]
	var next: float = speeds[(speeds.find(warp) + 1) % speeds.size()]
	warp = next if physical_warp or next <= limit else 1.0
	if not physical_warp and warp > 1.0:
		flight.state.angular_velocity = Vector3.ZERO
	if physical_warp and warp > 2.0 and _engines_running():
		_toast("High physical warp under thrust can reduce simulation accuracy. Use 2× for demanding burns.")
	_update_controls()

func _update_controls() -> void:
	_enforce_warp_limit()
	if is_instance_valid(navball):
		navball.state["sas"] = sas
		navball.state["throttle"] = throttle
		navball.queue_redraw()

func _toggle_hud() -> void:
	if mode != "flight":
		return
	hud_hidden = not hud_hidden
	_update_hud_visibility()

func _update_hud_visibility() -> void:
	header.visible = mode == "workshop" and not hud_hidden
	toast_label.visible = not hud_hidden
	flight_ui.visible = mode == "flight" and not hud_hidden
	_sync_map_rendering()

func _toggle_map() -> void:
	if hud_hidden:
		hud_hidden = false
		map_panel.hide()
		_update_hud_visibility()
	map_panel.visible = not map_panel.visible

func _sync_map_rendering() -> void:
	var showing := map_panel.is_visible_in_tree()
	# The map has its own 3D world. Keep only the active viewport rendering.
	get_viewport().disable_3d = showing
	world.rendering_suspended = showing
	if not showing and mode == "flight": world.sync_flight(flight.telemetry(),0.0)
	map_instrument.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if showing else SubViewport.UPDATE_DISABLED

func _input(event: InputEvent) -> void:
	if _preparing_launch:
		get_viewport().set_input_as_handled()
		return
	if _workshop_camera_input(event):
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(asset_viewer):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			_close_asset_viewer()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if mode == "workshop" and event.ctrl_pressed and event.physical_keycode in [KEY_Z, KEY_Y] and not get_viewport().gui_get_focus_owner() is LineEdit:
			if event.physical_keycode == KEY_Y or event.shift_pressed: _redo_edit()
			else: _undo_edit()
			get_viewport().set_input_as_handled()
			return
		if mode == "workshop" and not selected_part.is_empty() and not get_viewport().gui_get_focus_owner() is LineEdit:
			if event.physical_keycode == KEY_DELETE:
				_checkpoint()
				for root_id in _removal_roots(selected_part): Parts.Craft.remove_part(design.assembly,root_id)
				selected_part = ""
				highlight_action = ""
				_refresh_design()
				get_viewport().set_input_as_handled()
				return
			if event.physical_keycode == KEY_R:
				_checkpoint()
				for part in design.assembly.parts:
					if part.id == selected_part:
						var next_angle := fmod(float(part.rotation)+90.0,360.0)
						if part.kind != "separator" or Parts.Craft.surface_clear(design,part.parent,deg_to_rad(next_angle),part.surface_offset,part.id): part.rotation = next_angle
				_refresh_design()
				get_viewport().set_input_as_handled()
				return
			if event.ctrl_pressed and event.physical_keycode == KEY_D and selected_part.begins_with("tank_"):
				_attach_part("tank", "tank")
				get_viewport().set_input_as_handled()
				return
		if event.physical_keycode == KEY_ESCAPE:
			_toggle_pause()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_F11:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
		if mode == "flight" and not paused:
			# Typing signed burn values must not also throttle, stage, or close the map.
			if map_panel.visible and get_viewport().gui_get_focus_owner() is LineEdit:
				return
			if event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_X]:
				_cancel_warp_to()
			if event.physical_keycode in [KEY_SPACE, KEY_X, KEY_Z, KEY_T, KEY_M, KEY_H, KEY_PERIOD]:
				get_viewport().set_input_as_handled()
			match event.physical_keycode:
				KEY_SPACE: _stage()
				KEY_X: _set_throttle(0)
				KEY_Z: _set_throttle(1)
				KEY_T: _toggle_sas()
				KEY_M: _toggle_map()
				KEY_H: _toggle_hud()
				KEY_PERIOD: _cycle_warp(event.alt_pressed or event.meta_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if paused:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		world.orbit_camera(event.relative)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			world.zoom_camera(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			world.zoom_camera(1)

func _complete_mission() -> void:
	if flight_completed:
		return
	flight_completed = true
	var id: String = MISSIONS[mission_index].id
	if not id in profile.data.completed:
		profile.data.completed.append(id)
		if not profile.save():
			_toast(profile.last_error)
	sound.ping(true)
	_toast("Flight objective complete: " + MISSIONS[mission_index].name)

func _record_flight() -> void:
	if recorded:
		return
	recorded = true
	var state: Dictionary = flight.telemetry()
	profile.data.flights += 1
	profile.data.best_altitude = maxf(profile.data.best_altitude, state.max_altitude)
	if state.status == "landed":
		profile.data.recoveries += 1
		if mission_index < 2 and state.max_altitude >= MISSIONS[mission_index].target:
			_complete_mission()
	if not profile.save():
		_toast(profile.last_error)

func _modal_box(title: String, subtitle: String) -> VBoxContainer:
	_close_modal()
	paused = true
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(modal)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.035, 0.05, 0.8)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(backdrop)
	var panel := PanelContainer.new()
	modal.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_rect_offsets(panel, Rect2(-240, -285, 480, 570))
	panel.custom_minimum_size = Vector2(480, 0)
	panel.add_theme_stylebox_override("panel", _style(INK, Color("456166"), 12, 30))
	var box := VBoxContainer.new()
	panel.add_child(box)
	_label(box, "A P H E L I O N   /   FLIGHT WORKS", 11, MINT)
	_label(box, title, 31)
	_wrap(box, subtitle, 15)
	_rule(box)
	return box

func _show_debrief() -> void:
	var state: Dictionary = flight.telemetry()
	var landed: bool = state.status == "landed"
	var box := _modal_box("Welcome home." if landed else "A useful experiment.", "Capsule recovered. Every flight teaches you something." if landed else "The vehicle was lost. Your design and flight records are saved; the next attempt starts in the workshop.")
	_label(box, "MISSION COMPLETE" if flight_completed else "FLIGHT REPORT", 12, MINT if flight_completed else ORANGE)
	_label(box, "Peak altitude    %s\nTop speed        %.1f m/s\nFlight time       %d seconds" % [_distance(state.max_altitude), state.max_speed, state.time], 19)
	_spacer(box)
	_button(box, "Back to the workshop", _return_workshop, true)
	_button(box, "Fly this design again", _roll_out)

func _show_asset_viewer() -> void:
	if is_instance_valid(asset_viewer): return
	_close_modal()
	paused = true
	print("[main] _show_asset_viewer called")
	asset_viewer = preload("res://scenes/asset_viewer.tscn").instantiate()
	asset_viewer.embedded = true
	asset_viewer.close_requested.connect(_close_asset_viewer)
	ui.add_child(asset_viewer)
	get_viewport().disable_3d = true
	world.rendering_suspended = true

func _close_asset_viewer() -> void:
	if not is_instance_valid(asset_viewer): return
	ui.remove_child(asset_viewer)
	asset_viewer.queue_free()
	asset_viewer = null
	paused = false
	_sync_map_rendering()

func _toggle_pause() -> void:
	if modal != null:
		_close_modal()
		return
	var box := _modal_box("Take a breath.", "Design and records are saved locally. Flights in progress are not saved when you quit.")
	_button(box, "Resume", _close_modal, true)
	_button(box, "Asset viewer", _show_asset_viewer)
	if mode == "flight":
		_button(box, "H   %s HUD" % ("Show" if hud_hidden else "Hide"), func():
			_toggle_hud()
			_close_modal()
		)
		if flight.state.status in ["landed", "crashed"]:
			_button(box, "Flight report", _show_debrief)
		_button(box, "Return to workshop", _return_workshop)
	_button(box, "F11   Toggle fullscreen", _toggle_fullscreen)
	var audio_button := _button(box, "Sound: %s" % ("ON" if sound.enabled else "OFF"), func(): pass)
	audio_button.pressed.connect(func():
		sound.enabled = not sound.enabled
		profile.data.sound = sound.enabled
		if not profile.save():
			_toast(profile.last_error)
		audio_button.text = "Sound: %s" % ("ON" if sound.enabled else "OFF")
	)
	# Visual only; takes effect on the next frame, mid-flight included.
	var quality_button := _button(box, "Atmosphere: %s" % str(world.atmosphere_quality).capitalize(), func(): pass)
	quality_button.pressed.connect(func():
		var presets: Array = WorldView.AtmosphereQuality.MENU
		var next: String = presets[(presets.find(world.atmosphere_quality) + 1) % presets.size()]
		world.set_atmosphere_quality(next)
		profile.data.atmosphere_quality = next
		if not profile.save():
			_toast(profile.last_error)
		quality_button.text = "Atmosphere: %s" % next.capitalize()
	)
	_button(box, "Credits & licenses", _show_credits)
	_button(box, "Quit to desktop", _quit)
	_wrap(box, "Prototype %s  ·  Working title\nKeyboard + mouse  ·  F11 fullscreen" % ProjectSettings.get_setting("application/config/version", "dev"), 12)

func _show_credits() -> void:
	var box := _modal_box("Made for the climb.", "An original prototype for Bluffton Flight Works. All rocket meshes, environments, and sounds are generated by this project.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 260
	box.add_child(scroll)
	var text := RichTextLabel.new()
	text.custom_minimum_size.x = 395
	text.fit_content = true
	text.text = "GODOT ENGINE\nhttps://godotengine.org/license\n\n" + Engine.get_license_text() + "\n\nENGINE THIRD-PARTY LICENSES\n"
	var licenses: Dictionary = Engine.get_license_info()
	for key in licenses:
		text.text += "\n" + str(key) + "\n" + str(licenses[key]) + "\n"
	for item in Engine.get_copyright_info():
		text.text += "\n" + str(item) + "\n"
	scroll.add_child(text)
	_button(box, "Back to game", _close_modal, true)

func _close_modal() -> void:
	if modal != null:
		modal.queue_free()
		modal = null
	paused = false

func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _toast(text: String) -> void:
	if toast_label == null:
		return
	toast_label.text = text
	toast_label.modulate.a = 1
	toast_time = 5

func _distance(value: float) -> String:
	if not is_finite(value) or value > 1e8:
		return "Escape"
	if absf(value) >= 1000:
		return "%.2f km" % (value / 1000)
	return "%d m" % roundi(value)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()

func _quit() -> void:
	profile.data.design = design.duplicate(true)
	if mode == "flight" and flight.state.get("status") != "ready" and not recorded:
		_record_flight()
	if not profile.save():
		push_warning(profile.last_error)
	sound.shutdown()
	get_tree().quit()

func _smoke_test() -> void:
	await get_tree().process_frame
	assert(mode == "workshop")
	_change_tanks(1)
	assert(design.tanks >= 2)
	await _roll_out()
	assert(flight.state.status == "ready")
	# Flight hotkeys must work even when a UI button retains keyboard focus.
	warp_button.grab_focus()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.keycode = KEY_SPACE
	key.pressed = true
	get_viewport().push_input(key)
	assert(flight.state.status == "flying")
	assert(warp == 1)
	key = key.duplicate()
	key.pressed = false
	get_viewport().push_input(key)
	for i in range(120):
		flight.step(1.0 / 60.0, {"throttle": 1.0, "sas": true})
	assert(flight.telemetry().altitude > 0)
	world.sync_flight(flight.telemetry(), 1.0 / 60.0)
	_update_flight_ui()
	_toggle_map()
	assert(map_panel.visible)
	assert(get_viewport().disable_3d)
	assert(world.rendering_suspended)
	assert(map_instrument.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	# The map turns the flight view's 3D off; the cloud march must stop with it.
	world._clouds._before_draw()
	assert(not world._clouds.is_drawing())
	_toggle_map()
	assert(not world.rendering_suspended and not get_viewport().disable_3d)
	world._clouds._before_draw()
	assert(world._clouds.is_drawing() == (world._clouds.render_pass() != null and world._clouds.has_clouds()))
	assert(world._planet.position.is_equal_approx(FlightModel.PLANET_CENTER-Vector3(flight.state.position)))
	_toggle_map()
	_toggle_pause()
	assert(paused)
	_close_modal()
	_return_workshop()
	assert(mode == "workshop")
	assert(not get_viewport().disable_3d)
	assert(map_instrument.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	print("PASS: workshop, assembly, rollout, ignition, ascent, map, pause, return")
	sound.shutdown()
	await get_tree().process_frame
	get_tree().quit()


var _stage_panel_snapshot: Array = []

func _refresh_assembly() -> void:
	for child in assembly_list.get_children():
		assembly_list.remove_child(child)
		child.queue_free()
	_wrap(assembly_list, "Drag a part onto the rocket. It turns green when a connection surface is close, and red when placement is invalid.", 13)
	var symmetry := OptionButton.new()
	for count in [1,2,4,6,8]: symmetry.add_item("Single" if count == 1 else "%d-way symmetry" % count, count)
	symmetry.select([1,2,4,6,8].find(radial_symmetry))
	symmetry.tooltip_text = "Radial placement: orbit the camera to reach any side of a tank"
	symmetry.item_selected.connect(func(index):
		radial_symmetry = symmetry.get_item_id(index)
		_refresh_assembly.call_deferred()
	)
	assembly_list.add_child(symmetry)
	var catalogue := [
		["capsule", "Wren command capsule", "380 kg. Begin every vehicle with its command and recovery capsule."],
		["parachute", "Parachute–1 recovery module", "18 kg. Snap onto the capsule top. Animated deployment with an open recovery housing."],
		["decoupler", "Stack decoupler", "Mount below the capsule or gyro to release the lower stack, or below an engine to add a removable shell."],
		["reaction_wheel", "Gyro–1 reaction wheel", "50 kg · 12 kN·m torque per axis. Adds faster pitch, yaw and roll. Place a decoupler underneath to keep the gyro after separation."],
		["tank", "Canister–1 fuel tank", "720 kg fuel · 70 kg dry. Ivory shell with amber bands."],
		["sparrow", "Sparrow engine", "42 kN · 180 kg. Light, dependable starter engine."],
		["kestrel", "Kestrel engine", "64 kN · 260 kg. Efficient propulsion for orbit."],
		["titan", "Titan engine", "98 kN · 410 kg. Heavy lifting power."],
		["separator", "Separator–1 side separators", "12 kg each. Drag anywhere around a tank; choose Single, 2, 4, 6 or 8."],
		["boosters", "Booster–1 solid boosters", "22 kN · 90 kg dry + 320 kg fuel each. Share separator mounts with fuel tanks."],
		["fins", "Stabilizing fins", "45 kg set. Improve stability in the atmosphere."]
	]
	for item in catalogue:
		var card = preload("res://scripts/part_card.gd").new()
		card.part_id = item[0]
		card.title = item[1]
		card.description = item[2]
		card.locked = not _part_available(item[0])
		card.game = self
		assembly_list.add_child(card)
	_refresh_part_selection()
	# Fuel additions and camera/geometry edits usually leave stage rows intact.
	# Rebuilding dozens of controls and shaped labels caused another drop hitch.
	var warnings := Parts.Craft.warnings(design.assembly)
	var signature: Array = [design.assembly.stages, Parts.Craft.engines(design).map(func(engine): return [engine.id, engine.kind]), warnings]
	if signature == _stage_panel_snapshot: return
	_stage_panel_snapshot = signature.duplicate(true)
	for child in stage_preview.get_children():
		stage_preview.remove_child(child)
		child.queue_free()
	_wrap(stage_preview, "Drag items to combine blocks; empty blocks disappear. Matching items follow the selected symmetry count. Shift-drag moves one item. Drag headers to reorder.", 13)
	for index in range(design.assembly.stages.size()):
		var group = preload("res://scripts/stage_group.gd").new()
		group.game = self
		group.index = index
		stage_preview.add_child(group)
	var split_target = preload("res://scripts/stage_group.gd").NewBlock.new()
	split_target.game = self
	stage_preview.add_child(split_target)
	for warning in warnings:
		_wrap(stage_preview, warning, 12, ORANGE)
	_wrap(stage_preview, "Hover over an action to locate its part. Separation highlights the assembly that will leave the capsule. Unsafe chute stages wait for safe descent.", 12)


func _can_attach(part: String, slot: String) -> bool:
	if mode != "workshop" or paused:
		return false
	var kinds: Array = design.assembly.parts.map(func(item): return item.kind)
	match slot:
		"parachute": return part == "parachute" and _part_available(part)
		"capsule": return part == "capsule" and design.assembly.parts.is_empty()
		"engine_decoupler": return part == "decoupler" and not design.engine.is_empty() and not design.assembly.parts.any(func(item): return item.id == "engine_decoupler")
		"decoupler": return part == "decoupler" and not design.get("decoupler", false)
		"reaction_wheel": return part == "reaction_wheel" and _part_available(part)
		"tank": return part == "tank" and "capsule" in kinds and Parts.Craft.can_add_tank(design.assembly)
		"engine": return Parts.ENGINES.has(part) and "tank" in kinds
		"radial_tank": return part == "tank" and design.assembly.parts.size() + radial_symmetry <= Parts.Craft.MAX_PARTS and design.assembly.stages.size() + radial_symmetry <= Parts.Craft.MAX_STAGES and Parts.Craft.free_mounts(design.assembly).size() >= radial_symmetry
		"boosters": return part == "boosters" and design.assembly.parts.size() + radial_symmetry <= Parts.Craft.MAX_PARTS and not Parts.Craft.free_mounts(design.assembly).is_empty()
		_ when slot.begins_with("tank@") or slot.begins_with("side_decoupler@"):
			return _can_side_stack_attach(part, slot)
		_ when slot.begins_with("engine@"):
			if not Parts.Craft.radial_mount(design.assembly,slot.get_slice("@",1)).is_empty(): return _can_side_stack_attach(part, slot)
			return part in Parts.Craft.ENGINE_IDS and design.assembly.parts.any(func(item): return item.id == slot.get_slice("@", 1) and item.kind == "tank")
		_ when slot.begins_with("decoupler@"):
			if not Parts.Craft.radial_mount(design.assembly,slot.get_slice("@",1)).is_empty(): return _can_side_stack_attach(part, slot)
			var parent_id := slot.get_slice("@",1)
			var parent: Dictionary = Parts.Craft.geometry(design).by_id.get(parent_id,{})
			if part != "decoupler" or design.assembly.parts.size() >= Parts.Craft.MAX_PARTS or design.assembly.stages.size() >= Parts.Craft.MAX_STAGES: return false
			if parent.get("kind") == "reaction_wheel":
				return not design.assembly.parts.any(func(item): return item.parent == parent_id and item.port == "bottom" and item.kind == "decoupler")
			return parent.get("kind") in Parts.Craft.ENGINE_IDS and not design.assembly.parts.any(func(item): return item.parent == parent_id and item.port == "bottom")
		_ when slot.begins_with("separator@"):
			return part == "separator" and design.assembly.parts.size() + radial_symmetry <= Parts.Craft.MAX_PARTS and design.assembly.parts.any(func(item): return item.id == slot.get_slice("@", 1) and item.kind == "tank")
		_ when slot.begins_with("fins@"): return part == "fins" and not design.fins
	return false

func _part_available(part: String) -> bool:
	var kinds: Array = design.assembly.parts.map(func(item): return item.kind)
	if kinds.is_empty(): return part == "capsule"
	if part == "reaction_wheel": return "capsule" in kinds and design.assembly.parts.size() < Parts.Craft.MAX_PARTS
	if part == "parachute": return "capsule" in kinds and not "parachute" in kinds and design.assembly.parts.size() < Parts.Craft.MAX_PARTS
	if part == "decoupler": return not _snap_candidates(part).is_empty()
	if part == "tank": return "capsule" in kinds and (Parts.Craft.can_add_tank(design.assembly) or (design.assembly.parts.size() + radial_symmetry <= Parts.Craft.MAX_PARTS and (not Parts.Craft.free_mounts(design.assembly).is_empty() or design.assembly.parts.any(func(item): return item.kind == "tank" and not Parts.Craft.radial_mount(design.assembly,item.id).is_empty() and Parts.Craft.can_add_tank(design.assembly,item.id)))))
	if part == "fins": return "capsule" in kinds and not design.fins
	if not "tank" in kinds: return false
	if part == "separator": return design.assembly.parts.size() + radial_symmetry <= Parts.Craft.MAX_PARTS
	if part == "boosters": return design.assembly.parts.size() + radial_symmetry <= Parts.Craft.MAX_PARTS and _snap_candidates("boosters").size() >= radial_symmetry
	if not kinds.any(func(kind): return kind in Parts.Craft.ENGINE_IDS):
		return part == "tank" or part in Parts.Craft.ENGINE_IDS
	return part == "tank" or part in Parts.Craft.ENGINE_IDS or (part == "separator" and not design.get("separator", false)) or (part == "boosters" and design.assembly.parts.size() + radial_symmetry <= Parts.Craft.MAX_PARTS and not Parts.Craft.free_mounts(design.assembly).is_empty()) or (part == "fins" and not design.fins)

func _attach_part(part: String, slot: String) -> void:
	if not _can_attach(part, slot):
		return
	_checkpoint()
	if "@" in slot and part in Parts.Craft.ENGINE_IDS + ["tank", "decoupler"] and not Parts.Craft.radial_mount(design.assembly,slot.get_slice("@",1)).is_empty():
		design.assembly = _side_stack_edit(part,slot)
		_refresh_design.call_deferred()
		return
	if part == "separator" and not radial_snap.is_empty():
		var previous_stages: Array = design.assembly.stages.duplicate(true)
		for index in range(radial_snap.angles.size()):
			var angle: float = radial_snap.angles[index]
			Parts.Craft.add_part(design.assembly,"separator",radial_snap.get("parents",[])[index] if radial_snap.has("parents") else radial_snap.parent)
			var placed: Dictionary = design.assembly.parts[-1]
			placed.rotation = rad_to_deg(angle)
			placed.surface_offset = radial_snap.offset
		_group_added_stage_actions(design.assembly, previous_stages)
		_refresh_design.call_deferred()
		return
	if (part == "boosters" or (part == "tank" and slot == "radial_tank")) and not radial_snap.is_empty():
		var previous_stages: Array = design.assembly.stages.duplicate(true)
		for mount in radial_snap.mounts: Parts.Craft.add_part(design.assembly,part,mount)
		_group_added_stage_actions(design.assembly, previous_stages)
		_refresh_design.call_deferred()
		return
	var radial_parent := slot.get_slice("@", 1) if slot.begins_with("fins@") or slot.begins_with("separator@") or slot.begins_with("engine@") or slot.begins_with("decoupler@") else ""
	Parts.Craft.add_part(design.assembly, part, "engine" if slot == "engine_decoupler" else radial_parent)
	if part == "fins":
		for installed in design.assembly.parts:
			if installed.id == "fins": installed.surface_offset = drag_fin_offset
	_refresh_design.call_deferred()

func _fin_surface(parent_id: String) -> Array:
	if parent_id == "capsule":
		return [world._capsule_center_local - 0.75, world._capsule_center_local + 0.55]
	var center: float = world.installed_part_position(parent_id).y
	return [center - 0.82, center + 0.82]

# Attachment validation simulates a complete symmetric edit. Its result and
# local targets do not depend on the mouse or camera, only on the assembly.
var _drag_assembly_snapshot: Dictionary = {}
var _drag_symmetry_snapshot := -1
var _drag_candidates: Dictionary = {}
var _drag_validity: Dictionary = {}
var _drag_parents: Dictionary = {}

func _ensure_drag_cache() -> void:
	if _drag_symmetry_snapshot == radial_symmetry and _drag_assembly_snapshot == design.assembly: return
	_drag_assembly_snapshot = design.assembly.duplicate(true)
	_drag_symmetry_snapshot = radial_symmetry
	_drag_candidates.clear()
	_drag_validity.clear()
	_drag_parents.clear()

func _snap_candidates(part: String) -> Array:
	_ensure_drag_cache()
	if not _drag_candidates.has(part):
		_drag_candidates[part] = _calculate_snap_candidates(part)
	# Fin placement adjusts candidate heights for the current pointer.
	return _drag_candidates[part].duplicate(true)

func _calculate_snap_candidates(part: String) -> Array:
	var top := Parts.Craft.stack_top(design)
	if part == "parachute": return [["parachute", world.installed_part_position("parachute")]]
	if part == "capsule": return [["capsule", Vector3(0, world._capsule_center_local, 0)]]
	if part == "reaction_wheel":
		if not _part_available(part): return []
		var parent := Parts.Craft.reaction_wheel_parent(design.assembly)
		return [["reaction_wheel", Vector3(0, Parts.Craft.part_base(design, parent.id) - .1, 0)]]
	if part == "decoupler":
		var mounts: Array = []
		if not design.decoupler: mounts.append(["decoupler", Vector3(0, top + 0.1, 0)])
		for wheel in Parts.reaction_wheels(design):
			var wheel_slot := "decoupler@"+str(wheel.id)
			if _can_attach(part,wheel_slot): mounts.append([wheel_slot, Vector3(0,Parts.Craft.part_base(design,wheel.id)-.1,0)])
		for engine in Parts.Craft.engines(design):
			var slot := "engine_decoupler" if engine.id == "engine" else "decoupler@" + str(engine.id)
			if _can_attach(part, slot): mounts.append([slot, Parts.Craft.lateral_position(design,engine.id)+Vector3(0, Parts.Craft.engine_base(design,engine.id) + 0.1, 0)])
		for tank in design.assembly.parts:
			if tank.kind != "tank" or Parts.Craft.radial_mount(design.assembly,tank.id).is_empty(): continue
			var slot := "side_decoupler@"+str(tank.id)
			if _can_attach(part,slot): mounts.append([slot,Parts.Craft.lateral_position(design,tank.id)+Vector3(0,Parts.Craft.part_base(design,tank.id)+.1,0)])
		return mounts
	# These centers predict the finished placement while the connected lower
	# assembly moves down and the capsule stays fixed.
	if part == "tank":
		var parent: Dictionary = {}
		for item in design.assembly.parts:
			if item.kind in ["tank", "decoupler", "reaction_wheel"] and Parts.Craft.radial_mount(design.assembly,item.id).is_empty(): parent = item
		var bottom := Parts.Craft.part_base(design, str(parent.get("id", "capsule")))
		var mounts: Array = [["tank", Vector3(0, bottom - 1.075, 0)]]
		for item in design.assembly.parts:
			if item.kind not in ["tank","decoupler"] or Parts.Craft.radial_mount(design.assembly,item.id).is_empty(): continue
			mounts.append(["tank@"+str(item.id),Parts.Craft.lateral_position(design,item.id)+Vector3(0,Parts.Craft.part_base(design,item.id)-1.075,0)])
		return mounts
	if part in Parts.Craft.ENGINE_IDS:
		var mounts: Array = []
		var tanks: Array = design.assembly.parts.filter(func(item): return item.kind == "tank")
		for index in range(tanks.size() - 1, -1, -1):
			var tank: Dictionary = tanks[index]
			var children: Array = design.assembly.parts.filter(func(item): return item.parent == tank.id and item.port == "bottom")
			if not children.is_empty() and not children[0].kind in Parts.Craft.ENGINE_IDS: continue
			var slot := "engine" if index == tanks.size() - 1 else "engine@" + str(tank.id)
			var y := Parts.Craft.tank_center(design,tank.id) - 1.075 - 1.2
			mounts.append([slot if Parts.Craft.radial_mount(design.assembly,tank.id).is_empty() else "engine@"+str(tank.id), Parts.Craft.lateral_position(design,tank.id) + Vector3(0,y,0)])
		return mounts
	if part == "boosters":
		var result: Array = []
		for mount in Parts.Craft.radial_instances(design,"separator"):
			if Parts.Craft.free_mounts(design.assembly).any(func(item): return item.id == mount.id):
				var position: Vector3 = mount.position
				position += Vector3(sin(mount.angle),0,cos(mount.angle))*(1.96-1.17)
				result.append(["boosters",position])
		return result
	if part == "separator":
		var result: Array = []
		for item in design.assembly.parts:
			if item.kind == "tank": result.append(["separator@"+item.id,Vector3(0,world.installed_part_position(item.id).y,1.17)])
		return result
	if part == "fins":
		var surfaces: Array = [["fins@capsule", Vector3(1.5, world._capsule_center_local, 0)]]
		var tanks: Array = design.assembly.parts.filter(func(item): return item.kind == "tank")
		for index in range(tanks.size()):
			surfaces.append(["fins@" + str(tanks[index].id), Vector3(1.5, Parts.Craft.tank_center(design,tanks[index].id), 0)])
		return surfaces
	return []

func _update_build_drag(part: String, mouse: Vector2) -> bool:
	drag_snap_slot = ""
	var anchor := Vector3.ZERO
	var nearest := 86.0
	if part == "tank":
		radial_snap = _radial_surface_snap("tank",mouse)
		if not radial_snap.is_empty() and _can_attach(part,"radial_tank"):
			drag_snap_slot = "radial_tank"
			world.preview_radial(part,radial_snap.placements,mouse)
			return true
		radial_snap = {}
	if part in ["separator","boosters"]:
		radial_snap = _radial_surface_snap(part,mouse)
		if not radial_snap.is_empty(): drag_snap_slot = "separator@"+str(radial_snap.parent) if part == "separator" else "boosters"
		world.preview_radial(part,radial_snap.get("placements",[]),mouse)
		return not radial_snap.is_empty()
	if part == "capsule" and design.assembly.parts.is_empty():
		var center_x: float = world.camera.unproject_position(Vector3(0, world.WORKSHOP_CAMERA_FOCUS_Y, 0)).x
		if absf(mouse.x - center_x) < 92.0 and mouse.y > 145.0 and mouse.y < 610.0:
			var ray_origin: Vector3 = world.camera.project_ray_origin(mouse)
			var ray_direction: Vector3 = world.camera.project_ray_normal(mouse)
			if absf(ray_direction.z) > 0.0001:
				var point: Vector3 = ray_origin + ray_direction * (-ray_origin.z / ray_direction.z)
				drag_root_height = clampf(point.y, 3.5, Parts.Craft.MAX_ROOT_HEIGHT)
				drag_snap_slot = "capsule"
				anchor = Vector3(0, drag_root_height - world._rocket.position.y, 0)
		world.preview_drag(part, anchor, not drag_snap_slot.is_empty(), mouse)
		return not drag_snap_slot.is_empty()
	for candidate in _snap_candidates(part):
		if part == "fins":
			var parent_id: String = str(candidate[0]).get_slice("@", 1)
			var bounds := _fin_surface(parent_id)
			var ray_origin: Vector3 = world.camera.project_ray_origin(mouse)
			var ray_direction: Vector3 = world.camera.project_ray_normal(mouse)
			if absf(ray_direction.z) > 0.0001:
				var point: Vector3 = world._rocket.to_local(ray_origin + ray_direction * ((world._rocket.global_position.z - ray_origin.z) / ray_direction.z))
				candidate[1].y = clampf(point.y, bounds[0], bounds[1])
		var hit_anchor: Vector3 = candidate[1]
		var screen: Vector2 = world.camera.unproject_position(world._rocket.to_global(hit_anchor))
		var distance: float = screen.distance_to(mouse)
		if distance < nearest:
			if not _can_attach(part, candidate[0]): continue
			nearest = distance
			drag_snap_slot = candidate[0]
			anchor = candidate[1]
			if part == "fins":
				var parent_id := str(candidate[0]).get_slice("@", 1)
				var parent_center: float = world._capsule_center_local if parent_id == "capsule" else world.installed_part_position(parent_id).y
				drag_fin_offset = anchor.y - parent_center
	if "@" in drag_snap_slot and part in Parts.Craft.ENGINE_IDS + ["tank","decoupler"] and not Parts.Craft.radial_mount(design.assembly,drag_snap_slot.get_slice("@",1)).is_empty():
		var placements: Array = []
		for parent in _side_stack_parents(drag_snap_slot.get_slice("@",1)):
			placements.append({"angle":0.0,"position":Parts.Craft.lateral_position(design,parent)+Vector3(0,anchor.y,0)})
		world.preview_stack_parts(part,placements)
	else:
		world.preview_drag(part, anchor, not drag_snap_slot.is_empty(), mouse, drag_snap_slot == "fins@capsule")
	return not drag_snap_slot.is_empty()

func _finish_build_drag(part: String, mouse: Vector2) -> void:
	if _update_build_drag(part, mouse) and _can_attach(part, drag_snap_slot):
		_attach_part(part, drag_snap_slot)
		if part == "capsule":
			design.assembly.root_height = drag_root_height
			_refresh_design.call_deferred()
	_clear_build_drag()

func _clear_build_drag() -> void:
	drag_snap_slot = ""
	if is_instance_valid(world): world.preview_drag("", Vector3.ZERO, false, Vector2.ZERO)

func _begin_return_drag(id: String) -> void:
	return_drag_single = Input.is_key_pressed(KEY_SHIFT)
	return_drag_id = id
	return_drag_kind = ""
	for part in design.assembly.parts:
		if part.id == id:
			return_drag_kind = str(part.kind)
			break
	selected_part = id
	highlight_action = ""
	return_drag_snap_slot = ""

func _affected_part_ids(id: String) -> Array[String]:
	var result: Array[String] = []
	for root_id in _removal_roots(id,return_drag_single or (return_drag_id == id and Input.is_key_pressed(KEY_SHIFT))):
		for child in Parts.Craft.descendant_ids(design.assembly,root_id):
			if child not in result: result.append(child)
	return result

func _update_return_drag(id: String, mouse: Vector2) -> bool:
	if id != return_drag_id or return_drag_kind.is_empty(): return false
	return_drag_snap_slot = ""
	if return_drag_kind == "separator":
		radial_snap = _radial_surface_snap("separator",mouse,id,1)
		if not radial_snap.is_empty():
			return_drag_snap_slot = "separator@"+str(radial_snap.parent)
			world.preview_radial_move(id,radial_snap.placements[0])
		else: world.preview_subassembly_drag(_affected_part_ids(id),id,mouse,false)
		return not radial_snap.is_empty()
	if return_drag_kind == "capsule":
		var center_x: float = world.camera.unproject_position(Vector3(0, world.WORKSHOP_CAMERA_FOCUS_Y, 0)).x
		if absf(mouse.x - center_x) < 92.0 and mouse.y > 145.0 and mouse.y < 610.0:
			var ray_origin: Vector3 = world.camera.project_ray_origin(mouse)
			var ray_direction: Vector3 = world.camera.project_ray_normal(mouse)
			if absf(ray_direction.z) > 0.0001:
				var point: Vector3 = ray_origin + ray_direction * (-ray_origin.z / ray_direction.z)
				drag_root_height = clampf(point.y, 3.5, Parts.Craft.MAX_ROOT_HEIGHT)
				return_drag_snap_slot = "capsule"
				world.preview_drag("capsule", Vector3(0, drag_root_height - world._rocket.position.y, 0), true, mouse)
				return true
		world.preview_subassembly_drag(_affected_part_ids(id), id, mouse, false)
		return false
	var nearest := 86.0
	var anchor := Vector3.ZERO
	for candidate in _snap_candidates(return_drag_kind):
		if return_drag_kind == "fins":
			var candidate_parent: String = str(candidate[0]).get_slice("@", 1)
			var bounds := _fin_surface(candidate_parent)
			var ray_origin: Vector3 = world.camera.project_ray_origin(mouse)
			var ray_direction: Vector3 = world.camera.project_ray_normal(mouse)
			if absf(ray_direction.z) > 0.0001:
				var point: Vector3 = world._rocket.to_local(ray_origin + ray_direction * ((world._rocket.global_position.z - ray_origin.z) / ray_direction.z))
				candidate[1].y = clampf(point.y, bounds[0], bounds[1])
		var hit_anchor: Vector3 = candidate[1]
		var screen: Vector2 = world.camera.unproject_position(world._rocket.to_global(hit_anchor))
		var distance := screen.distance_to(mouse)
		if distance < nearest:
			nearest = distance
			return_drag_snap_slot = str(candidate[0])
			anchor = candidate[1]
			if return_drag_kind == "fins":
				var parent_id := return_drag_snap_slot.get_slice("@", 1)
				var parent_center: float = world._capsule_center_local if parent_id == "capsule" else world.installed_part_position(parent_id).y
				drag_fin_offset = anchor.y - parent_center
	if return_drag_snap_slot.is_empty():
		world.preview_subassembly_drag(_affected_part_ids(id), id, mouse, false)
	else:
		world.preview_subassembly_snap(_affected_part_ids(id), id, anchor, return_drag_snap_slot == "fins@capsule")
	return not return_drag_snap_slot.is_empty()

func _finish_return_drag(id: String, mouse: Vector2) -> void:
	if not _update_return_drag(id, mouse):
		_end_return_drag()
		return
	var changed := false
	if return_drag_kind == "fins" and return_drag_snap_slot.begins_with("fins@"):
		var parent_id := return_drag_snap_slot.get_slice("@", 1)
		for part in design.assembly.parts:
			if part.id == id and (part.parent != parent_id or absf(float(part.get("surface_offset", 0.0)) - drag_fin_offset) > 0.01):
				_checkpoint()
				part.parent = parent_id
				part.surface_offset = drag_fin_offset
				changed = true
	elif return_drag_kind == "separator" and not radial_snap.is_empty():
		_checkpoint()
		for part in design.assembly.parts:
			if part.id == id:
				part.parent = radial_snap.parent
				part.rotation = rad_to_deg(radial_snap.angles[0])
				part.surface_offset = radial_snap.offset
				# Legacy pairs retain symmetry until replaced from the catalogue.
				changed = true
	elif return_drag_kind == "capsule" and return_drag_snap_slot == "capsule":
		if absf(float(design.assembly.root_height) - drag_root_height) > 0.01:
			_checkpoint()
			design.assembly.root_height = drag_root_height
			changed = true
	if changed:
		if return_drag_kind == "separator":
			var pending: Array = design.assembly.parts.duplicate()
			var ordered: Array = []
			var seen := {}
			while not pending.is_empty():
				var before := pending.size()
				for item in pending.duplicate():
					if item.parent.is_empty() or seen.has(item.parent):
						ordered.append(item)
						seen[item.id] = true
						pending.erase(item)
				if pending.size() == before: break
			if pending.is_empty(): design.assembly.parts = ordered
		_toast("Part repositioned.")
		_refresh_design.call_deferred()
	_end_return_drag()

func _end_return_drag() -> void:
	return_drag_single = false
	return_drag_id = ""
	return_drag_kind = ""
	return_drag_snap_slot = ""
	if is_instance_valid(world): world.preview_drag("", Vector3.ZERO, false, Vector2.ZERO)

func _remove_part_to_catalogue(id: String) -> void:
	if mode != "workshop": return
	if not design.assembly.parts.any(func(part): return part.id == id): return
	_checkpoint()
	if id == "capsule":
		design.assembly.parts.clear()
		design.assembly.stages.clear()
	else:
		for root_id in _removal_roots(id,return_drag_id == id and (return_drag_single or Input.is_key_pressed(KEY_SHIFT))):
			Parts.Craft.remove_part(design.assembly,root_id)
	selected_part = ""
	hovered_part = ""
	highlight_action = ""
	_end_return_drag()
	_clear_build_drag()
	world.preview_part("")
	_toast("Part returned to inventory.")
	_refresh_design.call_deferred()

func _remove_attachment(slot: String) -> void:
	if mode != "workshop" or paused: return
	var id := slot
	if slot == "tank":
		if int(design.tanks) == 0:
			_toast("Keep one fuel tank connected to the core engine.")
			return
		for part in design.assembly.parts:
			if part.kind == "tank": id = part.id
	elif not slot in ["boosters", "separator", "fins", "decoupler", "engine_decoupler", "engine", "parachute"] and not slot.begins_with("separator_") and not slot.begins_with("boosters_") and not slot.begins_with("engine_") and not slot.begins_with("decoupler_") and not slot.begins_with("reaction_wheel_"):
		_toast("Drag an engine onto the mount to replace it.")
		return
	_checkpoint()
	for root_id in _removal_roots(id): Parts.Craft.remove_part(design.assembly,root_id)
	_refresh_design.call_deferred()

func _refresh_part_selection() -> void:
	_ensure_snap_geometry()
	for child in attachment_layer.get_children():
		attachment_layer.remove_child(child)
		child.queue_free()
	var tanks: Array = design.assembly.parts.filter(func(part): return part.kind == "tank")
	# Read central-part anchors from the rendered assembly so pointer regions
	# follow the same layout when fuel changes the rocket's local coordinates.
	var anchors := {
		"capsule": world.installed_part_position("capsule"),
		"parachute": world.installed_part_position("parachute"),
		"decoupler": world.installed_part_position("decoupler"),
		"engine": world.installed_part_position("engine")
	}
	for index in range(tanks.size()):
		anchors[tanks[index].id] = world.installed_part_position(str(tanks[index].id))
	var fins: Array = design.assembly.parts.filter(func(part): return part.kind == "fins")
	if not fins.is_empty():
		var parent_id: String = fins[0].parent
		var parent_center: float = world._capsule_center_local if parent_id == "capsule" else anchors.get(parent_id, Vector3(0, 1.5, 0)).y
		anchors.fins = Vector3(1.5, parent_center + float(fins[0].get("surface_offset", 0.0)), 0)
	var hit_sizes := {"parachute": Vector2(65,90), "capsule": Vector2(112,150), "decoupler": Vector2(118,34), "engine": Vector2(110,86)}
	for part in design.assembly.parts:
		var id: String = part.id
		var specs: Array = []
		if part.kind in ["boosters","separator"]:
			for instance in (_snap_separators if part.kind == "separator" else _snap_boosters):
				if instance.id == id: specs.append([instance.position,Vector2(65,240) if part.kind == "boosters" else Vector2(30,75)])
		elif id == "fins":
			var fin_anchor: Vector3 = anchors.get("fins", Vector3(0,1.5,0))
			for side in [-1.0,1.0]: specs.append([Vector3(side*1.38,fin_anchor.y,0),Vector2(72,145)])
		elif part.kind in Parts.Craft.ENGINE_IDS:
			specs.append([world.installed_part_position(id), Vector2(110,86)])
		elif part.kind in ["decoupler", "reaction_wheel"]:
			specs.append([world.installed_part_position(id), Vector2(118,34)])
		elif anchors.has(id):
			specs.append([anchors[id], hit_sizes.get(id, Vector2(112,128))])
		for spec in specs:
			var picker = preload("res://scripts/installed_part.gd").new()
			picker.game = self
			picker.part_id = id
			picker.anchor = spec[0]
			picker.hit_size = spec[1]
			# The thin decoupler overlaps the edge of adjacent large pointer
			# regions. Keep its exact visible strip first in pointer hit order.
			picker.z_index = 20 if part.kind in ["decoupler", "separator", "reaction_wheel"] else 0
			attachment_layer.add_child(picker)


func _checkpoint() -> void:
	undo_stack.append(design.duplicate(true))
	if undo_stack.size() > 50: undo_stack.pop_front()
	redo_stack.clear()

func _undo_edit() -> void:
	if mode != "workshop" or undo_stack.is_empty(): return
	redo_stack.append(design.duplicate(true))
	design = undo_stack.pop_back()
	craft_name.text = design.name
	_refresh_design()

func _redo_edit() -> void:
	if mode != "workshop" or redo_stack.is_empty(): return
	undo_stack.append(design.duplicate(true))
	design = redo_stack.pop_back()
	craft_name.text = design.name
	_refresh_design()

func _stage_action_for_part(id: String) -> String:
	var action := ""
	for part in design.assembly.parts:
		if part.id != id: continue
		if part.kind in Parts.Craft.ENGINE_IDS: action = "ignite:" + id
		elif part.kind == "boosters": action = "ignite:boosters"
		elif part.kind == "parachute": action = "deploy:capsule"
		elif part.kind in ["separator", "decoupler"]:
			action = "separate:boosters" if id == "separator" else "separate:" + id
	if design.assembly.stages.any(func(group): return group.has(action)): return action
	return ""

# Use the same rotational copies and connection depth as symmetry placement.
func _stage_drag_actions(action: String, together: bool = true) -> Array[String]:
	var result: Array[String] = []
	if not design.assembly.stages.any(func(group): return group.has(action)): return result
	result.append(action)
	if not together: return result
	for stage in design.assembly.stages:
		if not stage.has(action): continue
		for members in _stage_display_groups(stage):
			if action in members and members.size() > 1:
				result.assign(members)
				return result
	for id in _side_stack_parents(action.get_slice(":", 1)):
		var candidate := action.get_slice(":", 0) + ":" + id
		if not result.has(candidate) and design.assembly.stages.any(func(group): return group.has(candidate)):
			result.append(candidate)
	return result

# Display actual rotational groups independently of the builder's current selector.
func _stage_display_groups(actions: Array) -> Array:
	var groups: Array = []
	var kinds: Dictionary = {}
	for part in design.assembly.parts: kinds[part.id] = part.kind
	var seen: Dictionary = {}
	for action in actions:
		if seen.has(action): continue
		var members: Array = [action]
		for count in [8, 6, 4, 2]:
			var copies := _calculate_side_stack_parents(str(action).get_slice(":", 1), count)
			var candidates: Array = []
			for id in copies:
				var candidate: String = str(action).get_slice(":", 0) + ":" + id
				if candidate in actions and not seen.has(candidate) and kinds.get(id) == kinds.get(str(action).get_slice(":", 1)):
					candidates.append(candidate)
			if candidates.size() > members.size(): members = candidates
		for member in members: seen[member] = true
		groups.append(members)
	return groups

func _can_move_action(action: String, destination: int, together: bool = true) -> bool:
	if mode != "workshop" or paused: return false
	if destination < 0 or destination >= design.assembly.stages.size(): return false
	var actions := _stage_drag_actions(action, together)
	var target: Array = design.assembly.stages[destination]
	var added := 0
	for item in actions:
		if not target.has(item): added += 1
	return added > 0 and target.size() + added <= Parts.Craft.MAX_STAGE_ACTIONS

func _move_action(action: String, destination: int, together: bool = true) -> void:
	if not _can_move_action(action, destination, together): return
	var actions := _stage_drag_actions(action, together)
	var target: Array = design.assembly.stages[destination]
	_checkpoint()
	for group in design.assembly.stages:
		if group == target: continue
		for item in actions: group.erase(item)
	for item in actions:
		if not target.has(item): target.append(item)
	design.assembly.stages = design.assembly.stages.filter(func(group): return not group.is_empty())
	_refresh_design.call_deferred()

func _can_split_stage_action(action: String, together: bool = true) -> bool:
	if mode != "workshop" or paused: return false
	var actions := _stage_drag_actions(action, together)
	if actions.is_empty(): return false
	var emptied := 0
	var sources := 0
	for group in design.assembly.stages:
		if group.any(func(item): return actions.has(item)):
			sources += 1
			if group.all(func(item): return actions.has(item)): emptied += 1
	if sources == 1 and emptied == 1: return false
	return design.assembly.stages.size() - emptied + 1 <= Parts.Craft.MAX_STAGES

func _split_stage_action(action: String, together: bool = true) -> void:
	if not _can_split_stage_action(action, together): return
	var actions := _stage_drag_actions(action, together)
	_checkpoint()
	var stages: Array = []
	var inserted := false
	for group in design.assembly.stages:
		var source: bool = group.has(action)
		for item in actions: group.erase(item)
		if not group.is_empty(): stages.append(group)
		if source and not inserted:
			stages.append(actions)
			inserted = true
	design.assembly.stages = stages
	_refresh_design.call_deferred()

func _move_stage(source: int, destination: int) -> void:
	if mode == "flight":
		if not paused and flight.reorder_stage(source, destination):
			_last_stage_display = ""
			_update_flight_ui.call_deferred()
		return
	if source == destination or source < 0 or destination < 0 or source >= design.assembly.stages.size() or destination >= design.assembly.stages.size(): return
	_checkpoint()
	var group: Array = design.assembly.stages.pop_at(source)
	design.assembly.stages.insert(destination, group)
	_refresh_design.call_deferred()

func _delete_stage(index: int) -> void:
	if index < 0 or index >= design.assembly.stages.size(): return
	if design.assembly.stages.size() <= 1 or not design.assembly.stages[index].is_empty(): return
	_checkpoint()
	design.assembly.stages.remove_at(index)
	_refresh_design.call_deferred()


func _new_craft() -> void:
	_checkpoint()
	design = Parts.Craft.project(Parts.Craft.seed(), {"name": "New craft"})
	craft_name.text = design.name
	_refresh_design()


# Dragging changes the pointer every frame, but installed geometry only changes
# on an edit. Keep a value snapshot so undo and in-place part edits invalidate it.
var _snap_parts: Array = []
var _snap_positions: Dictionary = {}
var _snap_centers: Dictionary = {}
var _snap_separators: Array = []
var _snap_boosters: Array = []

func _ensure_snap_geometry() -> void:
	if _snap_parts == design.assembly.parts and not _snap_positions.is_empty(): return
	_snap_parts = design.assembly.parts.duplicate(true)
	_snap_positions.clear()
	_snap_centers.clear()
	for part in design.assembly.parts:
		if part.kind != "tank": continue
		_snap_positions[part.id] = Parts.Craft.lateral_position(design, part.id)
		_snap_centers[part.id] = Parts.Craft.tank_center(design, part.id)
	_snap_separators = Parts.Craft.radial_instances(design, "separator")
	_snap_boosters = Parts.Craft.radial_instances(design, "boosters")


func _radial_surface_snap(kind: String, mouse: Vector2, ignore: String = "", count_override: int = 0) -> Dictionary:
	_ensure_snap_geometry()
	var count := count_override if count_override > 0 else radial_symmetry
	if kind in ["boosters", "tank"]:
		var radius := 2.2 if kind == "tank" else 1.96
		var free: Array = Parts.Craft.free_mounts(design.assembly)
		if kind == "tank": free = free.filter(func(part): return part.port != "radial_pair")
		var mounts: Array = _snap_separators.filter(func(item): return free.any(func(part): return part.id == item.id))
		var nearest := 86.0
		var chosen: Dictionary = {}
		for mount in mounts:
			var pos: Vector3 = mount.position
			pos += Vector3(sin(mount.angle),0,cos(mount.angle))*(radius-1.17)
			var distance: float = world.camera.unproject_position(world._rocket.to_global(pos)).distance_to(mouse)
			if distance < nearest: nearest = distance; chosen = mount
		if chosen.is_empty(): return {}
		var ids: Array = []
		var placements: Array = []
		for index in range(count):
			var angle: float = chosen.angle + TAU*index/count
			var match_mount: Dictionary = {}
			for mount in mounts:
				if absf(angle_difference(angle,mount.angle)) < .04 and mount.position.distance_to(chosen.position.rotated(Vector3.UP,TAU*index/count)) < .04: match_mount = mount
			if match_mount.is_empty(): return {}
			if not ids.has(match_mount.id): ids.append(match_mount.id)
			placements.append({"angle":angle,"position":match_mount.position+Vector3(sin(angle),0,cos(angle))*(radius-1.17)})
		for placement in placements:
			for existing in _snap_boosters:
				var delta: Vector3 = placement.position-existing.position
				if Vector2(delta.x,delta.z).length() < 1.44 and absf(delta.y) < 5.28: return {}
		return {"mounts":ids,"placements":placements}
	var origin: Vector3 = world._rocket.to_local(world.camera.project_ray_origin(mouse))
	var direction: Vector3 = world._rocket.global_basis.inverse()*world.camera.project_ray_normal(mouse)
	var a := direction.x*direction.x+direction.z*direction.z
	if a < 0.000001: return {}
	var hits: Array = []
	var ignored := Parts.Craft.descendant_ids(design.assembly,ignore)
	for tank in design.assembly.parts:
		if tank.kind != "tank" or tank.id in ignored: continue
		var local_origin := origin-Vector3(_snap_positions[tank.id])
		var b := 2.0*(local_origin.x*direction.x+local_origin.z*direction.z)
		var c := local_origin.x*local_origin.x+local_origin.z*local_origin.z-.94*.94
		var discriminant := b*b-4.0*a*c
		if discriminant < 0.0: continue
		var t := (-b-sqrt(discriminant))/(2.0*a)
		if t < 0.0: continue
		var hit := local_origin+direction*t
		var center := float(_snap_centers[tank.id])
		if absf(hit.y-center) <= 1.075: hits.append({"tank":tank,"hit":hit,"distance":t,"center":center})
	hits.sort_custom(func(left,right): return left.distance < right.distance)
	if hits.is_empty(): return {}
	var chosen: Dictionary = hits[0]
	var tank: Dictionary = chosen.tank
	var offset := clampf(chosen.hit.y-chosen.center,-.37,.37)
	var angle := atan2(chosen.hit.x,chosen.hit.z)
	var parents: Array[String] = []
	if count > 1 and not Parts.Craft.radial_mount(design.assembly,tank.id).is_empty():
		parents = _side_stack_parents(tank.id)
		if parents.size() != count: return {}
	else:
		for index in range(count): parents.append(tank.id)
	var angles: Array = []
	var placements: Array = []
	for index in range(count):
		var theta := angle+TAU*index/count
		var position: Vector3 = _snap_positions[parents[index]] + Vector3(sin(theta)*1.17, float(_snap_centers[parents[index]])+offset, cos(theta)*1.17)
		for existing in _snap_separators:
			if existing.id == ignore: continue
			var separation: Vector3 = existing.position - position
			if Vector2(separation.x, separation.z).length() < .38 and absf(separation.y) < 1.42: return {}
		angles.append(theta)
		placements.append({"angle":theta,"position":position})
	return {"parent":tank.id,"parents":parents,"offset":offset,"angles":angles,"placements":placements}

# Match the same connection depth on the selected rotational copies.
func _side_stack_parents(id: String) -> Array[String]:
	_ensure_drag_cache()
	if not _drag_parents.has(id):
		_drag_parents[id] = _calculate_side_stack_parents(id)
	return _drag_parents[id]

func _calculate_side_stack_parents(id: String, count: int = 0) -> Array[String]:
	if count == 0: count = radial_symmetry
	_ensure_snap_geometry()
	var result: Array[String] = []
	var mount := Parts.Craft.radial_mount(design.assembly,id)
	if mount.is_empty(): return result
	var path: Array[String] = []
	var cursor := id
	while cursor != mount.id:
		var nodes: Array = design.assembly.parts.filter(func(part): return part.id == cursor)
		if nodes.is_empty(): return []
		path.push_front(nodes[0].kind)
		cursor = nodes[0].parent
	for index in range(count):
		var angle := deg_to_rad(float(mount.rotation)) + TAU*index/count
		var copies: Array = design.assembly.parts.filter(func(part): return part.kind == "separator" and Vector3(_snap_positions[part.parent]).distance_to(Vector3(_snap_positions[mount.parent]).rotated(Vector3.UP,TAU*index/count)) < .04 and absf(float(_snap_centers[part.parent])-float(_snap_centers[mount.parent])) < .04 and absf(float(part.surface_offset)-float(mount.surface_offset)) < .04 and absf(angle_difference(deg_to_rad(float(part.rotation)),angle)) < .04)
		if copies.size() != 1: return []
		cursor = copies[0].id
		for kind in path:
			var children: Array = design.assembly.parts.filter(func(part): return part.parent == cursor and part.port == "bottom" and (part.kind == kind or (part.kind in Parts.Craft.ENGINE_IDS and kind in Parts.Craft.ENGINE_IDS)))
			if children.size() != 1: return []
			cursor = children[0].id
		result.append(cursor)
	return result

func _side_stack_slot_accepts(part: String, slot: String) -> bool:
	if slot.begins_with("engine@") and part not in Parts.Craft.ENGINE_IDS: return false
	if slot.begins_with("decoupler@") and part != "decoupler": return false
	if (slot.begins_with("tank@") and part != "tank") or (slot.begins_with("side_decoupler@") and part != "decoupler"): return false
	return true

func _can_side_stack_attach(part: String, slot: String) -> bool:
	_ensure_drag_cache()
	if not _side_stack_slot_accepts(part, slot): return false
	var parents := _side_stack_parents(slot.get_slice("@", 1))
	if parents.is_empty(): return false
	# Rotational copies have the same validity. Store one boolean per group,
	# not a complete simulated craft for each of its eight possible targets.
	var group := parents.duplicate()
	group.sort()
	var key := part + ":" + slot.get_slice("@", 0) + ":" + ",".join(group)
	if not _drag_validity.has(key):
		_drag_validity[key] = not _calculate_side_stack_edit(part, slot).is_empty()
	return _drag_validity[key]

func _side_stack_edit(part: String, slot: String) -> Dictionary:
	# Construct the actual edit only on placement, in the selected copy's order.
	return _calculate_side_stack_edit(part, slot)

func _calculate_side_stack_edit(part: String, slot: String) -> Dictionary:
	if not _side_stack_slot_accepts(part, slot): return {}
	var parents := _side_stack_parents(slot.get_slice("@",1))
	if parents.is_empty(): return {}
	var craft: Dictionary = design.assembly.duplicate(true)
	for parent in parents:
		var before: Dictionary = craft.duplicate(true)
		Parts.Craft.add_part(craft,part,parent)
		if craft == before:
			# Replacing an identical engine is a valid no-op on that copy.
			if not (part in Parts.Craft.ENGINE_IDS and craft.parts.any(func(item): return item.parent == parent and item.kind == part)): return {}
	_group_added_stage_actions(craft, design.assembly.stages)
	return craft if Parts.Craft.valid(craft) else {}

# Resolve the installed group independently of the currently selected build symmetry.
# Missing copies (previous Shift removals) do not prevent removing the remainder.
func _removal_roots(id: String, single: bool = false) -> Array[String]:
	var result: Array[String] = [id]
	if single: return result
	var mount := Parts.Craft.radial_mount(design.assembly,id)
	if mount.is_empty(): return result
	var path: Array[String] = []
	var cursor := id
	while cursor != mount.id:
		var matches: Array = design.assembly.parts.filter(func(part): return part.id == cursor)
		if matches.is_empty(): return result
		path.push_front(matches[0].kind)
		cursor = matches[0].parent
	var matching_parents := _removal_roots(mount.parent)
	for copy in design.assembly.parts:
		if copy.kind != "separator" or copy.parent not in matching_parents or absf(float(copy.surface_offset)-float(mount.surface_offset)) > .04: continue
		cursor = copy.id
		for kind in path:
			var children: Array = design.assembly.parts.filter(func(part): return part.parent == cursor and (part.kind == kind or (part.kind in Parts.Craft.ENGINE_IDS and kind in Parts.Craft.ENGINE_IDS)))
			if children.size() != 1:
				cursor = ""
				break
			cursor = children[0].id
		if not cursor.is_empty() and cursor not in result: result.append(cursor)
	return result

# Only combine actions introduced by this placement; preserve existing custom stages.
func _group_added_stage_actions(craft: Dictionary, previous_stages: Array) -> void:
	var existing := {}
	for stage in previous_stages:
		for action in stage: existing[action] = true
	var targets := {}
	for stage in craft.stages:
		for action in stage.duplicate():
			if existing.has(action): continue
			var kind: String = action.get_slice(":", 0)
			if not targets.has(kind):
				targets[kind] = stage
			elif not is_same(targets[kind], stage):
				stage.erase(action)
				targets[kind].append(action)
	craft.stages = craft.stages.filter(func(stage): return not stage.is_empty())

func _warp_to_location(epoch: float) -> void:
	if mode != "flight" or paused or flight.state.status != "flying": return
	if not is_finite(epoch) or epoch <= flight.simulation_time() or epoch - flight.simulation_time() > 21600.0: return
	if flight.warp_limit(throttle) <= 1.0:
		_toast("Warp here is unavailable. Cut throttle and coast above the safe warp altitude.")
		return
	warp_target_time = epoch
	warp_target_body = str(flight.telemetry().reference_body)
	physical_warp = false
	_prepare_warp_to()
	map_instrument.warp_destination = warp_target_time
	_toast("Warping to the selected point. X or Stop returns to 1×.")

func _prepare_warp_to() -> void:
	if warp_target_time < 0.0: return
	if flight.state.status != "flying" or str(flight.state.get("reference_body", "")) != warp_target_body or flight.warp_limit(throttle) <= 1.0:
		_cancel_warp_to("Warp stopped: the coast or safe warp conditions changed.")
		return
	var remaining := warp_target_time - flight.simulation_time()
	if remaining <= 0.00001:
		_cancel_warp_to("Reached the selected orbit point. Time is back to 1×.")
		return
	physical_warp = false
	# Slow on approach. The final simulation step is also clamped to the epoch.
	var desired := minf(flight.warp_limit(throttle), maxf(1.0, remaining * 2.0))
	warp = 1.0
	for rate in [5.0, 10.0, 50.0, 100.0, 1000.0]:
		if rate <= desired: warp = rate

func _cancel_warp_to(message: String = "") -> void:
	if warp_target_time < 0.0: return
	warp_target_time = -1.0
	warp_target_body = ""
	warp = 1.0
	physical_warp = false
	if is_instance_valid(map_instrument): map_instrument.warp_destination = -1.0
	if not message.is_empty(): _toast(message)
	_enforce_warp_limit()
