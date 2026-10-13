extends SceneTree
## Step 1 of docs/CLOUD_RENDERER_PLAN.md: the refactored integrator must match
## the volume include frozen before CloudIntegral, with and without measured
## depth. Both run in one shader on identical rays; each pixel is pass/fail.
## Only valid while the shared helpers above the integrator are unchanged.
## Run graphically with scratch XDG_* dirs:
## tools/run.sh --script res://tests/_probe/cloud_integral_reference.gd
## Prints cloud_pixels so a view that sees no cloud is not mistaken for a pass.
const OLD_PATH := "res://docs/performance/cloud-foundation/clouds_volume.pre-integral.gdshaderinc.txt"
const CURRENT_PATH := "res://assets/shaders/clouds_volume.gdshaderinc"
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var old := FileAccess.get_file_as_string(OLD_PATH)
	var current := FileAccess.get_file_as_string(CURRENT_PATH)
	# Guard the common code: only the integration body is allowed to differ.
	var before := old.get_slice("// Integrates the volume along a view ray", 0)
	var now := current.get_slice("// Integrates along a normalized camera ray", 0)
	now = now.replace('#include "res://assets/shaders/cloud_integral.gdshaderinc"\n', '')
	if before != now:
		push_error("Reference shared helpers changed; cannot use this comparison")
		quit(1)
		return
	var start := old.find("vec4 integrate_clouds(")
	var end := old.find("vec3 cloud_view_ray(")
	if start < 0 or end < start:
		push_error("Frozen reference has no integrate_clouds body")
		quit(1)
		return
	var reference := old.substr(start, end - start).replace("vec4 integrate_clouds(", "vec4 reference_integrate_clouds(")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 64)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rect := ColorRect.new()
	rect.size = Vector2(viewport.size)
	viewport.add_child(rect)
	var noise: NoiseTexture3D = load("res://assets/cloud_volume_noise.tres")
	var detail: NoiseTexture3D = load("res://assets/cloud_detail_noise.tres")
	for i in 60: await process_frame
	# Mixed families: storm-free texels exercise authored cumulus/stratocumulus,
	# which any nonzero storm alpha disables; others mix storms at varied alpha.
	var map := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 16:
			var storm := 0.0 if (x + y) % 3 != 0 else 0.25 + 0.25 * float(x % 4)
			map.set_pixel(x, y, Color(fmod(x * 0.37, 1.0), fmod(y * 0.23 + 0.1, 1.0), fmod((x + y) * 0.19, 1.0), storm))
	var weather := ImageTexture.create_from_image(map)
	for measured in [false, true]:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\nrender_mode unshaded;\n#define CLOUD_OCCUPANCY\n" + ("#define CLOUD_MEASURE_DEPTH\n" if measured else "") + '#include "res://assets/shaders/clouds_volume.gdshaderinc"\n' + reference + """
uniform bool look_down = false;
void fragment() {
	vec2 xy = UV * 2.0 - 1.0;
	// The far view's planet spans about +/-10.6 degrees; aim rays at it.
	vec3 ray = look_down ? normalize(vec3(xy.x * 0.2, -1.0, xy.y * 0.2)) : normalize(vec3(xy.x, -xy.y, -0.2));
	float clip_distance = mod(floor(FRAGCOORD.x), 4.0) == 0.0 ? 0.1 : (mod(floor(FRAGCOORD.x), 4.0) == 1.0 ? 4.0 : 1e20);
	vec4 reference = reference_integrate_clouds(ray, clip_distance, FRAGCOORD.xy);
	vec4 current = integrate_clouds(ray, clip_distance, FRAGCOORD.xy);
	vec4 error = abs(current - reference);
	bool ok = all(lessThanEqual(error, vec4(0.00001)));
	COLOR = vec4(ok ? 0.0 : 1.0, ok ? 1.0 : 0.0, reference.a > 0.005 ? 1.0 : 0.0, 1.0);
}
"""
		var material := ShaderMaterial.new()
		material.shader = shader
		rect.material = material
		material.set_shader_parameter("cloud_noise", noise)
		material.set_shader_parameter("cloud_detail_noise", detail)
		material.set_shader_parameter("cloud_weather_map", weather)
		material.set_shader_parameter("cloud_world_to_local", Basis.IDENTITY)
		material.set_shader_parameter("cloud_low_min", Vector3(-620,-620,-620))
		material.set_shader_parameter("cloud_low_max", Vector3(620,620,620))
		material.set_shader_parameter("cloud_storm_min", Vector3(-620,-620,-620))
		material.set_shader_parameter("cloud_storm_max", Vector3(620,620,620))
		material.set_shader_parameter("atmosphere_view_samples", 4)
		material.set_shader_parameter("atmosphere_light_samples", 1)
		material.set_shader_parameter("cloud_height_km", 10.3)
		material.set_shader_parameter("cloud_thickness_km", 10.0)
		material.set_shader_parameter("cloud_deck_fraction", 0.14)
		for authored in [false, true]:
			material.set_shader_parameter("authored_weather", authored)
			for view in ["ground", "inside", "above", "orbit", "far", "night", "occupancy_miss", "cost"]:
				material.set_shader_parameter("cloud_occupancy_enabled", view == "occupancy_miss" or view == "above")
				material.set_shader_parameter("cloud_low_min", Vector3(900,900,900) if view == "occupancy_miss" else Vector3(-620,-620,-620))
				material.set_shader_parameter("cloud_storm_min", Vector3(900,900,900) if view == "occupancy_miss" else Vector3(-620,-620,-620))
				var altitude: float = {"ground":0.01,"inside":6.0,"above":20.0,"orbit":100.0,"far":2700.0,"night":6.0,"occupancy_miss":6.0,"cost":6.0}[view]
				material.set_shader_parameter("look_down", view == "far")
				material.set_shader_parameter("camera_planet_km", Vector3(0,600 + altitude,0))
				material.set_shader_parameter("sun_direction", Vector3.DOWN if view == "night" else Vector3.UP)
				RenderingServer.global_shader_parameter_set("cloud_cost_view", view == "cost")
				for i in 3: await process_frame
				await RenderingServer.frame_post_draw
				var capture := viewport.get_texture().get_image()
				var bad := 0
				var covered := 0
				for y in capture.get_height():
					for x in capture.get_width():
						var c := capture.get_pixel(x,y)
						if c.g < 0.99 or c.r > 0.01: bad += 1
						if c.b > 0.5: covered += 1
				print("REFERENCE measured=%s authored=%s view=%s bad_pixels=%d cloud_pixels=%d" % [measured, authored, view, bad, covered])
				if bad > 0:
					failures.append("Reference mismatch: %s/%s/%s" % [measured,authored,view])
					capture.save_png("user://cloud-integral-reference-failure-%s-%s-%s.png" % [measured,authored,view])
	RenderingServer.global_shader_parameter_set("cloud_cost_view", false)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: 32 configurations x 8192 rays agree with frozen pre-change integrator to 1e-5, including measured instrumentation")
	viewport.free()
	quit(0 if failures.is_empty() else 1)
