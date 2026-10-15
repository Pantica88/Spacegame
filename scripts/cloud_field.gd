extends RefCounted
## The cloud field on the CPU: a GDScript port of
## assets/shaders/cloud_field.gdshaderinc for the little light the GPU cannot
## hand back cheaply (sun and glow on a vessel), and the owner of the noise
## volumes both sides sample. Every function mirrors its shader namesake;
## tests/test_clouds.gd checks that they agree.
##
## Kilometres, in the cloud frame (planet-centred, rotating with the planet
## and the wind). The layer copies its uniforms into the public fields.

const SHAPE_KM := 14.0
const STORM_KM := 9.0
const DETAIL_KM := 1.8
const WEATHER_KM := 1100.0
const PATCH_KM := 61.0
const EXTINCTION := 26.0
const STORM_MIN := 0.16

## Same meaning as the shader uniforms of the same names.
var radii := Vector4(600.0, 601.8, 604.05, 613.5)
var params := Vector4(0.56, 1.0, 0.0, 0.0)
var evolution := Vector3.ZERO
var sun := Vector3.UP
var air := Vector4(600.0, 690.0, 1.0, 0.0)
## The painted weather map (cloud_weather_map.gd), or null for procedural.
var weather: Resource

static var _shape_bytes := PackedByteArray()
static var _detail_bytes := PackedByteArray()
static var _shape_size := 0
static var _detail_size := 0
static var _shape_texture: ImageTexture3D
static var _detail_texture: ImageTexture3D

## The noise volumes as textures, built once from the atlases in assets/clouds.
static func shape_texture() -> Texture3D:
	_load()
	return _shape_texture

static func detail_texture() -> Texture3D:
	_load()
	return _detail_texture

static func _load() -> void:
	if _shape_size > 0: return
	var shape: Image = load("res://assets/clouds/shape_noise.png")
	var detail: Image = load("res://assets/clouds/detail_noise.png")
	_shape_size = _volume(shape)
	_detail_size = _volume(detail)
	_shape_bytes = shape.get_data()
	_detail_bytes = detail.get_data()
	_shape_texture = _texture(shape, _shape_size)
	_detail_texture = _texture(detail, _detail_size)

## Side of the cube stored in an atlas of stacked slices.
static func _volume(atlas: Image) -> int:
	if atlas.get_format() != Image.FORMAT_RGBA8:
		atlas.convert(Image.FORMAT_RGBA8)
	assert(atlas.get_height() == atlas.get_width() * atlas.get_width(), "Cloud noise atlas must stack N slices of N x N")
	return atlas.get_width()

## The volume with its mip chain: each level halves every slice and
## averages pairs of slices from the level above.
static func _texture(atlas: Image, size: int) -> ImageTexture3D:
	var images: Array[Image] = []
	var slices: Array[Image] = []
	for z in size:
		slices.append(atlas.get_region(Rect2i(0, z * size, size, size)))
	var side := size
	while true:
		images.append_array(slices)
		if side == 1: break
		var half := side / 2
		var next: Array[Image] = []
		for z in half:
			var first := slices[z * 2].duplicate() as Image
			var second := slices[z * 2 + 1].duplicate() as Image
			first.resize(half, half, Image.INTERPOLATE_BILINEAR)
			second.resize(half, half, Image.INTERPOLATE_BILINEAR)
			var bytes := first.get_data()
			var other := second.get_data()
			for i in bytes.size():
				bytes[i] = (bytes[i] + other[i] + 1) >> 1
			next.append(Image.create_from_data(half, half, false, Image.FORMAT_RGBA8, bytes))
		slices = next
		side = half
	var texture := ImageTexture3D.new()
	texture.create(Image.FORMAT_RGBA8, size, size, size, true, images)
	return texture

