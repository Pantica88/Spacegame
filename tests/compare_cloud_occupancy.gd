extends SceneTree
## Deterministic whole-frame comparison, including authored empty-pass culling.
## --resolution 800x450 --disable-vsync --script res://tests/compare_cloud_occupancy.gd -- /tmp/clouds-reference.gdshader [output-directory]
## Performance is measured separately: image readbacks and pixel scans here are
## deliberately outside the timed rendering benchmark.
const World = preload("res://scripts/world_view.gd")
const Surface = preload("res://scripts/planet_surface.gd")
const Weather = preload("res://scripts/cloud_weather_map.gd")
const Tiles = preload("res://scripts/cloud_brush_library.gd")
const MAX_RGB_DELTA := 1.01 / 255.0

var world: Node3D
var definition: Resource
var original_weather: Resource
var reference: ShaderMaterial
var candidate: ShaderMaterial
var output_dir := "/tmp/aphelion-cloud-opt-20261006/images"
var failures: Array[String] = []
var results: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless":
		push_error("Cloud image comparisons require a graphical display.")
		quit(1)
		return
	if args.is_empty() or not FileAccess.file_exists(args[0]):
		push_error("Provide a saved reference cloud shader after --")
		quit(1)
		return
	if args.size() > 1:
		output_dir = args[1]
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Cannot create comparison output directory: " + output_dir)
		quit(1)
		return
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	world._rocket.hide()
	world._landscape.hide()
	_freeze_time(world)
	_freeze_material(world._sky_material)
	definition = Surface.home().definition
	original_weather = definition.cloud_weather
	candidate = world._clouds.material_override as ShaderMaterial
	reference = candidate.duplicate() as ShaderMaterial
	var reference_shader := Shader.new()
	reference_shader.code = FileAccess.get_file_as_string(args[0])
	reference.shader = reference_shader
	var noise: NoiseTexture3D = candidate.get_shader_parameter("cloud_noise")
	if noise.get_data().is_empty():
		await noise.changed
	var cases := _cases()
	for index in range(cases.size()):
		var test: Dictionary = cases[index]
		_set_case(test)
		var images: Dictionary = {}
		# Reverse pairs on alternate cases to avoid one-sided settling effects.
		var order := ["before", "after"] if index % 2 == 0 else ["after", "before"]
		for version in order:
			_bind_material(version == "before", bool(test.get("disabled", false)))
			for frame in range(8):
				await process_frame
			await RenderingServer.frame_post_draw
			var captured := root.get_texture().get_image()
			var path := output_dir.path_join(str(test.name) + "-" + version + ".png")
			if captured.save_png(path) != OK:
				failures.append("Could not save " + path)
			images[version] = captured
		world._clouds.hide()
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var clear := root.get_texture().get_image()
		var clear_name := str(test.name) + "-clear.png"
		if clear.save_png(output_dir.path_join(clear_name)) != OK:
			failures.append("Could not save " + clear_name)
		var metrics := _compare(images.before, images.after)
		var reference_cloud := _compare(images.before, clear)
		var candidate_cloud := _compare(images.after, clear)
		metrics["name"] = test.name
		metrics["before"] = str(test.name) + "-before.png"
		metrics["after"] = str(test.name) + "-after.png"
		metrics["clear"] = clear_name
		metrics["reference_cloud"] = reference_cloud
		metrics["candidate_cloud"] = candidate_cloud
		results.append(metrics)
		print("VISUAL %s max=%.8f mean=%.10f changed=%d/%d" % [test.name, metrics.max_rgb, metrics.mean_rgb, metrics.changed_pixels, metrics.pixels])
		print("CLOUD CONTRIBUTION %s reference max=%.8f mean=%.10f pixels=%d candidate max=%.8f mean=%.10f pixels=%d" % [test.name, reference_cloud.max_rgb, reference_cloud.mean_rgb, reference_cloud.contributing_pixels, candidate_cloud.max_rgb, candidate_cloud.mean_rgb, candidate_cloud.contributing_pixels])
		if float(metrics.max_rgb) > MAX_RGB_DELTA:
			failures.append("Reference pixels changed: %s (maximum %.8f)" % [test.name, metrics.max_rgb])
		if bool(test.get("expected_clear", false)) and (float(reference_cloud.max_rgb) > MAX_RGB_DELTA or float(candidate_cloud.max_rgb) > MAX_RGB_DELTA):
			failures.append("Empty/disabled clouds differ from a hidden pass: " + str(test.name))
	definition.cloud_weather = original_weather
	world._clouds.material_override = candidate
	world.queue_free()
	await process_frame
	var report := FileAccess.open(output_dir.path_join("comparison.json"), FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"max_allowed_rgb": MAX_RGB_DELTA, "cases": results, "failures": failures}, "\t"))
	else:
		failures.append("Could not save comparison.json")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS: %d deterministic cloud comparisons. Images: %s" % [results.size(), output_dir])
	quit(0 if failures.is_empty() else 1)

