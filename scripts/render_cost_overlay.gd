extends CanvasLayer
## Debug heatmap of rendering cost. F9 cycles off -> cloud samples -> overdraw.
## F10 cycles diagnostic builds of the cloud composite to compare their cost;
## run with --profile-gpu (not --gpu-profile) to time the transparent pass.
## GPUs give no per-pixel timings, so the cloud view counts density and shadow
## samples in each marched pixel (not individual texture reads), paired
## with the measured GPU time of the frame and of the reduced cloud pass.

enum Mode { OFF, CLOUD_SAMPLES, OVERDRAW }
const MODE_NAMES := ["", "Cloud density samples per marched pixel", "Overdraw (Godot)"]
# Must match cloud_cost_color() in clouds_volume.gdshaderinc.
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
# Keep the original renderer for paired comparisons. The other modes are
# diagnostic ablations: they can paint clouds through craft or alias edges.
const VARIANT_NAMES = preload("res://scripts/cloud_layer.gd").COMPOSITE_VARIANT_NAMES
var variant := 0
var _comparing := false # set by the first F10; keeps the readout up on the split
var _transparent_ms: Array[float] = []
var _transparent_text := ""

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
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F10:
		_set_variant((variant + 1) % VARIANT_NAMES.size())
		get_viewport().set_input_as_handled()

func _set_variant(next: int) -> void:
	var clouds: Variant = world.get("_clouds") if is_instance_valid(world) else null
	if not is_instance_valid(clouds): return
	variant = next
	_comparing = true
	clouds.set_composite_variant(variant)
	visible = mode != Mode.OFF or _comparing
	_transparent_ms.clear()
	_transparent_text = ""

## The main view's transparent pass, from per-pass timestamps that the renderer
## only captures under --profile-gpu. The main view renders last.
func _main_transparent_ms() -> float:
	var rd := RenderingServer.get_rendering_device()
	if rd == null: return -1.0
	var result := -1.0
	for i in range(rd.get_captured_timestamps_count() - 1):
		if rd.get_captured_timestamp_name(i) == "Render 3D Transparent Pass":
			result = (rd.get_captured_timestamp_gpu_time(i + 1) - rd.get_captured_timestamp_gpu_time(i)) / 1e6
	return result

func _set_mode(next: Mode) -> void:
	mode = next
	_legend.visible = mode == Mode.CLOUD_SAMPLES
	visible = mode != Mode.OFF or _comparing
	RenderingServer.global_shader_parameter_set("cloud_cost_view", mode == Mode.CLOUD_SAMPLES)
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_OVERDRAW if mode == Mode.OVERDRAW else Viewport.DEBUG_DRAW_DISABLED
	_hover_text = ""

func _process(delta: float) -> void:
	if not visible:
		return
	var main_rid := get_viewport().get_viewport_rid()
	var lines := [(MODE_NAMES[mode] if mode != Mode.OFF else "Cost view off") + "   (F9 to cycle)",
		"Frame GPU %.2f ms   CPU %.2f ms   %d FPS" % [RenderingServer.viewport_get_measured_render_time_gpu(main_rid),
			RenderingServer.viewport_get_measured_render_time_cpu(main_rid), Engine.get_frames_per_second()]]
	var lowres := _lowres_viewport()
	if lowres:
		RenderingServer.viewport_set_measure_render_time(lowres.get_viewport_rid(), true)
		lines.append("Reduced cloud pass GPU %.2f ms (%dx%d)" % [
			RenderingServer.viewport_get_measured_render_time_gpu(lowres.get_viewport_rid()), lowres.size.x, lowres.size.y])
	# Reading the frame back stalls the GPU, so sample the cursor only a few times a second.
	_since_sample += delta
	if mode == Mode.CLOUD_SAMPLES and _since_sample >= SAMPLE_INTERVAL:
		_since_sample = 0.0
		_hover_text = _sample_cursor()
	if not _hover_text.is_empty():
		lines.append(_hover_text)
	var transparent := _main_transparent_ms()
	if transparent >= 0.0:
		_transparent_ms.append(transparent)
	if _transparent_ms.size() >= 30:
		var sorted := _transparent_ms.duplicate()
		sorted.sort()
		_transparent_text = "Transparent pass GPU %.2f ms (median of 30 frames)" % sorted[sorted.size() / 2]
		_transparent_ms.clear()
	var variant_name: String = VARIANT_NAMES[variant]
	var clouds: Variant = world.get("_clouds") if is_instance_valid(world) else null
	if variant == 0 and is_instance_valid(clouds) and not clouds.uses_stencil_split():
		variant_name = "original (renderer fallback)"
	elif variant == VARIANT_NAMES.size() - 1 and is_instance_valid(clouds) and not clouds.uses_buffered():
		variant_name = "original (no compute backend)"
	lines.append("Cloud composite: %s   (F10 to cycle)" % variant_name)
	lines.append(_transparent_text if not _transparent_text.is_empty() else ("Transparent pass: measuring…" if transparent >= 0.0 else "Transparent pass: start with --profile-gpu to time it"))
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

func _lowres_viewport() -> SubViewport:
	var clouds: Variant = world.get("_clouds") if is_instance_valid(world) else null
	if clouds is Object and is_instance_valid(clouds) and clouds.has_method("lowres_viewport"):
		return clouds.lowres_viewport()
	return null
