extends CompositorEffect
## GPU half of the cloud renderer (docs/CLOUDS.md). Before the transparent
## pass, two compute dispatches run at half the internal resolution:
##   march    integrates cloud light along every view ray, stopping at the
##            nearest scene geometry, into a fresh light target and a depth
##            target (front, mean and end distances of the cloud, km);
##   resolve  blends the fresh light with last frame's result, reprojected
##            through the cloud's mean depth and clamped to the fresh
##            neighbourhood, into the display target. A copy keeps it as the
##            next frame's history.
## cloud_composite.gdshader upsamples the display and depth targets in the
## transparent pass. The march jitters its samples every frame; the resolve
## averages that noise away.
##
## Targets are created on the main thread (ensure_targets) so materials can
## bind them through Texture2DRD; the render callback only dispatches.

const FIELD := preload("res://assets/shaders/cloud_field.gdshaderinc")

const MARCH_SOURCE := """
#version 450
#define CLOUD_COMPUTE
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform CloudField {
	vec4 cloud_radii;
	vec4 cloud_params;
	vec4 cloud_evolution;
	vec4 cloud_sun;
	vec4 cloud_air;
};
layout(set = 0, binding = 1) uniform sampler3D cloud_shape_noise;
layout(set = 0, binding = 2) uniform sampler3D cloud_detail_noise;
layout(set = 0, binding = 3) uniform sampler2D cloud_weather_map;

#include_field

layout(set = 1, binding = 0, std140) uniform Frame {
	mat4 inv_projection;
	mat4 view_to_cloud;
	mat4 cloud_to_previous_view;
	mat4 previous_projection;
	vec4 camera_cloud;   // camera in the cloud frame (km); w: radius the march stops at
	vec4 motion;         // camera travel in the cloud frame since last frame (km); w: history valid
	vec4 sizes;          // march width, height; scene width, height
	vec4 frame_info;     // frame index, cost view, detail range (km), unused
};
layout(set = 1, binding = 1) uniform sampler2D scene_depth;
layout(set = 1, binding = 2, rgba16f) uniform restrict writeonly image2D fresh_light;
layout(set = 1, binding = 3, rgba32f) uniform restrict writeonly image2D cloud_depth;

const int MAX_STEPS = 256;

// Base step (km) at distance t: short near the camera, longer far away, but
// never so long that a far cloud is sampled by only a slice or two.
float step_at(float t, float fine, float coarse) {
	return clamp(0.03 + 0.006 * t, fine, coarse);
}

// The projection is the one the scene was drawn with: Vulkan's screen axes
// and reversed depth (1 at the near plane, 0 for sky) are built in.
vec3 view_ray(vec2 uv) {
	vec4 v = inv_projection * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	return normalize(mat3(view_to_cloud) * (v.xyz / v.w));
}

// Distance (km) to the nearest scene geometry among the full-resolution
// pixels this texel covers; 1e9 where there is only sky.
float scene_clip(ivec2 texel) {
	ivec2 scene = ivec2(sizes.zw);
	float nearest = 1e9;
	for (int i = 0; i < 4; i++) {
		ivec2 pixel = min(texel * 2 + ivec2(i & 1, i >> 1), scene - 1);
		float depth = texelFetch(scene_depth, pixel, 0).r;
		if (depth <= 0.0) { continue; }
		vec2 uv = (vec2(pixel) + 0.5) / sizes.zw;
		vec4 v = inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
		nearest = min(nearest, length(v.xyz / v.w) * 0.001);
	}
	return nearest;
}

// Independent pixel seeds avoid diagonal bands in partially covered cloud.
// A golden-ratio temporal sequence fills each ray interval evenly.
float jitter_at(vec2 pixel, float frame) {
	uvec2 cell = uvec2(pixel);
	uint seed = cell.x * 1973u + cell.y * 9277u + 89173u;
	seed = (seed ^ (seed >> 16u)) * 2246822519u;
	seed = (seed ^ (seed >> 13u)) * 3266489917u;
	seed ^= seed >> 16u;
	return fract(float(seed & 0x00ffffffu) / 16777216.0 + mod(frame, 4096.0) * 0.61803398875);
}

vec3 cost_color(float taps) {
	if (taps < 8.0) { return vec3(0.6); }
	if (taps < 16.0) { return vec3(0.0, 0.1, 1.0); }
	if (taps < 32.0) { return vec3(0.0, 0.8, 1.0); }
	if (taps < 64.0) { return vec3(0.0, 1.0, 0.2); }
	if (taps < 128.0) { return vec3(1.0, 1.0, 0.0); }
	if (taps < 256.0) { return vec3(1.0, 0.45, 0.0); }
	if (taps < 512.0) { return vec3(1.0, 0.0, 0.0); }
	return vec3(1.0, 0.0, 1.0);
}

void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	if (texel.x >= int(sizes.x) || texel.y >= int(sizes.y)) { return; }
	vec2 uv = (vec2(texel) + 0.5) / sizes.xy;
	vec3 ray = view_ray(uv);
	vec3 origin = camera_cloud.xyz;
	float clip = scene_clip(texel);

	vec3 light = vec3(0.0);
	float transmittance = 1.0;
	float front = -1.0;
	float weight_sum = 0.0;
	float distance_sum = 0.0;
	float end = 0.0;
	float clipped = 0.0;
	float taps = 0.0;

	// The shell between the cloud base and the highest cloud top.
	vec2 outer = cloud_sphere_hits(origin, ray, camera_cloud.w);
	float start = max(outer.x, 0.0);
	float stop = outer.y;
	vec2 ground = cloud_sphere_hits(origin, ray, cloud_radii.x);
	if (ground.y > ground.x && ground.x > 0.0) { stop = min(stop, ground.x); }
	vec2 inner = cloud_sphere_hits(origin, ray, cloud_radii.y);
	float r0 = length(origin);
	// Below the base the ray starts where it leaves the inner sphere. From
	// above, a ray dipping through the inner sphere skips the clear air there.
	vec2 gap = vec2(-1.0);
	if (r0 < cloud_radii.y) { start = max(start, inner.y); }
	else if (inner.y > inner.x && inner.x > start) { gap = inner; }
	if (clip < stop) { stop = clip; clipped = 1.0; }

	if (outer.y > 0.0 && stop > start) {
		float path = stop - start;
		if (gap.x > 0.0 && gap.x < stop) { path -= min(gap.y, stop) - gap.x; }
		// Steps grow with distance; the path's own length bounds them so a thin
		// layer seen from orbit still gets a few dozen samples.
		// Long horizon paths must not force kilometre-sized steps nearby.
		float fine = clamp(path / 160.0, 0.02, 0.06);
		float coarse = max(path / 48.0, fine);
		float jitter = jitter_at(vec2(texel), frame_info.x);
		float t = start + step_at(start, fine, coarse) * jitter;
		int empty = 0;
		float stride = 0.0;
		// After stepping from clear air into cloud the march backs up and
		// approaches again in short steps until refine_until.
		float refine_until = -1.0;
		vec3 sunlight = vec3(0.0);
		vec3 ambient = vec3(0.0);
		float lit_at = -1e9;
		float sun_depth = -1.0;
		vec4 w = vec4(0.0);
		float weather_at = -1e9;
		float cosine = dot(ray, cloud_sun.xyz);
		float sigma_scale = CLOUD_EXTINCTION * cloud_params.y;
		// Angle one march texel spans, and the shape volume's voxel, for its mip.
		float texel_angle = length(view_ray(uv + vec2(0.0, 1.0 / sizes.y)) - ray);
		float voxel_km = CLOUD_SHAPE_KM / float(textureSize(cloud_shape_noise, 0).x);
		// Where a ray from above enters the low formations' top.
		vec2 low_hits = cloud_sphere_hits(origin, ray, cloud_radii.z);
		float low_entry = r0 > cloud_radii.z && low_hits.y > low_hits.x ? low_hits.x : -1.0;
		for (int i = 0; i < MAX_STEPS; i++) {
			if (t >= stop) { break; }
			if (gap.x > 0.0 && t > gap.x && t < gap.y) { t = gap.y + step_at(gap.y, fine, coarse) * jitter; continue; }
			float step_km = step_at(t, fine, coarse);
			vec3 p = origin + ray * t;
			float r = length(p);
			// In the low formations no stride may climb more than a tenth of
			// their depth, or a thin sheet could fall between two samples.
			float stride_cap = 1e9;
			if (r < cloud_radii.z) {
				stride_cap = (cloud_radii.z - cloud_radii.y) * 0.1 / max(abs(dot(ray, p / r)), 0.03);
				step_km = min(step_km, stride_cap);
			}
			bool refining = t < refine_until;
			if (refining) { step_km = max(step_km * mix(0.25, 0.5, smoothstep(10.0, 100.0, t)), 0.012); }
			// Painted weather changes over kilometres; refresh it every half.
			if (abs(t - weather_at) > 0.5) {
				w = cloud_weather(p);
				weather_at = t;
			}
			// Where the weather allows no cloud, nothing can start within a few
			// kilometres across it (half a weather texel): jump ahead that far,
			// or from the storm band straight down to the low formations.
			bool storm_free = w.a <= CLOUD_STORM_MIN;
			bool low_free = w.r + w.g + w.b <= 0.0;
			if (storm_free && (low_free || r >= cloud_radii.z) && !refining) {
				float across = sqrt(max(1.0 - pow(dot(ray, p / r), 2.0), 0.0));
				float next = t + 3.0 / max(across, 1e-3);
				if (!low_free && low_entry > t) { next = min(next, low_entry); }
				// A fresh jitter after every jump, or the samples beyond it would
				// sit at the same depths each frame and slice far cloud into bands.
				t = max(next, t + step_km);
				t += step_at(t, fine, coarse) * jitter;
				weather_at = -1e9;
				// Never back up across a jump: the march approaches what lies
				// below in ordinary capped strides.
				stride = 0.0;
				empty = 0;
				continue;
			}
			float light_height;
			float detail = 1.0 - smoothstep(frame_info.z * 0.5, frame_info.z, t);
			// Blur only once a texel spans several voxels: closer, the seams
			// between cells are what make a deck read as cloud, not a sheet.
			float lod = clamp(log2(max(t * texel_angle / voxel_km, 1.0)) - 1.5, 0.0, 4.0);
			float density = cloud_density(p, w, detail, lod, light_height);
			taps += 1.0;
			if (density <= 0.0) {
				// Clear air: lengthen the stride a little at a time.
				empty += 1;
				stride = refining ? step_km : min(step_km * min(1.0 + float(empty) * 0.3, 2.5), max(stride_cap, step_km));
				t += stride;
				continue;
			}
			if (empty > 0 && !refining && stride > 0.03) {
				refine_until = t + step_km;
				t = max(t - stride, start) + step_km * 0.25 * jitter;
				empty = 0;
				continue;
			}
			empty = 0;
			float sigma = density * sigma_scale;
			// Keep each step's optical depth near one: a jittered step through
			// dense cloud would otherwise flip between clear and opaque.
			float dt = min(step_km, max(0.9 / sigma, 0.012 + t * 0.0004));
			if (abs(t - lit_at) > 40.0) {
				// Sunlight changes slowly; refresh it only across long rays.
				sunlight = cloud_sunlight(p);
				ambient = cloud_ambient(p, sunlight);
				lit_at = t;
			}
			if (front < 0.0) { front = t; }
			// Deep in, a sample adds little light: keep the last shadow estimate.
			if (transmittance > 0.15 || sun_depth < 0.0) {
				sun_depth = dot(sunlight, sunlight) > 0.0 ? cloud_sun_depth(p, w, cloud_sun.xyz, jitter, lod) : 0.0;
				taps += 4.0;
			}
			vec3 radiance = cloud_scatter(sun_depth, cosine, sunlight, ambient, light_height, density);
			float opacity = 1.0 - exp(-sigma * dt);
			float contribution = transmittance * opacity;
			light += radiance * contribution;
			distance_sum += t * contribution;
			weight_sum += contribution;
			transmittance *= 1.0 - opacity;
			if (transmittance < 0.01) {
				transmittance = 0.0;
				end = t;
				clipped = 0.0;
				break;
			}
			t += dt;
		}
		if (end <= 0.0) { end = stop; }
	}
	float mean = weight_sum > 0.0 ? distance_sum / weight_sum : -1.0;
	if (frame_info.y > 0.5) {
		light = cost_color(taps);
		transmittance = 0.0;
	}
	imageStore(fresh_light, texel, vec4(light, transmittance));
	imageStore(cloud_depth, texel, vec4(front, mean, end, clipped));
}
"""

