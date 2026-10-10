extends CompositorEffect
## Cloud march and temporal resolve as compute passes on the RenderingDevice
## (docs/MULTI_PLANET_ROADMAP.md, cloud renderer rebuild). CloudLayer owns it:
## each frame it calls prepare() with the cloud volume's uniforms and the
## camera's state; the render callback only dispatches, before the transparent
## pass where clouds.gdshader composites `output`.
const VOLUME := "res://assets/shaders/clouds_volume.gdshaderinc"
const PASSES := "res://assets/shaders/clouds_compute.gdshaderinc"
## Values the passes read besides the cloud volume's uniforms.
const FRAME_PARAMETERS := [
	["frame_inv_projection", "mat4"], ["frame_view_basis", "mat3"], ["frame_size", "vec2"],
	["frame_grid", "float"], ["frame_offset", "vec2"], ["reveal_offset", "vec2"],
	["previous_projection", "mat4"], ["previous_view_rotation", "mat3"],
	["cloud_motion", "mat3"], ["camera_offset_km", "vec3"],
	["history_valid", "bool"], ["history_tolerance", "float"],
]
## The volume's textures, at bindings 1, 2 and 3 of the march.
const SAMPLERS := {"cloud_noise": "sampler3D", "cloud_detail_noise": "sampler3D", "cloud_weather_map": "sampler2D"}
const SLOTS := {"float": 1, "int": 1, "bool": 1, "vec2": 1, "vec3": 1, "mat3": 3, "mat4": 4}

## Unmultiplied linear cloud light and opacity at screen resolution.
var output := Texture2DRD.new()
## False when the passes failed to compile.
var compiled := false
var _rd: RenderingDevice
# [name, type, first vec4 slot] for every buffer value.
var _layout: Array = []
var _slot_count := 0
var _march_shaders := {}
var _march_pipelines := {}
var _reveal_shaders := {}
var _reveal_pipelines := {}
var _resolve_shader := RID()
var _resolve_pipeline := RID()
var _buffer := RID()
var _sampler := RID()
var _blank_2d := RID()
var _images := {}
var _size := Vector2i.ZERO
var _march_size := Vector2i.ZERO
var _bounded := false
var _texture_rids := {}
var _runnable := false

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	var volume := _expand(VOLUME)
	var declarations := _parameter_block(volume)
	var passes: String = (load(PASSES) as ShaderInclude).code
	var samplers := ""
	var binding := 1
	for name in SAMPLERS:
		samplers += "layout(set = 0, binding = %d) uniform %s %s;\n" % [binding, SAMPLERS[name], name]
		binding += 1
	for bounded in [false, true]:
		for pass_name in ["MARCH", "REVEAL"]:
			var code := "#version 450\n#define CLOUD_%s\n%s%s%s%s\n%s" % [pass_name,
				"#define CLOUD_OCCUPANCY\n" if bounded else "", declarations, samplers, _strip_uniforms(volume), passes]
			var shader := _compile(code, pass_name.to_lower())
			if not shader.is_valid():
				return
			var shaders: Dictionary = _march_shaders if pass_name == "MARCH" else _reveal_shaders
			var pipelines: Dictionary = _march_pipelines if pass_name == "MARCH" else _reveal_pipelines
			shaders[bounded] = shader
			pipelines[bounded] = _rd.compute_pipeline_create(shader)
	_resolve_shader = _compile("#version 450\n#define CLOUD_RESOLVE\n%s\n%s" % [declarations, passes], "resolve")
	if not _resolve_shader.is_valid():
		return
	_resolve_pipeline = _rd.compute_pipeline_create(_resolve_shader)
	var bytes := PackedFloat32Array()
	bytes.resize(_slot_count * 4)
	_buffer = _rd.uniform_buffer_create(bytes.size() * 4, bytes.to_byte_array())
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_sampler = _rd.sampler_create(state)
	# Procedural weather binds no map.
	_blank_2d = _image(Vector2i.ONE, RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM)
	compiled = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		# Freeing a shader also frees its pipelines and cached uniform sets.
		for rid in _images.values() + _march_shaders.values() + _reveal_shaders.values() + [_resolve_shader, _buffer, _sampler, _blank_2d]:
			if rid.is_valid(): _rd.free_rid(rid)