## Linearly filtered, repeating lookup, as the GPU samples the volume.
static func _trilinear(bytes: PackedByteArray, size: int, uvw: Vector3) -> Color:
	var f := uvw * float(size) - Vector3(0.5, 0.5, 0.5)
	var fx := floorf(f.x)
	var fy := floorf(f.y)
	var fz := floorf(f.z)
	var tx := f.x - fx
	var ty := f.y - fy
	var tz := f.z - fz
	var x0 := posmod(int(fx), size)
	var y0 := posmod(int(fy), size)
	var z0 := posmod(int(fz), size)
	var x1 := (x0 + 1) % size
	var y1 := (y0 + 1) % size
	var z1 := (z0 + 1) % size
	var result := Color(0, 0, 0, 0)
	for corner in 8:
		var x := x1 if corner & 1 else x0
		var y := y1 if corner & 2 else y0
		var z := z1 if corner & 4 else z0
		var w := (tx if corner & 1 else 1.0 - tx) * (ty if corner & 2 else 1.0 - ty) * (tz if corner & 4 else 1.0 - tz)
		if w == 0.0: continue
		var i := ((z * size + y) * size + x) * 4
		result.r += bytes[i] * w
		result.g += bytes[i + 1] * w
		result.b += bytes[i + 2] * w
		result.a += bytes[i + 3] * w
	return result / 255.0

static func shape(uvw: Vector3) -> Color:
	_load()
	return _trilinear(_shape_bytes, _shape_size, uvw)

static func detail(uvw: Vector3) -> Color:
	_load()
	return _trilinear(_detail_bytes, _detail_size, uvw)

## Near and far crossings of a planet-centred sphere; (1, -1) for a miss.
static func sphere_hits(origin: Vector3, ray: Vector3, radius: float) -> Vector2:
	var b := origin.dot(ray)
	var h := b * b - (origin.length_squared() - radius * radius)
	if h < 0.0: return Vector2(1.0, -1.0)
	h = sqrt(h)
	return Vector2(-b - h, -b + h)

static func warp(p: Vector3) -> Vector3:
	return Vector3(sin(p.y * 0.083 + p.z * 0.047), sin(p.z * 0.071 + p.x * 0.059), sin(p.x * 0.067 + p.y * 0.091)) * 3.5

func weather_at(p: Vector3) -> Color:
	var direction := p.normalized()
	if params.z > 0.5 and weather != null:
		var patches := shape(direction * (radii.y / PATCH_KM) + Vector3(0.37, 0.11, 0.73)).b
		return weather.sample_direction(direction) * lerpf(0.78, 1.2, patches)
	var broad := shape(direction * (radii.y / WEATHER_KM) + evolution * 0.002)
	var amount := smoothstep(0.80 - params.x * 0.75, 1.05 - params.x * 0.75, broad.b)
	var layered := smoothstep(0.40, 0.62, broad.a)
	return Color(amount * (1.0 - layered) * 0.85, amount * layered * 0.8, 0.0, 0.0)

## Density before erosion, lighting height, erosion strength, lumps. The
## CPU only looks close by, at the full-resolution volume (mip 0).
func coarse(p: Vector3, r: float, w: Color) -> Vector4:
	var base := radii.y
	var hs := (r - base) / (radii.w - base)
	if hs <= 0.0 or hs >= 1.0: return Vector4.ZERO
	var hl := (r - base) / (radii.z - base)
	var low := hl < 1.0 and w.r + w.g + w.b > 0.0
	var storm := w.a > STORM_MIN
	if not low and not storm: return Vector4.ZERO
	var q := p - (p / r) * ((r - base) * 0.45)
	var n := shape((q + warp(q) + evolution) / SHAPE_KM)
	var density := 0.0
	var lit := 0.0
	var erode := 0.0
	if low:
		if w.r > 0.0:
			var cover := pow(minf(w.r, 1.0), 0.7) * 0.66
			var excess := clampf((n.r - 1.0 + cover) / maxf(cover, 0.05), 0.0, 1.0)
			var top := lerpf(0.4, 1.0, clampf(n.b * 1.6 - 0.3, 0.0, 1.0)) * lerpf(0.7, 1.0, w.r)
			var crown := top * sqrt(excess)
			var d := smoothstep(0.0, 0.3, excess) * smoothstep(0.0, 0.05, hl) * (1.0 - smoothstep(crown * 0.6, crown, hl))
			density += d
			lit += d * clampf(hl / maxf(crown, 0.05), 0.0, 1.0)
			erode += d * 0.8
		if w.g > 0.0:
			var top := (0.36 + 0.16 * n.b) * lerpf(0.6, 1.0, n.g)
			var profile := smoothstep(0.02, 0.1, hl) * (1.0 - smoothstep(top - 0.12, top, hl))
			var cover := minf(w.g, 1.0) * 0.72
			var cells := lerpf(n.r, n.g, 0.6)
			var d := smoothstep(1.0 - cover, 1.24 - cover, cells) * profile
			density += d
			lit += d * clampf(hl / top, 0.0, 1.0)
			erode += d * 0.65
		if w.b > 0.0:
			var top := 0.3 + 0.1 * n.b
			var profile := smoothstep(0.0, 0.08, hl) * (1.0 - smoothstep(top - 0.14, top, hl))
			var d := clampf(w.b * 1.45 - 0.12 + (n.r - 0.55) * 0.5, 0.0, 1.0) * profile
			density += d
			lit += d * clampf(hl / top, 0.0, 1.0)
			erode += d * 0.12
	if storm:
		var b := shape((p + warp(p) + evolution) / STORM_KM)
		var contour := clampf((b.r - 0.5) * 0.22 + (b.g - 0.5) * 0.12, -0.08, 0.08)
		var cap_low := lerpf(0.70, 0.58, w.a)
		var cap_high := lerpf(0.80, 0.97, w.a) + (n.b - 0.5) * 0.04
		var cap := smoothstep(cap_low - 0.05, cap_low + 0.05, hs)
		var need := lerpf(0.60, 0.22, cap) - contour
		var d := smoothstep(need - 0.05, need + 0.05, w.a) * smoothstep(STORM_MIN, STORM_MIN + 0.08, w.a) \
			* smoothstep(0.0, 0.02, hs) * (1.0 - smoothstep(cap_high - 0.08, cap_high, hs)) \
			* (0.75 + 0.45 * b.g)
		density += d
		lit += d * clampf(hs / cap_high, 0.0, 1.0)
		erode += d * 0.5
	if density <= 0.0: return Vector4.ZERO
	return Vector4(minf(density, 1.0), lit / density, erode / density, n.g)

