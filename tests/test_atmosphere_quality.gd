extends SceneTree
## Atmosphere quality presets and the precomputed sunlight table. Runs headless:
## tools/run.sh --headless --script res://tests/test_atmosphere_quality.gd
## Visual equivalence is measured by tests/benchmark_planet_rendering.gd.
const Quality = preload("res://scripts/atmosphere_quality.gd")
const Profile = preload("res://scripts/profile.gd")
const World = preload("res://scripts/world_view.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_presets()
	_test_bands()
	_test_sun_table()
	_test_profile()
	await _test_world()
	if failures.is_empty():
		print("PASS: %d atmosphere quality checks." % checks)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_presets() -> void:
	check(Quality.DEFAULT in Quality.MENU, "Default preset is offered in the menu")
	check(not "reference" in Quality.MENU and Quality.valid("reference"), "Reference path is kept but not offered")
	check(not Quality.valid("extreme") and not Quality.valid(""), "Unknown presets are rejected")
	# Ultra and reference are the original budgets: 16/2, 32/3 and 64/6.
	for preset in ["ultra", "reference"]:
		check(Quality.PRESETS[preset].view == [16, 32, 64] and Quality.PRESETS[preset].light == [2, 3, 6], preset + " keeps the original sample budgets")
	check(Quality.uses_sun_table("ultra") and not Quality.uses_sun_table("reference"), "Only the reference preset uses the light loop")
	for preset in ["ultra", "reference"]:
		check(Quality.settings(preset).surface_step == 0.03 and not Quality.settings(preset).half_res_sky, preset + " keeps the original step length and full-resolution sky")
	var previous_step := 1.0
	for preset in Quality.MENU:
		var step: float = Quality.settings(preset).surface_step
		check(step >= 0.03 and step <= previous_step, "%s surface step is no coarser than the preset below it" % preset)
		previous_step = step
	for band in range(3):
		var previous := 0
		for preset in Quality.MENU:
			var view: int = Quality.PRESETS[preset].view[band]
			var light: int = Quality.PRESETS[preset].light[band]
			# atmosphere.gdshaderinc: VIEW_SAMPLES = 64, light loop up to 6;
			# fewer than two view steps is undefined in its clamp().
			check(view >= 2 and view <= 64, "%s band %d view samples within the shader limit" % [preset, band])
			check(light >= 1 and light <= 6, "%s band %d light samples within the shader limit" % [preset, band])
			check(view >= previous, "%s band %d is not cheaper than the preset below it" % [preset, band])
			# Lower presets must keep the sunlight colour of ultra.
			check(light == Quality.PRESETS.ultra.light[band], "%s band %d keeps ultra's light quadrature" % [preset, band])
			previous = view

func _test_bands() -> void:
	# Verdant: 600 km radius, 90 km of air.
	for case in [[0.0, 0], [44.9, 0], [45.0, 1], [479.0, 1], [480.0, 2], [12000.0, 2]]:
		var samples := Quality.samples("ultra", case[0], 90.0, 600.0)
		check(samples == Vector2i([16, 32, 64][case[1]], [2, 3, 6][case[1]]), "Observer at %.1f km uses band %d" % case)
	check(Quality.samples("low", 0.0, 90.0, 600.0) == Vector2i(Quality.PRESETS.low.view[0], 2), "Low preset selects its own view budget")
	check(Quality.samples("bogus", 0.0, 90.0, 600.0) == Quality.samples(Quality.DEFAULT, 0.0, 90.0, 600.0), "Unknown preset falls back to the default")

func _test_sun_table() -> void:
	var table: ImageTexture = Quality.sun_depth_table(600.0, 690.0, 6)
	check(table.get_size() == Vector2(Quality.SUN_DEPTH_SIZE), "Table has the shader's SUN_DEPTH_SIZE")
	check(Quality.sun_depth_table(600.0, 690.0, 6) == table, "Tables are cached per body and light count")
	check(Quality.sun_depth_table(600.0, 690.0, 2) != table, "Each light count has its own quadrature")
	var image := table.get_image()
	check(image.get_format() == Image.FORMAT_RGH, "Half floats keep the table filterable on every renderer")
	var width := Quality.SUN_DEPTH_SIZE.x
	var height := Quality.SUN_DEPTH_SIZE.y
	# Straight up from the ground: the six-sample loop, evaluated here directly.
	var expected := _loop_depth(600.0, 1.0, 600.0, 690.0, 6)
	var zenith := image.get_pixel(width - 1, 0)
	check(absf(zenith.r - expected.x) < expected.x * 0.002 and absf(zenith.g - expected.y) < expected.y * 0.002, "Zenith depth matches the light loop (%s vs %s)" % [Vector2(zenith.r, zenith.g), expected])
	var low_sun := _loop_depth(600.0 + 90.0 * 10.0 / (height - 1), -1.0 + 2.0 * 140.0 / (width - 1), 600.0, 690.0, 3)
	var sampled := Quality.sun_depth_table(600.0, 690.0, 3).get_image().get_pixel(140, 10)
	check(absf(sampled.r - low_sun.x) < low_sun.x * 0.002, "Grazing depth matches the three-sample loop")
	# Air thins with height and toward the zenith.
	check(image.get_pixel(200, 0).r > image.get_pixel(200, 20).r and image.get_pixel(200, 20).r > image.get_pixel(200, 40).r, "Depth falls with height")
	check(image.get_pixel(150, 5).r > image.get_pixel(200, 5).r and image.get_pixel(200, 5).r > image.get_pixel(255, 5).r, "Depth falls as the sun rises")
	var airless := ShaderMaterial.new()
	Quality.apply_sun_depth_table(airless, 16.0, 16.0, 6)
	check(airless.get_shader_parameter("atmosphere_sun_depth_radii") == Vector2.ZERO, "Airless bodies keep the loop (which returns early)")
	var disabled := ShaderMaterial.new()
	Quality.apply_sun_depth_table(disabled, 600.0, 690.0, 6, false)
	check(disabled.get_shader_parameter("atmosphere_sun_depth_radii") == Vector2.ZERO, "Reference preset clears the table")

## atmosphere.gdshaderinc's light loop for one point, in km.
func _loop_depth(radius: float, cosine: float, body: float, air: float, count: int) -> Vector2:
	var thickness := air - body
	var b := radius * cosine
	var length := maxf(-b + sqrt(maxf(b * b - radius * radius + air * air, 0.0)), 0.0)
	var depth := Vector2.ZERO
	for step in range(count):
		var u := (float(step) + 0.5) / count
		var along := u * u * length
		var h := maxf(sqrt(radius * radius + along * along + 2.0 * radius * along * cosine) - body, 0.0)
		var edge := 1.0 - smoothstep(thickness * 0.7, thickness, h)
		depth += Vector2(exp(-h / (thickness * 0.32)), exp(-h / (thickness * 0.09))) * edge * length * float(2 * step + 1) / float(count * count)
	return depth

func _test_profile() -> void:
	check(Profile._defaults().atmosphere_quality == Quality.DEFAULT, "New profiles start at the default preset")
	check(Profile._sanitize({"atmosphere_quality": "low"}).atmosphere_quality == "low", "A saved menu preset is restored")
	for invalid in ["reference", "extreme", 3, null]:
		check(Profile._sanitize({"atmosphere_quality": invalid}).atmosphere_quality == Quality.DEFAULT, "Invalid saved preset %s falls back to the default" % str(invalid))

func _test_world() -> void:
	var world: Node3D = World.new()
	root.add_child(world)
	world.set_mode("flight")
	await process_frame
	var materials: Array = [world._sky_material, world._planet.material_override, world._ocean.material()]
	check(world.atmosphere_quality == Quality.DEFAULT, "The world starts at the default preset")
	for preset in Quality.MENU + ["reference"]:
		world.set_atmosphere_quality(preset)
		var expected := Quality.samples(preset, 0.0, 90.0, 600.0)
		for material in materials:
			check(material.get_shader_parameter("atmosphere_view_samples") == expected.x, "%s applies its view budget at runtime" % preset)
			var radii: Vector2 = material.get_shader_parameter("atmosphere_sun_depth_radii")
			check(radii == (Vector2(600.0, 690.0) if preset != "reference" else Vector2.ZERO), "%s sets the sunlight table for the home body" % preset)
		var settings: Dictionary = Quality.settings(preset)
		check((world._sky_material.shader != World.SKY_SHADER) == settings.half_res_sky, "%s selects its sky resolution" % preset)
		check(("render_mode use_half_res_pass" in world._sky_material.shader.code) == settings.half_res_sky, "%s sky variant matches its render mode" % preset)
		for material in materials:
			check(is_equal_approx(material.get_shader_parameter("atmosphere_surface_step"), settings.surface_step), "%s applies its surface step" % preset)
		var table_samples: Variant = world._sky_material.get_shader_parameter("atmosphere_sun_depth_samples")
		if preset != "reference":
			check(table_samples == expected.y, "%s table matches the band's light count" % preset)
	world.set_atmosphere_quality("ultra")
	world.set_atmosphere_quality("extreme")
	check(world.atmosphere_quality == "ultra", "Unknown presets leave the current one in place")
	# Simulation state is untouched by the preset.
	var flight_position: Vector3 = world._flight_position
	world.set_atmosphere_quality("low")
	check(world._flight_position == flight_position and world._mode == "flight", "Quality changes do not move the craft or change mode")
	world.queue_free()
	await process_frame
