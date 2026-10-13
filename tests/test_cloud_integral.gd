extends SceneTree
## Runs the production integration helpers on a local GPU device. The CPU
## oracle uses direct prefix products and a two-pass variance, independently
## of the shader's running transmittance and anchored Welford implementation.
## tools/run.sh --script res://tests/test_cloud_integral.gd
const INTEGRAL_PATH := "res://assets/shaders/cloud_integral.gdshaderinc"
const INPUT_STRIDE := 16 # Count followed by up to three (RGB, opacity, km) rows.
const OUTPUT_STRIDE := 15
const FIELD_NAMES := ["light.r", "light.g", "light.b", "transmittance",
	"weighted_distance_km", "density_samples", "traversed", "depth.weight",
	"depth.mean_km", "depth.variance_km2", "depth.valid", "depth.last_distance_km",
	"depth.origin_km", "depth.mean_offset_km", "depth.m2_km2"]
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _cases() -> Array[Dictionary]:
	# Inputs are exactly representable binary fractions except the intentionally
	# tiny opacity, which is quantized through the same float32 input buffer.
	return [
		{"name": "no hit", "samples": []},
		{"name": "clear samples", "samples": [[8.0, 2.0, 0.5, 0.0, 900.0]]},
		{"name": "at camera", "samples": [[2.0, 4.0, 1.0, 0.25, 0.0]]},
		{"name": "thin below display cutoff", "samples": [[8.0, 2.0, 0.5, 0.0001, 23.0]]},
		{"name": "thin below transmittance precision", "samples": [[8.0, 2.0, 0.5, 0.00000001, 23.0]]},
		{"name": "ordered HDR layers", "samples": [[8.0, 2.0, 0.5, 0.25, 2.0], [0.5, 4.0, 16.0, 0.5, 10.0]]},
		{"name": "reversed HDR layers", "samples": [[0.5, 4.0, 16.0, 0.5, 2.0], [8.0, 2.0, 0.5, 0.25, 10.0]]},
		{"name": "unlit layers", "samples": [[0.0, 0.0, 0.0, 0.25, 2.0], [0.0, 0.0, 0.0, 0.5, 10.0]]},
		{"name": "opaque foreground", "samples": [[2.0, 1.0, 0.5, 1.0, 3.0], [128.0, 128.0, 128.0, 0.75, 9.0]]},
		{"name": "distant thin bank", "samples": [[1.0, 2.0, 4.0, 0.25, 3000.0], [4.0, 2.0, 1.0, 0.5, 3000.125]]},
		{"name": "distant clear gap", "samples": [[1.0, 2.0, 4.0, 0.125, 5000.0], [99.0, 99.0, 99.0, 0.0, 5000.25], [4.0, 2.0, 1.0, 0.75, 5000.5]]},
	]

func _input(cases: Array[Dictionary]) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(cases.size() * INPUT_STRIDE)
	for i in cases.size():
		var samples: Array = cases[i].samples
		values[i * INPUT_STRIDE] = samples.size()
		for j in samples.size():
			for k in 5:
				values[i * INPUT_STRIDE + 1 + j * 5 + k] = samples[j][k]
	return values

func _expected(input: PackedFloat32Array, case_index: int, measure_depth: bool) -> PackedFloat64Array:
	var expected := PackedFloat64Array()
	expected.resize(OUTPUT_STRIDE)
	var base := case_index * INPUT_STRIDE
	var count := int(input[base])
	expected[3] = 1.0
	expected[5] = count
	expected[6] = 1.0 if count > 0 else 0.0
	var weights := PackedFloat64Array()
	var distances := PackedFloat64Array()
	for j in count:
		var sample_base := base + 1 + j * 5
		var opacity: float = input[sample_base + 3]
		var weight := opacity
		# Direct product of all preceding layer transmissions: the reference
		# does not use the production accumulator's intermediate state.
		for earlier in j:
			weight *= 1.0 - float(input[base + 1 + earlier * 5 + 3])
		var distance: float = input[sample_base + 4]
		weights.append(weight)
		distances.append(distance)
		for channel in 3:
			expected[channel] += float(input[sample_base + channel]) * weight
		expected[3] *= 1.0 - opacity
		expected[4] += distance * weight
		if measure_depth and weight > 0.0:
			if expected[7] == 0.0: expected[12] = distance
			expected[7] += weight
			expected[11] = distance
	if measure_depth and expected[7] > 0.0:
		expected[8] = expected[4] / expected[7]
		expected[10] = 1.0
		expected[13] = expected[8] - expected[12]
		# Independent two-pass population variance in CPU double precision.
		for j in count:
			expected[14] += weights[j] * pow(distances[j] - expected[8], 2.0)
		expected[9] = expected[14] / expected[7]
	return expected

