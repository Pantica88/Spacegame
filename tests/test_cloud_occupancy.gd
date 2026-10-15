extends SceneTree
## CPU regression for conservative authored-cloud occupancy (cloud_weather_map.gd):
## has_clouds() decides whether the clouds draw, and get_occupancy_bounds()
## whether a map has storms. Layer visibility itself is in test_clouds.gd.
## Run: tools/run.sh --headless --script res://tests/test_cloud_occupancy.gd

const Weather = preload("res://scripts/cloud_weather_map.gd")

var failures: Array[String] = []
var sampled_directions := 0
var occupied_samples := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_cache_and_edits()
	_test_batched_edits()
	_test_channels_and_assignment()
	_test_persistence()
	_test_filtered_support()
	_test_random_support()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS: cloud occupancy cache, all channels, edit/load/restore/duplicate invalidation, and conservative filtered seam/pole bounds (%d directions, %d occupied)." % [sampled_directions, occupied_samples])
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _blank(width: int, height: int, format: Image.Format = Image.FORMAT_RGBA8) -> Image:
	var result := Image.create(width, height, false, format)
	result.fill(Color(0, 0, 0, 0))
	return result

func _solid(weights: Color) -> Image:
	var result := _blank(8, 8)
	result.fill(weights)
	return result

func _test_cache_and_edits() -> void:
	var weather := Weather.new()
	weather.initialize(32, 16)
	check(not weather.has_clouds(), "New authored weather is empty")
	var clear_image: Image = weather.snapshot()
	var empty_bounds: PackedVector3Array = weather.get_occupancy_bounds()
	check(empty_bounds.size() == 4 and _absent(empty_bounds, 0) and _absent(empty_bounds, 2), "Empty weather has no occupied family bounds")
	var cached_revision: int = weather._occupancy_revision
	for index in range(20):
		check(not weather.has_clouds() and weather.get_occupancy_bounds() == empty_bounds, "Unchanged weather retains cached occupancy")
	check(weather._occupancy_revision == cached_revision and cached_revision == weather.revision, "Occupancy cache tracks the current weather revision")
	check(not weather.stamp(Vector3.ZERO, 0.3, _solid(Color(1, 0, 0, 0)), 1.0), "Invalid stamp does not edit weather")
	check(weather.revision == cached_revision, "No-op stamp does not invalidate the cache")
	check(weather.stamp(Vector3.RIGHT, 0.4, _solid(Color(1, 0, 0, 0)), 1.0), "Painting edits the empty weather")
	check(weather._occupancy_revision != weather.revision, "A real stroke invalidates cached occupancy")
	check(weather.has_clouds(), "Painting enables occupied weather")
	var painted_image: Image = weather.snapshot()
	var painted_bounds: PackedVector3Array = weather.get_occupancy_bounds()
	check(not _absent(painted_bounds, 0) and _absent(painted_bounds, 2), "RGB-only paint occupies only the regular family")
	check(weather.stamp(Vector3.RIGHT, 0.8, null, 1.0, 0.0, true, 0.01), "Eraser removes the entire smaller stroke")
	check(not weather.has_clouds(), "Erasing the last nonzero texel empties the cache")
	weather.restore(painted_image)
	check(weather.has_clouds() and weather.get_occupancy_bounds() == painted_bounds, "Undo restores occupied bounds exactly")
	weather.restore(clear_image)
	check(not weather.has_clouds(), "Redo to an empty snapshot clears cached occupancy")
	weather.restore(painted_image)
	weather.clear()
	check(not weather.has_clouds() and _absent(weather.get_occupancy_bounds(), 0), "Clear invalidates occupied bounds")
	weather.restore(painted_image)
	weather.initialize(17, 9)
	check(not weather.has_clouds(), "Reinitialization invalidates the previous weather cache")

