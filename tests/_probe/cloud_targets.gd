extends SceneTree
## Prints statistics of the cloud pass's GPU targets for one hover view.
const HOVER = preload("res://scenes/hover_preview.tscn")

func _initialize() -> void: _run.call_deferred()

func _stats(rd: RenderingDevice, rid: RID, label: String) -> void:
	var data := rd.texture_get_data(rid, 0)
	var format := rd.texture_get_format(rid)
	var floats: PackedFloat32Array
	if format.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT:
		floats = data.to_float32_array()
	else:
		floats = PackedFloat32Array()
		for i in range(0, data.size(), 2): floats.append(data.decode_half(i))
	var count := floats.size() / 4
	var lo := [INF, INF, INF, INF]
	var hi := [-INF, -INF, -INF, -INF]
	var mean := [0.0, 0.0, 0.0, 0.0]
	for i in count:
		for c in 4:
			var v := floats[i * 4 + c]
			lo[c] = minf(lo[c], v)
			hi[c] = maxf(hi[c], v)
			mean[c] += v / count
	print("%s %dx%d min %s max %s mean %s" % [label, format.width, format.height, lo, hi, mean])
	var w := format.width
	for p: Vector2i in [Vector2i(w / 2, format.height / 4), Vector2i(w / 2, format.height / 2), Vector2i(w / 2, format.height * 3 / 4)]:
		var i := (p.y * w + p.x) * 4
		print("  at %s: %s" % [p, [floats[i], floats[i + 1], floats[i + 2], floats[i + 3]]])

func _run() -> void:
	var hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	var v := OS.get_environment("PROBE_VIEW").split(" ")
	if v.size() >= 5:
		hover.hover_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
		hover.hover_yaw = float(v[3])
		hover.hover_pitch = float(v[4])
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	var march = hover._clouds.render_pass()
	var rd := RenderingServer.get_rendering_device()
	print("dispatched ", march.dispatched, " ready ", march.is_ready(), " drawing ", hover._clouds.is_drawing(), " light rid ", march.light_texture.texture_rd_rid, " valid ", march.light_texture.get_rid())
	print("field ", march.field_values)
	print("history valid ", march._previous_valid, " last drawn ", march._last_drawn, " frames drawn ", Engine.get_frames_drawn(), " motion ", march._previous_camera)
	var fresh := rd.texture_get_data(march._fresh, 0)
	var shown := rd.texture_get_data(march._display, 0)
	var differ := 0
	for i in range(0, fresh.size(), 2):
		if absf(fresh.decode_half(i) - shown.decode_half(i)) > 0.001: differ += 1
	print("display differs from fresh in %d of %d channels" % [differ, fresh.size() / 2])
	_stats(rd, march._fresh, "fresh")
	_stats(rd, march._display, "display")
	_stats(rd, march._depth, "depth")
	var first := rd.texture_get_data(march._fresh, 0)
	await RenderingServer.frame_post_draw
	var second := rd.texture_get_data(march._fresh, 0)
	var changed := 0
	var lit := 0
	for i in range(0, first.size(), 8):
		if first.decode_half(i + 6) < 0.999 or second.decode_half(i + 6) < 0.999:
			lit += 1
			if absf(first.decode_half(i + 6) - second.decode_half(i + 6)) > 0.01: changed += 1
	print("fresh transmittance changed between frames in %d of %d cloudy texels; frame index %d" % [changed, lit, march._frame_index])
	# PROBE_DUMP=<dir>: the fresh and display targets as images (opacity shown).
	if OS.get_environment("PROBE_DUMP") != "":
		var size2: Vector2i = march.target_size()
		for pair in [["fresh", march._fresh], ["display", march._display]]:
			var bytes := rd.texture_get_data(pair[1], 0)
			var img := Image.create(size2.x, size2.y, false, Image.FORMAT_RGB8)
			for y in size2.y:
				for x in size2.x:
					var i := (y * size2.x + x) * 8
					var a := 1.0 - bytes.decode_half(i + 6)
					img.set_pixel(x, y, Color(clampf(bytes.decode_half(i), 0, 1), clampf(bytes.decode_half(i + 2), 0, 1), a))
			img.save_png(OS.get_environment("PROBE_DUMP") + "/" + pair[0] + ".png")
	# Per-texel range of the fresh transmittance over 16 frames in a window.
	if OS.get_environment("PROBE_WINDOW") != "":
		var wnd := OS.get_environment("PROBE_WINDOW").split(" ")
		var x0 := int(wnd[0]); var y0 := int(wnd[1]); var ww := int(wnd[2]); var hh := int(wnd[3])
		var size: Vector2i = march.target_size()
		var lo := PackedFloat32Array(); lo.resize(ww * hh); lo.fill(9.0)
		var hi := PackedFloat32Array(); hi.resize(ww * hh); hi.fill(-9.0)
		var held := PackedFloat32Array(); held.resize(ww * hh)
		for f in 16:
			await RenderingServer.frame_post_draw
			var now := rd.texture_get_data(march._fresh, 0)
			var disp := rd.texture_get_data(march._display, 0)
			for y in hh:
				for x in ww:
					var i := ((y0 + y) * size.x + x0 + x) * 8 + 6
					var tv := now.decode_half(i)
					lo[y * ww + x] = minf(lo[y * ww + x], tv)
					hi[y * ww + x] = maxf(hi[y * ww + x], tv)
					held[y * ww + x] = disp.decode_half(i)
		for y in range(0, hh, 2):
			var line := ""
			for x in range(0, ww, 2):
				var k := y * ww + x
				line += "%s" % ("." if hi[k] > 0.995 else ("#" if hi[k] - lo[k] < 0.02 else ("o" if absf(held[k] - (hi[k] + lo[k]) * 0.5) < (hi[k] - lo[k]) * 0.3 else "x")))
			print(line)
	var column := int(OS.get_environment("PROBE_COLUMN")) if OS.get_environment("PROBE_COLUMN") != "" else -1
	if column >= 0:
		var light := rd.texture_get_data(march._fresh, 0)
		var depth := rd.texture_get_data(march._depth, 0).to_float32_array()
		var size: Vector2i = march.target_size()
		for y in range(int(OS.get_environment("PROBE_ROW_FROM")), int(OS.get_environment("PROBE_ROW_TO"))):
			var i := (y * size.x + column) * 4
			print("row %d  T %.3f  light %.3f  front %.2f mean %.2f end %.2f clipped %.0f" % [y, light.decode_half(i * 2 + 6), light.decode_half(i * 2), depth[i], depth[i + 1], depth[i + 2], depth[i + 3]])
	quit(0)
