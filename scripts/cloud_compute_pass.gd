extends CompositorEffect
## Opt-in cloud march (docs/CLOUD_RENDERER_PLAN.md, step 2). Before the
## transparent pass, integrates a fresh reduced-resolution frame against the
## resolved scene depth into float targets that the composite upsamples:
##   light:  premultiplied cloud light (legacy working space), transmittance
##   depth:  clip used (km, 1e20 where geometry did not cut the clouds),
##           contribution mean (km, -1 when empty), spread (km), front (km)
## Backend plumbing only: the volume code comes from cloud_volume_compute.gd.
## Targets are created on the main thread (ensure_targets) so materials can
## sample them; the render callback only dispatches into them.
const Compute = preload("res://scripts/cloud_volume_compute.gd")

const ENTRY := """
layout(set = 1, binding = 0) uniform sampler2D scene_depth;
layout(set = 1, binding = 1, rgba32f) uniform restrict writeonly image2D light_out;
layout(set = 1, binding = 2, rgba32f) uniform restrict writeonly image2D depth_out;
layout(set = 1, binding = 3, std430) restrict readonly buffer Frame {
	mat4 inv_projection;
	mat4 camera_basis;
	vec4 sizes; // target width, height; scene width, height
} frame;
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// clouds.gdshader's scene_clip(): view distance, ignoring depth beyond 100 km
// where reconstructed orbital depth is too imprecise to clip clouds.
float scene_distance_km(vec2 uv) {
	float depth = textureLod(scene_depth, uv, 0.0).r;
	vec4 scene = frame.inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	float distance_km = length(scene.xyz / scene.w) * 0.001;
	return distance_km < 100.0 ? distance_km : 1e20;
}

void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(texel, ivec2(frame.sizes.xy)))) { return; }
	cloud_load_params();
	vec2 uv = (vec2(texel) + 0.5) / frame.sizes.xy;
	// The farthest geometry among the scene pixels this texel covers. Nearer
	// pixels (a craft's silhouette) are incompatible and marched afresh.
	vec2 footprint = 0.5 / frame.sizes.xy - 0.5 / frame.sizes.zw;
	float clip = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 corner = vec2(float(i & 1) * 2.0 - 1.0, float(i >> 1) * 2.0 - 1.0);
		clip = max(clip, scene_distance_km(uv + corner * footprint));
	}
	vec4 view_ray = frame.inv_projection * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 ray = normalize(mat3(frame.camera_basis) * view_ray.xyz);
	CloudIntegral raw = integrate_cloud_volume(ray, clip, vec2(texel) + 0.5);
	vec4 segments = cloud_ray_segments(ray);
	bool beyond = clip >= segments.y || (segments.w >= segments.y && clip >= segments.z);
	imageStore(light_out, texel, vec4(raw.light, raw.transmittance));
	imageStore(depth_out, texel, vec4(beyond ? 1e20 : clip,
		cloud_depth_valid(raw.depth) ? cloud_depth_mean_km(raw.depth) : -1.0,
		sqrt(cloud_depth_variance_km2(raw.depth)), raw.depth.origin_km));
}
"""

## Uniform values as the layer last set them (see cloud_layer.gd _param()).
var values := {}
var bounded := false
## Sampled by the composite; valid once ensure_targets() has run.
var light_texture := Texture2DRD.new()
var depth_texture := Texture2DRD.new()
## Frames dispatched, for tests and diagnostics.
var dispatched := 0

var _rd: RenderingDevice
var _shaders := {}
var _pipelines := {}
var _sampler_linear: RID
var _sampler_nearest: RID
var _params := RID()
var _params_size := 0
var _frame := RID()
var _targets: Array[RID] = []
var _target_size := Vector2i.ZERO
var _scene_size := Vector2i.ZERO
var _placeholder: ImageTexture

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	access_resolved_depth = true
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		enabled = false
		return
	var state := RDSamplerState.new()
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_sampler_linear = _rd.sampler_create(state)
	state = RDSamplerState.new()
	_sampler_nearest = _rd.sampler_create(state)
	_frame = _rd.storage_buffer_create(36 * 4)
	# Procedural weather binds no map; the slot still needs a texture.
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	_placeholder = ImageTexture.create_from_image(image)

## Whether this backend can run the pass at all.
static func supported() -> bool:
	return RenderingServer.get_rendering_device() != null \
		and RenderingServer.get_current_rendering_method() == "forward_plus"

## (Re)creates the float targets for a scene of scene_size pixels.
func ensure_targets(scene_size: Vector2i, scale: float) -> void:
	if _rd == null: return
	var size := Vector2i((Vector2(scene_size) * scale).round()).max(Vector2i.ONE)
	if size == _target_size and scene_size == _scene_size: return
	_free_targets()
	var format := RDTextureFormat.new()
	format.width = size.x
	format.height = size.y
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	for i in 2:
		var rid := _rd.texture_create(format, RDTextureView.new())
		# Until the first dispatch: clear sky (no light, full transmittance).
		_rd.texture_clear(rid, Color(0, 0, 0, 1) if i == 0 else Color(1e20, -1, 0, 0), 0, 1, 0, 1)
		_targets.append(rid)
	light_texture.texture_rd_rid = _targets[0]
	depth_texture.texture_rd_rid = _targets[1]
	_target_size = size
	_scene_size = scene_size

