extends SceneTree
## Graphical test of production cloud traversal and its measured result.
## ./tools/run.sh --script res://tests/test_cloud_volume_result.gd
## The only replaced function is density: intervals, sampling, extinction,
## accumulation and the compatibility wrapper all execute production code.
const VOLUME_PATH := "res://assets/shaders/clouds_volume.gdshaderinc"
const CHECK_NAMES := ["finite transmittance", "finite accumulated light", "extinction weight",
	"depth support", "legacy depth agreement", "optical path", "measured depth", "compatibility output"]
var failures: Array[String] = []

const HEADER := """shader_type canvas_item;
render_mode unshaded, blend_disabled;
#define CLOUD_MEASURE_DEPTH
uniform int fixture_profile = 0;
uniform float fixture_density = 0.15;
uniform vec3 fixture_ray = vec3(0.0, 1.0, 0.0);
uniform float fixture_clip = 1000.0;
uniform int fixture_kind = 1;
uniform float expected_path_km = 10.0;
uniform vec2 expected_depth = vec2(0.0);
uniform vec2 depth_tolerance = vec2(0.02, 0.05);
"""

const DENSITY := """vec3 sample_formation(vec3 point, float height, float detail_weight, bool fine) {
	bool filled = fixture_profile == 0 || (fixture_profile == 1
		&& (height < 0.14 || (height >= 0.76 && height < 0.86)));
	float density = filled && height >= 0.0 && height < 1.0 ? fixture_density : 0.0;
	return vec3(density, clamp(height, 0.0, 1.0), height >= 0.14 ? 1.0 : 0.0);
}
"""

