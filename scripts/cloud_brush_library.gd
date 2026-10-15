extends RefCounted
## Deterministic cloud formation tiles. RGBA are cloud category weights, not
## display colors. Every tile has soft, irregular edges and transparent data
## corners; use preview_image() to display the weights as visible clouds.

const WeatherMap = preload("res://scripts/cloud_weather_map.gd")
static var _tiles: Dictionary = {}

static func categories() -> Array[Dictionary]:
	return [
		{"id": "cumulus", "name": "Cumulus", "description": "Scattered fair-weather puffs with clear blue gaps."},
		{"id": "streets", "name": "Cloud streets", "description": "Wind-aligned rows of cumulus; rotate to set the wind direction."},
		{"id": "stratocumulus", "name": "Stratocumulus", "description": "Connected low cloud cells with irregular openings."},
		{"id": "overcast", "name": "Overcast", "description": "A broad stratus blanket with softly broken edges."},
		{"id": "storm", "name": "Storm systems", "description": "Dense storm cores, spreading anvils and surrounding cumulus."},
		{"id": "mushroom", "name": "Mushroom clouds", "description": "A narrow rising column beneath a broad, rounded billowing cap."},
		{"id": "cirrus", "name": "Wispy layer", "description": "Thin streaks and veils for gentle transitions between formations."},
	]

static func tile(id: String, variant: int = 0, size: int = 128) -> Image:
	var resolution := clampi(size, 16, 512)
	var key := "%s:%d:%d" % [id, variant, resolution]
	if _tiles.has(key):
		return _tiles[key]
	var result := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	var seed_value := 17171 + variant * 977
	var detail := _noise(seed_value, 2.8)
	var broad := _noise(seed_value + 39, 0.75)
	var cellular := FastNoiseLite.new()
	cellular.seed = seed_value + 123
	cellular.noise_type = FastNoiseLite.TYPE_CELLULAR
	cellular.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	cellular.frequency = 4.6
	for y in range(resolution):
		for x in range(resolution):
			var point := (Vector2(x + 0.5, y + 0.5) / float(resolution) - Vector2(0.5, 0.5)) * 2.0
			var fine := detail.get_noise_2d(point.x * 3.0, point.y * 3.0)
			var broad_value := broad.get_noise_2d(point.x * 3.0, point.y * 3.0)
			var cell := cellular.get_noise_2d(point.x, point.y)
			var edge := 1.0 - smoothstep(0.64, 1.0, point.length() + broad_value * 0.12)
			var weights := Color(0, 0, 0, 0)
			match id:
				"cumulus":
					weights.r = (1.0 - smoothstep(-0.78, -0.46, cell + fine * 0.13)) * (0.70 + broad_value * 0.35)
				"streets":
					var stripe := sin((point.x + broad_value * 0.11) * 31.0)
					weights.r = smoothstep(-0.12, 0.65, stripe) * (0.30 + 0.65 * smoothstep(-0.42, 0.27, fine + broad_value * 0.25))
				"stratocumulus":
					weights.g = (0.33 + 0.61 * smoothstep(-0.92, -0.40, cell + fine * 0.14)) * (0.85 + broad_value * 0.25)
				"overcast":
					weights.b = 0.80 + broad_value * 0.19 + fine * 0.10
				"storm":
					var core := exp(-pow(Vector2(point.x + 0.12, point.y + 0.12).length() * 2.9, 2.0))
					var anvil := exp(-pow(Vector2((point.x - 0.12) * 1.1, (point.y - 0.14) * 2.3).length() * 1.9, 2.0))
					weights.a = clampf(maxf(core, anvil * 0.88) * (0.93 + fine * 0.18), 0.0, 1.0)
					weights.r = (1.0 - weights.a) * (1.0 - smoothstep(-0.79, -0.44, cell + fine * 0.13)) * 0.36
					weights.g = (1.0 - weights.a - weights.r) * anvil * 0.30
				"cirrus":
					var streak := sin((point.x * 0.8 + point.y * 0.35 + broad_value * 0.12) * 33.0)
					weights.b = smoothstep(-0.40, 0.85, streak) * (0.15 + 0.28 * smoothstep(-0.40, 0.35, fine))
				"mushroom":
					# Radial coverage encodes the column's nested density contours.
					# The volume expands these contours into a rounded cap at height.
					var radial := (point - Vector2(broad_value * 0.025, 0.0)).length()
					weights.a = clampf(1.0 - radial / 0.85 + fine * 0.025, 0.0, 1.0)
				_:
					weights.r = 0.7
			result.set_pixel(x, y, WeatherMap._bounded_weights(weights * edge))
	_tiles[key] = result
	return result

