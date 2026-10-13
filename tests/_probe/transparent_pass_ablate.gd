extends SceneTree
## Attributes the 3D transparent pass during the 4x ascent. Run with
## --profile-gpu (the help text says --gpu-profile, which does nothing) so the
## renderer captures per-pass timestamps. Cycles ablation modes every
## MODE_FRAMES frames so each comparison happens at nearly the same altitude.
const MODE_FRAMES := 8
const SKIP := 3 # timestamps trail the frame that changed visibility
# Each mode lists what it hides; "all" shows what remains without any of them.
const MODES := {"none": [], "glow": ["glow"], "plume": ["plume"],
	"rootglow": ["rootglow"], "clouds": ["clouds"], "ocean": ["ocean"], "sun": ["sun"], "map": ["map"],
	"all": ["glow", "plume", "rootglow", "clouds", "ocean", "sun", "map"],
	"all+rocket": ["glow", "plume", "rootglow", "clouds", "ocean", "sun", "map", "rocket"],
	"all+planet": ["glow", "plume", "rootglow", "clouds", "ocean", "sun", "map", "planet"],
	"all+pad": ["glow", "plume", "rootglow", "clouds", "ocean", "sun", "map", "pad"]}
var active_modes: Array = []
var map_viewports := {}
var main: Node
var mode := "none"
var hidden: Array = []

func _initialize() -> void: _run.call_deferred()

func _median(values: Array) -> float:
	if values.is_empty(): return NAN
	values.sort()
	return values[values.size() / 2]

func _flames() -> Array:
	var world = main.world
	var result: Array = world._main_flames + world._booster_flames
	for id in world._engine_flames: result.append_array(world._engine_flames[id])
	return result

# Runs after the physics ticks and before drawing.
func _process(_delta: float) -> bool:
	if main == null or main.mode != "flight": return false
	var world = main.world
	hidden = MODES[mode]
	if "glow" in hidden: world._clear_aero_glow()
	for flame in _flames():
		if not is_instance_valid(flame): continue
		for mesh in flame.find_children("*", "MeshInstance3D", true, false):
			var shader: String = mesh.material_override.shader.resource_path if mesh.material_override is ShaderMaterial else ""
			if shader.ends_with("rocket_exhaust.gdshader"): mesh.visible = not "plume" in hidden
			if shader.ends_with("rocket_root_glow.gdshader"): mesh.visible = not "rootglow" in hidden
	world._clouds.visible = not "clouds" in hidden
	if "ocean" in hidden and is_instance_valid(world._ocean): world._ocean.visible = false
	if map_viewports.is_empty():
		for viewport in main.find_children("*", "SubViewport", true, false):
			if viewport != world._clouds.lowres_viewport(): map_viewports[viewport] = viewport.render_target_update_mode
	for viewport in map_viewports:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if "map" in hidden else map_viewports[viewport]
	world._rocket.visible = not "rocket" in hidden
	world._planet.visible = not "planet" in hidden
	world._landscape.visible = not "pad" in hidden
	var sun: Node3D = world.find_child("Sun", true, false)
	if sun: sun.visible = not "sun" in hidden
	return false

