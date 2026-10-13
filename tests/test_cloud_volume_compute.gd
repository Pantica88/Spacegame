extends SceneTree
## Graphical parity test: the generated compute volume (cloud_volume_compute.gd)
## against the spatial include, on identical rays, parameters and textures.
## The canvas shader integrates each ray itself and compares the compute
## result, read through Texture2DRD, in float.
## tools/run.sh --script res://tests/test_cloud_volume_compute.gd
const Compute = preload("res://scripts/cloud_volume_compute.gd")
const SIZE := Vector2i(128, 64)
const VIEWS := ["ground", "inside", "above", "orbit", "far", "night", "occupancy_miss"]
const ALTITUDES := {"ground": 0.01, "inside": 6.0, "above": 20.0, "orbit": 100.0, "far": 2700.0,
	"night": 6.0, "occupancy_miss": 6.0}
var failures: Array[String] = []

# Rays and clips shared verbatim by both sides.
const RAYS := """
vec3 fixture_ray(vec2 pixel, vec2 size, bool down) {
	vec2 xy = pixel / size * 2.0 - 1.0;
	// The far view's planet spans about +/-10.6 degrees; aim rays at it.
	return down ? normalize(vec3(xy.x * 0.2, -1.0, xy.y * 0.2)) : normalize(vec3(xy.x, -xy.y, -0.2));
}
float fixture_clip(vec2 pixel) {
	float column = mod(floor(pixel.x), 4.0);
	return column == 0.0 ? 0.1 : (column == 1.0 ? 4.0 : 1e20);
}
"""

const ENTRY := """
layout(set = 1, binding = 0, rgba32f) uniform restrict writeonly image2D light_out;
layout(set = 1, binding = 1, rgba32f) uniform restrict writeonly image2D depth_out;
layout(set = 1, binding = 2, rgba32f) uniform restrict writeonly image2D extra_out;
layout(push_constant, std430) uniform Fixture { vec2 size; float look_down; float pad; } fixture;
""" + RAYS + """
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(texel, ivec2(fixture.size)))) { return; }
	cloud_load_params();
	vec2 pixel = vec2(texel) + 0.5;
	CloudIntegral raw = integrate_cloud_volume(fixture_ray(pixel, fixture.size, fixture.look_down != 0.0), fixture_clip(pixel), pixel);
	imageStore(light_out, texel, vec4(raw.light, raw.transmittance));
	imageStore(depth_out, texel, vec4(raw.weighted_distance_km, cloud_depth_mean_km(raw.depth), cloud_depth_variance_km2(raw.depth), raw.depth.weight));
	imageStore(extra_out, texel, vec4(raw.density_samples, raw.traversed ? 1.0 : 0.0, raw.depth.origin_km, raw.depth.last_distance_km));
}
"""