func _freeze_material(material: ShaderMaterial) -> void:
	if material == null or material.shader == null or not material.shader.code.contains("TIME"):
		return
	var frozen := Shader.new()
	frozen.code = material.shader.code.replace("TIME", "0.0")
	material.shader = frozen

func _freeze_time(node: Node) -> void:
	if node is GeometryInstance3D and node.material_override is ShaderMaterial:
		_freeze_material(node.material_override as ShaderMaterial)
	for child in node.get_children():
		_freeze_time(child)

func _solid(weights: Color) -> Image:
	var result := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	result.fill(weights)
	return result

func _uniform_weather(weights: Color) -> Resource:
	var weather := Weather.new()
	var pixels := Image.create(512, 256, false, Image.FORMAT_RGBA8)
	pixels.fill(weights)
	weather.restore(pixels)
	return weather

func _family_weather(family: String) -> Resource:
	if family == "procedural":
		return null
	if family == "empty" or family == "disabled":
		return Weather.new()
	if original_weather == null:
		return _uniform_weather(Color(0.4, 0.3, 0.3, 0) if family == "regular" else Color(0, 0, 0, 1) if family == "storm" else Color(0.3, 0.2, 0.1, 0.4))
	var pixels: Image = original_weather.snapshot()
	if family != "both":
		for y in range(pixels.get_height()):
			for x in range(pixels.get_width()):
				var weights := pixels.get_pixel(x, y)
				pixels.set_pixel(x, y, Color(weights.r, weights.g, weights.b, 0.0) if family == "regular" else Color(0, 0, 0, weights.a))
	var weather := Weather.new()
	weather.restore(pixels)
	return weather