## Density and lighting height after erosion (detail 0 skips the erosion).
func density_at(p: Vector3, w: Color, detail_weight: float) -> Vector2:
	var c := coarse(p, p.length(), w)
	if c.x <= 0.0 or detail_weight <= 0.0: return Vector2(c.x, c.y)
	var fine := detail((p + evolution * 2.5) / DETAIL_KM)
	var finer := detail((p + evolution * 4.0) / (DETAIL_KM * 0.33)).g
	var fbm := fine.r * 0.5 + fine.g * 0.3 + finer * 0.2
	var billow := lerpf(1.0 - fbm, fbm, clampf(c.y * 3.0, 0.0, 1.0))
	var e := c.z * detail_weight * billow
	return Vector2(clampf((c.x - e) / maxf(1.0 - e, 0.05), 0.0, 1.0), c.y)

static func hg(cosine: float, g: float) -> float:
	return (1.0 - g * g) / pow(maxf(1.0 + g * g - 2.0 * g * cosine, 1e-4), 1.5)

func scatter(sun_depth: float, cosine: float, sunlight: Vector3, ambient: Vector3, light_height: float, density: float) -> Vector3:
	var tau := sun_depth * EXTINCTION * params.y
	var direct := 0.0
	var a := 1.0
	var b := 1.0
	var g := 1.0
	for i in 3:
		var phase := lerpf(hg(cosine, -0.2 * g), hg(cosine, 0.7 * g), 0.55)
		direct += a * exp(-tau * b) * phase
		a *= 0.45
		b *= 0.45
		g *= 0.5
	var powder := lerpf(1.0, 1.0 - exp(-density * 8.0), 0.5 * (1.0 - cosine) * 0.5)
	return sunlight * direct * 0.42 * powder + ambient * lerpf(0.35, 1.0, light_height)

func sunlight_at(p: Vector3) -> Vector3:
	var r := p.length()
	var ground := air.x
	var horizon := -sqrt(maxf(0.0, 1.0 - ground * ground / (r * r)))
	var elevation := (p / r).dot(sun) - horizon
	var daylight := smoothstep(-0.012, 0.025, elevation)
	if daylight <= 0.0: return Vector3.ZERO
	var air_height := maxf(air.y - ground, 0.001)
	var path := maxf(sphere_hits(p, sun, air.y).y, 0.0)
	var depth := Vector2.ZERO
	for i in 6:
		var u := (float(i) + 0.5) / 6.0
		var q := p + sun * (u * u * path)
		var h := maxf(q.length() - ground, 0.0)
		depth += Vector2(exp(-h / (air_height * 0.32)), exp(-h / (air_height * 0.09))) * path * (2.0 * float(i) + 1.0) / 36.0
	depth -= Vector2(0.32, 0.09) * air_height
	var tau := (Vector3(0.014, 0.035, 0.085) * depth.x + Vector3(0.009, 0.009, 0.009) * depth.y) * air.z
	tau = tau.max(Vector3.ZERO) * 0.3
	var tint := Vector3.ONE.lerp(Vector3(1.3, 0.62, 0.36), 1.0 - smoothstep(0.0, 0.25, elevation))
	return Vector3(exp(-tau.x), exp(-tau.y), exp(-tau.z)) * tint * daylight

