extends RefCounted
## GLSL compute source generated from the spatial cloud includes, so compute
## passes run the same density, lighting and integration code as the shaders.
##
## Each Godot uniform becomes a private global, filled at the start of a pass
## by cloud_load_params() from one vec4-per-slot storage buffer (binding 0 of
## set 0). Samplers take the following bindings in source order. The caller
## appends its own entry point and resources (set 1 onward).
const VOLUME_PATH := "res://assets/shaders/clouds_volume.gdshaderinc"
const PARAMS_BINDING := 0

## Parsed layout of the volume's uniforms: name -> {type, slot, default}.
var params := {}
## Slots in the parameter buffer, one vec4 each (mat3 uses three).
var slot_count := 0
## Sampler names in binding order (binding = index + 1).
var samplers: Array[String] = []
## Volume code with uniforms replaced, before any entry point.
var library := ""

static var _cached: RefCounted

static func shared() -> RefCounted:
	if _cached == null:
		_cached = load("res://scripts/cloud_volume_compute.gd").new()
		_cached._build()
	return _cached

func _build() -> void:
	var declarations := ""
	var body := ""
	var uniform := RegEx.create_from_string("^\\s*(global\\s+)?uniform\\s+(\\w+)\\s+(\\w+)\\s*(:[^=;]*)?(=\\s*([^;]+))?;")
	for line in _expanded(VOLUME_PATH).split("\n"):
		var found := uniform.search(line)
		if found == null:
			body += line + "\n"
			continue
		var type := found.get_string(2)
		var name := found.get_string(3)
		if type.begins_with("sampler"):
			samplers.append(name)
			declarations += "layout(set = 0, binding = %d) uniform %s %s;\n" % [samplers.size(), type, name]
			continue
		var size := 3 if type == "mat3" else 1
		params[name] = {"type": type, "slot": slot_count, "default": _parse_default(type, found.get_string(6))}
		slot_count += size
		declarations += "%s %s;\n" % [type, name]
	var loader := "void cloud_load_params() {\n"
	for name in params:
		var entry: Dictionary = params[name]
		var slot: int = entry.slot
		match entry.type:
			"float": loader += "\t%s = cloud_params[%d].x;\n" % [name, slot]
			"int": loader += "\t%s = int(cloud_params[%d].x);\n" % [name, slot]
			"bool": loader += "\t%s = cloud_params[%d].x != 0.0;\n" % [name, slot]
			"vec2": loader += "\t%s = cloud_params[%d].xy;\n" % [name, slot]
			"vec3": loader += "\t%s = cloud_params[%d].xyz;\n" % [name, slot]
			"vec4": loader += "\t%s = cloud_params[%d];\n" % [name, slot]
			"mat3": loader += "\t%s = mat3(cloud_params[%d].xyz, cloud_params[%d].xyz, cloud_params[%d].xyz);\n" % [name, slot, slot + 1, slot + 2]
			_: push_error("Cloud compute: unsupported uniform type %s %s" % [entry.type, name])
	loader += "}\n"
	library = """layout(set = 0, binding = %d, std430) restrict readonly buffer CloudVolumeParams { vec4 cloud_params[]; };
%s
// Compute has no implicit derivatives. The volume's textures carry no mipmaps,
// so explicit level 0 samples exactly what the fragment shaders read.
#define texture(s, p) textureLod(s, p, 0.0)
%s
#undef texture
%s""" % [PARAMS_BINDING, declarations, body, loader]

## Complete compute source: version, defines, the volume library, then main.
func source(defines: PackedStringArray, entry: String) -> String:
	var prefix := "#version 450\n"
	for define in defines: prefix += "#define %s\n" % define
	return prefix + library + entry

## Parameter buffer for the given uniform values; missing ones keep defaults.
func pack(values: Dictionary) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(slot_count * 4)
	for name in params:
		var entry: Dictionary = params[name]
		var value: Variant = values.get(name, entry.default)
		var base: int = entry.slot * 4
		match typeof(value):
			TYPE_BOOL: data[base] = 1.0 if value else 0.0
			TYPE_INT, TYPE_FLOAT: data[base] = float(value)
			TYPE_VECTOR2:
				data[base] = value.x
				data[base + 1] = value.y
			TYPE_VECTOR3:
				for i in 3: data[base + i] = value[i]
			TYPE_VECTOR4, TYPE_COLOR:
				for i in 4: data[base + i] = value[i]
			TYPE_BASIS:
				# Godot's mat3 uniforms take the basis axes as columns.
				for column in 3:
					for i in 3: data[base + column * 4 + i] = value[column][i]
	return data

static func _expanded(path: String) -> String:
	var text := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges().begins_with("#include \""):
			text += _expanded(line.get_slice('"', 1)) + "\n"
		else:
			text += line + "\n"
	return text

static func _parse_default(type: String, text: String) -> Variant:
	var numbers := PackedFloat32Array()
	for found in RegEx.create_from_string("-?[0-9]*\\.?[0-9]+(e-?[0-9]+)?").search_all(text.get_slice("(", 1) if "(" in text else text):
		numbers.append(found.get_string().to_float())
	match type:
		"bool": return text.strip_edges() == "true"
		"int": return int(numbers[0]) if numbers.size() > 0 else 0
		"float": return numbers[0] if numbers.size() > 0 else 0.0
		"vec2": return Vector2(numbers[0], numbers[1]) if numbers.size() >= 2 else Vector2.ZERO
		"vec3":
			if numbers.size() >= 3: return Vector3(numbers[0], numbers[1], numbers[2])
			return Vector3.ONE * numbers[0] if numbers.size() == 1 else Vector3.ZERO
		"mat3": return Basis.IDENTITY if text.is_empty() else Basis.IDENTITY
	return 0.0