func target_size() -> Vector2i:
	return _target_size

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT or _targets.is_empty(): return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data()
	if buffers == null or scene == null: return
	# A resize reaches the targets next frame; never write outside them.
	if buffers.get_internal_size() != _scene_size: return
	var pipeline := _pipeline()
	if not pipeline.is_valid(): return
	var shader: RID = _shaders[bounded]
	var data: PackedFloat32Array = Compute.shared().pack(values)
	if data.size() * 4 != _params_size:
		if _params.is_valid(): _rd.free_rid(_params)
		_params_size = data.size() * 4
		_params = _rd.storage_buffer_create(_params_size, data.to_byte_array())
	else:
		_rd.buffer_update(_params, 0, _params_size, data.to_byte_array())
	var frame := PackedFloat32Array()
	var inverse := scene.get_cam_projection().inverse()
	for column in 4:
		for row in 4: frame.append(inverse[column][row])
	var basis := scene.get_cam_transform().basis
	for column in 3:
		for row in 3: frame.append(basis[column][row])
		frame.append(0.0)
	frame.append_array([0.0, 0.0, 0.0, 1.0])
	frame.append_array([_target_size.x, _target_size.y, _scene_size.x, _scene_size.y])
	_rd.buffer_update(_frame, 0, frame.size() * 4, frame.to_byte_array())
	var volume: Array[RDUniform] = [_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, [_params])]
	var compute: RefCounted = Compute.shared()
	for index in compute.samplers.size():
		var texture: Variant = values.get(compute.samplers[index])
		if not texture is Texture: texture = _placeholder
		volume.append(_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, index + 1,
			[_sampler_linear, RenderingServer.texture_get_rd_texture((texture as Texture).get_rid())]))
	var outputs: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [_sampler_nearest, buffers.get_depth_layer(0)]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [_targets[0]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 2, [_targets[1]]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 3, [_frame]),
	]
	# Named for --profile-gpu captures and the cost overlay.
	_rd.capture_timestamp("Cloud compute march")
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, pipeline)
	_rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(shader, 0, volume), 0)
	_rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(shader, 1, outputs), 1)
	_rd.compute_list_dispatch(list, (_target_size.x + 7) / 8, (_target_size.y + 7) / 8, 1)
	_rd.compute_list_end()
	_rd.capture_timestamp("Cloud compute march done")
	dispatched += 1

func _pipeline() -> RID:
	if not _pipelines.has(bounded):
		var defines := PackedStringArray(["CLOUD_MEASURE_DEPTH"])
		if bounded: defines.append("CLOUD_OCCUPANCY")
		var source := RDShaderSource.new()
		source.source_compute = Compute.shared().source(defines, ENTRY)
		var spirv := _rd.shader_compile_spirv_from_source(source)
		if not spirv.compile_error_compute.is_empty():
			push_error("Cloud compute pass failed to compile: " + spirv.compile_error_compute)
			_pipelines[bounded] = RID()
			return RID()
		_shaders[bounded] = _rd.shader_create_from_spirv(spirv)
		_pipelines[bounded] = _rd.compute_pipeline_create(_shaders[bounded])
	return _pipelines[bounded]

static func _uniform(type: int, binding: int, ids: Array) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for id in ids: uniform.add_id(id)
	return uniform

func _free_targets() -> void:
	light_texture.texture_rd_rid = RID()
	depth_texture.texture_rd_rid = RID()
	for rid in _targets: _rd.free_rid(rid)
	_targets.clear()
	_target_size = Vector2i.ZERO
	_scene_size = Vector2i.ZERO

## Frees every GPU resource; the pass stays disabled afterwards. The owning
## layer calls this when it is deleted, since a Resource can outlive it.
func release() -> void:
	enabled = false
	if _rd == null: return
	_free_targets()
	# Shaders own their pipelines and cached uniform sets.
	for shader in _shaders.values(): _rd.free_rid(shader)
	_shaders.clear()
	_pipelines.clear()
	for rid in [_params, _frame, _sampler_linear, _sampler_nearest]:
		if rid.is_valid(): _rd.free_rid(rid)
	_params = RID()
	_frame = RID()
	_sampler_linear = RID()
	_sampler_nearest = RID()
	_rd = null

func _notification(what: int) -> void:
	# Script methods are unavailable while a Resource is being deleted; free
	# anything release() did not inline.
	if what != NOTIFICATION_PREDELETE or _rd == null: return
	for rid in _targets: _rd.free_rid(rid)
	for shader in _shaders.values(): _rd.free_rid(shader)
	for rid in [_params, _frame, _sampler_linear, _sampler_nearest]:
		if rid.is_valid(): _rd.free_rid(rid)
