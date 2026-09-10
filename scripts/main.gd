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
var flight_ui: Control
var modal: Control
var toast_label: Label
var toast_time := 0.0
var mode := "workshop"
var paused := false
var mission_index := 0
var throttle := 1.0
var sas := true
var warp := 1.0
var recorded := false
var flight_completed := false
var stats_labels: Dictionary = {}
var telem_labels: Dictionary = {}
var tank_label: Label
var craft_name: LineEdit
var craft_caption: Label
var mission_description: Label
var mission_tag: Label
var mission_hint: Label
var flight_hint: Label
var mission_progress: ProgressBar
var status_label: Label
var time_label: Label
var fuel_bar: ProgressBar
var booster_bar: ProgressBar
var throttle_slider: HSlider
var sas_button: Button
var warp_button: Button
var stage_button: Button
var navball: Control
var map_panel: PanelContainer
var map_instrument: Control
var launch_button: Button
var engine_buttons: Dictionary = {}
var attachment_layer: Control
var build_drop_area: Control
var drag_snap_slot := ""
var drag_root_height := 7.5
var highlight_action := ""
var selected_part := ""
var hovered_part := ""
var return_drag_id := ""
var return_drag_kind := ""
var return_drag_snap_slot := ""
var drag_fin_offset := 0.0
var flight_stage_list: VBoxContainer
var _last_stage_display := ""
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
	add_child(world)
	world.set_design(design)
	world.set_mode("workshop")
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
	toast_label = _label(ui, "", 16, MINT)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_rect_offsets(toast_label, Rect2(-340, 104, 680, 36))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh_design(false)
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
	var title := _label(bar, "BUILD SOMETHING WORTH BRINGING HOME.", 12, MUTED)
	title.position = Vector2(530, 35)
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
	var orbit_hint := _label(workshop, "RMB + DRAG  rotate    ·    SCROLL  zoom", 12, MUTED)
	orbit_hint.anchor_left = 0.5
	orbit_hint.anchor_right = 0.5
	orbit_hint.anchor_top = 1
	orbit_hint.anchor_bottom = 1
	_rect_offsets(orbit_hint, Rect2(-220, -130, 440, 24))
	orbit_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

