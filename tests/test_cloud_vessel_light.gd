extends SceneTree
## Vessel sunlight is shaded by the cloud volume between the vessel and sun.
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
	var clouds: MeshInstance3D = CloudLayer.new()
	planet.add_child(clouds)
	WorkerThreadPool.wait_for_task_completion(CloudLayer._noise_task)
	check(CloudLayer._noise_ready(), "CPU noise mirror is built")
	_test_procedural(clouds)
	_test_authored(clouds)
	_test_glow(clouds)
	_test_time_lapse(clouds, planet)
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS: vessel sunlight is shaded below and inside cloud, unshaded above it, in clear sky, and without an atmosphere; surrounding cloud glows grey at noon and red at sunset; both stay steady as time warp spins the planet and sweeps the sun.")
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _definition() -> Resource:
	var definition: Resource = Definition.new()
	definition.cloud_wind_speed = 0.0
	definition.cloud_evolution = 0.0
	return definition

func _point(direction: Vector3, altitude_m: float, definition: Resource) -> Vector3:
	return direction.normalized() * (float(definition.radius) + altitude_m) * 0.001

func _test_procedural(clouds: MeshInstance3D) -> void:
	var definition := _definition()
	definition.cloud_coverage = 1.0
	definition.cloud_density = 2.5
	var darkest := 1.0
	var above := 0.0
	for i in range(64):
		var direction := Vector3(cos(i * 0.37), 1.0, sin(i * 0.53))
		clouds.update_weather(definition, Vector3.ZERO, direction.normalized(), true)
		darkest = minf(darkest, clouds.sun_transmittance(_point(direction, 3000.0, definition)))
		above = maxf(above, 1.0 - clouds.sun_transmittance(_point(direction, 9000.0, definition)))
	check(darkest < 0.3, "Overcast procedural deck darkens a vessel below it (darkest %.3f)" % darkest)
	check(above == 0.0, "A vessel above the deck with a high sun is fully lit")
	definition.atmosphere_visual_density = 0.0
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	check(clouds.sun_transmittance(_point(Vector3.UP, 3000.0, definition)) == 1.0, "Airless bodies cast no cloud shade")

func _test_authored(clouds: MeshInstance3D) -> void:
	var definition := _definition()
	var weather: Resource = Weather.new()
	weather.initialize(256, 128)
	var overcast := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	overcast.fill(Color(0, 0, 1, 0))
	weather.stamp(Vector3.UP, 0.3, overcast, 1.0)
	definition.cloud_weather = weather
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	var under: float = clouds.sun_transmittance(_point(Vector3.UP, 3000.0, definition))
	check(under < 0.8, "Painted overcast shades a vessel beneath it (%.3f)" % under)
	var inside: float = clouds.sun_transmittance(_point(Vector3.UP, 5500.0, definition))
	check(inside < 1.0 and inside >= under, "A vessel inside the deck is partly shaded (%.3f)" % inside)
	var storm := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	storm.fill(Color(0, 0, 0, 1))
	weather.stamp(Vector3.UP, 0.3, storm, 1.0)
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	var dark: float = clouds.sun_transmittance(_point(Vector3.UP, 3000.0, definition))
	check(dark < 0.1 and dark < under, "A storm leaves a vessel beneath it in deep shade (%.3f)" % dark)
	clouds.update_weather(definition, Vector3.ZERO, Vector3.DOWN, true)
	var clear: float = clouds.sun_transmittance(_point(Vector3.DOWN, 3000.0, definition))
	check(clear == 1.0, "Clear painted sky leaves the vessel fully lit (%.3f)" % clear)
	definition.cloud_weather = Weather.new()
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	check(clouds.sun_transmittance(_point(Vector3.UP, 3000.0, definition)) == 1.0, "Empty painted weather casts no shade")