func _source(measure_depth: bool) -> String:
	var prefix := "#version 450\n"
	if measure_depth: prefix += "#define CLOUD_MEASURE_DEPTH\n"
	return prefix + FileAccess.get_file_as_string(INTEGRAL_PATH) + """
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) readonly buffer Input { float values[]; } samples;
layout(set = 0, binding = 1, std430) writeonly buffer Output { float values[]; } output_data;
void main() {
	int case_index = int(gl_GlobalInvocationID.x);
	int start = case_index * 16;
	int count = int(samples.values[start]);
	CloudIntegral result = cloud_integral_empty();
	result.traversed = count > 0;
	for (int i = 0; i < count; i++) {
		int s = start + 1 + i * 5;
		result.density_samples += 1.0;
		cloud_integral_add(result, vec3(samples.values[s], samples.values[s + 1], samples.values[s + 2]),
			samples.values[s + 3], samples.values[s + 4]);
	}
	int o = case_index * 15;
	output_data.values[o] = result.light.r;
	output_data.values[o + 1] = result.light.g;
	output_data.values[o + 2] = result.light.b;
	output_data.values[o + 3] = result.transmittance;
	output_data.values[o + 4] = result.weighted_distance_km;
	output_data.values[o + 5] = result.density_samples;
	output_data.values[o + 6] = result.traversed ? 1.0 : 0.0;
	output_data.values[o + 7] = result.depth.weight;
	output_data.values[o + 8] = cloud_depth_mean_km(result.depth);
	output_data.values[o + 9] = cloud_depth_variance_km2(result.depth);
	output_data.values[o + 10] = cloud_depth_valid(result.depth) ? 1.0 : 0.0;
	output_data.values[o + 11] = result.depth.last_distance_km;
	output_data.values[o + 12] = result.depth.origin_km;
	output_data.values[o + 13] = result.depth.mean_offset_km;
	output_data.values[o + 14] = result.depth.m2_km2;
}
"""

func _gpu(rd: RenderingDevice, input: PackedFloat32Array, count: int, measure_depth: bool) -> PackedFloat32Array:
	var source := RDShaderSource.new()
	source.source_compute = _source(measure_depth)
	var spirv := rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		failures.append("Shared cloud include failed compute compilation: " + spirv.compile_error_compute)
		return PackedFloat32Array()
	var owned: Array[RID] = []
	var shader := rd.shader_create_from_spirv(spirv)
	owned.append(shader)
	var input_buffer := rd.storage_buffer_create(input.size() * 4, input.to_byte_array())
	owned.append(input_buffer)
	# NaNs make an unwritten output fail instead of looking like a valid zero.
	var unwritten := PackedFloat32Array()
	unwritten.resize(count * OUTPUT_STRIDE)
	unwritten.fill(NAN)
	var output_buffer := rd.storage_buffer_create(unwritten.size() * 4, unwritten.to_byte_array())
	owned.append(output_buffer)
	var input_uniform := RDUniform.new()
	input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	input_uniform.binding = 0
	input_uniform.add_id(input_buffer)
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 1
	output_uniform.add_id(output_buffer)
	var uniforms := rd.uniform_set_create([input_uniform, output_uniform], shader, 0)
	owned.append(uniforms)
	var pipeline := rd.compute_pipeline_create(shader)
	owned.append(pipeline)
	for resource in owned:
		if not resource.is_valid():
			failures.append("Failed to allocate the cloud integration GPU fixture")
			_release(rd, owned)
			return PackedFloat32Array()
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniforms, 0)
	rd.compute_list_dispatch(list, count, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var actual := rd.buffer_get_data(output_buffer).to_float32_array()
	_release(rd, owned)
	return actual

func _release(rd: RenderingDevice, owned: Array[RID]) -> void:
	owned.reverse()
	for resource in owned:
		if resource.is_valid(): rd.free_rid(resource)

func _compare(cases: Array[Dictionary], input: PackedFloat32Array, actual: PackedFloat32Array, measure_depth: bool) -> void:
	if actual.size() != cases.size() * OUTPUT_STRIDE:
		failures.append("GPU integration output has the wrong size")
		return
	for i in cases.size():
		var expected := _expected(input, i, measure_depth)
		for field in OUTPUT_STRIDE:
			var observed: float = actual[i * OUTPUT_STRIDE + field]
			# Relative tolerance suits float32 arithmetic without hiding the
			# distant bank's small variance or the tiny positive depth weight.
			var tolerance := maxf(absf(expected[field]) * 0.000002, 0.000000000001)
			if not is_finite(observed) or absf(observed - expected[field]) > tolerance:
				failures.append("%s depth=%s %s: GPU %.12g, expected %.12g (tolerance %.3g)" % [
					cases[i].name, measure_depth, FIELD_NAMES[field], observed, expected[field], tolerance])

func _run() -> void:
	if RenderingServer.get_rendering_device() == null:
		print("SKIP: cloud integration GPU test needs a RenderingDevice backend; headless/Compatibility did not execute it")
		quit(0)
		return
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("Cannot create a local RenderingDevice for cloud integration validation")
		quit(1)
		return
	var cases := _cases()
	var input := _input(cases)
	var measured := _gpu(rd, input, cases.size(), true)
	_compare(cases, input, measured, true)
	var legacy := _gpu(rd, input, cases.size(), false)
	_compare(cases, input, legacy, false)
	if measured.size() == legacy.size() and not measured.is_empty():
		for i in cases.size():
			for field in 7:
				if measured[i * OUTPUT_STRIDE + field] != legacy[i * OUTPUT_STRIDE + field]:
					failures.append("Depth instrumentation changed legacy %s for %s" % [FIELD_NAMES[field], cases[i].name])
	rd.free()
	for failure in failures: push_error(failure)
	if failures.is_empty():
		print("PASS: GPU cloud integral, %d analytic cases, measured/legacy parity, thin and distant depth precision" % cases.size())
	quit(0 if failures.is_empty() else 1)