func _build_flight_ui() -> void:
	flight_ui = Control.new()
	flight_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flight_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(flight_ui)
	flight_ui.hide()
	var left := _panel(flight_ui, Rect2(24, 122, 286, 240))
	_label(left, "FLIGHT DIRECTOR", 11, MINT)
	status_label = _label(left, "ON THE PAD", 25)
	time_label = _label(left, "T + 00:00", 15, MUTED)
	mission_progress = ProgressBar.new()
	mission_progress.custom_minimum_size.y = 5
	mission_progress.show_percentage = false
	left.add_child(mission_progress)
	flight_hint = _wrap(left, "", 15, PAPER)
	var right := _panel(flight_ui, Rect2(-300, 122, 276, 398), true)
	_label(right, "LIVE TELEMETRY", 11, MINT)
	for entry in [["altitude", "ALTITUDE"], ["terrain_clearance", "GROUND CLEARANCE"], ["speed", "SURFACE SPEED"], ["vertical_speed", "VERTICAL SPEED"], ["apoapsis", "APOAPSIS"], ["periapsis", "PERIAPSIS"]]:
		_label(right, entry[1], 10, MUTED)
		telem_labels[entry[0]] = _label(right, "0 m", 27 if entry[0] == "altitude" else 22)
	_label(right, "LIQUID FUEL", 10, MUTED)
	fuel_bar = ProgressBar.new()
	fuel_bar.custom_minimum_size.y = 8
	fuel_bar.show_percentage = false
	right.add_child(fuel_bar)
	_label(right, "SOLID BOOSTERS", 10, MUTED)
	booster_bar = ProgressBar.new()
	booster_bar.custom_minimum_size.y = 5
	booster_bar.show_percentage = false
	right.add_child(booster_bar)
	var controls := _panel(flight_ui, Rect2(24, -222, 310, 198), false, true)
	controls.add_theme_constant_override("separation", 8)
	_label(controls, "THROTTLE   /   SHIFT + CTRL", 11, MUTED)
	throttle_slider = HSlider.new()
	throttle_slider.min_value = 0
	throttle_slider.max_value = 100
	throttle_slider.value = 100
	throttle_slider.custom_minimum_size.y = 26
	throttle_slider.value_changed.connect(func(value: float): throttle = value / 100)
	controls.add_child(throttle_slider)
	var buttons := HBoxContainer.new()
	controls.add_child(buttons)
	_button(buttons, "X   Cut", func(): _set_throttle(0)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(buttons, "Z   Full", func(): _set_throttle(1)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sas_button = _button(controls, "T   Stability assist: ON", _toggle_sas)
	_wrap(controls, "W A S D   steer       Q E   roll", 12)
	var actions := _panel(flight_ui, Rect2(-310, -222, 286, 198), true, true)
	stage_button = _button(actions, "SPACE   Ignite engines", _stage, true)
	_button(actions, "P   Deploy parachute", _chute)
	var action_row := HBoxContainer.new()
	actions.add_child(action_row)
	warp_button = _button(action_row, "1× time", _cycle_warp)
	warp_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(action_row, "M   Map", _toggle_map).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sequence_panel := _panel(flight_ui, Rect2(24, 410, 250, 210))
	_label(sequence_panel, "STAGE SEQUENCE", 11, MINT)
	var sequence_scroll := ScrollContainer.new()
	sequence_scroll.custom_minimum_size.y = 145
	sequence_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sequence_panel.add_child(sequence_scroll)
	flight_stage_list = VBoxContainer.new()
	flight_stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sequence_scroll.add_child(flight_stage_list)
	var ball_root := Control.new()
	flight_ui.add_child(ball_root)
	ball_root.anchor_left = 0.5
	ball_root.anchor_right = 0.5
	ball_root.anchor_top = 1
	ball_root.anchor_bottom = 1
	_rect_offsets(ball_root, Rect2(-102, -226, 204, 204))
	ball_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	navball = Instruments.new()
	navball.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ball_root.add_child(navball)
	var ball_label := _label(ball_root, "ATTITUDE  /  SURFACE", 10, MUTED)
	ball_label.position = Vector2(33, 195)
	map_panel = PanelContainer.new()
	flight_ui.add_child(map_panel)
	map_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_panel.offset_top = 90
	map_panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.07, 0.1, 0.97), Color("51727a"), 12, 0))
	map_instrument = preload("res://scripts/orbital_map.gd").new()
	map_instrument.source_world = world
	map_panel.add_child(map_instrument)
	map_panel.hide()
	map_panel.visibility_changed.connect(_sync_map_rendering)
	_sync_map_rendering()

func _refresh_design(save: bool = true) -> void:
	design = Parts.Craft.project(Parts.Craft.load_craft(design), design)
	world.set_design(design)
	var stats: Dictionary = Parts.stats(design)
	tank_label.text = "%d tanks · %s" % [design.tanks, "no engine" if design.engine.is_empty() else "%s engine" % stats.engine_name]
	_refresh_assembly()
	craft_caption.text = design.name
	stats_labels.wet_mass.text = "%.2f t" % (stats.wet_mass / 1000)
	stats_labels.thrust.text = "%d kN" % (stats.thrust / 1000)
	stats_labels.twr.text = "%.2f" % stats.twr
	stats_labels.delta_v.text = "%s m/s" % str(roundi(stats.delta_v))
	stats_labels.fuel_mass.text = "%.2f t" % (stats.core_fuel_mass / 1000)
	stats_labels.readiness.text = "✓  Flight checks complete. Ready for rollout." if stats.twr > 1.05 else "Low thrust: use a stronger engine or fewer tanks."
	stats_labels.readiness.add_theme_color_override("font_color", MINT if stats.twr > 1.05 else ORANGE)
	launch_button.disabled = stats.twr <= 1.05
	var blockers := Parts.Craft.blockers(design.assembly)
	if not blockers.is_empty():
		launch_button.disabled = true
		stats_labels.readiness.text = "\n".join(blockers)
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
	if amount > 0 and design.tanks < 4:
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
	if design.has("assembly") and (not Parts.Craft.blockers(design.assembly).is_empty() or Parts.stats(design).twr <= 1.05):
		_toast("Complete the flight checks before rollout.")
		return
	_close_modal()
	_save_design()
	mode = "flight"
	workshop.hide()
	flight_ui.show()
	flight.reset(design)
	map_instrument.reset_history(Vector3(flight.state.position))
	world.set_design(design)
	world.set_mode("flight")
	world.sync_flight(flight.telemetry(), 0)
	throttle = 1
	sas = true
	warp = 1
	recorded = false
	flight_completed = false
	_update_controls()
	_update_flight_ui()
	_toast("Launchpad clear. Press SPACE to ignite.")