func _test_glow(clouds: MeshInstance3D) -> void:
	var definition := _definition()
	definition.cloud_coverage = 1.0
	definition.cloud_density = 2.5
	var vessel := _point(Vector3.UP, 3000.0, definition)
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	var noon: Color = clouds.cloud_glow(vessel, true)
	check(noon.a > 0.3, "Overcast deck fills much of the vessel's surroundings (%.3f)" % noon.a)
	check(noon.b >= noon.r * 0.6 and noon.r > 0.05, "Noon overcast glows neutral grey (%s)" % noon)
	var sunset := Vector3(0.0, 0.05, 1.0).normalized()
	clouds.update_weather(definition, Vector3.ZERO, sunset, true)
	var smothered: Color = clouds.cloud_glow(vessel, true)
	check(smothered.r < noon.r * 0.5, "A thick deck the low sun cannot reach stays dim beneath (%s)" % smothered)
	var broken := _definition()
	clouds.update_weather(broken, Vector3.ZERO, sunset, true)
	var red: Color = clouds.cloud_glow(vessel, true)
	check(red.a > 0.2 and red.r > red.b * 1.5, "Broken sunset cloud glows red onto the vessel (%s)" % red)
	var above: Color = clouds.cloud_glow(_point(Vector3.UP, 9000.0, broken), true)
	check(above.a > 0.0 and above.r > above.b * 1.5, "Sunset cloud tops glow red up onto a vessel above them (%s)" % above)
	definition.atmosphere_visual_density = 0.0
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	check(clouds.cloud_glow(vessel, true).a == 0.0, "No cloud means no cloud glow")
	# Round-robin refresh still converges on the full estimate.
	definition.atmosphere_visual_density = 1.0
	clouds.update_weather(definition, Vector3.ZERO, Vector3.UP, true)
	var stepped := Color()
	for i in range(clouds.GLOW_DIRECTIONS.size()):
		stepped = clouds.cloud_glow(vessel)
	check(stepped.is_equal_approx(noon), "Per-frame refresh matches the full glow (%s vs %s)" % [stepped, noon])

## Time warp spins the planet under a sweeping sun. Lighting must follow the
## clouds with the planet and change smoothly with the sun, or the launch pad
## flickers.
func _test_time_lapse(clouds: MeshInstance3D, planet: Node3D) -> void:
	var definition := _definition()
	var vessel_local := _point(Vector3(0.3, 1.0, 0.2), 20.0, definition)
	var sun_local := Vector3(0.4, 0.6, 0.5).normalized()
	planet.basis = Basis.IDENTITY
	clouds.update_weather(definition, Vector3.ZERO, sun_local, true)
	var rest: Color = clouds.cloud_glow(vessel_local, true)
	var rest_sun: float = clouds.sun_transmittance(vessel_local)
	planet.basis = Basis(Vector3(0.2, 1.0, -0.1).normalized(), 1.7)
	clouds.update_weather(definition, Vector3.ZERO, planet.basis * sun_local, true)
	var spun: Color = clouds.cloud_glow(planet.basis * vessel_local, true)
	var spun_sun: float = clouds.sun_transmittance(planet.basis * vessel_local)
	check(spun.is_equal_approx(rest) or (spun - rest).v < 0.002, "Glow follows the clouds as the planet spins (%s vs %s)" % [spun, rest])
	check(absf(spun_sun - rest_sun) < 0.002, "Sun shading follows the clouds as the planet spins")
	planet.basis = Basis.IDENTITY
	definition.cloud_coverage = 0.8
	var previous := -1.0
	var largest := 0.0
	for i in range(400):
		# 0.05° of sun travel per frame: 1000x warp on a six-hour day.
		var angle := deg_to_rad(10.0 + i * 0.05)
		clouds.update_weather(definition, Vector3.ZERO, Vector3(0.0, sin(angle), cos(angle)), true)
		var light: float = clouds.sun_transmittance(_point(Vector3.UP, 1000.0, definition))
		if previous >= 0.0:
			largest = maxf(largest, absf(light - previous))
		previous = light
	check(largest < 0.06, "Sun shading changes smoothly as the sun sweeps (largest step %.3f)" % largest)