func _test_batched_edits() -> void:
	var weather := Weather.new()
	weather.initialize(64, 32)
	weather.has_clouds()
	var regular := _solid(Color(1, 0, 0, 0))
	var storm := _solid(Color(0, 0, 0, 1))
	weather.stamp(Vector3(1, 0.5, 0).normalized(), 0.35, regular, 1.0)
	weather.stamp(Vector3(0, -0.6, 1).normalized(), 0.35, storm, 1.0)
	_check_full_rebuild(weather, "Multiple strokes before querying occupancy")
	var mixed_snapshot: Image = weather.snapshot()
	weather.stamp(Vector3(1, 0.5, 0).normalized(), 0.7, null, 1.0, 0.0, true, 0.01)
	_check_full_rebuild(weather, "Erasing a family shrinks previously occupied bounds")
	check(_absent(weather.get_occupancy_bounds(), 0) and not _absent(weather.get_occupancy_bounds(), 2), "Erasing regular clouds preserves separately painted storm occupancy")
	weather.stamp(Vector3.DOWN, 0.2, regular, 1.0)
	weather.clear()
	weather.stamp(Vector3.UP, 0.2, storm, 1.0)
	_check_full_rebuild(weather, "A queued stroke followed by clear and a second stroke")
	weather.restore(mixed_snapshot)
	weather.stamp(Vector3.LEFT, 0.3, regular, 1.0)
	_check_full_rebuild(weather, "Restore followed by a stroke before querying occupancy")
	weather.initialize(19, 11)
	weather.stamp(Vector3.RIGHT, 0.5, regular, 1.0)
	_check_full_rebuild(weather, "Resize followed by a stroke before querying occupancy")

func _check_full_rebuild(weather: Resource, context: String) -> void:
	var rebuilt := Weather.new()
	rebuilt.image = weather.snapshot()
	check(weather.has_clouds() == rebuilt.has_clouds(), context + " preserves exact global emptiness")
	check(weather.get_occupancy_bounds() == rebuilt.get_occupancy_bounds(), context + " matches independent full occupancy rebuild")

func _test_channels_and_assignment() -> void:
	var weather := Weather.new()
	for channel in range(4):
		var source := _blank(11, 7)
		var weights := Color(0, 0, 0, 0)
		weights[channel] = 1.0 / 255.0
		source.set_pixel(0, 0, weights)
		weather.image = source
		check(weather.has_clouds(), "One least-significant byte in channel %d counts as occupied" % channel)
		var bounds: PackedVector3Array = weather.get_occupancy_bounds()
		check(_absent(bounds, 0) == (channel == 3) and _absent(bounds, 2) == (channel != 3), "Channel %d maps to the correct cloud family without interpreting alpha as transparency" % channel)
		weather.image = _blank(9, 5)
		check(not weather.has_clouds(), "Assigning a blank image invalidates channel %d occupancy" % channel)
	var tiny := _blank(3, 5, Image.FORMAT_RGBAF)
	tiny.set_pixel(1, 2, Color(0, 0, 0, 0.0000001))
	weather.image = tiny
	check(weather.has_clouds() and not _absent(weather.get_occupancy_bounds(), 2), "Float alpha below RGBA8 precision remains occupied")
	tiny = _blank(3, 5, Image.FORMAT_RGBAF)
	tiny.set_pixel(1, 2, Color(0.0000001, 0, 0, 0))
	weather.image = tiny
	check(weather.has_clouds() and not _absent(weather.get_occupancy_bounds(), 0), "Float RGB below RGBA8 precision remains occupied")
	weather.image = null
	check(not weather.has_clouds(), "Null image initializes valid empty weather")

func _test_persistence() -> void:
	var weather := Weather.new()
	weather.image = _blank(13, 9)
	weather.image.set_pixel(12, 8, Color(0.25, 0, 0, 0.5))
	var bounds: PackedVector3Array = weather.get_occupancy_bounds()
	check(weather.has_clouds(), "Persistence fixture contains both cloud families")
	var copied: Resource = weather.duplicate(true)
	check(copied.has_clouds() and copied.get_occupancy_bounds() == bounds, "Deep duplication rebuilds correct occupancy")
	copied.clear()
	check(not copied.has_clouds() and weather.has_clouds(), "Clearing a duplicate does not alter its source cache or image")
	var path := "/tmp/aphelion-cloud-occupancy-%d.tres" % OS.get_process_id()
	var saved := ResourceSaver.save(weather, path)
	check(saved == OK, "Occupancy fixture saves successfully")
	if saved == OK:
		var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(loaded != null, "Saved occupied weather loads")
		if loaded != null:
			check(loaded.has_clouds() and loaded.get_occupancy_bounds() == bounds, "Loaded images rebuild occupied family bounds")
			loaded.clear()
			check(not loaded.has_clouds() and weather.has_clouds(), "Loaded resource edits invalidate its cache independently")
		DirAccess.remove_absolute(path)
	weather.clear()
	saved = ResourceSaver.save(weather, path)
	check(saved == OK, "Empty occupancy fixture saves successfully")
	if saved == OK:
		var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(loaded != null and not loaded.has_clouds(), "Loaded empty weather does not reuse stale occupied bounds")
		DirAccess.remove_absolute(path)