# Times the main view's transparent pass with stripped composite shaders.
func _variants() -> void:
	var material: ShaderMaterial = main.world._clouds.material_override
	var original: Shader = material.shader
	var code := original.code
	var safe_loop := "bool lowres_safe = true;\n\tif (lowres_enabled) {"
	var mix_call := "vec4 mixed = display_mix_premultiplied(result.rgb, result.a, texture(scene_color, SCREEN_UV).rgb);"
	var safe_start := code.find("bool lowres_safe = true;")
	var safe_end := code.find("// Silhouette pixels blend")
	safe_loop = code.substr(safe_start, safe_end - safe_start)
	var nomarch := code.replace("return integrate_clouds(ray, clip, frag);", "return upsample_clouds(uv);").replace("vec4 full = integrate_clouds(ray, clip, frag);", "vec4 full = reduced;")
	var nosafe := code.replace(safe_loop, "bool lowres_safe = true;\n\t")
	var nomix := code.replace(mix_call, "vec4 mixed = vec4(result.rgb * result.a, result.a);")
	var bare := nomarch.replace(safe_loop, "bool lowres_safe = true;\n\t").replace(mix_call, "vec4 mixed = vec4(result.rgb * result.a, result.a);")
	var shaders := {"current": original}
	var entries := [["nosafe", nosafe], ["bare", bare]]
	# PROBE_BASELINE=<path>: another composite shader source to compare against.
	if OS.get_environment("PROBE_BASELINE") != "":
		entries.append(["baseline", FileAccess.get_file_as_string(OS.get_environment("PROBE_BASELINE"))])
	for entry in entries:
		var shader := Shader.new()
		shader.code = entry[1]
		shaders[entry[0]] = shader
	var from := float(OS.get_environment("PROBE_FROM")) if OS.get_environment("PROBE_FROM") != "" else 12000.0
	var to := float(OS.get_environment("PROBE_ALTITUDE")) if OS.get_environment("PROBE_ALTITUDE") != "" else 22000.0
	while main.flight.state.altitude < from - 3000.0: await process_frame
	# Compile every variant before measuring.
	for name in shaders:
		material.shader = shaders[name]
		for i in range(4): await process_frame
	var samples := {}
	var frame := 0
	var names: Array = shaders.keys()
	while main.flight.state.altitude < to:
		var name: String = names[(frame / MODE_FRAMES) % names.size()]
		material.shader = shaders[name]
		await process_frame
		frame += 1
		if frame % MODE_FRAMES < SKIP or main.flight.state.altitude < from: continue
		var t := _main_transparent()
		if t > 0.0:
			if not samples.has(name): samples[name] = []
			samples[name].append(t)
	material.shader = original
	for name in names:
		print("VARIANT %-8s main transparent %.2f ms  n=%d" % [name, _median(samples.get(name, [])), samples.get(name, []).size()])

func _main_transparent() -> float:
	var rd := RenderingServer.get_rendering_device()
	var last := -1.0
	for i in range(rd.get_captured_timestamps_count() - 1):
		if rd.get_captured_timestamp_name(i) == "Render 3D Transparent Pass":
			last = (rd.get_captured_timestamp_gpu_time(i + 1) - rd.get_captured_timestamp_gpu_time(i)) / 1e6
	return last

func _passes() -> Dictionary:
	var rd := RenderingServer.get_rendering_device()
	var result := {}
	var count := rd.get_captured_timestamps_count()
	if count < 2: return result
	for i in range(count - 1):
		var name := rd.get_captured_timestamp_name(i)
		var ms := (rd.get_captured_timestamp_gpu_time(i + 1) - rd.get_captured_timestamp_gpu_time(i)) / 1e6
		result[name] = result.get(name, 0.0) + ms
	result["total"] = (rd.get_captured_timestamp_gpu_time(count - 1) - rd.get_captured_timestamp_gpu_time(0)) / 1e6
	return result

func _shader_name(material: Material) -> String:
	if material == null: return ""
	var text := ""
	if material is ShaderMaterial and material.shader: text = material.shader.resource_path.get_file()
	elif material is BaseMaterial3D: text = "Std(transp=%d)" % material.transparency
	else: text = material.get_class()
	if material.next_pass: text += "+" + _shader_name(material.next_pass)
	return text