const RESOLVE_SOURCE := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform Frame {
	mat4 inv_projection;
	mat4 view_to_cloud;
	mat4 cloud_to_previous_view;
	mat4 previous_projection;
	vec4 camera_cloud;
	vec4 motion;
	vec4 sizes;
	vec4 frame_info;
};
layout(set = 0, binding = 1) uniform sampler2D fresh_light;
layout(set = 0, binding = 2) uniform sampler2D cloud_depth;
layout(set = 0, binding = 3) uniform sampler2D history_light;
layout(set = 0, binding = 4, rgba16f) uniform restrict writeonly image2D display_light;

// Share of last frame kept where its reprojection is trusted.
const float HISTORY = 0.9;

void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(sizes.xy);
	if (texel.x >= size.x || texel.y >= size.y) { return; }
	vec4 fresh = texelFetch(fresh_light, texel, 0);
	if (motion.w < 0.5) {
		imageStore(display_light, texel, fresh);
		return;
	}
	// Where the cloud is: its mean depth, else where the march ended.
	vec4 depth = texelFetch(cloud_depth, texel, 0);
	float distance_km = depth.y > 0.0 ? depth.y : max(depth.z, 1.0);
	vec2 uv = (vec2(texel) + 0.5) / sizes.xy;
	vec4 v = inv_projection * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 ray = normalize(mat3(view_to_cloud) * (v.xyz / v.w));
	// The same cloud point, relative to last frame's camera.
	vec3 previous = mat3(cloud_to_previous_view) * (ray * distance_km + motion.xyz);
	vec4 projected = previous_projection * vec4(previous * 1000.0, 1.0);
	vec4 result = fresh;
	if (projected.w > 0.0) {
		vec2 ndc = projected.xy / projected.w;
		vec2 previous_uv = ndc * 0.5 + 0.5;
		if (all(greaterThanEqual(previous_uv, vec2(0.0))) && all(lessThanEqual(previous_uv, vec2(1.0)))) {
			vec4 history = textureLod(history_light, previous_uv, 0.0);
			// Clamp the history to what this frame's neighbourhood allows.
			vec4 mean = vec4(0.0);
			vec4 square = vec4(0.0);
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					vec4 c = texelFetch(fresh_light, clamp(texel + ivec2(x, y), ivec2(0), size - 1), 0);
					mean += c;
					square += c * c;
				}
			}
			mean /= 9.0;
			vec4 spread = sqrt(max(square / 9.0 - mean * mean, vec4(0.0)));
			history = clamp(history, mean - spread * 2.0, mean + spread * 2.0);
			result = mix(fresh, history, HISTORY);
		}
	}
	imageStore(display_light, texel, result);
}
"""

## Uniform values for the CloudField block, as the layer last set them.
var field_values := PackedFloat32Array()
var weather_texture: Texture2D
var shape_texture: Texture3D
var detail_texture: Texture3D
## Cloud frame for this frame: planet centre and world-to-cloud rotation,
## captured just before drawing (cloud_layer.gd).
var planet_origin := Vector3.ZERO
var world_to_cloud := Basis.IDENTITY
## Radius (km) the march stops at: storm tops, or the low formations' tops.
var march_top_km := 0.0
## Distance (km) beyond which fine erosion fades out.
var detail_range_km := 40.0
var cost_view := false
## Sampled by the composite. New objects whenever the targets are made, so
## materials bind the real textures rather than a placeholder;
## targets_revision counts them.
var light_texture: Texture2DRD
var depth_texture: Texture2DRD
var targets_revision := 0
## Internal size of the last scene this pass was asked to draw, for the
## layer to size the targets from.
var observed_scene_size := Vector2i.ZERO
## Frames dispatched, for tests and diagnostics.
var dispatched := 0

var _rd: RenderingDevice
var _march_shader := RID()
var _march_pipeline := RID()
var _resolve_shader := RID()
var _resolve_pipeline := RID()
var _linear_repeat := RID()
var _linear_clamp := RID()
var _nearest := RID()
var _weather_sampler := RID()
var _field_buffer := RID()
var _frame_buffer := RID()
var _fresh := RID()
var _depth := RID()
var _display := RID()
var _history := RID()
var _target_size := Vector2i.ZERO
var _scene_size := Vector2i.ZERO
var _placeholder: ImageTexture
var _frame_index := 0
var _last_drawn := -10
var _previous_valid := false
var _previous_camera := Vector3.ZERO
var _previous_view_to_cloud := Basis.IDENTITY
var _previous_projection := Projection.IDENTITY

const FRAME_FLOATS := 16 * 4 + 4 * 4

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	access_resolved_depth = true
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		enabled = false
		return
	_linear_repeat = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT, RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT, true)
	_linear_clamp = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	_nearest = _sampler(RenderingDevice.SAMPLER_FILTER_NEAREST, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	# Longitude wraps, latitude stops at the poles.
	_weather_sampler = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	_field_buffer = _rd.uniform_buffer_create(5 * 16)
	_frame_buffer = _rd.uniform_buffer_create(FRAME_FLOATS * 4)
	_placeholder = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	_march_shader = _compile(MARCH_SOURCE.replace("#include_field", FIELD.code), "march")
	_resolve_shader = _compile(RESOLVE_SOURCE, "resolve")
	if _march_shader.is_valid(): _march_pipeline = _rd.compute_pipeline_create(_march_shader)
	if _resolve_shader.is_valid(): _resolve_pipeline = _rd.compute_pipeline_create(_resolve_shader)
	if not _march_pipeline.is_valid() or not _resolve_pipeline.is_valid():
		enabled = false

## Whether this renderer can run the pass at all.
static func supported() -> bool:
	return RenderingServer.get_rendering_device() != null \
		and RenderingServer.get_current_rendering_method() == "forward_plus"

## Whether the pipelines compiled and targets exist.
func is_ready() -> bool:
	return _rd != null and _march_pipeline.is_valid() and _resolve_pipeline.is_valid() and _fresh.is_valid()

func _sampler(filter: int, repeat_u: int, repeat_v: int, mipmaps: bool = false) -> RID:
	var state := RDSamplerState.new()
	state.mag_filter = filter
	state.min_filter = filter
	if mipmaps: state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.repeat_u = repeat_u
	state.repeat_v = repeat_v
	state.repeat_w = repeat_u
	return _rd.sampler_create(state)

func _compile(source_text: String, label: String) -> RID:
	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = source_text
	var spirv := _rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		push_error("Cloud %s shader failed to compile: %s" % [label, spirv.compile_error_compute])
		return RID()
	return _rd.shader_create_from_spirv(spirv, "Cloud " + label)

## (Re)creates the targets for a scene of scene_size internal pixels.
func ensure_targets(scene_size: Vector2i) -> void:
	if _rd == null or scene_size.x <= 0 or scene_size.y <= 0: return
	if scene_size == _scene_size: return
	_free_targets()
	var size := Vector2i((scene_size + Vector2i.ONE) / 2)
	_fresh = _target(size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Color(0, 0, 0, 1))
	_display = _target(size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Color(0, 0, 0, 1))
	_history = _target(size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Color(0, 0, 0, 1))
	_depth = _target(size, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, Color(-1, -1, 0, 0))
	light_texture = Texture2DRD.new()
	light_texture.texture_rd_rid = _display
	depth_texture = Texture2DRD.new()
	depth_texture.texture_rd_rid = _depth
	targets_revision += 1
	_target_size = size
	_scene_size = scene_size
	_previous_valid = false

func target_size() -> Vector2i:
	return _target_size

func _target(size: Vector2i, format_id: int, clear: Color) -> RID:
	var format := RDTextureFormat.new()
	format.width = size.x
	format.height = size.y
	format.format = format_id
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var rid := _rd.texture_create(format, RDTextureView.new())
	_rd.texture_clear(rid, clear, 0, 1, 0, 1)
	return rid

## Forget the previous frame, so the next one starts from fresh samples.
func reset_history() -> void:
	_previous_valid = false

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT or _rd == null: return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data()
	if buffers == null or scene == null: return
	observed_scene_size = buffers.get_internal_size()
	# Targets follow the scene on the main thread; skip until they match.
	if observed_scene_size != _scene_size or _fresh == RID(): return
	if field_values.size() != 20 or shape_texture == null or detail_texture == null: return
	_rd.buffer_update(_field_buffer, 0, field_values.size() * 4, field_values.to_byte_array())

	var camera := scene.get_cam_transform()
	var projection := scene.get_cam_projection()
	var view_to_cloud := (world_to_cloud * camera.basis).orthonormalized()
	# Double precision on the CPU: the camera relative to the planet centre.
	var camera_cloud := world_to_cloud * ((camera.origin - planet_origin) * 0.001)
	var drawn := Engine.get_frames_drawn()
	var motion := camera_cloud - _previous_camera
	# History survives ordinary flight; a cut, a jump or a skipped frame
	# (map view, hidden clouds) starts over.
	var valid := _previous_valid and drawn - _last_drawn <= 2 and motion.length() < maxf(2.0, (camera_cloud.length() - march_top_km) * 0.25) and not cost_view
	var frame := PackedFloat32Array()
	frame.resize(FRAME_FLOATS)
	_put_projection(frame, 0, projection.inverse())
	_put_basis(frame, 16, view_to_cloud)
	_put_basis(frame, 32, _previous_view_to_cloud.transposed())
	_put_projection(frame, 48, _previous_projection)
	_put_vector(frame, 64, camera_cloud, march_top_km)
	_put_vector(frame, 68, motion, 1.0 if valid else 0.0)
	_put_vector(frame, 72, Vector3(_target_size.x, _target_size.y, _scene_size.x), _scene_size.y)
	_put_vector(frame, 76, Vector3(_frame_index, 1.0 if cost_view else 0.0, detail_range_km), 0.0)
	_rd.buffer_update(_frame_buffer, 0, frame.size() * 4, frame.to_byte_array())

	var weather: Texture2D = weather_texture if weather_texture != null else _placeholder
	# A texture made this frame may not reach the device until the next one.
	for texture in [shape_texture, detail_texture, weather]:
		if not _rd.texture_is_valid(_rd_texture(texture)): return
	var field_uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_field_buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_linear_repeat, _rd_texture(shape_texture)]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_linear_repeat, _rd_texture(detail_texture)]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_weather_sampler, _rd_texture(weather)]),
	]
	var march_uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_frame_buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_nearest, buffers.get_depth_layer(0)]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 2, [_fresh]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 3, [_depth]),
	]
	var resolve_uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_frame_buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_nearest, _fresh]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_nearest, _depth]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_linear_clamp, _history]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 4, [_display]),
	]
	var field_set := UniformSetCacheRD.get_cache(_march_shader, 0, field_uniforms)
	var march_set := UniformSetCacheRD.get_cache(_march_shader, 1, march_uniforms)
	var resolve_set := UniformSetCacheRD.get_cache(_resolve_shader, 0, resolve_uniforms)
	var groups := Vector2i((_target_size.x + 7) / 8, (_target_size.y + 7) / 8)
	_rd.capture_timestamp("Clouds: march")
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _march_pipeline)
	_rd.compute_list_bind_uniform_set(list, field_set, 0)
	_rd.compute_list_bind_uniform_set(list, march_set, 1)
	_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
	_rd.compute_list_end()
	_rd.capture_timestamp("Clouds: resolve")
	list = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _resolve_pipeline)
	_rd.compute_list_bind_uniform_set(list, resolve_set, 0)
	_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
	_rd.compute_list_end()
	_rd.texture_copy(_display, _history, Vector3.ZERO, Vector3.ZERO, Vector3(_target_size.x, _target_size.y, 1), 0, 0, 0, 0)
	_rd.capture_timestamp("Clouds: done")

	_previous_valid = true
	_previous_camera = camera_cloud
	_previous_view_to_cloud = view_to_cloud
	_previous_projection = projection
	_last_drawn = drawn
	_frame_index += 1
	dispatched += 1

## GPU milliseconds of the most recently captured march and resolve, from
## this pass's timestamps; -1 when the last frame captured none.
static func captured_gpu_ms() -> float:
	var rd := RenderingServer.get_rendering_device()
	if rd == null: return -1.0
	var start := -1
	for i in range(rd.get_captured_timestamps_count()):
		var label := rd.get_captured_timestamp_name(i)
		if label == "Clouds: march": start = i
		elif label == "Clouds: done" and start >= 0:
			return (rd.get_captured_timestamp_gpu_time(i) - rd.get_captured_timestamp_gpu_time(start)) / 1e6
	return -1.0

static func _rd_texture(texture: Texture) -> RID:
	return RenderingServer.texture_get_rd_texture(texture.get_rid())

static func _uniform(type: int, binding: int, ids: Array) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for id in ids: uniform.add_id(id)
	return uniform

static func _put_projection(target: PackedFloat32Array, offset: int, value: Projection) -> void:
	for column in 4:
		var c: Vector4 = value[column]
		for row in 4: target[offset + column * 4 + row] = c[row]

# A basis as a column-major mat4 (std140 mat3 columns are padded anyway).
static func _put_basis(target: PackedFloat32Array, offset: int, value: Basis) -> void:
	for column in 3:
		var c: Vector3 = value[column]
		for row in 3: target[offset + column * 4 + row] = c[row]
	target[offset + 15] = 1.0

static func _put_vector(target: PackedFloat32Array, offset: int, value: Vector3, w: float) -> void:
	target[offset] = value.x
	target[offset + 1] = value.y
	target[offset + 2] = value.z
	target[offset + 3] = w

func _free_targets() -> void:
	# Detach the wrappers first: a material still holding them must not
	# rebuild its uniforms around freed textures.
	for wrapper in [light_texture, depth_texture]:
		if wrapper != null: wrapper.texture_rd_rid = RID()
	light_texture = null
	depth_texture = null
	for rid in [_fresh, _display, _history, _depth]:
		if rid.is_valid(): _rd.free_rid(rid)
	_fresh = RID()
	_display = RID()
	_history = RID()
	_depth = RID()
	_target_size = Vector2i.ZERO
	_scene_size = Vector2i.ZERO

## Frees every GPU resource; the pass stays disabled afterwards. The layer
## calls this when it is deleted, since a Resource can outlive it.
func release() -> void:
	enabled = false
	if _rd == null: return
	_free_targets()
	# Freeing a shader frees its pipeline and cached uniform sets.
	for rid in [_march_shader, _resolve_shader, _linear_repeat, _linear_clamp, _nearest, _weather_sampler, _field_buffer, _frame_buffer]:
		if rid.is_valid(): _rd.free_rid(rid)
	_march_shader = RID()
	_resolve_shader = RID()
	_march_pipeline = RID()
	_resolve_pipeline = RID()
	_rd = null
