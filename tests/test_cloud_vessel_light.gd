extends SceneTree
## Vessel light from the clouds (cloud_layer.gd sun_transmittance() and
## cloud_glow(), evaluated on the CPU by cloud_field.gd).
## Run: tools/run.sh --headless --script res://tests/test_cloud_vessel_light.gd

const Weather = preload("res://scripts/cloud_weather_map.gd")
const Definition = preload("res://scripts/planet_definition.gd")
const CloudLayer = preload("res://scripts/cloud_layer.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var planet := Node3D.new()
	root.add_child(planet)
	var clouds: Node3D = CloudLayer.new()
	planet.add_child(clouds)
	_test_overcast(clouds)
	_test_storm_and_clear(clouds)
	_test_glow(clouds)
	_test_spin_and_sweep(clouds, planet)
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS: vessel sunlight is shaded under and inside painted cloud, deeply under a storm, never above the cloud, in clear sky or without air; surrounding cloud glows neutral at noon and warm at sunset; both follow the clouds as the planet spins and change smoothly as the sun sweeps.")
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _definition() -> Resource:
	var definition: Resource = Definition.new()
	definition.cloud_wind_speed = 0.0
	definition.cloud_evolution = 0.0
	return definition

## Weather painted with one formation mixture over a cap around +Y.
func _painted(weights: Color, radius: float = 0.4) -> Resource:
	var weather: Resource = Weather.new()
	weather.initialize(256, 128)
	var tile := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	tile.fill(weights)
	weather.stamp(Vector3.UP, radius, tile, 1.0, 0.0, false, 0.2)
	return weather

func _point(direction: Vector3, altitude_m: float, definition: Resource) -> Vector3:
	return direction.normalized() * (float(definition.radius) + altitude_m) * 0.001

func _test_overcast(clouds: Node3D) -> void:
	var definition := _definition()
	definition.cloud_weather = _painted(Color(0, 0, 1, 0))
	var heights: Vector3 = CloudLayer.heights(definition)
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	var under: float = clouds.sun_transmittance(_point(Vector3.UP, heights.x * 0.5, definition))
	check(under < 0.2, "Painted overcast shades a vessel beneath it (%.3f)" % under)
	# Climbing through the deck, the shade lifts steadily to full sun.
	var previous := under
	var steady := true
	var partial := false
	for i in range(41):
		var light: float = clouds.sun_transmittance(_point(Vector3.UP, heights.x + (heights.y - heights.x) * 0.5 * i / 40.0, definition))
		steady = steady and light >= previous - 0.02
		partial = partial or (light > 0.05 and light < 0.95)
		previous = light
	check(steady and partial and previous == 1.0, "Shade lifts steadily from the deck's base to its top (ends at %.3f)" % previous)
	var above: float = clouds.sun_transmittance(_point(Vector3.UP, heights.y + 500.0, definition))
	check(above == 1.0, "A vessel above the deck with a high sun is fully lit (%.3f)" % above)
	definition.atmosphere_visual_density = 0.0
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	check(clouds.sun_transmittance(_point(Vector3.UP, heights.x * 0.5, definition)) == 1.0, "Airless bodies cast no cloud shade")
	definition.atmosphere_visual_density = 1.0
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, false)
	check(clouds.sun_transmittance(_point(Vector3.UP, heights.x * 0.5, definition)) == 1.0, "Hidden clouds cast no shade")

func _test_storm_and_clear(clouds: Node3D) -> void:
	var definition := _definition()
	var heights: Vector3 = CloudLayer.heights(definition)
	definition.cloud_weather = _painted(Color(0, 0, 0, 1))
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	var dark: float = clouds.sun_transmittance(_point(Vector3.UP, heights.x * 0.5, definition))
	check(dark < 0.02, "A storm leaves a vessel beneath it in deep shade (%.3f)" % dark)
	var top: float = clouds.sun_transmittance(_point(Vector3.UP, heights.z + 500.0, definition))
	check(top == 1.0, "Above the storm tops the sun is unshaded (%.3f)" % top)
	clouds.update_weather(definition, Vector3.ZERO, Vector3.DOWN, true)
	var clear: float = clouds.sun_transmittance(_point(Vector3.DOWN, heights.x * 0.5, definition))
	check(clear == 1.0, "Unpainted sky leaves the vessel fully lit (%.3f)" % clear)
	definition.cloud_weather = Weather.new()
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	check(clouds.sun_transmittance(_point(Vector3.UP, heights.x * 0.5, definition)) == 1.0, "Empty painted weather casts no shade")