const DIAGNOSTIC := """
void fragment() {
	CloudIntegral raw = integrate_cloud_volume(fixture_ray, fixture_clip, vec2(0.5));
	float opacity = 1.0 - raw.transmittance;
	float mean_km = cloud_depth_mean_km(raw.depth);
	float variance_km2 = cloud_depth_variance_km2(raw.depth);
	bool has_depth = cloud_depth_valid(raw.depth);
	bool checks[8];
	checks[0] = raw.transmittance >= 0.0 && raw.transmittance <= 1.0;
	checks[1] = all(greaterThanEqual(raw.light, vec3(0.0))) && all(lessThan(raw.light, vec3(100.0)));
	checks[2] = abs(raw.depth.weight - opacity) < 0.00005;
	checks[3] = has_depth
		? raw.depth.origin_km >= 0.0 && mean_km >= raw.depth.origin_km - 0.001
			&& mean_km <= raw.depth.last_distance_km + 0.001 && variance_km2 >= 0.0
		: mean_km == 0.0 && variance_km2 == 0.0 && raw.depth.weight == 0.0;
	checks[4] = has_depth
		? abs(mean_km * raw.depth.weight - raw.weighted_distance_km) < max(0.0001, raw.weighted_distance_km * 0.00001)
		: raw.weighted_distance_km == 0.0;
	checks[5] = false;
	checks[6] = false;
	if (fixture_kind == 0 || fixture_kind == 4) {
		checks[5] = opacity == 0.0 && !has_depth && raw.light == vec3(0.0);
		checks[6] = fixture_kind == 0 ? !raw.traversed && raw.density_samples == 0.0
			: raw.traversed && raw.density_samples > 0.0;
	} else if (fixture_kind == 1) {
		checks[5] = abs(raw.transmittance - exp(-fixture_density * 1.2 * expected_path_km)) < 0.00003;
		checks[6] = raw.traversed && has_depth && raw.density_samples > 0.0
			&& abs(mean_km - expected_depth.x) < depth_tolerance.x
			&& abs(variance_km2 - expected_depth.y) < depth_tolerance.y;
	} else if (fixture_kind == 2) {
		checks[5] = raw.transmittance < 0.025 && raw.transmittance > 0.005;
		checks[6] = raw.traversed && has_depth && raw.depth.origin_km >= 3.0
			&& raw.depth.last_distance_km < 4.4 && mean_km > 3.0 && mean_km < 3.5;
	} else if (fixture_kind == 3) {
		checks[5] = raw.transmittance > 0.4 && raw.transmittance < 0.8;
		checks[6] = raw.traversed && has_depth && raw.depth.origin_km < 4.4
			&& raw.depth.last_distance_km > 10.6 && mean_km > 4.4 && variance_km2 > 4.0;
	}
	vec4 legacy = integrate_clouds(fixture_ray, fixture_clip, vec2(0.5));
	if (cloud_cost_view && raw.traversed) {
		checks[7] = distance(legacy.rgb, cloud_cost_color(raw.density_samples)) < 0.00001 && legacy.a == 1.0;
	} else if (opacity < 0.005) {
		checks[7] = legacy == vec4(0.0);
	} else {
		// Atmosphere is disabled in this fixture, so the adapter only divides
		// accumulated light by opacity. This also catches an extra alpha factor.
		checks[7] = abs(legacy.a - opacity) < 0.00001
			&& distance(legacy.rgb, raw.light / opacity) < 0.00001;
	}
	int index = clamp(int(floor(UV.x * 8.0)), 0, 7);
	// Binary colours survive display transfer functions and 8-bit readback.
	COLOR = checks[index] ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);
}
"""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Cloud volume result validation requires a graphical renderer; run without --headless.")
		quit(1)
		return
	var source := _expanded_source(VOLUME_PATH)
	var anchor := "vec3 sample_formation("
	if source.count(anchor) != 1:
		push_error("Expected exactly one production density function; the diagnostic fixture was not installed.")
		quit(1)
		return
	var start := source.find(anchor)
	var end := source.find("\n}\n", start)
	if end < start:
		push_error("Could not find the production density function's closing brace.")
		quit(1)
		return
	source = source.substr(0, start) + DENSITY + source.substr(end + 3)
	var shader := Shader.new()
	shader.code = HEADER + source + DIAGNOSTIC
	var material := ShaderMaterial.new()
	material.shader = shader
	var parameters := {"authored_weather": true, "cloud_occupancy_enabled": false,
		"BODY_RADIUS": 600.0, "AIR_RADIUS": 690.0, "cloud_height_km": 8.0,
		"cloud_thickness_km": 10.0, "cloud_deck_fraction": 0.14,
		"cloud_density_scale": 1.0, "atmosphere_density_scale": 0.0,
		"sun_direction": Vector3.UP, "cloud_world_to_local": Basis.IDENTITY}
	for parameter in parameters:
		material.set_shader_parameter(parameter, parameters[parameter])
	var viewport := SubViewport.new()
	viewport.size = Vector2i(8, 4)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rectangle := ColorRect.new()
	rectangle.size = Vector2(8, 4)
	rectangle.material = material
	viewport.add_child(rectangle)
	var fixtures := _fixtures()
	for cost in [false, true]:
		RenderingServer.global_shader_parameter_set("cloud_cost_view", cost)
		for fixture in fixtures:
			for parameter in fixture.uniforms:
				material.set_shader_parameter(parameter, fixture.uniforms[parameter])
			for frame in range(3): await process_frame
			await RenderingServer.frame_post_draw
			var result := viewport.get_texture().get_image()
			for index in CHECK_NAMES.size():
				var pixel := result.get_pixel(index, 1)
				if pixel.g < 0.99 or pixel.r > 0.01 or pixel.b > 0.01:
					failures.append("%s (cost=%s): %s" % [fixture.name, cost, CHECK_NAMES[index]])
	# Reading a shader global is editor-only and logs an error; restore the
	# project default (project.godot [shader_globals]) instead.
	RenderingServer.global_shader_parameter_set("cloud_cost_view", false)
	viewport.free()
	for failure in failures: push_error(failure)
	if failures.is_empty():
		print("PASS: production cloud traversal measures empty, clipped, interior, opaque, separated, grazing and thin rays; legacy colour/cost output is preserved")
	quit(0 if failures.is_empty() else 1)

