extends Node3D
## Reusable deployment visual; advanced by flight time so pause freezes the animation.
const PackedHousing = preload("res://assets/models/parachute_1/parachute_1.glb")
const CanopyCloth = preload("res://scripts/parachute_cloth.gd")
const HOUSING_SCALE := 0.53
const CAP_SEAM := 0.85
const ATTACHMENT_EYE := 0.64
const DURATION := 2.6
const TetherPhysics = preload("res://scripts/cap_tether.gd")
const CollapseBake = preload("res://scripts/chute_collapse_bake.gd")
const COLLAPSE_BAKE_PATH := "res://assets/models/parachute_1/collapse_bake.res"
# The live canopy's shape at touchdown blends into the baked collapse.
const COLLAPSE_BLEND_SECONDS := 0.5
var rope := TetherPhysics.new()
var cap_released := false
var housing: Node3D
var canopy: Node3D
var cap_pivot: Node3D
var tether: MultiMeshInstance3D
var elapsed := 0.0
var opened := false
var cut := false
var cut_root: Node3D
var canopy_attitude := Quaternion.IDENTITY
var surface_normal := Vector3.UP
var surface_offset := -2.565
var resting := false
# Terrain relief around the hull, in module space; see set_relief().
var relief := PackedFloat32Array()
var relief_size := 0
var relief_spacing := 1.0
var relief_axes := Basis.IDENTITY
# After touchdown the spent chute replays a baked collapse of the real cloth
# while it fades out, so landing costs no cloth simulation. A cut-away chute
# keeps simulating as it fades. Either way it stops once hidden.
const FADE_SECONDS := 1.2
var collapse_bake: Resource
var _replaying := false
var _replay_time := 0.0
var _canopy_offset := PackedVector3Array()
var _rope_offset := PackedVector3Array()
var fade_after_landing := true
var fade := 1.0
var _fade_materials: Array[BaseMaterial3D] = []

func _ready() -> void:
	housing = PackedHousing.instantiate()
	housing.scale = Vector3.ONE * HOUSING_SCALE
	add_child(housing)
	var cap := housing.find_child("Nose_cap", true, false) as Node3D
	assert(cap != null, "Parachute asset needs a separate nose cap")
	cap_pivot = Node3D.new()
	cap_pivot.position.y = CAP_SEAM * HOUSING_SCALE
	add_child(cap_pivot)
	cap.reparent(cap_pivot)
	if ResourceLoader.exists(COLLAPSE_BAKE_PATH):
		collapse_bake = load(COLLAPSE_BAKE_PATH)
	canopy = CanopyCloth.new()
	add_child(canopy)
	tether = MultiMeshInstance3D.new()
	var cord := CylinderMesh.new()
	cord.top_radius = 0.007
	cord.bottom_radius = 0.007
	cord.height = 1.0
	cord.radial_segments = 8
	var cord_mesh := ArrayMesh.new()
	cord_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cord.get_mesh_arrays())
	tether.multimesh = MultiMesh.new()
	tether.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	tether.multimesh.mesh = cord_mesh
	tether.multimesh.instance_count = TetherPhysics.SEGMENTS
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("99988d")
	cloth.roughness = 0.95
	tether.material_override = cloth
	add_child(tether)
	advance(false, 0.0)

