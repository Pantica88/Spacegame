extends SceneTree
## Heatmaps PROBE_VIEW with each cloud class (weather channel) masked out in
## the shader, plus reduced-pass GPU time. Occupancy boxes stay as painted.
const HOVER = preload("res://scenes/hover_preview.tscn")
const INC := "res://assets/shaders/clouds_volume.gdshaderinc"
const LOOKUP := "return texture(cloud_weather_map, uv);"
var hover

func _initialize() -> void: _run.call_deferred()

func _patched(base: Shader, bounded: bool, mask: String) -> Shader:
	var inc := FileAccess.get_file_as_string(INC)
	assert(inc.contains(LOOKUP))
	inc = inc.replace(LOOKUP, "return texture(cloud_weather_map, uv) * vec4(%s);" % mask)
	var s := Shader.new()
	s.code = ("#define CLOUD_OCCUPANCY\n" if bounded else "") + base.code.replace('#include "%s"' % INC, inc)
	return s

func _plain(s: Shader) -> Shader:
	if not s.code.begins_with("#define CLOUD_OCCUPANCY\n"): return s
	var p := Shader.new(); p.code = s.code.substr("#define CLOUD_OCCUPANCY\n".length()); return p

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	var clouds = hover._clouds
	clouds.time_scale = 0.0
	var v := OS.get_environment("PROBE_VIEW").split(" ")
	hover.hover_time = float(v[0])
	hover.hover_position = Vector3(float(v[1]), float(v[2]), float(v[3]))
	hover.hover_yaw = float(v[4]); hover.hover_pitch = float(v[5])
	clouds.weather_time = float(v[6])
	for i in range(60): await process_frame
	var comp: ShaderMaterial = clouds.material_override
	var low: ShaderMaterial = clouds._lowres_material
	var bounded: bool = comp.shader.code.begins_with("#define CLOUD_OCCUPANCY")
	var comp_base := _plain(comp.shader)
	var low_base := _plain(low.shader)
	var low_rid: RID = clouds.lowres_viewport().get_viewport_rid()
	var main_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(low_rid, true)
	RenderingServer.viewport_set_measure_render_time(main_rid, true)
	print("bounded=", bounded)
	var out := OS.get_environment("PROBE_SHOTS")
	# Channels: r cumulus puffs, g stratocumulus cells, b stratus sheet, a storms.
	var configs := {"all": "1,1,1,1", "no_cumulus": "0,1,1,1", "no_cells": "1,0,1,1",
		"no_sheet": "1,1,0,1", "no_storm": "1,1,1,0", "storm_only": "0,0,0,1", "none": "0,0,0,0"}
	for name in configs:
		comp.shader = _patched(comp_base, bounded, configs[name])
		low.shader = _patched(low_base, bounded, configs[name])
		RenderingServer.global_shader_parameter_set("cloud_cost_view", false)
		for i in range(150): await process_frame
		var low_ms := 0.0
		var main_ms := 0.0
		for i in range(120):
			await process_frame
			low_ms += RenderingServer.viewport_get_measured_render_time_gpu(low_rid)
			main_ms += RenderingServer.viewport_get_measured_render_time_gpu(main_rid)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/look_" + name + ".png")
		RenderingServer.global_shader_parameter_set("cloud_cost_view", true)
		for i in range(30): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/heat_" + name + ".png")
		print("COST %-11s reduced_pass %.2f ms  frame %.2f ms" % [name, low_ms / 120.0, main_ms / 120.0])
	quit(0)