func _cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	var families := {}
	for family in ["both", "regular", "storm", "empty", "disabled", "procedural"]:
		families[family] = _family_weather(family)
		for altitude in [30.0, 3850.0, 100000.0]:
			cases.append({"name": "%s-%.0fm" % [family, altitude], "weather": families[family], "altitude": altitude, "disabled": family == "disabled", "expected_clear": family == "empty" or family == "disabled"})
	for family in ["both", "regular", "storm", "procedural"]:
		cases.append({"name": family + "-ground-sunset", "weather": families[family], "altitude": 30.0, "view": Vector3(0, 0.04, -1), "sun": Vector3(0, 0.025, -1)})
		cases.append({"name": family + "-interior", "weather": families[family], "altitude": 4200.0, "view": Vector3(0, 0.02, -1)})
		cases.append({"name": family + "-horizon-gap", "weather": families[family], "altitude": 3400.0, "view": Vector3(0, -0.06, -1), "sun": Vector3(0, 0.025, -1)})
		cases.append({"name": family + "-orbit", "weather": families[family], "altitude": 100000.0, "view": Vector3.DOWN, "up": Vector3.FORWARD})
		cases.append({"name": family + "-globe-sunset", "weather": families[family], "altitude": 1600000.0, "view": Vector3.DOWN, "up": Vector3.FORWARD, "sun": Vector3(1, -0.18, 0)})
	var radius := float(definition.radius)
	for anchor in [Vector3.LEFT, Vector3.UP, Vector3.DOWN]:
		var label := "seam" if anchor == Vector3.LEFT else "north-pole" if anchor == Vector3.UP else "south-pole"
		var sparse := Weather.new()
		sparse.stamp(anchor, 0.06, _solid(Color(0.4, 0.25, 0.15, 0.2)), 0.8, 0.0, false, 0.85)
		sparse.stamp((anchor + Vector3.FORWARD * 0.035).normalized(), 0.045, Tiles.tile("mushroom", 1), 0.9)
		var tangent := Vector3.BACK
		cases.append({"name": "sparse-" + label + "-side", "weather": sparse, "observer": anchor * (radius + 8200.0) + tangent * 35000.0, "target": anchor * (radius + 8200.0), "up": anchor, "sun": (anchor + tangent * 0.3).normalized(), "fov": 40.0})
		cases.append({"name": "sparse-" + label + "-orbit", "weather": sparse, "observer": anchor * (radius + 100000.0), "target": Vector3.ZERO, "up": tangent, "sun": anchor})
	var overlap := Weather.new()
	overlap.stamp(Vector3.UP, 0.05, Tiles.tile("stratocumulus", 2), 0.8)
	overlap.stamp(Vector3(0.02, 1, -0.015).normalized(), 0.055, Tiles.tile("mushroom", 1), 0.9)
	overlap.stamp(Vector3(-0.02, 1, -0.04).normalized(), 0.04, Tiles.tile("storm", 2), 0.65)
	for angle in [0.0, 1.137]:
		var spin := Basis(Vector3.UP, angle)
		cases.append({"name": "overlap-rotation-%.3f" % angle, "weather": overlap, "observer": Vector3(0, radius + 8000.0, 35000), "target": Vector3(0, radius + 8000.0, 0), "up": Vector3.UP, "basis": spin, "fov": 40.0})
	for distant_weather in ["regular", "sparse"]:
		cases.append({"name": distant_weather + "-distant-orbit", "weather": families["regular"] if distant_weather == "regular" else overlap,
			"altitude": radius * 9.0, "view": Vector3.DOWN, "up": Vector3.FORWARD})
	# Rotate an off-pole patch and move the observer with it. Occupancy is in
	# the body's local frame while the camera and ray remain in world space.
	var local_anchor := Vector3(1, 0.3, 0.2).normalized()
	var off_pole := Weather.new()
	off_pole.stamp(local_anchor, 0.04, Tiles.tile("mushroom", 2), 1.0)
	off_pole.stamp((local_anchor + Vector3.UP * 0.02).normalized(), 0.035, Tiles.tile("stratocumulus", 1), 0.7)
	for angle in [0.0, 1.137]:
		var spin := Basis(Vector3.UP, angle)
		var anchor := spin * local_anchor
		var tangent := anchor.cross(Vector3.UP).normalized()
		cases.append({"name": "sparse-off-pole-rotation-%.3f" % angle, "weather": off_pole, "observer": anchor * (radius + 8200.0) + tangent * 35000.0, "target": anchor * (radius + 8200.0), "up": anchor, "basis": spin, "sun": (anchor + tangent * 0.3).normalized(), "fov": 40.0})
	for category in ["mushroom", "storm"]:
		var silhouette := Weather.new()
		silhouette.stamp(Vector3.UP, 0.025, Tiles.tile(category), 1.0)
		cases.append({"name": category + "-silhouette", "weather": silhouette, "observer": Vector3(0, radius + 8000.0, 35000), "target": Vector3(0, radius + 8000.0, 0), "up": Vector3.UP, "sun": Vector3(0.3, 0.9, 0.3), "fov": 40.0})
		cases.append({"name": category + "-interior", "weather": silhouette, "observer": Vector3(0, radius + 8000.0, 0), "target": Vector3(0, radius + 8000.0, -30000), "up": Vector3.UP})
	var banks := Weather.new()
	banks.stamp(Vector3(0, cos(0.015), -sin(0.015)), 0.02, Tiles.tile("stratocumulus", 1), 0.9)
	banks.stamp(Vector3(0, cos(0.17), -sin(0.17)), 0.025, Tiles.tile("mushroom", 2), 1.0)
	cases.append({"name": "sparse-near-and-far-banks", "weather": banks, "altitude": 3400.0, "view": Vector3(0, -0.055, -1), "sun": Vector3(0, 0.025, -1)})
	var far_bank := Weather.new()
	far_bank.stamp(Vector3(0, cos(0.17), -sin(0.17)), 0.025, Tiles.tile("mushroom", 2), 1.0)
	cases.append({"name": "sparse-far-bank-only", "weather": far_bank, "altitude": 3400.0, "view": Vector3(0, -0.055, -1), "sun": Vector3(0, 0.025, -1)})
	# Isolated edge texels exercise bilinear footprints across wrap and clamp.
	var edge_pixels := Image.create(512, 256, false, Image.FORMAT_RGBA8)
	edge_pixels.fill(Color(0, 0, 0, 0))
	for location in [Vector2i(0, 128), Vector2i(511, 128), Vector2i(15, 0), Vector2i(31, 255)]:
		edge_pixels.set_pixelv(location, Color(0.2, 0.15, 0.15, 0.5))
	var edges := Weather.new()
	edges.restore(edge_pixels)
	for anchor in [Vector3.LEFT, Vector3.UP, Vector3.DOWN]:
		var label := "seam" if anchor == Vector3.LEFT else "north" if anchor == Vector3.UP else "south"
		cases.append({"name": "filtered-texel-" + label, "weather": edges, "observer": anchor * (radius + 3800.0) + Vector3.BACK * 2000.0, "target": anchor * (radius + 4500.0), "up": anchor, "fov": 60.0})
	return cases