func advance(deployed: bool, delta: float, landed: bool = false, visual_delta: float = -1.0) -> void:
	# Deployment follows simulation time; cosmetic cloth/cap use real frame time.
	var motion_delta := delta if visual_delta < 0.0 else visual_delta
	if not deployed and not cut and fade < 1.0:
		_set_fade(1.0)
		_replaying = false
	elif fade_after_landing and (cut or (deployed and landed)):
		_set_fade(move_toward(fade, 0.0, maxf(motion_delta, 0.0) / FADE_SECONDS))
		if fade <= 0.0: return
		if not cut and _replay_collapse(motion_delta): return
	if cut:
		canopy.advance(motion_delta, true)
		rope.advance(motion_delta, false, cap_pivot.position, cap_pivot.basis.y)
		cap_pivot.position = rope.points[TetherPhysics.SEGMENTS]
		var axis := (rope.points[TetherPhysics.SEGMENTS + 1] - cap_pivot.position).normalized()
		cap_pivot.quaternion = Quaternion(Vector3.UP, axis)
		_update_cord()
		return
	var was_open := opened
	opened = deployed
	elapsed = minf(DURATION, elapsed + maxf(delta, 0.0)) if deployed else 0.0
	var release := smoothstep(0.0, 0.65, elapsed)
	var lift := smoothstep(0.25, 1.5, elapsed)
	var inflate := smoothstep(1.15, DURATION, elapsed)
	# Ejection clears the rim, then the rope and cap move under physical forces.
	cap_pivot.position = Vector3(-1.1 * release, CAP_SEAM * HOUSING_SCALE + 0.48 * sin(release * PI) - 0.1 * release, 0)
	cap_pivot.rotation = Vector3(0.0, 0.0, deg_to_rad(105.0) * release)
	canopy.visible = elapsed > 0.25
	canopy.position.y = ATTACHMENT_EYE * HOUSING_SCALE
	if deployed:
		var module_frame := global_basis.orthonormalized()
		var airflow: Vector3 = module_frame * rope.air_velocity
		var support: Vector3 = airflow.normalized() if airflow.length() > 0.5 else -(module_frame * rope.acceleration).normalized()
		if support.length_squared() < 0.5: support = Vector3.UP
		var target := Quaternion(Vector3.UP, support)
		if not was_open:
			canopy_attitude = target
		elif not landed:
			canopy_attitude = canopy_attitude.slerp(target, 1.0 - exp(-5.0 * maxf(delta, 0.0)))
		# A settled canopy shares the rotating terrain frame with its hull.
		if not resting:
			canopy.quaternion = module_frame.get_rotation_quaternion().inverse() * canopy_attitude
	else:
		canopy.quaternion = Quaternion.IDENTITY
	canopy.scale = Vector3(lerpf(0.025, 1.0, inflate), lerpf(0.015, 1.0, lift), lerpf(0.025, 1.0, inflate))
	var cloth_frame := canopy.basis.orthonormalized()
	canopy.hull_basis = cloth_frame
	canopy.hull_offset = canopy.position
	canopy.acceleration = cloth_frame.transposed() * rope.acceleration
	canopy.air_velocity = cloth_frame.transposed() * rope.air_velocity
	canopy.ground_normal = cloth_frame.transposed() * surface_normal
	canopy.ground_offset = surface_offset - canopy.position.dot(surface_normal)
	_update_relief(cloth_frame)
	if not deployed and was_open:
		canopy.reset()
	elif elapsed >= DURATION:
		canopy.advance(motion_delta, landed)
	tether.visible = elapsed > 0.01
	if not deployed:
		cap_released = false
		rope.reset(cap_pivot.position, cap_pivot.basis.y)
	elif not was_open:
		rope.reset(cap_pivot.position, cap_pivot.basis.y)
	if deployed:
		if elapsed >= 0.65 and not cap_released:
			cap_released = true
			rope.reset(cap_pivot.position, cap_pivot.basis.y, Vector3(-0.8, 0.6, 0.25))
		rope.advance(motion_delta, not cap_released, cap_pivot.position, cap_pivot.basis.y)
		if cap_released:
			cap_pivot.position = rope.points[TetherPhysics.SEGMENTS]
			var cap_axis := (rope.points[TetherPhysics.SEGMENTS + 1] - cap_pivot.position).normalized()
			cap_pivot.quaternion = Quaternion(Vector3.UP, cap_axis)
	_update_cord()

func _replay_collapse(delta: float) -> bool:
	if collapse_bake == null or collapse_bake.canopy_frames.size() < 2: return false
	var canopy_frames: Array[PackedVector3Array] = collapse_bake.canopy_frames
	var rope_frames: Array[PackedVector3Array] = collapse_bake.rope_frames
	if canopy_frames[0].size() != canopy.points.size() or rope_frames[0].size() != rope.points.size(): return false
	if not _replaying:
		_replaying = true
		_replay_time = 0.0
		_canopy_offset = _offsets(canopy.points, canopy_frames[0])
		_rope_offset = _offsets(rope.points, rope_frames[0])
	_replay_time += maxf(delta, 0.0)
	var blend := 1.0 - smoothstep(0.0, COLLAPSE_BLEND_SECONDS, _replay_time)
	var cloth := CollapseBake.sample(canopy_frames, collapse_bake.frame_seconds, _replay_time)
	for i in range(cloth.size()): cloth[i] += _canopy_offset[i] * blend
	canopy.points = cloth
	canopy.previous = cloth.duplicate()
	canopy.grounded = true
	if delta > 0.0: canopy.redraw()
	var cord := CollapseBake.sample(rope_frames, collapse_bake.frame_seconds, _replay_time)
	for i in range(cord.size()): cord[i] += _rope_offset[i] * blend
	rope.points = cord
	rope.previous = cord.duplicate()
	cap_pivot.position = rope.points[TetherPhysics.SEGMENTS]
	cap_pivot.quaternion = Quaternion(Vector3.UP, (rope.points[TetherPhysics.SEGMENTS + 1] - cap_pivot.position).normalized())
	_update_cord()
	return true