func _expanded_source(path: String) -> String:
	var expanded := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges().begins_with("#include \""):
			expanded += _expanded_source(line.get_slice('"', 1)) + "\n"
		else:
			expanded += line + "\n"
	return expanded

func _fixture(name: String, kind: int, origin: Vector3, clip: float, density: float,
		segments: Array[Vector2] = []) -> Dictionary:
	var path := 0.0
	for segment in segments: path += segment.y - segment.x
	return {"name": name, "uniforms": {"fixture_kind": kind, "camera_planet_km": origin,
		"fixture_ray": Vector3.UP, "fixture_clip": clip, "fixture_density": density,
		"fixture_profile": 0, "expected_path_km": path,
		"expected_depth": _analytic_depth(segments, density * 1.2), "depth_tolerance": Vector2(0.02, 0.08)}}

func _fixtures() -> Array[Dictionary]:
	var cases: Array[Dictionary] = [
		_fixture("ray misses shell", 0, Vector3(0, 700, 0), 1000.0, 0.15),
		_fixture("clip before shell", 0, Vector3(0, 600, 0), 2.0, 0.15),
		_fixture("uniform full shell", 1, Vector3(0, 600, 0), 1000.0, 0.15, [Vector2(3, 13)]),
		_fixture("clip within cloud", 1, Vector3(0, 600, 0), 3.7, 0.15, [Vector2(3, 3.7)]),
		_fixture("camera inside cloud", 1, Vector3(0, 604, 0), 0.7, 0.15, [Vector2(0, 0.7)]),
		_fixture("opaque early exit", 2, Vector3(0, 600, 0), 1000.0, 4.0),
		_fixture("separated deck and storm", 3, Vector3(0, 600, 0), 1000.0, 0.15),
		_fixture("marched empty shell", 4, Vector3(0, 600, 0), 1000.0, 0.15),
		_fixture("thin volume below display cutoff", 1, Vector3(0, 600, 0), 1000.0, 0.0001, [Vector2(3, 13)]),
	]
	cases[6].uniforms.fixture_profile = 1
	cases[7].uniforms.fixture_profile = 2
	cases[8].uniforms.depth_tolerance = Vector2(0.08, 0.12)
	# This ray misses solid ground but leaves and re-enters the cloud shell.
	# Analytic intervals include both banks while excluding the clear-air gap.
	var ray := Vector3(0, -0.08, -sqrt(1.0 - 0.08 * 0.08))
	var b := 604.0 * ray.y
	var inner_root := sqrt(b * b - 604.0 * 604.0 + 603.0 * 603.0)
	var outer_root := sqrt(b * b - 604.0 * 604.0 + 613.0 * 613.0)
	var grazing := _fixture("grazing ray retains both banks", 1, Vector3(0, 604, 0), 1000.0, 0.02,
		[Vector2(0, -b - inner_root), Vector2(-b + inner_root, -b + outer_root)])
	grazing.uniforms.fixture_ray = ray
	grazing.uniforms.depth_tolerance = Vector2(0.15, 5.0)
	cases.append(grazing)
	return cases

## Exact moments of constant extinction in disjoint intervals. This reference
## does not reproduce the renderer's step grid or its sample accumulation.
func _analytic_depth(segments: Array[Vector2], extinction: float) -> Vector2:
	var transmission := 1.0
	var total_weight := 0.0
	var first := 0.0
	var second := 0.0
	for segment in segments:
		var length_km := segment.y - segment.x
		var exponential := exp(extinction * length_km)
		var local_mean := 1.0 / extinction - length_km / (exponential - 1.0)
		var variance := 1.0 / (extinction * extinction) - length_km * length_km * exponential / pow(exponential - 1.0, 2.0)
		var mean := segment.x + local_mean
		var weight := transmission * (1.0 - 1.0 / exponential)
		first += mean * weight
		second += (variance + mean * mean) * weight
		total_weight += weight
		transmission /= exponential
	if total_weight == 0.0: return Vector2.ZERO
	var mean := first / total_weight
	return Vector2(mean, maxf(second / total_weight - mean * mean, 0.0))