# Lists drawable geometry with its materials and screen-relevant size.
func _list_transparent(node: Node, camera: Camera3D) -> void:
	if node is GeometryInstance3D and node.is_visible_in_tree():
		var g: GeometryInstance3D = node
		var mats := []
		if g.material_override: mats.append("override:" + _shader_name(g.material_override))
		if g.material_overlay: mats.append("overlay:" + _shader_name(g.material_overlay))
		if g is MeshInstance3D and g.mesh:
			for i in range(g.mesh.get_surface_count()):
				var m: Material = g.get_active_material(i)
				if m and m != g.material_override: mats.append(_shader_name(m))
		var aabb := g.global_transform * g.get_aabb()
		var distance := camera.global_position.distance_to(aabb.get_center())
		var joined := ", ".join(mats)
		if not ("aerothermal" in joined or "exhaust" in joined or "root_glow" in joined): print("GEOM %s  size=%.1f dist=%.1f  %s" % [g.get_path(), aabb.size.length(), distance, ", ".join(mats.slice(0, 3))])
	for child in node.get_children(): _list_transparent(child, camera)

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in range(20): await process_frame
	await main._roll_out()
	for i in range(60): await process_frame
	main.set_process_input(false)
	main.set_process_unhandled_input(false)
	main.set_process_shortcut_input(false)
	root.gui_disable_input = true
	main.sas = true
	main._set_throttle(1.0)
	main._stage()
	if OS.get_environment("PROBE_WARP") != "": main._select_warp_step(int(OS.get_environment("PROBE_WARP")))
	var floor_altitude := float(OS.get_environment("PROBE_FROM")) if OS.get_environment("PROBE_FROM") != "" else 0.0
	var limit := float(OS.get_environment("PROBE_ALTITUDE")) if OS.get_environment("PROBE_ALTITUDE") != "" else 42000.0
	var bands := {}
	var frame := 0
	if OS.get_environment("PROBE_VARIANTS") != "":
		await _variants()
		quit(0)
		return
	if OS.get_environment("PROBE_SHOTS") != "":
		var out := OS.get_environment("PROBE_OUT")
		for target in OS.get_environment("PROBE_SHOTS").split(","):
			while main.flight.state.altitude < float(target): await process_frame
			for view in [false, true]:
				RenderingServer.global_shader_parameter_set("cloud_cost_view", view)
				for i in range(4): await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/shot_%s_%s.png" % [out, target, "cost" if view else "normal"])
			RenderingServer.global_shader_parameter_set("cloud_cost_view", false)
		quit(0)
		return
	if OS.get_environment("PROBE_PREDRAW") != "":
		while main.flight.state.altitude < float(OS.get_environment("PROBE_PREDRAW")): await process_frame
		RenderingServer.frame_pre_draw.connect(func():
			var overlays := 0
			for mesh in main.world.find_children("*", "MeshInstance3D", true, false):
				if mesh.material_overlay != null and mesh.is_visible_in_tree(): overlays += 1
			var trail = main.world._heat_trail
			print("PREDRAW mode=%s overlays=%d trail=%s" % [mode, overlays, is_instance_valid(trail) and trail.is_visible_in_tree()]))
		for m in ["none", "all", "glow", "none"]:
			mode = m
			for i in range(3): await process_frame
		quit(0)
		return
	if OS.get_environment("PROBE_DUMP") != "":
		while main.flight.state.altitude < float(OS.get_environment("PROBE_DUMP")): await process_frame
		for i in range(5): await process_frame
		var rd := RenderingServer.get_rendering_device()
		print("viewports: main=%s lowres=%s" % [root.get_viewport_rid(), main.world._clouds.lowres_viewport().get_viewport_rid()])
		for i in range(rd.get_captured_timestamps_count() - 1):
			print("TS %-45s %7.3f ms" % [rd.get_captured_timestamp_name(i), (rd.get_captured_timestamp_gpu_time(i + 1) - rd.get_captured_timestamp_gpu_time(i)) / 1e6])
		quit(0)
		return
	if OS.get_environment("PROBE_LIST") != "":
		while main.flight.state.altitude < float(OS.get_environment("PROBE_LIST")): await process_frame
		_list_transparent(root, main.world.camera)
		quit(0)
		return
	while main.flight.state.altitude < limit:
		if active_modes.is_empty():
			active_modes = OS.get_environment("PROBE_MODES").split(",") if OS.get_environment("PROBE_MODES") != "" else MODES.keys()
		mode = active_modes[(frame / MODE_FRAMES) % active_modes.size()]
		await process_frame
		frame += 1
		if frame % MODE_FRAMES < SKIP or main.flight.state.altitude < floor_altitude: continue
		var band := int(main.flight.state.altitude / 3000.0) * 3
		var passes := _passes()
		if passes.is_empty(): continue
		var key := "%d|%s" % [band, mode]
		if not bands.has(key): bands[key] = {"transparent": [], "total": [], "canvas": [], "opaque": []}
		bands[key].transparent.append(passes.get("Render 3D Transparent Pass", 0.0))
		bands[key].canvas.append(passes.get("Render CanvasItems", 0.0))
		bands[key].opaque.append(passes.get("Render Opaque Pass", 0.0))
		bands[key].total.append(passes.total)
	print("ABLATE band(km)  mode     transparent  opaque  canvas  total   (median GPU ms)")
	var seen := []
	for key in bands:
		var band := int(key.get_slice("|", 0))
		if band in seen: continue
		seen.append(band)
		for m in MODES:
			var k := "%d|%s" % [band, m]
			if not bands.has(k): continue
			var b: Dictionary = bands[k]
			print("ABLATE %3d-%3d  %-8s  %6.2f  %6.2f  %6.2f  %6.2f  n=%d" % [band, band + 3, m, _median(b.transparent), _median(b.opaque), _median(b.canvas), _median(b.total), b.total.size()])
	quit(0)