func _test_filtered_support() -> void:
	var weather := Weather.new()
	# Singleton texels keep the bounds narrow enough to expose lost extrema;
	# every edge texel is exercised, including irregular and minimal map sizes.
	for size in [Vector2i(1, 1), Vector2i(2, 3), Vector2i(7, 5), Vector2i(13, 9)]:
		for y in range(size.y):
			for x in range(size.x):
				var source := _blank(size.x, size.y)
				source.set_pixel(x, y, Color(1.0 / 255.0, 0, 0, 1.0 / 255.0))
				weather.image = source
				var bounds: PackedVector3Array = weather.get_occupancy_bounds()
				for fy in [-0.9999, -0.5, 0.0, 0.5, 0.9999]:
					for fx in [-0.9999, -0.5, 0.0, 0.5, 0.9999]:
						var u: float = (x + 0.5 + fx) / float(size.x)
						var v: float = clampf((y + 0.5 + fy) / float(size.y), 0.0, 1.0)
						_check_direction(weather, bounds, _direction(u, v), "singleton %s (%d,%d)" % [size, x, y])
				# Spherical extrema are not generally at texel centers or corners.
				for axis in [Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
					_check_direction(weather, bounds, axis, "cardinal singleton %s (%d,%d)" % [size, x, y])

func _test_random_support() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5192381
	var weather := Weather.new()
	for index in range(20):
		var width := rng.randi_range(5, 39)
		var height := rng.randi_range(3, 23)
		var source := _blank(width, height)
		for pixel in range(5):
			var weights := Color(0, 0, 0, 0)
			weights[rng.randi_range(0, 3)] = float(rng.randi_range(1, 255)) / 255.0
			source.set_pixel(rng.randi_range(0, width - 1), rng.randi_range(0, height - 1), weights)
		weather.image = source
		var bounds: PackedVector3Array = weather.get_occupancy_bounds()
		for sample in range(1200):
			_check_direction(weather, bounds, _direction(rng.randf(), rng.randf()), "random map %d" % index)
		# Test both longitude limits and the polar clamping region explicitly.
		for longitude in range(101):
			var u := float(longitude) / 100.0
			for v in [0.0, 0.0000001, 0.25 / float(height), 1.0 - 0.25 / float(height), 0.9999999, 1.0]:
				_check_direction(weather, bounds, _direction(u, v), "polar map %d" % index)
		for latitude in range(101):
			var v := float(latitude) / 100.0
			for u in [0.0, 0.0000001, 0.9999999, 1.0]:
				_check_direction(weather, bounds, _direction(u, v), "seam map %d" % index)
	check(occupied_samples > 1000, "Conservative support checks actually encounter occupied filtered samples")

func _direction(u: float, v: float) -> Vector3:
	var longitude := (u - 0.5) * TAU
	var theta := v * PI
	return Vector3(cos(longitude) * sin(theta), cos(theta), sin(longitude) * sin(theta))

func _check_direction(weather: Resource, bounds: PackedVector3Array, direction: Vector3, context: String) -> void:
	sampled_directions += 1
	var weights: Color = weather.sample_direction(direction)
	if weights.r > 0.0 or weights.g > 0.0 or weights.b > 0.0:
		occupied_samples += 1
		check(_contains(bounds, 0, direction), "RGB filtered density lies inside occupancy bounds: %s direction %s" % [context, direction])
	if weights.a > 0.0:
		occupied_samples += 1
		check(_contains(bounds, 2, direction), "Storm filtered density lies inside occupancy bounds: %s direction %s" % [context, direction])

func _absent(bounds: PackedVector3Array, first: int) -> bool:
	return bounds[first].x > bounds[first + 1].x or bounds[first].y > bounds[first + 1].y or bounds[first].z > bounds[first + 1].z

func _contains(bounds: PackedVector3Array, first: int, point: Vector3) -> bool:
	return point.x >= bounds[first].x and point.x <= bounds[first + 1].x and point.y >= bounds[first].y and point.y <= bounds[first + 1].y and point.z >= bounds[first].z and point.z <= bounds[first + 1].z

