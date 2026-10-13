extends RefCounted
## Atmospheric rendering quality. Presets change only shader sample budgets;
## flight, physics and saved planets never read them. See
## docs/RENDERING_PERFORMANCE.md for the measurements behind each value.

## Sunlight optical-depth table (atmosphere.gdshaderinc). Columns are the sun
## cosine from -1 to 1, rows the height from the ground to the top of the air.
## 256 x 64 half floats keep sunlight transmittance within 0.002 of the loop.
## One table per light sample count reproduces the loop's own quadrature, so
## each altitude band keeps its original appearance.
const SUN_DEPTH_SIZE := Vector2i(256, 64)

static var _sun_depth_tables := {}

## Rayleigh (R) and Mie (G) optical depth in km from each table point to the
## top of the air, at density scale 1, using the shader loop's quadrature
## with light_samples steps. Cached per body size and sample count (about
## 10 ms per sample to build); density changes do not need a rebuild.
static func sun_depth_table(body_radius_km: float, air_radius_km: float, light_samples: int = 6) -> ImageTexture:
	light_samples = clampi(light_samples, 1, 6)
	var key := Vector3(body_radius_km, air_radius_km, light_samples)
	if _sun_depth_tables.has(key):
		return _sun_depth_tables[key]
	var thickness := maxf(air_radius_km - body_radius_km, 0.001)
	var rayleigh_height := thickness * 0.32
	var mie_height := thickness * 0.09
	var edge_start := thickness * 0.7
	var data := PackedFloat32Array()
	data.resize(SUN_DEPTH_SIZE.x * SUN_DEPTH_SIZE.y * 2)
	var index := 0
	for row in range(SUN_DEPTH_SIZE.y):
		var radius := body_radius_km + thickness * float(row) / float(SUN_DEPTH_SIZE.y - 1)
		for column in range(SUN_DEPTH_SIZE.x):
			var cosine := -1.0 + 2.0 * float(column) / float(SUN_DEPTH_SIZE.x - 1)
			# Distance to the top of the air along the sun (sphere_interval().y).
			var b := radius * cosine
			var sun_length := maxf(-b + sqrt(maxf(b * b - radius * radius + air_radius_km * air_radius_km, 0.0)), 0.0)
			var rayleigh := 0.0
			var mie := 0.0
			for step in range(light_samples):
				var u := (float(step) + 0.5) / light_samples
				var along := u * u * sun_length
				var height := maxf(sqrt(radius * radius + along * along + 2.0 * radius * along * cosine) - body_radius_km, 0.0)
				var edge := 1.0 - smoothstep(edge_start, thickness, height)
				var weight := sun_length * float(2 * step + 1) / float(light_samples * light_samples) * edge
				rayleigh += exp(-height / rayleigh_height) * weight
				mie += exp(-height / mie_height) * weight
			data[index] = rayleigh
			data[index + 1] = mie
			index += 2
	var image := Image.create_from_data(SUN_DEPTH_SIZE.x, SUN_DEPTH_SIZE.y, false, Image.FORMAT_RGF, data.to_byte_array())
	image.convert(Image.FORMAT_RGH)
	var texture := ImageTexture.create_from_image(image)
	_sun_depth_tables[key] = texture
	return texture

## Point a material's atmosphere at the sunlight table for one body. Calls
## for any other body (a moon's foreground haze, a different planet) keep
## the light loop, since the table only matches the radii it was built for.
static func apply_sun_depth_table(material: ShaderMaterial, body_radius_km: float, air_radius_km: float, light_samples: int, enabled: bool = true) -> void:
	if not enabled or air_radius_km <= body_radius_km:
		material.set_shader_parameter("atmosphere_sun_depth_radii", Vector2.ZERO)
		return
	material.set_shader_parameter("atmosphere_sun_depth", sun_depth_table(body_radius_km, air_radius_km, light_samples))
	material.set_shader_parameter("atmosphere_sun_depth_samples", clampi(light_samples, 1, 6))
	material.set_shader_parameter("atmosphere_sun_depth_radii", Vector2(body_radius_km, air_radius_km))

## View-ray and sunlight sample limits for the observer in the lower half of
## the air, up to 0.8 body radii, and beyond.
## "ultra" keeps the original budgets. "reference" is the original rendering
## path (no sunlight table) kept for A/B validation; menus do not offer it.
const PRESETS := {
	"ultra": {"view": [16, 32, 64], "light": [2, 3, 6], "sun_table": true},
	"reference": {"view": [16, 32, 64], "light": [2, 3, 6], "sun_table": false},
}
const MENU := ["ultra"]
const DEFAULT := "ultra"

static func valid(preset: String) -> bool:
	return PRESETS.has(preset)

static func uses_sun_table(preset: String) -> bool:
	return bool(PRESETS.get(preset, PRESETS[DEFAULT]).sun_table)

## View and light sample limits for an observer altitude, all in km.
static func samples(preset: String, observer_altitude: float, air_height: float, body_radius: float) -> Vector2i:
	var settings: Dictionary = PRESETS.get(preset, PRESETS[DEFAULT])
	var band := 0 if observer_altitude < air_height * 0.5 else (1 if observer_altitude < body_radius * 0.8 else 2)
	return Vector2i(settings.view[band], settings.light[band])

## Build every table a preset can select for a body, so crossing an altitude
## band never builds one mid-flight.
static func prepare(preset: String, body_radius_km: float, air_radius_km: float) -> void:
	if not uses_sun_table(preset) or air_radius_km <= body_radius_km: return
	for count in PRESETS.get(preset, PRESETS[DEFAULT]).light:
		sun_depth_table(body_radius_km, air_radius_km, count)
