extends SceneTree
## Headless regression for authored weather. Run with tools/run.sh --headless --script res://tests/test_cloud_painting.gd.

const Weather = preload("res://scripts/cloud_weather_map.gd")
const Tiles = preload("res://scripts/cloud_brush_library.gd")
const Definition = preload("res://scripts/planet_definition.gd")
const CloudLayer = preload("res://scripts/cloud_layer.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_tiles()
	_test_generator()
	_test_spherical_painting()
	_test_blending_and_history()
	_test_capture_and_persistence()
	_test_renderer_binding()
	if failures.is_empty():
		print("PASS: cloud tile categories, seeded random generation, mushroom contours, deterministic variants, spherical seams/poles, feathering, bounded blending, erase, history, capture, persistence and renderer binding.")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _test_tiles() -> void:
	var fingerprints: Array[int] = []
	var categories := ["cumulus", "streets", "stratocumulus", "overcast", "storm", "cirrus", "mushroom"]
	check(Tiles.categories().size() >= categories.size(), "Cloud library exposes every included formation category")
	for category in categories:
		var tile: Image = Tiles.tile(category, 0, 64)
		check(tile != null and not tile.is_empty(), "%s generates a usable tile" % category)
		if tile == null or tile.is_empty():
			continue
		check(tile.get_size() == Vector2i(64, 64), "%s honors tile resolution" % category)
		check(tile.get_data() == Tiles.tile(category, 0, 64).get_data(), "%s seed is deterministic" % category)
		check(tile.get_data() != Tiles.tile(category, 1, 64).get_data(), "%s has distinct variants" % category)
		check(_weight_sum(tile) > 1.0, "%s contains painted formation coverage" % category)
		check(_bounded(tile), "%s keeps four formation weights bounded" % category)
		var fingerprint := hash(tile.get_data())
		check(not fingerprints.has(fingerprint), "%s has a distinct cloud pattern" % category)
		fingerprints.append(fingerprint)

func _test_generator() -> void:
	var first: Resource = Tiles.generate_weather(9231, 16)
	var repeated: Resource = Tiles.generate_weather(9231, 16)
	var different: Resource = Tiles.generate_weather(9232, 16)
	check(first.image.get_data() == repeated.image.get_data(), "Same seed reproduces identical weather")
	check(first.image.get_data() != different.image.get_data(), "Different seeds produce different skies")
	check(_weight_sum(first.image) > 10.0 and _bounded(first.image), "Generated formations contain bounded cloud coverage")
	var mushrooms: Resource = Tiles.generate_weather(52, 16, 0.9, "mushroom")
	var storm_weight := 0.0
	for y in range(mushrooms.image.get_height()):
		for x in range(mushrooms.image.get_width()):
			var pixel: Color = mushrooms.image.get_pixel(x, y)
			storm_weight += pixel.a
			check(pixel.r + pixel.g + pixel.b == 0.0, "Mushroom-only generation preserves the chosen formation family")
	check(storm_weight > 1.0, "Mushroom clouds appear in generated weather")
	var mushroom: Image = Tiles.tile("mushroom")
	check(mushroom.get_pixel(64, 64).a > mushroom.get_pixel(85, 64).a, "Mushroom density contours support a narrower stem and wider cap")

func _test_spherical_painting() -> void:
	var weather := Weather.new()
	weather.initialize()
	var solid := _solid(Color(1, 0, 0, 0))
	check(weather.stamp(Vector3.LEFT, 0.32, solid, 1.0), "A brush crossing the longitude seam changes the map")
	var left: Color = weather.sample_direction(Vector3(-1, 0, -0.005).normalized())
	var right: Color = weather.sample_direction(Vector3(-1, 0, 0.005).normalized())
	check(left.r > 0.9 and right.r > 0.9, "Painting wraps across both sides of the longitude seam")
	check(absf(left.r - right.r) < 0.025, "A seamless brush has matching coverage on both sides of the seam")
	check(_coverage(weather.sample_direction(Vector3.RIGHT)) < 0.001, "A seam stamp does not spill onto the opposite hemisphere")
	weather.clear()
	check(weather.stamp(Vector3.UP, 0.32, solid, 1.0), "A north-pole brush changes the map")
	for longitude in [0.0, PI * 0.5, PI, PI * 1.5]:
		var nearby := Vector3(sin(0.06) * cos(longitude), cos(0.06), sin(0.06) * sin(longitude))
		check(weather.sample_direction(nearby).r > 0.85, "Polar coverage stays connected across all longitudes")
	check(_coverage(weather.sample_direction(Vector3.DOWN)) < 0.001, "Polar painting stays on the intended hemisphere")
	weather.clear()
	weather.stamp(Vector3.RIGHT, 0.4, solid, 1.0, 0.0, false, 0.75)
	var center: float = weather.sample_direction(Vector3.RIGHT).r
	var feather: float = weather.sample_direction(Vector3(cos(0.35), 0, sin(0.35))).r
	var outside: float = weather.sample_direction(Vector3(cos(0.46), 0, sin(0.46))).r
	check(center > 0.9 and feather > 0.001 and feather < center * 0.6, "Brush edges feather smoothly into surrounding clear weather")
	check(outside < 0.001, "Feathering leaves weather outside the brush radius untouched")

func _test_blending_and_history() -> void:
	var weather := Weather.new()
	weather.initialize()
	var clear_snapshot: Image = weather.snapshot()
	var cumulus := _solid(Color(1, 0, 0, 0))
	var strata := _solid(Color(0, 1, 0, 0))
	weather.stamp(Vector3.RIGHT, 0.35, cumulus, 0.7)
	var first_snapshot: Image = weather.snapshot()
	weather.stamp(Vector3.RIGHT, 0.35, strata, 0.5)
	var mixed: Color = weather.sample_direction(Vector3.RIGHT)
	check(mixed.r > 0.05 and mixed.g > 0.05, "Overlapping brushes retain a mixture of cloud families")
	for index in range(12):
		weather.stamp(Vector3.RIGHT, 0.35, Tiles.tile("storm", index % 3, 64), 0.7, index * 0.4)
	check(_bounded(weather.image), "Repeated mixed brush strokes cannot overfill the weather channels")
	check(_weight_sum(clear_snapshot) == 0.0, "Snapshots are independent of subsequent strokes")
	weather.restore(first_snapshot)
	check(weather.image.get_data() == first_snapshot.get_data(), "Restoring an undo snapshot recovers the exact painted map")
	var before_erase: Color = weather.sample_direction(Vector3.RIGHT)
	weather.stamp(Vector3.RIGHT, 0.35, cumulus, 0.5, 0.0, true)
	check(weather.sample_direction(Vector3.RIGHT).r < before_erase.r * 0.7, "Soft erasing reduces painted density")
	weather.stamp(Vector3.RIGHT, 0.35, cumulus, 1.0, 0.0, true)
	check(_coverage(weather.sample_direction(Vector3.RIGHT)) < 0.015, "Full erasing restores clear weather without an opaque alpha residue")
	weather.restore(first_snapshot)
	weather.stamp(Vector3.RIGHT, 0.35, _solid(Color(0, 0, 0, 0)), 1.0, 0.0, true)
	check(_coverage(weather.sample_direction(Vector3.RIGHT)) < 0.015, "Eraser clears clouds beneath holes in the selected tile")
	weather.restore(first_snapshot)
	weather.stamp(Vector3.RIGHT, 0.35, null, 1.0, 0.0, true)
	check(_coverage(weather.sample_direction(Vector3.RIGHT)) < 0.015, "Eraser uses its round footprint even without a selected tile")
	weather.restore(clear_snapshot)
	check(_weight_sum(weather.image) == 0.0, "Restoring the initial snapshot returns to a completely clear map")

func _test_capture_and_persistence() -> void:
	var weather := Weather.new()
	weather.initialize()
	weather.stamp(Vector3.RIGHT, 0.4, _solid(Color(0, 0.2, 0.1, 0.7)), 1.0)
	var captured: Image = weather.capture(Vector3.RIGHT, 0.4, 64)
	check(captured.get_size() == Vector2i(64, 64) and _weight_sum(captured) > 1.0, "Capturing an authored formation produces a reusable tile")
	check(_bounded(captured), "Capturing preserves valid formation mixtures")
	var reused := Weather.new()
	reused.initialize()
	reused.stamp(Vector3.FORWARD, 0.3, captured, 1.0, 0.8)
	check(reused.sample_direction(Vector3.FORWARD).a > 0.4, "A captured tile retains its storm category when painted elsewhere")
	var path := "user://cloud-painting-test/weather.tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := ResourceSaver.save(weather, path)
	check(saved == OK, "Weather can be saved as a resource")
	if saved == OK:
		var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(loaded != null, "Weather reloads from disk")
		if loaded != null:
			check(loaded.image.get_data() == weather.image.get_data(), "Saved formations round-trip without channel or alpha loss")
			loaded.clear()
			check(_weight_sum(weather.image) > 1.0, "Reloaded weather does not share mutable image data with its source")
	var planet := Definition.new()
	check(planet.cloud_weather == null, "Existing planet definitions retain procedural clouds by default")
	planet.cloud_weather = weather
	var moon := Definition.new()
	moon.cloud_weather = reused
	planet.moons.append(moon)
	var planet_path := "user://cloud-painting-test/planet.tres"
	var planet_saved := ResourceSaver.save(planet, planet_path)
	check(planet_saved == OK, "Planet and moon weather save with their owning definitions")
	if planet_saved == OK:
		var loaded: Resource = ResourceLoader.load(planet_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(loaded != null and loaded.cloud_weather != null and loaded.moons.size() == 1, "Saved planet system reloads with authored weather")
		if loaded != null and loaded.cloud_weather != null and loaded.moons.size() == 1:
			check(loaded.cloud_weather.image.get_data() == weather.image.get_data(), "Planet weather retains its exact painted channels")
			check(loaded.moons[0].cloud_weather.image.get_data() == reused.image.get_data(), "Moon weather remains independent from its parent")

func _test_renderer_binding() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var layer := CloudLayer.new()
	holder.add_child(layer)
	var planet := Definition.new()
	layer.update_weather(planet, Vector3.UP * 601.0, Vector3.UP, true)
	var material := layer.material_override as ShaderMaterial
	check(not bool(material.get_shader_parameter("authored_weather")), "Unpainted planets retain the procedural rendering path")
	planet.cloud_weather = Weather.new()
	planet.cloud_weather.initialize()
	planet.cloud_weather.stamp(Vector3.UP, 0.3, _solid(Color(0, 0, 0, 1)), 0.8)
	layer.update_weather(planet, Vector3.UP * 601.0, Vector3.UP, true)
	check(bool(material.get_shader_parameter("authored_weather")), "The cloud renderer enables authored weather for painted planets")
	check(material.get_shader_parameter("cloud_weather_map") == planet.cloud_weather.get_texture(), "Editor and flight rendering bind the same authored texture")
	var texture: ImageTexture = planet.cloud_weather.get_texture()
	planet.cloud_weather.stamp(Vector3.UP, 0.3, _solid(Color(1, 0, 0, 0)), 0.5)
	layer.update_weather(planet, Vector3.UP * 601.0, Vector3.UP, true)
	check(material.get_shader_parameter("cloud_weather_map") == texture, "Painting updates the bound weather texture without replacing it")
	planet.cloud_weather = null
	layer.update_weather(planet, Vector3.UP * 601.0, Vector3.UP, true)
	check(not bool(material.get_shader_parameter("authored_weather")), "Returning to procedural weather resets the renderer mode")
	planet.atmosphere_height = 0.0
	layer.update_weather(planet, Vector3.UP * 601.0, Vector3.UP, true)
	check(not layer.visible, "Airless worlds hide authored and procedural weather")
	holder.free()

func _solid(value: Color) -> Image:
	var result := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	result.fill(value)
	return result

func _coverage(value: Color) -> float:
	return value.r + value.g + value.b + value.a

func _weight_sum(value: Image) -> float:
	var total := 0.0
	for y in range(value.get_height()):
		for x in range(value.get_width()):
			total += _coverage(value.get_pixel(x, y))
	return total

func _bounded(value: Image) -> bool:
	for y in range(value.get_height()):
		for x in range(value.get_width()):
			if _coverage(value.get_pixel(x, y)) > 1.000001:
				return false
	return true