func _return_workshop() -> void:
	if mode == "flight" and flight.state.get("status") != "ready" and not recorded:
		_record_flight()
	_close_modal()
	mode = "workshop"
	flight_ui.hide()
	workshop.show()
	map_panel.hide()
	world.set_design(design)
	world.set_mode("workshop")
	_refresh_design(false)

func _physics_process(delta: float) -> void:
	if mode != "flight" or paused:
		return
	world.advance_solar_time(delta * warp)
	world.set_planet_time(float(flight.state.time))
	var before: String = flight.state.get("status", "ready")
	if before == "flying":
		var adjustment := float(Input.is_physical_key_pressed(KEY_SHIFT)) - float(Input.is_physical_key_pressed(KEY_CTRL))
		_set_throttle(throttle + adjustment * delta * 0.5)
		var controls := {"pitch": float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)), "yaw": float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), "roll": float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)), "throttle": throttle, "sas": sas}
		flight.step(delta * warp, controls)
		var state: Dictionary = flight.telemetry()
		map_instrument.record_flight(state)
		world.sync_flight(state, delta)
		if mission_index == 2 and state.get("orbit_achieved", false):
			_complete_mission()
		if state.status in ["landed", "crashed"]:
			_record_flight()
			_show_debrief()
	_update_flight_ui()

func _process(delta: float) -> void:
	if mode == "workshop":
		if not get_viewport().gui_is_dragging(): _update_part_hover()
		if not return_drag_kind.is_empty() and get_viewport().gui_is_dragging():
			var mouse := get_viewport().get_mouse_position()
			var over_catalogue: bool = assembly_list.get_parent().get_global_rect().has_point(mouse)
			if over_catalogue:
				return_drag_snap_slot = "inventory"
				world.preview_subassembly_drag(_affected_part_ids(return_drag_id), return_drag_id, mouse, true)
			else:
				_update_return_drag(return_drag_id, mouse)
		else:
			var preview := selected_part
			if not get_viewport().gui_is_dragging() and not highlight_action.is_empty():
				preview = highlight_action.get_slice(":", 1)
				if preview == "decoupler": preview = "separation"
			if not get_viewport().gui_is_dragging():
				if not selected_part.is_empty(): world.preview_subassembly(_affected_part_ids(selected_part), true)
				elif not hovered_part.is_empty(): world.preview_subassembly(_affected_part_ids(hovered_part), false)
				else: world.preview_part(preview)
	if toast_time > 0:
		toast_time -= delta
		toast_label.modulate.a = minf(1.0, maxf(0.0, toast_time))
	var power := 0.0
	if mode == "flight" and not paused and flight.state.get("status") == "flying":
		if flight.state.get("engine_on", false) and flight.state.get("fuel", 0) > 0:
			power = throttle
		if flight.state.get("boosters_attached", false) and flight.state.get("booster_fuel", 0) > 0:
			power = maxf(power, 0.6)
	sound.set_thrust(power, delta)

func _update_part_hover() -> void:
	hovered_part = _part_at(get_viewport().get_mouse_position())

