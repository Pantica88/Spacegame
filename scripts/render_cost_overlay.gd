extends CanvasLayer
## Debug heatmap of rendering cost. F9 cycles off -> cloud samples -> overdraw.
## GPUs give no per-pixel timings, so the cloud view counts the density
## evaluations in each marched ray (cloud_render_pass.gd), paired with the
## measured GPU time of the frame and of the cloud march itself.

const CloudPass = preload("res://scripts/cloud_render_pass.gd")

enum Mode { OFF, CLOUD_SAMPLES, OVERDRAW }
const MODE_NAMES := ["", "Cloud density samples per marched ray", "Overdraw (Godot)"]
# Must match cost_color() in cloud_render_pass.gd.
const BANDS: Array[Color] = [Color(0.6, 0.6, 0.6), Color(0.0, 0.1, 1.0), Color(0.0, 0.8, 1.0), Color(0.0, 1.0, 0.2),
	Color(1.0, 1.0, 0.0), Color(1.0, 0.45, 0.0), Color(1.0, 0.0, 0.0), Color(1.0, 0.0, 1.0)]
const BAND_LABELS := ["<8", "8-15", "16-31", "32-63", "64-127", "128-255", "256-511", "512+"]
const SAMPLE_INTERVAL := 0.25

var world: Node
var mode := Mode.OFF
var _label := Label.new()
var _legend := HBoxContainer.new()
var _since_sample := SAMPLE_INTERVAL
var _hover_text := ""
var _cloud_ms: Array[float] = []
var _cloud_text := ""

func _ready() -> void:
	layer = 100
	var panel := PanelContainer.new()
	# Bottom-left keeps clear of the flight and hover HUDs at the top.
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_child(_label)
	for i in BANDS.size():
		var swatch := ColorRect.new()
		swatch.color = BANDS[i]
		swatch.custom_minimum_size = Vector2(46, 14)
		var tag := Label.new()
		tag.text = BAND_LABELS[i]
		tag.add_theme_font_size_override("font_size", 10)
		var cell := VBoxContainer.new()
		cell.add_child(swatch)
		cell.add_child(tag)
		_legend.add_child(cell)
	column.add_child(_legend)
	panel.add_child(column)
	add_child(panel)
	visible = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F9:
		_set_mode(((mode + 1) % Mode.size()) as Mode)
		get_viewport().set_input_as_handled()

func _set_mode(next: Mode) -> void:
	mode = next
	_legend.visible = mode == Mode.CLOUD_SAMPLES
	visible = mode != Mode.OFF
	var clouds: Variant = world.get("_clouds") if is_instance_valid(world) else null
	if is_instance_valid(clouds): clouds.cost_view = mode == Mode.CLOUD_SAMPLES
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_OVERDRAW if mode == Mode.OVERDRAW else Viewport.DEBUG_DRAW_DISABLED
	_hover_text = ""

func _process(delta: float) -> void:
	if not visible:
		return
	var main_rid := get_viewport().get_viewport_rid()
	var lines := [(MODE_NAMES[mode] if mode != Mode.OFF else "Cost view off") + "   (F9 to cycle)",
		"Frame GPU %.2f ms   CPU %.2f ms   %d FPS" % [RenderingServer.viewport_get_measured_render_time_gpu(main_rid),
			RenderingServer.viewport_get_measured_render_time_cpu(main_rid), Engine.get_frames_per_second()]]
	var march := CloudPass.captured_gpu_ms()
	if march >= 0.0:
		_cloud_ms.append(march)
	if _cloud_ms.size() >= 30:
		var sorted := _cloud_ms.duplicate()
		sorted.sort()
		_cloud_text = "Cloud march GPU %.2f ms (median of 30 frames)" % sorted[sorted.size() / 2]
		_cloud_ms.clear()
	if not _cloud_text.is_empty():
		lines.append(_cloud_text)
	# Reading the frame back stalls the GPU, so sample the cursor only a few times a second.
	_since_sample += delta
	if mode == Mode.CLOUD_SAMPLES and _since_sample >= SAMPLE_INTERVAL:
		_since_sample = 0.0
		_hover_text = _sample_cursor()
	if not _hover_text.is_empty():
		lines.append(_hover_text)
	_label.text = "\n".join(lines)

func _sample_cursor() -> String:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return ""
	var cursor := get_viewport().get_mouse_position() * Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var pixel := Vector2i(cursor)
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height():
		return ""
	var seen := image.get_pixelv(pixel)
	# Tonemapping shifts the colours a little; the nearest band is close enough.
	var best := 0
	var best_distance := INF
	for i in BANDS.size():
		var band := BANDS[i]
		var distance := Vector3(seen.r - band.r, seen.g - band.g, seen.b - band.b).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = i
	if best_distance > 0.08 or maxf(seen.r, maxf(seen.g, seen.b)) < 0.45:
		return "Under cursor: no cloud march (or not a band colour)"
	return "Under cursor: ~%s density samples" % BAND_LABELS[best]