static func _offsets(live: PackedVector3Array, baked: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(live.size())
	for i in range(live.size()): result[i] = live[i] - baked[i]
	return result

## Draws the chute materials behind the launch cover so neither the faded
## (touchdown) nor the opaque (deployment) shader variant compiles in flight.
func prewarm_fade(on: bool, opaque: bool = false) -> void:
	if on:
		_set_fade(1.0 if opaque else 0.5)
		canopy.visible = true
		tether.visible = true
	else:
		_set_fade(1.0)
		canopy.visible = elapsed > 0.25

func _set_fade(value: float) -> void:
	fade = value
	# Compatibility rendering ignores GeometryInstance3D.transparency, so blend
	# each material's alpha; opaque again once fully restored.
	if _fade_materials.is_empty():
		_fade_materials.append_array(canopy.materials)
		_fade_materials.append(canopy.cords.material_override)
		_fade_materials.append(tether.material_override)
		for node in cap_pivot.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			for surface in range(mesh.get_surface_override_material_count()):
				var material := mesh.get_active_material(surface)
				if material is BaseMaterial3D:
					material = material.duplicate()
					mesh.set_surface_override_material(surface, material)
					_fade_materials.append(material)
	var alpha := smoothstep(0.0, 1.0, fade)
	for material: BaseMaterial3D in _fade_materials:
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if fade >= 1.0 else BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = alpha
	var hidden := fade <= 0.0
	canopy.fabric.visible = not hidden
	canopy.cords.visible = not hidden
	tether.visible = not hidden and elapsed > 0.01
	cap_pivot.visible = not hidden

func set_air_forces(relative_acceleration: Vector3, local_air_velocity: Vector3, air_density: float) -> void:
	if cut: return
	canopy.density = clampf(air_density, 0, 10)
	rope.acceleration = relative_acceleration.limit_length(100)
	rope.air_velocity = local_air_velocity.limit_length(80)
	rope.density = clampf(air_density, 0, 10)

func _update_cord() -> void:
	for i in range(TetherPhysics.SEGMENTS):
		var a: Vector3 = rope.points[i]
		var b: Vector3 = rope.points[i + 1]
		var direction := b - a
		var length := maxf(direction.length(), 0.00001)
		var basis := Basis(Quaternion(Vector3.UP, direction / length)) if direction.length() > 0.00001 else Basis.IDENTITY
		tether.multimesh.set_instance_transform(i, Transform3D(basis * Basis.from_scale(Vector3(1, length, 1)), (a + b) * 0.5))

func set_ground(normal: Vector3, offset: float) -> void:
	surface_normal = normal.normalized()
	surface_offset = offset

## Heights above the ground plane on a square grid centred under the module.
## Axes x and z span the grid, y is the ground normal; all in module space.
func set_relief(heights: PackedFloat32Array, size: int, spacing: float, axes: Basis) -> void:
	relief = heights
	relief_size = size
	relief_spacing = spacing
	relief_axes = axes
	canopy.relief = heights
	canopy.relief_size = size
	canopy.relief_revision += 1

func _update_relief(cloth_frame: Basis) -> void:
	if relief_size < 2: return
	var half := (relief_size - 1) * 0.5
	var cloth_to_module := cloth_frame.transposed()
	canopy.relief_u = cloth_to_module * relief_axes.x / relief_spacing
	canopy.relief_v = cloth_to_module * relief_axes.z / relief_spacing
	canopy.relief_origin = Vector2(canopy.position.dot(relief_axes.x) / relief_spacing + half, canopy.position.dot(relief_axes.z) / relief_spacing + half)

func cut_away(ground: Node3D, gravity := Vector3(0, -9.81, 0)) -> void:
	if cut: return
	cut = true
	# Leave the spent cloth at the landing site instead of repacking it on the ship.
	canopy.ground_normal = canopy.basis.orthonormalized().transposed() * surface_normal
	canopy.ground_offset = surface_offset - canopy.position.dot(surface_normal)
	canopy.reparent(ground, true)
	canopy.acceleration = canopy.global_basis.orthonormalized().transposed() * gravity
	canopy.air_velocity = Vector3.ZERO
	canopy.release()
	cut_root = Node3D.new()
	ground.add_child(cut_root)
	cut_root.global_transform = global_transform
	cap_pivot.reparent(cut_root, true)
	tether.reparent(cut_root, true)
	rope.detached = true
	rope.acceleration = cut_root.global_basis.orthonormalized().transposed() * gravity
	rope.air_velocity = Vector3.ZERO
	rope.ground_normal = surface_normal
	rope.ground_offset = surface_offset

func _exit_tree() -> void:
	if cut and is_instance_valid(canopy): canopy.queue_free()
	if is_instance_valid(cut_root): cut_root.queue_free()