func _part_at(mouse: Vector2) -> String:
	var best_id := ""
	var best_score := INF
	for picker in attachment_layer.get_children():
		if not picker is Control or not picker.get_global_rect().has_point(mouse): continue
		var half_size: Vector2 = picker.size * 0.5
		var delta: Vector2 = mouse - picker.get_global_rect().get_center()
		var score: float = Vector2(delta.x / maxf(1.0, half_size.x), delta.y / maxf(1.0, half_size.y)).length_squared()
		# At distant zoom, neighboring stack targets overlap heavily. The thin
		# decoupler owns the pointer near its ring rather than losing to a tank.
		if picker.part_id == "decoupler": score *= 0.35
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
	var state: Dictionary = flight.telemetry()
	telem_labels.altitude.text = _distance(state.altitude)
	telem_labels.terrain_clearance.text = _distance(state.terrain_clearance)
	telem_labels.speed.text = "%.1f m/s" % state.get("speed", Vector3(state.velocity).length())
	telem_labels.vertical_speed.text = "%+.1f m/s" % state.vertical_speed
	telem_labels.apoapsis.text = _distance(state.apoapsis)
	telem_labels.periapsis.text = _distance(state.periapsis)
	fuel_bar.value = float(state.fuel) / maxf(1, float(state.max_fuel)) * 100
	booster_bar.value = float(state.get("booster_fraction", 0)) * 100
	time_label.text = "T + %02d:%02d     /     %s" % [int(state.time) / 60, int(state.time) % 60, design.name]
	var names := {"ready": "ON THE PAD", "flying": "ASCENT", "landed": "WELCOME HOME", "crashed": "SIGNAL LOST"}
	status_label.text = names.get(state.status, "IN FLIGHT")
	if state.status == "flying":
		status_label.text = "DESCENT" if state.vertical_speed < -2 else "ASCENT"
		if state.altitude > 18000:
			status_label.text = "ABOVE THE SKY"
		if state.get("in_stable_orbit", false):
			status_label.text = "IN ORBIT"
		if state.chute_deployed:
			status_label.text = "UNDER CANOPY"
	mission_progress.value = clampf(float(state.max_altitude) / MISSIONS[mission_index].target * 100, 0, 100)
	flight_hint.text = _flight_advice(state)
	var plan := Parts.stage_plan(design)
	var next_stage := int(state.get("stage_index", 0))
	stage_button.text = "SPACE   " + plan[next_stage] if next_stage < plan.size() else "Staging complete"
	var display_key := str(plan) + str(next_stage)
	if display_key != _last_stage_display:
		_last_stage_display = display_key
		for child in flight_stage_list.get_children():
			flight_stage_list.remove_child(child)
			child.queue_free()
		for index in range(plan.size()):
			var marker := "✓" if index < next_stage else ("▶" if index == next_stage else "·")
			_wrap(flight_stage_list, "%s %02d  %s" % [marker, index + 1, plan[index]], 12, MINT if index == next_stage else MUTED)
	stage_button.tooltip_text = stage_button.text
	stage_button.clip_text = true
	stage_button.add_theme_font_size_override("font_size", 14)
	stage_button.disabled = next_stage >= plan.size() or state.status in ["landed", "crashed"]
	navball.state = state
	navball.queue_redraw()
	if map_panel.visible:
		map_instrument.state = state
		map_instrument.queue_redraw()

func _flight_advice(state: Dictionary) -> String:
	if state.status == "ready":
		return "Press SPACE to ignite. Start with a straight climb, then experiment with your design."
	if state.boosters_attached and design.get("booster_first", false):
		return "Boosters spent. Press SPACE to jettison them and ignite the core." if state.booster_fuel <= 0.0 else "Flying on solid boosters. The core fuel is reserved. Wait for booster burnout, then press SPACE."
	if state.chute_deployed:
		return "Canopy open. Let the capsule descend. Use time acceleration to speed up the return."
	if state.capsule_only:
		return "Press P below 2.5 km, while descending under 180 m/s, to deploy the parachute."
	if state.vertical_speed < -2:
		return "Coming down. Press SPACE to separate the capsule, then P when the chute is safe."
	if mission_index < 2 and state.max_altitude >= MISSIONS[mission_index].target:
		return "Target altitude reached! Press X to cut thrust. Separate the capsule, then recover safely."
	if state.fuel <= 0:
		return "Liquid fuel depleted. Separate the capsule for recovery, or check your trajectory with M."
	if mission_index == 2:
		return "Turn gently with W A S D. An orbit needs sideways speed; use M to watch both ends rise."
	return "Climb to %s, cut thrust with X, and bring the capsule home." % _distance(MISSIONS[mission_index].target)

func _set_throttle(value: float) -> void:
	throttle = clampf(value, 0, 1)
	throttle_slider.set_value_no_signal(throttle * 100)

func _stage() -> void:
	if mode != "flight" or paused:
		return
	if design.has("assembly"):
		_toast(flight.execute_stage())
	elif flight.state.status == "ready":
		flight.ignite()
		_toast("Ignition. Your flight begins.")
	else:
		_toast(flight.stage())
	world.sync_flight(flight.telemetry(), 0)
	_update_flight_ui()

func _chute() -> void:
	if mode == "flight" and not paused:
		_toast(flight.deploy_chute())
		world.sync_flight(flight.telemetry(), 0)

func _toggle_sas() -> void:
	sas = not sas
	_update_controls()

