extends SceneTree
## Altitude sweep through the cloud base with per-system ablations.
## Drives World.sync_flight every frame, as flight does, so CPU work counts.
const World = preload("res://scripts/world_view.gd")
const Surface = preload("res://scripts/planet_surface.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
var world
var mode := "baseline"
var altitude := 1000.0
var pitch := 0.22
var sync_us: Array[float] = []
var sim_time := 0.0
var sun_override := Vector3.ZERO
var ocean_shader: Shader
var variant_shaders := {}
var dense_mesh: Mesh
var terrain_shader: Shader
var terrain_variants := {}
var coarse_mesh: Mesh

func _initialize() -> void: _run.call_deferred()

func _med(values: Array) -> float:
	var v := values.duplicate()
	v.sort()
	return v[v.size() / 2] if not v.is_empty() else 0.0

func _state() -> Dictionary:
	return {"position": Vector3(0, altitude, 0), "altitude": altitude, "orientation": Basis.IDENTITY,
		"engine_on": false, "fuel": 1.0, "boosters_attached": true, "capsule_only": false, "chute_deployed": false,
		"velocity": Vector3(0, 0, 0), "simulation_time": sim_time}

func _step() -> void:
	world._pitch = pitch
	var t := Time.get_ticks_usec()
	world.sync_flight(_state(), 1.0 / 60.0)
	if sun_override != Vector3.ZERO:
		world._sun_physical_position = sun_override.normalized() * 1.0e11
		world._update_atmosphere()
	sync_us.append(float(Time.get_ticks_usec() - t) / 1000.0)
	world._clouds.visible = mode != "no_clouds"
	world._rocket.visible = mode != "no_rocket"
	world._planet.visible = mode != "no_terrain"
	world._landscape.visible = mode != "no_terrain"
	if mode == "no_ocean" or mode == "no_terrain":
		world._ocean.visible = false
	world._ocean.material().shader = variant_shaders.get(mode, ocean_shader)
	world._ocean.material().set_shader_parameter("cloud_reflection_strength", 0.0 if mode in ["no_cloud_refl", "no_refl", "no_vertex_sky"] else 1.0)
	world._ocean.material().set_shader_parameter("sky_view_samples", 16 if mode == "sky16" else 6)
	world._ocean.material().set_shader_parameter("sky_reflection_strength", 0.0 if mode in ["no_sky_refl", "no_refl", "no_vertex_sky"] else 1.0)
	world._planet.material_override.shader = terrain_variants.get(mode, terrain_shader)
	if mode == "both":
		world._ocean.material().shader = variant_shaders["ocean_vertex_air"]
		world._planet.material_override.shader = terrain_variants["terrain_skip_covered"]
	world._ocean.mesh = coarse_mesh if mode == "coarse_ocean_mesh" else dense_mesh
	root.msaa_3d = Viewport.MSAA_DISABLED if mode == "no_msaa" else Viewport.MSAA_2X
	var density := 0.0 if mode == "no_air" else float(Surface.home().definition.atmosphere_visual_density)
	for m in [world._sky_material, world._planet.material_override, world._ocean.material()]:
		m.set_shader_parameter("atmosphere_density_scale", density)

func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var res := OS.get_environment("PROBE_RES").split("x") if OS.get_environment("PROBE_RES") != "" else PackedStringArray(["1280","720"])
	root.size = Vector2i(int(res[0]), int(res[1]))
	DisplayServer.window_set_size(root.size)
	print("PROBE msaa=%d size=%s" % [root.msaa_3d, root.size])
	if OS.get_environment("PROBE_DENSE") == "1":
		var weather := Weather.new()
		var map := Image.create(512, 256, false, Image.FORMAT_RGBA8)
		map.fill(Color(0.35, 0.2, 0.15, 0.3))
		weather.restore(map)
		Surface.home().definition.cloud_weather = weather
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	world.set_sun_direction(Vector3(0.3, 0.8, 0.5).normalized())
	ocean_shader = world._ocean.material().shader
	dense_mesh = world._ocean.mesh
	var frag_at := ocean_shader.code.find("void fragment()")
	var no_swell := Shader.new()
	no_swell.code = ocean_shader.code.substr(0, frag_at) + ocean_shader.code.substr(frag_at).replace("i < 4", "i < 0")
	variant_shaders["no_ocean_swell"] = no_swell
	var no_oair := Shader.new()
	no_oair.code = ocean_shader.code.replace("vec3 air = scatter_air(camera_planet_km, normalize(ray), length(ray), transmission);", "transmission = vec3(1.0); vec3 air = vec3(0.0);")
	variant_shaders["no_ocean_air"] = no_oair
	var no_screen := Shader.new()
	no_screen.code = ocean_shader.code.replace("vec3 screen_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, depth_blend_power * 2.5).rgb;", "vec3 screen_color = vec3(0.2);").replace("float depth = linear_depth(texture(DEPTH_TEXTURE, SCREEN_UV).r, SCREEN_UV, INV_PROJECTION_MATRIX);", "float depth = -VERTEX.z + 50.0;")
	variant_shaders["no_ocean_screen"] = no_screen
	var vair := Shader.new()
	var oc := ocean_shader.code.replace("varying float cell_size;", "varying float cell_size;\nvarying vec3 air_v;\nvarying vec3 trans_v;")
	oc = oc.replace("\tVERTEX += to_local * up * height;", "\tvec3 ray_v = (world_pos - planet_center_world) * 0.001 - camera_planet_km;\n\tvec3 tv;\n\tair_v = scatter_air(camera_planet_km, normalize(ray_v), length(ray_v), tv);\n\ttrans_v = tv;\n\tVERTEX += to_local * up * height;")
	oc = oc.replace("vec3 air = scatter_air(camera_planet_km, normalize(ray), length(ray), transmission);", "transmission = trans_v; vec3 air = air_v;")
	vair.code = oc
	variant_shaders["ocean_vertex_air"] = vair
	var notap := Shader.new()
	notap.code = ocean_shader.code.replace("if (sun_shadow < 0.0) {", "if (false) {").replace("float sun_shadow = -1.0;", "float sun_shadow = 0.6;")
	variant_shaders["refl_notap"] = notap
	var one := Shader.new()
	one.code = notap.code.replace("for (int i = 0; i < 2; i++) {", "for (int i = 0; i < 1; i++) {")
	variant_shaders["refl_one"] = one
	var sky_px := Shader.new()
	sky_px.code = ocean_shader.code.replace("vec3 sky = sky_light;", "vec3 sky_t;\n\tvec3 sky = scatter_air(origin_km, bounce, 1.0e6, sky_t);").replace("sky_light = scatter_air(", "sky_light = vec3(0.0) * scatter_air(")
	variant_shaders["sky_per_pixel"] = sky_px
	var no_vsky := Shader.new()
	no_vsky.code = ocean_shader.code.replace("sky_light = scatter_air_steps((world_pos - planet_center_world) * 0.001, reflect(view_dir, up), 1.0e6, BODY_RADIUS, AIR_RADIUS, atmosphere_density_scale, sky_view_samples, 1, sky_transmission);", "")
	assert(no_vsky.code != ocean_shader.code)
	variant_shaders["no_vertex_sky"] = no_vsky
	var skip_all := Shader.new()
	skip_all.code = ocean_shader.code.replace("-INV_VIEW_MATRIX[2].xyz) > -0.3)", "-INV_VIEW_MATRIX[2].xyz) > 2.0)")
	assert(skip_all.code != ocean_shader.code)
	variant_shaders["skip_all_vertex"] = skip_all
	for k in ["0.5", "1.0"]:
		var col := Shader.new()
		col.code = oc.replace("\tfloat angle = r / planet_radius;", "\tfloat cam_h = max(length(camera_planet_km) * 1000.0 - planet_radius, 0.0);\n\tfloat cc = %s * cam_h;\n\tfloat edge_r = base_extent + stretch;\n\tr = (sqrt(r * r + cc * cc) - cc) * edge_r / max(sqrt(edge_r * edge_r + cc * cc) - cc, 1.0);\n\tfloat angle = r / planet_radius;" % k)
		variant_shaders["vair_collapse_" + k] = col
	terrain_shader = world._planet.material_override.shader
	var tskip := Shader.new()
	tskip.code = terrain_shader.code.replace("vec3 air = scatter_air(ray_origin,normalize(ray),length(ray),transmission);", "vec3 air = vec3(0.0); transmission = vec3(1.0);\n\tif (!(water_cutout_radius > 0.0 && surface_color.a > 0.7 && length(VERTEX) < water_cutout_radius && seabed_fade >= 1.0)) { air = scatter_air(ray_origin,normalize(ray),length(ray),transmission); }")
	terrain_variants["terrain_skip_covered"] = tskip
	var src := (load("res://scripts/ocean_patch.gd") as GDScript).source_code.replace("class_name OceanPatch", "").replace("const RINGS := 384", "const RINGS := 96").replace("const SEGMENTS := 512", "const SEGMENTS := 256")
	var coarse_script := GDScript.new()
	coarse_script.source_code = src
	coarse_script.reload()
	coarse_mesh = coarse_script._build_rings()
	print("PROBE ocean tris dense=%d coarse=%d" % [dense_mesh.surface_get_array_index_len(0) / 3, coarse_mesh.surface_get_array_index_len(0) / 3])
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var cloud_vps: Array = [world._clouds.lowres_viewport()] + Array(world._clouds._resolve)
	for v in cloud_vps: RenderingServer.viewport_set_measure_render_time(v.get_viewport_rid(), true)
	altitude = 1000.0
	_step()
	for i in range(30): await process_frame
	print("PROBE shade_bottom_alt_m=%.0f shade_top_alt_m=%.0f" % [(world._clouds._shade_bottom - world._clouds._shade_ground) * 1000.0, (world._clouds._shade_top - world._clouds._shade_ground) * 1000.0])
	var alts := [1000.0, 3000.0, 4500.0, 5000.0, 5200.0, 5500.0, 6500.0, 9000.0]
	if OS.get_environment("PROBE_ALTS") != "":
		alts.clear()
		for a in OS.get_environment("PROBE_ALTS").split(","): alts.append(float(a))
	var modes := OS.get_environment("PROBE_MODES").split(",") if OS.get_environment("PROBE_MODES") != "" else PackedStringArray(["baseline", "no_clouds", "no_ocean", "no_air", "no_rocket", "no_terrain"])
	if OS.get_environment("PROBE_SHOTS") != "":
		await _shots()
		quit(0)
		return
	var pitches := [0.22, -0.35, -0.9]
	if OS.get_environment("PROBE_PITCH") != "":
		pitches.clear()
		for x in OS.get_environment("PROBE_PITCH").split(","): pitches.append(float(x))
	for p in pitches:
		pitch = p
		for a in alts:
			altitude = a
			var line := "PROBE pitch %5.2f alt %6.0f |" % [p, a]
			for m in modes:
				mode = m
				for i in range(15):
					_step()
					await process_frame
				var frames: Array[float] = []
				var gpu: Array[float] = []
				var cgpu: Array[float] = []
				sync_us.clear()
				var last := Time.get_ticks_usec()
				for i in range(60):
					_step()
					await RenderingServer.frame_post_draw
					var now := Time.get_ticks_usec()
					frames.append(float(now - last) / 1000.0)
					last = now
					gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
					var c := 0.0
					for v in cloud_vps: c += RenderingServer.viewport_get_measured_render_time_gpu(v.get_viewport_rid())
					cgpu.append(c)
				line += " %s f%.2f g%.2f c%.2f cpu%.2f |" % [m, _med(frames), _med(gpu), _med(cgpu), _med(sync_us)]
			print(line)
	quit(0)


func _grab(settle: int = 20) -> Image:
	for i in range(settle):
		_step()
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _shots() -> void:
	var out := OS.get_environment("PROBE_SHOTS")
	world._clouds.time_scale = 0.0
	var day := float(Surface.home().definition.rotation_seconds)
	for sun in [["noon", Vector3.ZERO], ["sunset_front", Vector3(-0.55, 0.06, -0.83)]]:
		sun_override = sun[1]
		_step()
		print("SUNDIR %s %s" % [sun[0], world._sun_direction.dot(world._surface_up)])
		for a in [30.0, 4871.0]:
			altitude = a
			for combo in [[0.62, 0.22], [0.62, 0.45]]:
				var yaw: float = combo[0]
				var pv: float = combo[1]
				world._yaw = yaw
				pitch = pv
				mode = OS.get_environment("PROBE_A")
				await _grab(400)
				var base: Image = await _grab()
				mode = OS.get_environment("PROBE_B")
				var cand: Image = await _grab()
				mode = OS.get_environment("PROBE_A")
				var again: Image = await _grab()
				var floor_max := 0.0
				for y in range(0, base.get_height(), 2):
					for x in range(0, base.get_width(), 2):
						var e := base.get_pixel(x, y) - again.get_pixel(x, y)
						floor_max = maxf(floor_max, maxf(absf(e.r), maxf(absf(e.g), absf(e.b))))
				var mx := 0.0
				var total := 0.0
				var over := 0
				for y in range(0, base.get_height(), 2):
					for x in range(0, base.get_width(), 2):
						var d := base.get_pixel(x, y) - cand.get_pixel(x, y)
						var m := maxf(absf(d.r), maxf(absf(d.g), absf(d.b)))
						mx = maxf(mx, m)
						total += m
						if m > 4.0 / 255.0: over += 1
				var n := (base.get_width() / 2) * (base.get_height() / 2)
				var tag := "%s_%05d_%d_p%d" % [sun[0], int(a), int(yaw * 10), int(pv * 100)]
				base.save_png(out + "/" + tag + "_base.png")
				cand.save_png(out + "/" + tag + "_vair.png")
				print("SHOT floor %.1f | %s max %.1f/255 mean %.3f/255 over4 %.3f%%" % [floor_max * 255.0, tag, mx * 255.0, total / n * 255.0, 100.0 * over / n])
