extends Resource
## Authored equirectangular cloud weights: R cumulus, G stratocumulus,
## B stratus/overcast, A storm. Alpha is DATA, never image transparency.
## Nonnegative weights sum to at most one; an empty pixel is (0, 0, 0, 0).
## u = atan2(direction.z, direction.x) / TAU + 0.5; v = acos(direction.y) / PI.

var revision := 0
var _texture: ImageTexture
var _texture_revision := -1
var _directions := PackedVector3Array()
var _direction_size := Vector2i.ZERO
var _occupancy_revision := -1
var _has_clouds := false
var _occupancy_bounds := PackedVector3Array()
var _occupancy_rows := PackedVector3Array()
var _occupancy_size := Vector2i.ZERO
var _occupancy_dirty_rows := Vector2i(0, 2147483647)

@export var image: Image:
	set(value):
		image = value
		_touch()

func _init() -> void:
	initialize()

func initialize(width: int = 512, height: int = 256) -> void:
	image = Image.create(maxi(width, 8), maxi(height, 4), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

func clear() -> void:
	_ensure_image()
	image.fill(Color(0, 0, 0, 0))
	_touch()

func snapshot() -> Image:
	_ensure_image()
	return image.duplicate() as Image

func restore(source: Image) -> void:
	if source == null or source.is_empty():
		return
	var restored := source.duplicate() as Image
	if restored.get_format() != Image.FORMAT_RGBA8:
		restored.convert(Image.FORMAT_RGBA8)
	image = restored

func get_texture() -> ImageTexture:
	_ensure_image()
	if _texture == null or _texture.get_width() != image.get_width() or _texture.get_height() != image.get_height():
		_texture = ImageTexture.create_from_image(image)
		_texture_revision = revision
	elif _texture_revision != revision:
		_texture.update(image)
		_texture_revision = revision
	return _texture

## Derived from CPU weather data once per revision, never from a GPU readback.
## Every nonzero weight counts, including faint storm backgrounds and feathers.
func has_clouds() -> bool:
	_ensure_occupancy()
	return _has_clouds

## Local unit-direction bounds: RGB minimum/maximum, then alpha minimum/maximum.
## An absent family's minimum exceeds its maximum. Consumers must expand these
## directions over their own radial shell without changing the integration grid.
func get_occupancy_bounds() -> PackedVector3Array:
	_ensure_occupancy()
	return _occupancy_bounds

func _ensure_occupancy() -> void:
	_ensure_image()
	if _occupancy_revision == revision:
		return
	_occupancy_revision = revision
	_has_clouds = false
	_occupancy_bounds = PackedVector3Array([Vector3.ONE, -Vector3.ONE, Vector3.ONE, -Vector3.ONE])
	var width := image.get_width()
	var height := image.get_height()
	if _occupancy_size != image.get_size():
		_occupancy_size = image.get_size()
		_occupancy_rows.resize(height * 4)
		_occupancy_dirty_rows = Vector2i(0, height - 1)
	var longitude_bounds: Array[Vector4] = []
	for x in range(width):
		# A linearly filtered texel contributes one full texel-center spacing
		# either side of its center. Unwrapped trig intervals also cover U=0/1.
		var first := (x - 0.5) / float(width) * TAU - PI
		var last := (x + 1.5) / float(width) * TAU - PI
		var cosine := _cosine_bounds(first, last)
		var sine := _cosine_bounds(first - PI * 0.5, last - PI * 0.5)
		longitude_bounds.append(Vector4(cosine.x, cosine.y, sine.x, sine.y))
	var bytes := image.get_data()
	var rgba8 := image.get_format() == Image.FORMAT_RGBA8
	# A brush changes only its latitude span. Retain all other row bounds so
	# live painting/erasing does not add a complete map scan on every stroke.
	for y in range(maxi(_occupancy_dirty_rows.x, 0), mini(_occupancy_dirty_rows.y + 1, height)):
		for family in [0, 2]:
			_occupancy_rows[y * 4 + family] = Vector3.ONE
			_occupancy_rows[y * 4 + family + 1] = -Vector3.ONE
		# The shader clamps V to polar texel centers, so an occupied polar row
		# continues all the way to its pole, not just to its texel footprint.
		var first := maxf(0.0, (y - 0.5) / float(height) * PI)
		var last := minf(PI, (y + 1.5) / float(height) * PI)
		var sine_min := minf(sin(first), sin(last))
		var sine_max := 1.0 if first <= PI * 0.5 and last >= PI * 0.5 else maxf(sin(first), sin(last))
		var y_min := cos(last)
		var y_max := cos(first)
		var regular_longitude := Vector4(1.0, -1.0, 1.0, -1.0)
		var storm_longitude := Vector4(1.0, -1.0, 1.0, -1.0)
		for x in range(width):
			var regular: bool
			var storm: bool
			if rgba8:
				var offset := (y * width + x) * 4
				regular = bytes[offset] != 0 or bytes[offset + 1] != 0 or bytes[offset + 2] != 0
				storm = bytes[offset + 3] != 0
			else:
				var weights := image.get_pixel(x, y)
				regular = weights.r != 0.0 or weights.g != 0.0 or weights.b != 0.0
				storm = weights.a != 0.0
			if not regular and not storm:
				continue
			var longitude := longitude_bounds[x]
			if regular:
				regular_longitude.x = minf(regular_longitude.x, longitude.x)
				regular_longitude.y = maxf(regular_longitude.y, longitude.y)
				regular_longitude.z = minf(regular_longitude.z, longitude.z)
				regular_longitude.w = maxf(regular_longitude.w, longitude.w)
			if storm:
				storm_longitude.x = minf(storm_longitude.x, longitude.x)
				storm_longitude.y = maxf(storm_longitude.y, longitude.y)
				storm_longitude.z = minf(storm_longitude.z, longitude.z)
				storm_longitude.w = maxf(storm_longitude.w, longitude.w)
		_include_row_bounds(regular_longitude, sine_min, sine_max, y_min, y_max, y * 4)
		_include_row_bounds(storm_longitude, sine_min, sine_max, y_min, y_max, y * 4 + 2)
	_occupancy_dirty_rows = Vector2i(height, -1)
	for y in range(height):
		for family in [0, 2]:
			var minimum := _occupancy_rows[y * 4 + family]
			var maximum := _occupancy_rows[y * 4 + family + 1]
			if minimum.x > maximum.x:
				continue
			_has_clouds = true
			_occupancy_bounds[family] = _occupancy_bounds[family].min(minimum)
			_occupancy_bounds[family + 1] = _occupancy_bounds[family + 1].max(maximum)
	# Round outward before sending single-precision vectors to the shader.
	for family in [0, 2]:
		if _occupancy_bounds[family].x <= _occupancy_bounds[family + 1].x:
			_occupancy_bounds[family] -= Vector3.ONE * 0.000001
			_occupancy_bounds[family + 1] += Vector3.ONE * 0.000001

func _include_row_bounds(longitude: Vector4, sine_min: float, sine_max: float, y_min: float, y_max: float, row_offset: int) -> void:
	if longitude.x > longitude.y:
		return
	# The latitude interval is identical for every texel in a row. Union their
	# longitude extrema first to avoid per-pixel Cartesian bound allocations.
	# sin(theta) is nonnegative, so these products contain all XYZ extrema.
	var minimum := Vector3(minf(longitude.x * sine_min, longitude.x * sine_max), y_min,
		minf(longitude.z * sine_min, longitude.z * sine_max))
	var maximum := Vector3(maxf(longitude.y * sine_min, longitude.y * sine_max), y_max,
		maxf(longitude.w * sine_min, longitude.w * sine_max))
	_occupancy_rows[row_offset] = minimum
	_occupancy_rows[row_offset + 1] = maximum

static func _cosine_bounds(first: float, last: float) -> Vector2:
	var minimum := minf(cos(first), cos(last))
	var maximum := maxf(cos(first), cos(last))
	if ceilf(first / TAU) * TAU <= last:
		maximum = 1.0
	if PI + ceilf((first - PI) / TAU) * TAU <= last:
		minimum = -1.0
	return Vector2(minimum, maximum)

## Apply an azimuthal equidistant footprint on the sphere. The tangent frame
## is shared by capture(), so saved formations retain their shape and rotation.
## Source-over coverage preserves existing clouds through holes in the tile;
## painting another category smoothly exchanges weights without dark seams.
func stamp(center: Vector3, angular_radius: float, tile: Image, strength: float, rotation: float = 0.0, erase: bool = false, feather: float = 0.5) -> bool:
	if not paint_layers.is_empty():
		return stamp_layer(center, angular_radius, tile, strength, rotation, erase, feather)
	if center.length_squared() < 0.000001 or strength <= 0.0 or angular_radius <= 0.0:
		return false
	if not erase and (tile == null or tile.is_empty()):
		return false
	_ensure_image()
	_ensure_directions()
	var normal := center.normalized()
	var radius := clampf(angular_radius, 0.0001, PI * 0.49)
	var frame := _tangent_frame(normal, rotation)
	var edge_start := 1.0 - clampf(feather, 0.01, 1.0)
	var minimum_dot := cos(radius)
	var latitude := acos(clampf(normal.y, -1.0, 1.0))
	var width := image.get_width()
	var height := image.get_height()
	var first_row := maxi(0, floori((latitude - radius) / PI * height - 0.5))
	var last_row := mini(height - 1, ceili((latitude + radius) / PI * height - 0.5))
	var changed_pixels := false
	for y in range(first_row, last_row + 1):
		for x in range(width):
			var direction := _directions[y * width + x]
			var alignment := direction.dot(normal)
			if alignment <= minimum_dot:
				continue
			var angle := acos(clampf(alignment, -1.0, 1.0))
			var distance := angle / radius
			var tangent := direction - normal * alignment
			if tangent.length_squared() > 0.00000001:
				tangent = tangent.normalized() * distance
			var uv := Vector2(tangent.dot(frame[0]), tangent.dot(frame[1])) * 0.5 + Vector2(0.5, 0.5)
			# Erasing uses the whole soft round footprint, including tile holes.
			var target := Color(0, 0, 0, 0) if erase else _sample_tile(tile, uv)
			var coverage := 1.0 if erase else target.r + target.g + target.b + target.a
			if coverage < 0.00001:
				continue
			var opacity := clampf(strength, 0.0, 1.0) * (1.0 - smoothstep(edge_start, 1.0, distance)) * minf(coverage, 1.0)
			var previous := image.get_pixel(x, y)
			var next := previous * (1.0 - opacity)
			if not erase:
				next += target * (opacity / coverage)
			next = _bounded_weights(next)
			if next != previous:
				image.set_pixel(x, y, next)
				changed_pixels = true
	if changed_pixels:
		_touch(first_row, last_row)
	return changed_pixels

## Capture a circular spherical region into a reusable RGBA tile. Blank corners
## and the brush's feathered placement prevent square boundaries when reused.
func capture(center: Vector3, angular_radius: float, size: int = 128, rotation: float = 0.0) -> Image:
	_ensure_image()
	var result := Image.create(maxi(size, 8), maxi(size, 8), false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	if center.length_squared() < 0.000001 or angular_radius <= 0.0:
		return result
	var normal := center.normalized()
	var frame := _tangent_frame(normal, rotation)
	var radius := clampf(angular_radius, 0.0001, PI * 0.49)
	for y in range(result.get_height()):
		for x in range(result.get_width()):
			var position := (Vector2(x + 0.5, y + 0.5) / float(result.get_width()) - Vector2(0.5, 0.5)) * 2.0
			var distance := position.length()
			if distance >= 1.0:
				continue
			var tangent: Vector3 = frame[0] * position.x + frame[1] * position.y
			var angle := radius * distance
			var direction := normal * cos(angle)
			if distance > 0.00001:
				direction += tangent / distance * sin(angle)
			result.set_pixel(x, y, _bounded_weights(sample_direction(direction)))
	return result

func sample_direction(direction: Vector3) -> Color:
	_ensure_image()
	if direction.length_squared() < 0.000001:
		return Color(0, 0, 0, 0)
	var normal := direction.normalized()
	var u := atan2(normal.z, normal.x) / TAU + 0.5
	var v := acos(clampf(normal.y, -1.0, 1.0)) / PI
	var fx := u * image.get_width() - 0.5
	var fy := clampf(v * image.get_height() - 0.5, 0.0, image.get_height() - 1.0)
	var x0 := floori(fx)
	var y0 := floori(fy)
	var x1 := posmod(x0 + 1, image.get_width())
	x0 = posmod(x0, image.get_width())
	var y1 := mini(y0 + 1, image.get_height() - 1)
	return image.get_pixel(x0, y0).lerp(image.get_pixel(x1, y0), fx - floorf(fx)).lerp(image.get_pixel(x0, y1).lerp(image.get_pixel(x1, y1), fx - floorf(fx)), fy - floorf(fy))

func _ensure_image() -> void:
	if image == null or image.is_empty():
		initialize()

func _ensure_directions() -> void:
	var size := image.get_size()
	if _direction_size == size:
		return
	_direction_size = size
	_directions.resize(size.x * size.y)
	for y in range(size.y):
		var theta := (y + 0.5) / float(size.y) * PI
		for x in range(size.x):
			var longitude := ((x + 0.5) / float(size.x) - 0.5) * TAU
			_directions[y * size.x + x] = Vector3(cos(longitude) * sin(theta), cos(theta), sin(longitude) * sin(theta))

func _touch(first_row: int = 0, last_row: int = 2147483647) -> void:
	_occupancy_dirty_rows.x = mini(_occupancy_dirty_rows.x, first_row)
	_occupancy_dirty_rows.y = maxi(_occupancy_dirty_rows.y, last_row)
	revision += 1
	emit_changed()

static func _tangent_frame(normal: Vector3, rotation: float) -> Array[Vector3]:
	var east := Vector3(-normal.z, 0.0, normal.x)
	if east.length_squared() < 0.000001:
		east = Vector3.RIGHT
	east = east.normalized()
	var south := normal.cross(east).normalized()
	return [east * cos(rotation) + south * sin(rotation), south * cos(rotation) - east * sin(rotation)]

static func _sample_tile(tile: Image, uv: Vector2) -> Color:
	var position := uv.clamp(Vector2.ZERO, Vector2.ONE) * Vector2(tile.get_width() - 1, tile.get_height() - 1)
	var x0 := floori(position.x)
	var y0 := floori(position.y)
	var x1 := mini(x0 + 1, tile.get_width() - 1)
	var y1 := mini(y0 + 1, tile.get_height() - 1)
	return tile.get_pixel(x0, y0).lerp(tile.get_pixel(x1, y0), position.x - x0).lerp(tile.get_pixel(x0, y1).lerp(tile.get_pixel(x1, y1), position.x - x0), position.y - y0)

## Quantize together rather than rounding channels independently past 1.0.
static func _bounded_weights(value: Color) -> Color:
	value = Color(maxf(value.r, 0.0), maxf(value.g, 0.0), maxf(value.b, 0.0), maxf(value.a, 0.0))
	var total := value.r + value.g + value.b + value.a
	if total > 1.0:
		value *= 1.0 / total
	var channels := PackedInt32Array([roundi(value.r * 255.0), roundi(value.g * 255.0), roundi(value.b * 255.0), roundi(value.a * 255.0)])
	var excess := channels[0] + channels[1] + channels[2] + channels[3] - 255
	if excess > 0:
		var largest := 0
		for index in range(1, 4):
			if channels[index] > channels[largest]:
				largest = index
		channels[largest] -= excess
	return Color(channels[0] / 255.0, channels[1] / 255.0, channels[2] / 255.0, channels[3] / 255.0)

# Layers are stored bottom-to-top. The image above remains the runtime composite
# so existing renderers and old planet resources keep the same weather contract.
@export var paint_layers: Array[Dictionary] = []
@export var active_layer: int = 0
var _paint_worker: Resource

func ensure_layers() -> void:
	if paint_layers.is_empty():
		paint_layers.append({"name": "Clouds 1", "visible": true, "locked": false, "opacity": 1.0, "image": snapshot()})
	active_layer = clampi(active_layer, 0, paint_layers.size() - 1)

func layer_editable() -> bool:
	ensure_layers()
	return paint_layers[active_layer].visible and not paint_layers[active_layer].locked

func add_paint_layer() -> void:
	ensure_layers()
	var blank := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 0))
	paint_layers.append({"name": "Clouds %d" % (paint_layers.size() + 1), "visible": true, "locked": false, "opacity": 1.0, "image": blank})
	active_layer = paint_layers.size() - 1
	rebuild_layers()