func _set_case(test: Dictionary) -> void:
	definition.cloud_weather = test.weather
	var altitude := float(test.get("altitude", 30.0))
	world._clouds.material_override = candidate
	world.sync_flight({"position": Vector3(0, altitude, 0), "altitude": altitude, "orientation": Basis.IDENTITY, "engine_on": false, "fuel": 0.0, "boosters_attached": false, "capsule_only": false, "chute_deployed": false}, 0.0)
	world._rocket.hide()
	world._landscape.hide()
	world._planet.basis = test.get("basis", Basis.IDENTITY)
	var observer: Vector3 = test.get("observer", Vector3.UP * (float(definition.radius) + altitude))
	world.camera.position = world._planet.position + observer
	var direction: Vector3 = test.get("view", Vector3(0, 0.7 if altitude < 10000.0 else -1.0, -1.0))
	var target: Vector3 = test.get("target", observer + direction * 1000.0)
	world.camera.look_at(world._planet.position + target, test.get("up", Vector3.UP))
	world.camera.fov = float(test.get("fov", 43.0))
	world.set_sun_direction(test.get("sun", Vector3(0, 0.8, -0.6)))
	world._update_atmosphere()

func _bind_material(is_reference: bool, disabled: bool) -> void:
	var layer: MeshInstance3D = world._clouds
	var observer: Vector3 = (world.camera.global_position - world._planet.global_position) * 0.001
	# Update the production material first, then copy all common parameters.
	layer.material_override = candidate
	layer.update_weather(definition, observer, world._sun_direction, not disabled)
	if not is_reference:
		return
	for uniform in reference.shader.get_shader_uniform_list():
		var name: StringName = uniform.name
		var value: Variant = candidate.get_shader_parameter(name)
		if value != null:
			reference.set_shader_parameter(name, value)
	layer.material_override = reference
	# An empty-map fast path may return before rebinding uniforms. Explicitly
	# supply the old renderer's values so its reference pass still draws empty
	# weather, with the same shell, camera, texture and noise as the candidate.
	var atmosphere_height := float(definition.atmosphere_height)
	var height := minf(maxf(minf(atmosphere_height * 0.22, 6000.0), float(definition.relief) + 1600.0), atmosphere_height * 0.65)
	var thickness := minf(1400.0, atmosphere_height * 0.15)
	var weather: Resource = definition.cloud_weather
	reference.set_shader_parameter("authored_weather", weather != null)
	if weather != null:
		var bottom := height - thickness * 0.5
		var storm_thickness := maxf(thickness, minf(10000.0, atmosphere_height * 0.88 - bottom))
		reference.set_shader_parameter("cloud_weather_map", weather.get_texture())
		reference.set_shader_parameter("cloud_deck_fraction", thickness / storm_thickness)
		height = bottom + storm_thickness * 0.5
		thickness = storm_thickness
	else:
		reference.set_shader_parameter("cloud_weather_map", null)
		reference.set_shader_parameter("cloud_deck_fraction", 1.0)
	reference.set_shader_parameter("BODY_RADIUS", float(definition.radius) * 0.001)
	reference.set_shader_parameter("AIR_RADIUS", (float(definition.radius) + atmosphere_height) * 0.001)
	reference.set_shader_parameter("cloud_height_km", height * 0.001)
	reference.set_shader_parameter("cloud_thickness_km", thickness * 0.001)
	reference.set_shader_parameter("atmosphere_density_scale", float(definition.atmosphere_visual_density))
	reference.set_shader_parameter("camera_planet_km", observer)
	reference.set_shader_parameter("sun_direction", world._sun_direction)
	reference.set_shader_parameter("cloud_world_to_local", world._planet.global_basis.transposed())
	layer.global_position = world.camera.get_camera_transform().origin
	layer.visible = not disabled and atmosphere_height > 0.0 and float(definition.atmosphere_visual_density) > 0.0

func _compare(before: Image, after: Image) -> Dictionary:
	var max_delta := 0.0
	var total := 0.0
	var changed := 0
	var contributing := 0
	for y in range(before.get_height()):
		for x in range(before.get_width()):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			var delta := Vector3(absf(a.r - b.r), absf(a.g - b.g), absf(a.b - b.b))
			var peak := maxf(delta.x, maxf(delta.y, delta.z))
			max_delta = maxf(max_delta, peak)
			total += delta.x + delta.y + delta.z
			if peak > 0.0:
				changed += 1
			if peak > MAX_RGB_DELTA:
				contributing += 1
	var count := before.get_width() * before.get_height()
	return {"max_rgb": max_delta, "mean_rgb": total / (float(count) * 3.0), "changed_pixels": changed, "contributing_pixels": contributing, "pixels": count}