func _cycle_warp() -> void:
	warp = 3 if warp == 1 else (8 if warp == 3 else 1)
	_update_controls()

func _update_controls() -> void:
	sas_button.text = "T   Stability assist: %s" % ("ON" if sas else "OFF")
	warp_button.text = "%d× time" % warp
	throttle_slider.set_value_no_signal(throttle * 100)

func _toggle_map() -> void:
	map_panel.visible = not map_panel.visible

func _sync_map_rendering() -> void:
	var showing := map_panel.is_visible_in_tree()
	# The map has its own 3D world. Keep only the active viewport rendering.
	get_viewport().disable_3d = showing
	world.rendering_suspended = showing
	if not showing and mode == "flight": world.sync_flight(flight.telemetry(),0.0)
	map_instrument.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if showing else SubViewport.UPDATE_DISABLED

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if mode == "workshop" and event.ctrl_pressed and event.physical_keycode in [KEY_Z, KEY_Y] and not get_viewport().gui_get_focus_owner() is LineEdit:
			if event.physical_keycode == KEY_Y or event.shift_pressed: _redo_edit()
			else: _undo_edit()
			get_viewport().set_input_as_handled()
			return
		if mode == "workshop" and not selected_part.is_empty() and not get_viewport().gui_get_focus_owner() is LineEdit:
			if event.physical_keycode == KEY_DELETE:
				_checkpoint()
				Parts.Craft.remove_part(design.assembly, selected_part)
				selected_part = ""
				highlight_action = ""
				_refresh_design()
				get_viewport().set_input_as_handled()
				return
			if event.physical_keycode == KEY_R:
				_checkpoint()
				for part in design.assembly.parts:
					if part.id == selected_part: part.rotation = (int(part.rotation) + 90) % 360
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
			if event.physical_keycode in [KEY_SPACE, KEY_P, KEY_X, KEY_Z, KEY_T, KEY_M, KEY_PERIOD]:
				get_viewport().set_input_as_handled()
			match event.physical_keycode:
				KEY_SPACE: _stage()
				KEY_P: _chute()
				KEY_X: _set_throttle(0)
				KEY_Z: _set_throttle(1)
				KEY_T: _toggle_sas()
				KEY_M: _toggle_map()
				KEY_PERIOD: _cycle_warp()

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

func _toggle_pause() -> void:
	if modal != null:
		_close_modal()
		return
	var box := _modal_box("Take a breath.", "Design and records are saved locally. Flights in progress are not saved when you quit.")
	_button(box, "Resume", _close_modal, true)
	if mode == "flight":
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
	_roll_out()
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
	_toggle_map()
	assert(not world.rendering_suspended and not get_viewport().disable_3d)
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