func ambient_at(p: Vector3, sunlight: Vector3) -> Vector3:
	var elevation := p.normalized().dot(sun)
	var sky := Vector3(0.62, 0.42, 0.36).lerp(Vector3(0.36, 0.48, 0.70), smoothstep(-0.02, 0.3, elevation))
	var day := smoothstep(-0.18, 0.2, elevation)
	return Vector3(0.004, 0.006, 0.011) + sky * day * 0.34 * lerpf(0.55, 1.0, sunlight.dot(Vector3.ONE) / 3.0)

## Fraction of direct sunlight reaching p through the cloud: the coarse
## density on a fixed grid along the sun ray, up to 8 km of cloud shell.
func sun_transmittance(p: Vector3) -> float:
	var top := radii.w if params.w > 0.5 else radii.z
	var exit := sphere_hits(p, sun, top).y
	if exit <= 0.0: return 1.0
	var start := 0.0
	var r := p.length()
	if r < radii.y:
		start = sphere_hits(p, sun, radii.y).y
	elif r > top:
		start = maxf(sphere_hits(p, sun, top).x, 0.0)
	var end := minf(exit, start + 8.0)
	if end <= start: return 1.0
	const STEP := 0.4
	var optical := 0.0
	var index := floori(start / STEP)
	while float(index) * STEP < end:
		var a := maxf(float(index) * STEP, start)
		var b := minf(float(index + 1) * STEP, end)
		var q := p + sun * ((a + b) * 0.5)
		optical += coarse(q, q.length(), weather_at(q)).x * (b - a)
		if optical * EXTINCTION * params.y > 6.0: return 0.0
		index += 1
	return exp(-optical * EXTINCTION * params.y)

## Light of the cloud along one view ray from p, up to range_km: unmultiplied
## RGB and opacity. The cloud above each sample stands in for its sun shadow.
func trace(p: Vector3, ray: Vector3, range_km: float, samples: int) -> Color:
	var top := radii.w if params.w > 0.5 else radii.z
	var exit := sphere_hits(p, ray, top).y
	if exit <= 0.0: return Color(0, 0, 0, 0)
	var start := 0.0
	var r := p.length()
	if r < radii.y:
		start = sphere_hits(p, ray, radii.y).y
	elif r > top:
		start = maxf(sphere_hits(p, ray, top).x, 0.0)
	var end := minf(exit, start + range_km)
	var ground := sphere_hits(p, ray, radii.x)
	if ground.y > ground.x and ground.x > 0.0: end = minf(end, ground.x)
	if end <= start: return Color(0, 0, 0, 0)
	var step := (end - start) / float(samples)
	var cosine := ray.dot(sun)
	var color := Vector3.ZERO
	var remaining := 1.0
	var sunlight := Vector3.ZERO
	var ambient := Vector3.ZERO
	var lit := false
	for i in samples:
		var q := p + ray * (start + (float(i) + 0.5) * step)
		var c := coarse(q, q.length(), weather_at(q))
		if c.x <= 0.0: continue
		if not lit:
			sunlight = sunlight_at(q)
			ambient = ambient_at(q, sunlight)
			lit = true
		var opacity := 1.0 - exp(-c.x * EXTINCTION * params.y * step)
		color += scatter((1.0 - c.y) * c.x * 1.2, cosine, sunlight, ambient, c.y, c.x) * remaining * opacity
		remaining *= 1.0 - opacity
		if remaining < 0.02: break
	var alpha := 1.0 - remaining
	if alpha < 0.004: return Color(0, 0, 0, 0)
	return Color(color.x / alpha, color.y / alpha, color.z / alpha, alpha)