func stamp_layer(center: Vector3, radius: float, tile: Image, strength: float, rotation: float, erase: bool, feather: float) -> bool:
	if not layer_editable(): return false
	if _paint_worker == null: _paint_worker = get_script().new()
	_paint_worker.image = paint_layers[active_layer].image
	var modified: bool = _paint_worker.stamp(center, radius, tile, strength, rotation, erase, feather)
	if modified:
		var latitude := acos(clampf(center.normalized().y, -1.0, 1.0))
		var span := clampf(radius, 0.0001, PI * 0.49)
		rebuild_layers(maxi(0, floori((latitude - span) / PI * image.get_height() - 0.5)), mini(image.get_height() - 1, ceili((latitude + span) / PI * image.get_height() - 0.5)))
	return modified

func replace_active_layer(source: Image) -> bool:
	if not layer_editable(): return false
	var replacement := source.duplicate() as Image
	if replacement.get_size() != image.get_size():
		replacement.resize(image.get_width(), image.get_height())
	paint_layers[active_layer].image = replacement
	rebuild_layers()
	return true

func rebuild_layers(first_row: int = 0, last_row: int = -1) -> void:
	if paint_layers.is_empty(): return
	var result := image.duplicate() as Image
	if last_row < 0: last_row = image.get_height() - 1
	result.fill_rect(Rect2i(0, first_row, image.get_width(), last_row - first_row + 1), Color(0, 0, 0, 0))
	for layer in paint_layers:
		if not layer.visible: continue
		var source: Image = layer.image
		for y in range(first_row, last_row + 1):
			for x in range(result.get_width()):
				var top := source.get_pixel(x, y) * clampf(float(layer.get("opacity", 1.0)), 0.0, 1.0)
				var coverage := clampf(top.r + top.g + top.b + top.a, 0.0, 1.0)
				if coverage > 0.0:
					result.set_pixel(x, y, _bounded_weights(top + result.get_pixel(x, y) * (1.0 - coverage)))
	image = result

func layer_snapshot() -> Resource:
	var copy: Resource = get_script().new()
	copy.image = snapshot()
	copy.active_layer = active_layer
	for layer in paint_layers:
		var entry: Dictionary = layer.duplicate()
		entry.image = layer.image.duplicate()
		copy.paint_layers.append(entry)
	return copy