func _test_glow(clouds: Node3D) -> void:
	var definition := _definition()
	definition.cloud_weather = _painted(Color(0, 0, 1, 0))
	var heights: Vector3 = CloudLayer.heights(definition)
	var vessel := _point(Vector3.UP, heights.x * 0.5, definition)
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	var noon: Color = clouds.cloud_glow(vessel, true)
	check(noon.a > 0.3, "An overcast deck fills much of the vessel's surroundings (%.3f)" % noon.a)
	check(noon.b >= noon.r * 0.75 and noon.r > 0.05, "Noon overcast glows neutral (%s)" % noon)
	var sunset := Vector3(0.0, 0.06, 1.0).normalized()
	definition.cloud_weather = _painted(Color(0.6, 0, 0, 0))
	clouds.update_weather(definition, Vector3.ZERO, sunset, true)
	var warm: Color = clouds.cloud_glow(_point(Vector3.UP, heights.y + 800.0, definition), true)
	check(warm.a > 0.0 and warm.r > warm.b * 1.3, "Sunset cloud tops glow warm onto a vessel above them (%s)" % warm)
	definition.atmosphere_visual_density = 0.0
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	check(clouds.cloud_glow(vessel, true).a == 0.0, "No cloud means no cloud glow")
	# Refreshing one view per call converges on the full estimate.
	definition.atmosphere_visual_density = 1.0
	definition.cloud_weather = _painted(Color(0, 0, 1, 0))
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	var stepped := Color()
	for i in range(CloudLayer.GLOW_DIRECTIONS.size()):
		stepped = clouds.cloud_glow(vessel)
	check(stepped.is_equal_approx(noon), "Per-frame refresh matches the full glow (%s vs %s)" % [stepped, noon])

## Time warp spins the planet under a sweeping sun. Lighting must follow the
## clouds with the planet and change smoothly with the sun.
func _test_spin_and_sweep(clouds: Node3D, planet: Node3D) -> void:
	var definition := _definition()
	# A closed deck with some cumulus, so the swept sun must cross cloud.
	definition.cloud_weather = _painted(Color(0.1, 0.4, 0.5, 0), 0.6)
	var heights: Vector3 = CloudLayer.heights(definition)
	var vessel := _point(Vector3(0.2, 1.0, 0.1), heights.x * 0.6, definition)
	var sun := Vector3(0.4, 0.6, 0.5).normalized()
	planet.basis = Basis.IDENTITY
	clouds.update_weather(definition, Vector3.ZERO, sun, true)
	var rest: Color = clouds.cloud_glow(vessel, true)
	var rest_sun: float = clouds.sun_transmittance(vessel)
	planet.basis = Basis(Vector3(0.2, 1.0, -0.1).normalized(), 1.7)
	clouds.update_weather(definition, Vector3.ZERO, planet.basis * sun, true)
	var spun: Color = clouds.cloud_glow(planet.basis * vessel, true)
	var spun_sun: float = clouds.sun_transmittance(planet.basis * vessel)
	check(absf(spun.r - rest.r) + absf(spun.g - rest.g) + absf(spun.b - rest.b) + absf(spun.a - rest.a) < 0.01, "Glow follows the clouds as the planet spins (%s vs %s)" % [spun, rest])
	check(absf(spun_sun - rest_sun) < 0.002, "Sun shading follows the clouds as the planet spins (%.4f vs %.4f)" % [spun_sun, rest_sun])
	planet.basis = Basis.IDENTITY
	var previous := -1.0
	var largest := 0.0
	var lowest := 1.0
	for i in range(400):
		# 0.05 degrees of sun travel per frame: 1000x warp on a six-hour day.
		var angle := deg_to_rad(10.0 + i * 0.05)
		clouds.update_weather(definition, Vector3.ZERO, Vector3(0.0, sin(angle), cos(angle)), true)
		var light: float = clouds.sun_transmittance(_point(Vector3.UP, heights.x * 0.6, definition))
		lowest = minf(lowest, light)
		if previous >= 0.0:
			largest = maxf(largest, absf(light - previous))
		previous = light
	check(lowest < 0.9, "The swept sun passes behind cloud at least once (lowest %.3f)" % lowest)
	check(largest < 0.06, "Sun shading changes smoothly as the sun sweeps (largest step %.3f)" % largest)