## A local RNG makes the same seed reproducible without affecting gameplay RNG.
## Generation uses the same spherical stamps and blend rules as manual painting.
static func generate_weather(seed_value: int, formation_count: int = 64, density: float = 0.8, category: String = "mixed", selected_types: Array[String] = [], options: Dictionary = {}) -> Resource:
	var weather := WeatherMap.new()
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var choices := ["cumulus", "cumulus", "streets", "stratocumulus", "stratocumulus", "overcast", "storm", "cirrus", "mushroom"]
	# Normalize to catalog order so checkbox click order cannot change the seed.
	var mix: Array[String] = []
	for entry in categories():
		if entry.id in selected_types: mix.append(entry.id)
	# Seeded shuffle, then cycle: every chosen type participates when there are
	# at least as many formations as types, with counts differing by at most one.
	for index in range(mix.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var swap := mix[index]
		mix[index] = mix[other]
		mix[other] = swap
	var schedule: Array[String] = []
	if options.has("weights") and not mix.is_empty():
		var weights: Dictionary = options.weights
		var total := 0.0
		for id in mix: total += maxf(float(weights.get(id, 1.0)), 0.0)
		if total <= 0.0: return weather
		var allocated := {}
		for id in mix: allocated[id] = 0
		for slot in range(clampi(formation_count, 1, 160)):
			var chosen := mix[0]
			var deficit := -INF
			for id in mix:
				var desired := (slot + 1) * maxf(float(weights.get(id, 1.0)), 0.0) / total - int(allocated[id])
				if desired > deficit:
					deficit = desired
					chosen = id
			schedule.append(chosen)
			allocated[chosen] += 1
	var mask: Image = options.get("mask")
	var positions: Array[Vector2i] = []
	if mask != null:
		for y in range(mask.get_height()):
			for x in range(mask.get_width()):
				if mask.get_pixel(x, y).r > 0.0: positions.append(Vector2i(x, y))
		if positions.is_empty(): return weather
	for index in range(clampi(formation_count, 1, 160)):
		var latitude := random.randf_range(-1.0, 1.0)
		var longitude := random.randf_range(-PI, PI)
		var horizontal := sqrt(maxf(0.0, 1.0 - latitude * latitude))
		var center := Vector3(cos(longitude) * horizontal, latitude, sin(longitude) * horizontal)
		if mask != null:
			var pixel: Vector2i = positions[random.randi_range(0, positions.size() - 1)]
			center = preload("res://scripts/cloud_design.gd").direction_at(pixel.x, pixel.y, mask.get_size())
		var id: String = choices[random.randi_range(0, choices.size() - 1)] if category == "mixed" else category
		if not mix.is_empty(): id = mix[index % mix.size()]
		if not schedule.is_empty(): id = schedule[index]
		var minimum := clampf(float(options.get("min_radius", 12.0)), 1, 70)
		var maximum := clampf(float(options.get("max_radius", 32.0)), minimum, 70)
		var radius := deg_to_rad(random.randf_range(minimum, maximum))
		if id == "mushroom": radius *= 0.45
		weather.stamp(center, radius, tile(id, random.randi_range(0, 3)), clampf(density, 0.0, 1.0) * random.randf_range(0.65, 1.0), random.randf_range(-PI, PI), false, 0.55)
	return weather

static func preview(id: String, variant: int = 0, size: int = 96) -> Image:
	return preview_image(tile(id, variant), size)

## Deliberately composite alpha/storm as a weight, never as transparency.
static func preview_image(weights: Image, size: int = 96) -> Image:
	var resolution := clampi(size, 8, 512)
	var result := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	var background := Color("102638")
	result.fill(background)
	if weights == null or weights.is_empty():
		return result
	for y in range(resolution):
		for x in range(resolution):
			var sample := WeatherMap._sample_tile(weights, Vector2(x + 0.5, y + 0.5) / float(resolution))
			var total := clampf(sample.r + sample.g + sample.b + sample.a, 0.0, 1.0)
			var color := background * (1.0 - total)
			color += Color("f1f7ff") * sample.r + Color("a8d9e8") * sample.g + Color("b8bdcd") * sample.b + Color("bdacd9") * sample.a
			color.a = 1.0
			result.set_pixel(x, y, color)
	return result

static func _noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	return noise