func _refresh_assembly() -> void:
	for container in [assembly_list, stage_preview]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_wrap(assembly_list, "Drag a part onto the rocket. It turns green when a connection surface is close, and red when placement is invalid.", 13)
	var catalogue := [
		["capsule", "Wren command capsule", "380 kg. Begin every vehicle with its command and recovery capsule."],
		["decoupler", "Capsule decoupler", "Separates the recovery capsule from its launch assembly."],
		["tank", "FL-18 fuel tank", "720 kg fuel · 70 kg dry. Adds range and launch mass."],
		["sparrow", "Sparrow engine", "42 kN · 180 kg. Light, dependable starter engine."],
		["kestrel", "Kestrel engine", "64 kN · 260 kg. Efficient propulsion for orbit."],
		["titan", "Titan engine", "98 kN · 410 kg. Heavy lifting power."],
		["boosters", "Twin solid boosters", "44 kN combined. Burn until empty; attach as a balanced pair."],
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
	_wrap(stage_preview, "Drag actions between stages. Drag stage headers to reorder. Space fires one group.", 13)
	for index in range(design.assembly.stages.size()):
		var group = preload("res://scripts/stage_group.gd").new()
		group.game = self
		group.index = index
		stage_preview.add_child(group)
	var add := _button(stage_preview, "New stage", func():
		_checkpoint()
		design.assembly.stages.append([])
		_refresh_design.call_deferred()
	)
	add.disabled = design.assembly.stages.size() >= 12
	for warning in Parts.Craft.warnings(design.assembly):
		_wrap(stage_preview, warning, 12, ORANGE)
	_wrap(stage_preview, "Hover over an action to locate its part. Separation highlights the assembly that will leave the capsule. Unsafe chute stages wait for safe descent.", 12)


func _can_attach(part: String, slot: String) -> bool:
	if mode != "workshop" or paused:
		return false
	match slot:
		"capsule": return part == "capsule" and design.assembly.parts.is_empty()
		"decoupler": return part == "decoupler" and not design.get("decoupler", false)
		"tank": return part == "tank" and int(design.tanks) < 4
		"engine": return Parts.ENGINES.has(part)
		"boosters": return part == "boosters" and not design.boosters and design.tanks > 0
		_ when slot.begins_with("fins@"): return part == "fins" and not design.fins
	return false

func _part_available(part: String) -> bool:
	var kinds: Array = design.assembly.parts.map(func(item): return item.kind)
	if kinds.is_empty(): return part == "capsule"
	if not "decoupler" in kinds: return part == "decoupler"
	if not "tank" in kinds: return part == "tank"
	if not kinds.any(func(kind): return kind in Parts.Craft.ENGINE_IDS):
		return part == "tank" or part in Parts.Craft.ENGINE_IDS
	return part == "tank" or part in Parts.Craft.ENGINE_IDS or (part == "boosters" and not design.boosters) or (part == "fins" and not design.fins)

func _attach_part(part: String, slot: String) -> void:
	if not _can_attach(part, slot):
		return
	_checkpoint()
	var radial_parent := slot.get_slice("@", 1) if slot.begins_with("fins@") else ""
	Parts.Craft.add_part(design.assembly, part, radial_parent)
	if part == "fins":
		for installed in design.assembly.parts:
			if installed.id == "fins": installed.surface_offset = drag_fin_offset
	_refresh_design.call_deferred()

func _fin_surface(parent_id: String) -> Array:
	if parent_id == "capsule":
		return [world._capsule_center_local - 0.75, world._capsule_center_local + 0.55]
	var center: float = world.installed_part_position(parent_id).y
	return [center - 0.82, center + 0.82]

func _snap_candidates(part: String) -> Array:
	var top := (2.0 if not design.engine.is_empty() else 0.0) + float(design.tanks) * 2.15
	if part == "capsule": return [["capsule", Vector3(0, world._capsule_center_local, 0)]]
	if part == "decoupler": return [["decoupler", Vector3(0, top + 0.1, 0)]]
	# These centers predict the finished placement while the connected lower
	# assembly moves down and the capsule stays fixed.
	if part == "tank": return [["tank", Vector3(0, 0.91 if not design.engine.is_empty() else -1.075, 0)]]
	if part in Parts.Craft.ENGINE_IDS: return [["engine", Vector3(0, -1.2, 0)]]
	if part == "boosters": return [["boosters", Vector3(-1.63, 4, 0)]]
	if part == "fins":
		var surfaces: Array = [["fins@capsule", Vector3(1.5, world._capsule_center_local, 0)]]
		var tanks: Array = design.assembly.parts.filter(func(item): return item.kind == "tank")
		for index in range(tanks.size()):
			surfaces.append(["fins@" + str(tanks[index].id), Vector3(1.5, top - float(index) * 2.15 - 1.075, 0)])
		return surfaces
	return []

func _update_build_drag(part: String, mouse: Vector2) -> bool:
	drag_snap_slot = ""
	var anchor := Vector3.ZERO
	var nearest := 86.0
	if part == "capsule" and design.assembly.parts.is_empty():
		var center_x: float = world.camera.unproject_position(Vector3(0, world.WORKSHOP_CAMERA_FOCUS_Y, 0)).x
		if absf(mouse.x - center_x) < 92.0 and mouse.y > 145.0 and mouse.y < 610.0:
			var ray_origin: Vector3 = world.camera.project_ray_origin(mouse)
			var ray_direction: Vector3 = world.camera.project_ray_normal(mouse)
			if absf(ray_direction.z) > 0.0001:
				var point: Vector3 = ray_origin + ray_direction * (-ray_origin.z / ray_direction.z)
				drag_root_height = clampf(point.y, 3.5, 13.0)
				drag_snap_slot = "capsule"
				anchor = Vector3(0, drag_root_height - world._rocket.position.y, 0)
		world.preview_drag(part, anchor, not drag_snap_slot.is_empty(), mouse)
		return not drag_snap_slot.is_empty()
	for candidate in _snap_candidates(part):
		if not _can_attach(part, candidate[0]): continue
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
			nearest = distance
			drag_snap_slot = candidate[0]
			anchor = candidate[1]
			if part == "fins":
				var parent_id := str(candidate[0]).get_slice("@", 1)
				var parent_center: float = world._capsule_center_local if parent_id == "capsule" else world.installed_part_position(parent_id).y
				drag_fin_offset = anchor.y - parent_center
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
	return Parts.Craft.descendant_ids(design.assembly, id)

func _update_return_drag(id: String, mouse: Vector2) -> bool:
	if id != return_drag_id or return_drag_kind.is_empty(): return false
	return_drag_snap_slot = ""
	if return_drag_kind == "capsule":
		var center_x: float = world.camera.unproject_position(Vector3(0, world.WORKSHOP_CAMERA_FOCUS_Y, 0)).x
		if absf(mouse.x - center_x) < 92.0 and mouse.y > 145.0 and mouse.y < 610.0:
			var ray_origin: Vector3 = world.camera.project_ray_origin(mouse)
			var ray_direction: Vector3 = world.camera.project_ray_normal(mouse)
			if absf(ray_direction.z) > 0.0001:
				var point: Vector3 = ray_origin + ray_direction * (-ray_origin.z / ray_direction.z)
				drag_root_height = clampf(point.y, 3.5, 13.0)
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
	elif return_drag_kind == "capsule" and return_drag_snap_slot == "capsule":
		if absf(float(design.assembly.root_height) - drag_root_height) > 0.01:
			_checkpoint()
			design.assembly.root_height = drag_root_height
			changed = true
	if changed:
		_toast("Part repositioned.")
		_refresh_design.call_deferred()
	_end_return_drag()

func _end_return_drag() -> void:
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
		Parts.Craft.remove_part(design.assembly, id)
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
	elif not slot in ["boosters", "fins", "decoupler", "engine"]:
		_toast("Drag an engine onto the mount to replace it.")
		return
	_checkpoint()
	Parts.Craft.remove_part(design.assembly, id)
	_refresh_design.call_deferred()

func _refresh_part_selection() -> void:
	for child in attachment_layer.get_children():
		attachment_layer.remove_child(child)
		child.queue_free()
	var tanks: Array = design.assembly.parts.filter(func(part): return part.kind == "tank")
	# Read central-part anchors from the rendered assembly so pointer regions
	# follow the same layout when fuel changes the rocket's local coordinates.
	var anchors := {
		"capsule": world.installed_part_position("capsule"),
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
	var hit_sizes := {"capsule": Vector2(112,150), "decoupler": Vector2(118,34), "engine": Vector2(110,86)}
	for part in design.assembly.parts:
		var id: String = part.id
		var specs: Array = []
		if id == "boosters":
			for side in [-1.0,1.0]: specs.append([Vector3(side*1.63,3.5,0),Vector2(76,260)])
		elif id == "fins":
			var fin_anchor: Vector3 = anchors.get("fins", Vector3(0,1.5,0))
			for side in [-1.0,1.0]: specs.append([Vector3(side*1.38,fin_anchor.y,0),Vector2(72,145)])
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
			picker.z_index = 20 if id == "decoupler" else 0
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

func _move_action(action: String, destination: int) -> void:
	if destination < 0 or destination >= design.assembly.stages.size(): return
	if design.assembly.stages[destination].has(action): return
	_checkpoint()
	for group in design.assembly.stages: group.erase(action)
	design.assembly.stages[destination].append(action)
	_refresh_design.call_deferred()

func _move_stage(source: int, destination: int) -> void:
	if source == destination or source < 0 or destination < 0 or source >= design.assembly.stages.size() or destination >= design.assembly.stages.size(): return
	_checkpoint()
	var group: Array = design.assembly.stages.pop_at(source)
	design.assembly.stages.insert(destination, group)
	_refresh_design.call_deferred()

func _delete_stage(index: int) -> void:
	if design.assembly.stages.size() <= 1 or not design.assembly.stages[index].is_empty(): return
	_checkpoint()
	design.assembly.stages.remove_at(index)
	_refresh_design.call_deferred()


func _new_craft() -> void:
	_checkpoint()
	design = Parts.Craft.project(Parts.Craft.seed(), {"name": "New craft"})
	craft_name.text = design.name
	_refresh_design()