## Source of a shader include with its includes inlined.
static func _expand(path: String) -> String:
	var code := ""
	for line in (load(path) as ShaderInclude).code.split("\n"):
		if line.strip_edges().begins_with("#include"):
			code += _expand(line.get_slice("\"", 1)) + "\n"
		else:
			code += line + "\n"
	return code

static func _uniform_pattern() -> RegEx:
	return RegEx.create_from_string("(?m)^\\s*uniform\\s+(\\w+)\\s+(\\w+)[^;]*;")

static func _strip_uniforms(code: String) -> String:
	return _uniform_pattern().sub(code, "", true)

## The parameter buffer and a macro per value naming its slot, so the volume's
## Godot-language code reads its uniforms unchanged.
func _parameter_block(volume: String) -> String:
	var entries := []
	for match in _uniform_pattern().search_all(volume):
		if not SAMPLERS.has(match.get_string(2)):
			entries.append([match.get_string(2), match.get_string(1)])
	entries.append_array(FRAME_PARAMETERS)
	var macros := ""
	for entry in entries:
		var slot := _slot_count
		var type: String = entry[1]
		_layout.append([entry[0], type, slot])
		_slot_count += SLOTS[type]
		var expression: String
		match type:
			"float": expression = "P[%d].x" % slot
			"int": expression = "int(P[%d].x)" % slot
			"bool": expression = "(P[%d].x > 0.5)" % slot
			"vec2": expression = "P[%d].xy" % slot
			"vec3": expression = "P[%d].xyz" % slot
			"mat3": expression = "mat3(P[%d].xyz, P[%d].xyz, P[%d].xyz)" % [slot, slot + 1, slot + 2]
			"mat4": expression = "mat4(P[%d], P[%d], P[%d], P[%d])" % [slot, slot + 1, slot + 2, slot + 3]
		macros += "#define %s (%s)\n" % [entry[0], expression]
	return "layout(set = 0, binding = 0, std140) uniform CloudParameters { vec4 P[%d]; };\n%s" % [_slot_count, macros]

## Names and types of the volume uniforms the buffer carries.
func volume_parameters() -> Array:
	return _layout.filter(func(entry: Array) -> bool: return not FRAME_PARAMETERS.any(func(frame: Array) -> bool: return frame[0] == entry[0]))

func _compile(code: String, label: String) -> RID:
	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = code
	var spirv := _rd.shader_compile_spirv_from_source(source)
	if spirv.compile_error_compute != "":
		push_error("Cloud %s pass failed to compile:\n%s" % [label, spirv.compile_error_compute])
		return RID()
	return _rd.shader_create_from_spirv(spirv, "Cloud " + label)