const COMPARE := """
uniform sampler2D compute_light : filter_nearest;
uniform sampler2D compute_depth : filter_nearest;
uniform sampler2D compute_extra : filter_nearest;
uniform bool look_down = false;
uniform vec2 fixture_size = vec2(128.0, 64.0);
""" + RAYS + """
bool near_value(float a, float b, float relative, float absolute) {
	return abs(a - b) <= max(abs(b) * relative, absolute);
}
void fragment() {
	ivec2 texel = ivec2(FRAGCOORD.xy);
	vec2 pixel = vec2(texel) + 0.5;
	CloudIntegral raw = integrate_cloud_volume(fixture_ray(pixel, fixture_size, look_down), fixture_clip(pixel), pixel);
	vec4 light = texelFetch(compute_light, texel, 0);
	vec4 depth = texelFetch(compute_depth, texel, 0);
	vec4 extra = texelFetch(compute_extra, texel, 0);
	// Fragment and compute compilations differ in the last bits, which can
	// flip a branch (storm tap pair, sun march, early exit) on a few rays.
	// Require agreement far below one 8-bit display step instead of identity.
	float opacity = 1.0 - raw.transmittance;
	vec3 color = raw.light / max(opacity, 1e-4);
	vec3 compute_color = light.rgb / max(1.0 - light.a, 1e-4);
	bool ok = extra.y == (raw.traversed ? 1.0 : 0.0);
	ok = ok && abs(light.a - raw.transmittance) <= 1e-3;
	ok = ok && (opacity <= 0.005 || length(compute_color - color) <= 2e-3 * max(length(color), 1e-3));
	ok = ok && near_value(depth.w, raw.depth.weight, 0.0, 1e-3);
	// Reported, not required: floor() on the step grid rounds differently.
	bool same_work = extra.x == raw.density_samples;
	// Depth is judged against each ray's own spread. Measured on the RX 580:
	// mean within 2.4% of spread, spread within 10% when both did the same
	// work. Spread weighs distance squared, so where a branch flipped, one
	// faint extra sample kilometres away legitimately changes it.
	float sigma = sqrt(cloud_depth_variance_km2(raw.depth));
	ok = ok && (raw.depth.weight <= 0.0 || abs(depth.y - cloud_depth_mean_km(raw.depth)) <= max(0.05 * sigma, 0.01));
	ok = ok && (raw.depth.weight <= 0.0 || !same_work || abs(sqrt(depth.z) - sigma) <= max(0.2 * sigma, 0.01));
	ok = ok && !any(isnan(light)) && !any(isinf(light)) && !any(isnan(depth)) && !any(isinf(depth)) && !any(isnan(extra));
	COLOR = vec4(ok ? 0.0 : 1.0, same_work ? 1.0 : 0.0, raw.transmittance < 0.995 ? 1.0 : 0.0, 1.0);
}
"""

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		print("SKIP: cloud compute parity needs a RenderingDevice backend")
		quit(0)
		return
	var noise: NoiseTexture3D = load("res://assets/cloud_volume_noise.tres")
	var detail: NoiseTexture3D = load("res://assets/cloud_detail_noise.tres")
	for i in 60: await process_frame
	var map := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 16:
			# Storm-free texels exercise authored cumulus and stratocumulus.
			var storm := 0.0 if (x + y) % 3 != 0 else 0.25 + 0.25 * float(x % 4)
			map.set_pixel(x, y, Color(fmod(x * 0.37, 1.0), fmod(y * 0.23 + 0.1, 1.0), fmod((x + y) * 0.19, 1.0), storm))
	var weather := ImageTexture.create_from_image(map)
	var compute: RefCounted = Compute.shared()
	_check(compute.samplers == ["cloud_noise", "cloud_detail_noise", "cloud_weather_map"], "Sampler bindings follow source order: %s" % [compute.samplers])
	_check(compute.params.has("cloud_cost_view") and compute.params.has("camera_planet_km") and compute.params.has("cloud_world_to_local"), "Volume, atmosphere and global uniforms are all parameters")
	var targets: Array[Texture2DRD] = []
	var target_rids: Array[RID] = []
	var format := RDTextureFormat.new()
	format.width = SIZE.x
	format.height = SIZE.y
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	for i in 3:
		var rid := rd.texture_create(format, RDTextureView.new())
		target_rids.append(rid)
		var wrapper := Texture2DRD.new()
		wrapper.texture_rd_rid = rid
		targets.append(wrapper)
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE)
	viewport.add_child(rect)
	var sampler_state := RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	var sampler := rd.sampler_create(sampler_state)
	var configurations := 0
	for bounded in [false, true]:
		var defines := PackedStringArray(["CLOUD_MEASURE_DEPTH"])
		if bounded: defines.append("CLOUD_OCCUPANCY")
		var spirv_source := RDShaderSource.new()
		spirv_source.source_compute = compute.source(defines, ENTRY)
		var spirv := rd.shader_compile_spirv_from_source(spirv_source)
		if not spirv.compile_error_compute.is_empty():
			failures.append("Generated compute volume failed to compile (bounded=%s): %s" % [bounded, spirv.compile_error_compute])
			break
		var shader := rd.shader_create_from_spirv(spirv)
		var pipeline := rd.compute_pipeline_create(shader)
		var canvas_shader := Shader.new()
		var prefix := "shader_type canvas_item;\nrender_mode unshaded, blend_disabled;\n#define CLOUD_MEASURE_DEPTH\n"
		if bounded: prefix += "#define CLOUD_OCCUPANCY\n"
		canvas_shader.code = prefix + '#include "res://assets/shaders/clouds_volume.gdshaderinc"\n' + COMPARE
		var material := ShaderMaterial.new()
		material.shader = canvas_shader
		rect.material = material
		material.set_shader_parameter("compute_light", targets[0])
		material.set_shader_parameter("compute_depth", targets[1])
		material.set_shader_parameter("compute_extra", targets[2])
		material.set_shader_parameter("fixture_size", Vector2(SIZE))
		for authored in [false, true]:
			for view in VIEWS:
				var values := {
					"cloud_noise": noise, "cloud_detail_noise": detail, "cloud_weather_map": weather,
					"cloud_world_to_local": Basis(Vector3(0.3, 1.0, 0.2).normalized(), 0.7),
					"atmosphere_view_samples": 4, "atmosphere_light_samples": 1,
					"cloud_height_km": 10.3, "cloud_thickness_km": 10.0, "cloud_deck_fraction": 0.14,
					"authored_weather": authored, "cloud_occupancy_enabled": view == "occupancy_miss" or view == "above",
					"cloud_low_min": Vector3.ONE * (900.0 if view == "occupancy_miss" else -620.0),
					"cloud_low_max": Vector3.ONE * 620.0,
					"cloud_storm_min": Vector3.ONE * (900.0 if view == "occupancy_miss" else -620.0),
					"cloud_storm_max": Vector3.ONE * 620.0,
					"camera_planet_km": Vector3(0, 600.0 + ALTITUDES[view], 0),
					"sun_direction": Vector3.DOWN if view == "night" else Vector3(0.3, 0.8, -0.5).normalized(),
					"cloud_evolution_offset": Vector3(1.5, -0.25, 3.0), "cloud_coverage": 0.62, "cloud_density_scale": 1.3,
				}
				for name in values: material.set_shader_parameter(name, values[name])
				material.set_shader_parameter("look_down", view == "far")
				var params := rd.storage_buffer_create(compute.slot_count * 16, compute.pack(values).to_byte_array())
				var set0: Array[RDUniform] = [_buffer_uniform(0, params)]
				for index in compute.samplers.size():
					var texture: Texture = values[compute.samplers[index]]
					var uniform := RDUniform.new()
					uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					uniform.binding = index + 1
					uniform.add_id(sampler)
					uniform.add_id(RenderingServer.texture_get_rd_texture(texture.get_rid()))
					set0.append(uniform)
				var set1: Array[RDUniform] = []
				for index in 3:
					var image := RDUniform.new()
					image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
					image.binding = index
					image.add_id(target_rids[index])
					set1.append(image)
				var uniform_sets := [rd.uniform_set_create(set0, shader, 0), rd.uniform_set_create(set1, shader, 1)]
				var push := PackedFloat32Array([SIZE.x, SIZE.y, 1.0 if view == "far" else 0.0, 0.0]).to_byte_array()
				RenderingServer.call_on_render_thread(func() -> void:
					var list := rd.compute_list_begin()
					rd.compute_list_bind_compute_pipeline(list, pipeline)
					rd.compute_list_bind_uniform_set(list, uniform_sets[0], 0)
					rd.compute_list_bind_uniform_set(list, uniform_sets[1], 1)
					rd.compute_list_set_push_constant(list, push, push.size())
					rd.compute_list_dispatch(list, (SIZE.x + 7) / 8, (SIZE.y + 7) / 8, 1)
					rd.compute_list_end())
				for frame in 3: await process_frame
				await RenderingServer.frame_post_draw
				var capture := viewport.get_texture().get_image()
				var bad := 0
				var branched := 0
				var covered := 0
				for y in SIZE.y:
					for x in SIZE.x:
						var color := capture.get_pixel(x, y)
						if color.r > 0.5: bad += 1
						if color.g < 0.5: branched += 1
						if color.b > 0.5: covered += 1
				configurations += 1
				print("COMPUTE bounded=%s authored=%s view=%s bad_rays=%d branched_rays=%d cloud_rays=%d" % [bounded, authored, view, bad, branched, covered])
				if bad > 0:
					failures.append("Compute volume differs from the spatial include: bounded=%s authored=%s %s (%d rays)" % [bounded, authored, view, bad])
					capture.save_png("user://cloud-compute-%s-%s-%s.png" % [bounded, authored, view])
				if view != "occupancy_miss" or not authored:
					_check(covered > 500, "%s/%s/%s sees cloud" % [bounded, authored, view])
				for set in uniform_sets: rd.free_rid(set)
				rd.free_rid(params)
		rd.free_rid(pipeline)
		rd.free_rid(shader)
	viewport.free()
	for wrapper in targets: wrapper.texture_rd_rid = RID()
	for rid in target_rids: rd.free_rid(rid)
	rd.free_rid(sampler)
	for failure in failures: push_error(failure)
	if failures.is_empty():
		print("PASS: generated compute volume matches the spatial include on %d configurations x %d rays" % [configurations, SIZE.x * SIZE.y])
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _buffer_uniform(binding: int, buffer: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	return uniform
