extends RefCounted
## CPU-only cloud design operations. Alpha is a storm weight, not transparency.
const Weather = preload("res://scripts/cloud_weather_map.gd")

static func direction_at(x: int, y: int, size: Vector2i) -> Vector3:
	var latitude := (y + 0.5) / size.y * PI
	var longitude := ((x + 0.5) / size.x - 0.5) * TAU
	return Vector3(cos(longitude) * sin(latitude), cos(latitude), sin(longitude) * sin(latitude))

static func region_mask(size: Vector2i, options: Dictionary, selection: Resource = null) -> Image:
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	mask.fill(Color(1, 0, 0, 0))
	var region := int(options.get("region", 0))
	if region == 1:
		if selection == null:
			mask.fill(Color(0, 0, 0, 0))
		else:
			mask = selection.image.duplicate()
			if mask.get_size() != size: mask.resize(size.x, size.y)
	elif region == 2:
		var south := minf(options.get("south", -30.0), options.get("north", 30.0))
		var north := maxf(options.get("south", -30.0), options.get("north", 30.0))
		for y in range(size.y):
			var latitude := 90.0 - (y + 0.5) / size.y * 180.0
			var amount := 1.0 if latitude >= south and latitude <= north else 0.0
			mask.fill_rect(Rect2i(0, y, size.x, 1), Color(amount, 0, 0, 0))
	return mask

static func combine(base: Image, generated: Image, mask: Image, additive: bool) -> Image:
	var result := base.duplicate() as Image
	var incoming := generated.duplicate() as Image
	if incoming.get_size() != base.get_size(): incoming.resize(base.get_width(), base.get_height())
	for y in range(base.get_height()):
		for x in range(base.get_width()):
			var amount := mask.get_pixel(x, y).r
			if amount <= 0: continue
			var old := base.get_pixel(x, y)
			var top := incoming.get_pixel(x, y)
			var target := top
			if additive:
				var coverage := clampf(top.r + top.g + top.b + top.a, 0, 1)
				target = top + old * (1 - coverage)
			result.set_pixel(x, y, Weather._bounded_weights(old.lerp(target, amount)))
	return result

static func retouch(weather: Resource, center: Vector3, radius: float, amount: float, soften: bool) -> bool:
	if not weather.layer_editable(): return false
	var source: Image = weather.paint_layers[weather.active_layer].image
	var result := source.duplicate() as Image
	var sampler := Weather.new()
	sampler.image = source
	var changed := false
	var size := source.get_size()
	var step_angle := PI / size.y
	var latitude := acos(clampf(center.y, -1, 1))
	var first_row := maxi(0, floori((latitude - radius) / PI * size.y - 0.5))
	var last_row := mini(size.y - 1, ceili((latitude + radius) / PI * size.y - 0.5))
	for y in range(first_row, last_row + 1):
		for x in range(size.x):
			var direction := direction_at(x, y, size)
			var angle := direction.angle_to(center)
			if angle >= radius: continue
			var old := source.get_pixel(x, y)
			var average := old
			var frame := Weather._tangent_frame(direction, 0)
			for tangent in [frame[0], -frame[0], frame[1], -frame[1]]:
				average += sampler.sample_direction(direction * cos(step_angle) + tangent * sin(step_angle))
			average *= 0.2
			# Soften only thins boundaries; smooth redistributes neighboring paint.
			if soften and _coverage(average) > _coverage(old): average = old
			var next := Weather._bounded_weights(old.lerp(average, clampf(amount, 0, 1) * (1 - smoothstep(0.4, 1.0, angle / radius))))
			if next != old:
				result.set_pixel(x, y, next)
				changed = true
	if changed: weather.replace_active_layer(result)
	return changed

static func transform_region(weather: Resource, source_center: Vector3, destination: Vector3, radius: float, rotation: float, scale: float) -> bool:
	if not weather.layer_editable() or source_center == Vector3.ZERO or destination == Vector3.ZERO: return false
	if source_center.distance_to(destination) < 0.000001 and absf(rotation) < 0.000001 and absf(scale - 1.0) < 0.000001: return false
	var original: Image = weather.paint_layers[weather.active_layer].image
	var result := original.duplicate() as Image
	var sampler := Weather.new()
	sampler.image = original
	var source_frame := Weather._tangent_frame(source_center, 0)
	var target_frame := Weather._tangent_frame(destination, rotation)
	var target_radius := minf(radius * clampf(scale, 0.25, 3.0), PI * 0.49)
	# Clear the source first; sample exclusively from the untouched original.
	for y in range(result.get_height()):
		for x in range(result.get_width()):
			var direction := direction_at(x, y, result.get_size())
			var distance := direction.angle_to(source_center) / radius
			if distance < 1.0:
				result.set_pixel(x, y, Weather._bounded_weights(original.get_pixel(x, y) * smoothstep(0.85, 1.0, distance)))
	for y in range(result.get_height()):
		for x in range(result.get_width()):
			var direction := direction_at(x, y, result.get_size())
			var angle := direction.angle_to(destination)
			if angle >= target_radius: continue
			var tangent := (direction - destination * direction.dot(destination)).normalized()
			var mapped: Vector3 = source_frame[0] * tangent.dot(target_frame[0]) + source_frame[1] * tangent.dot(target_frame[1])
			var source_angle := angle / target_radius * radius
			var sample_direction := source_center * cos(source_angle) + mapped * sin(source_angle)
			var paint := sampler.sample_direction(sample_direction) * (1.0 - smoothstep(0.85, 1.0, angle / target_radius))
			result.set_pixel(x, y, Weather._bounded_weights(paint + result.get_pixel(x, y) * (1.0 - _coverage(paint))))
	return weather.replace_active_layer(result)

static func _coverage(value: Color) -> float:
	return clampf(value.r + value.g + value.b + value.a, 0, 1)