func _image(size: Vector2i, format: int) -> RID:
	var description := RDTextureFormat.new()
	description.width = size.x
	description.height = size.y
	description.format = format
	description.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var rid := _rd.texture_create(description, RDTextureView.new(), [])
	_rd.texture_clear(rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
	return rid

func _free_images() -> void:
	output.texture_rd_rid = RID()
	for rid in _images.values():
		_rd.free_rid(rid)
	_images.clear()

func _allocate(size: Vector2i, march_size: Vector2i) -> void:
	_free_images()
	var color := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	var depth := RenderingDevice.DATA_FORMAT_R32_SFLOAT
	_images = {
		"fresh_color": _image(march_size, color), "fresh_depth": _image(march_size, depth),
		"history_color": _image(size, color), "history_depth": _image(size, depth),
		"out_color": _image(size, color), "out_depth": _image(size, depth),
		"reveal_color": _image((size + Vector2i.ONE) / 2, color), "reveal_depth": _image((size + Vector2i.ONE) / 2, depth),
	}
	output.texture_rd_rid = _images.out_color
	_size = size
	_march_size = march_size

## Sizes the images and fills the parameter buffer for this frame. values maps
## every buffer name to its value; textures maps SAMPLERS names to Textures.
func prepare(size: Vector2i, grid: int, values: Dictionary, bounded: bool, textures: Dictionary) -> void:
	_runnable = false
	if not compiled:
		return
	var march_size := (size + Vector2i.ONE * (grid - 1)) / grid
	if size != _size or march_size != _march_size:
		_allocate(size, march_size)
	var data := PackedFloat32Array()
	data.resize(_slot_count * 4)
	for entry in _layout:
		_pack(data, entry[2] * 4, entry[1], values.get(entry[0]))
	_rd.buffer_update(_buffer, 0, data.size() * 4, data.to_byte_array())
	_bounded = bounded
	for name in SAMPLERS:
		var texture: Texture = textures.get(name)
		var rid := RenderingServer.texture_get_rd_texture(texture.get_rid()) if texture != null else RID()
		if not rid.is_valid():
			# A noise texture still generating; the weather map may be absent.
			if name != "cloud_weather_map": return
			rid = _blank_2d
		_texture_rids[name] = rid
	_runnable = true

static func _pack(data: PackedFloat32Array, at: int, type: String, value: Variant) -> void:
	if value == null:
		return
	match type:
		"float", "int": data[at] = float(value)
		"bool": data[at] = 1.0 if value else 0.0
		"vec2":
			data[at] = value.x
			data[at + 1] = value.y
		"vec3":
			data[at] = value.x
			data[at + 1] = value.y
			data[at + 2] = value.z
		"mat3":
			var basis: Basis = value
			for column in range(3):
				var axis: Vector3 = basis[column]
				for row in range(3): data[at + column * 4 + row] = axis[row]
		"mat4":
			var projection: Projection = value
			for column in range(4):
				var axis: Vector4 = projection[column]
				for row in range(4): data[at + column * 4 + row] = axis[row]

func _uniform(type: int, binding: int, ids: Array) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for id in ids: uniform.add_id(id)
	return uniform

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if not _runnable:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null or buffers.get_internal_size() != _size:
		return
	var image := RenderingDevice.UNIFORM_TYPE_IMAGE
	var march_shader: RID = _march_shaders[_bounded]
	var march_set := UniformSetCacheRD.get_cache(march_shader, 0, [
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_sampler, _texture_rids.cloud_noise]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_sampler, _texture_rids.cloud_detail_noise]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_sampler, _texture_rids.cloud_weather_map]),
		_uniform(image, 4, [_images.fresh_color]),
		_uniform(image, 5, [_images.fresh_depth]),
	])
	var reveal_shader: RID = _reveal_shaders[_bounded]
	var reveal_set := UniformSetCacheRD.get_cache(reveal_shader, 0, [
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_sampler, _texture_rids.cloud_noise]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_sampler, _texture_rids.cloud_detail_noise]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_sampler, _texture_rids.cloud_weather_map]),
		_uniform(image, 4, [_images.reveal_color]),
		_uniform(image, 5, [_images.reveal_depth]),
		_uniform(image, 6, [_images.history_depth]),
	])
	var resolve_set := UniformSetCacheRD.get_cache(_resolve_shader, 0, [
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_buffer]),
		_uniform(image, 1, [_images.fresh_color]),
		_uniform(image, 2, [_images.fresh_depth]),
		_uniform(image, 3, [_images.history_color]),
		_uniform(image, 4, [_images.history_depth]),
		_uniform(image, 5, [_images.out_color]),
		_uniform(image, 6, [_images.out_depth]),
		_uniform(image, 7, [_images.reveal_color]),
		_uniform(image, 8, [_images.reveal_depth]),
	])
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _march_pipelines[_bounded])
	_rd.compute_list_bind_uniform_set(list, march_set, 0)
	_rd.compute_list_dispatch(list, ceili(_march_size.x / 8.0), ceili(_march_size.y / 8.0), 1)
	# Most reveal threads find exact history and return at once.
	_rd.compute_list_bind_compute_pipeline(list, _reveal_pipelines[_bounded])
	_rd.compute_list_bind_uniform_set(list, reveal_set, 0)
	_rd.compute_list_dispatch(list, ceili(_size.x / 16.0), ceili(_size.y / 16.0), 1)
	_rd.compute_list_add_barrier(list)
	_rd.compute_list_bind_compute_pipeline(list, _resolve_pipeline)
	_rd.compute_list_bind_uniform_set(list, resolve_set, 0)
	_rd.compute_list_dispatch(list, ceili(_size.x / 8.0), ceili(_size.y / 8.0), 1)
	_rd.compute_list_end()
	# This frame's result is the next frame's history.
	var extent := Vector3(_size.x, _size.y, 1)
	_rd.texture_copy(_images.out_color, _images.history_color, Vector3.ZERO, Vector3.ZERO, extent, 0, 0, 0, 0)
	_rd.texture_copy(_images.out_depth, _images.history_depth, Vector3.ZERO, Vector3.ZERO, extent, 0, 0, 0, 0)
