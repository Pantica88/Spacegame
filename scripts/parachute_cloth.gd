extends Node3D
## Flexible fabric with inextensible suspension cords, in housing space.
const SIDES := 24
const RINGS := 7
const CORD_STEPS := 6
const CLOTH_COUNT := SIDES * RINGS
const STEP := 1.0 / 60.0
const Hull = preload("res://scripts/recovery_hull.gd")
var points := PackedVector3Array()
var previous := PackedVector3Array()
var rest := PackedVector3Array()
var links: Array[Vector4] = []
var lambdas := PackedFloat32Array()
var weights := PackedFloat32Array()
var vent_perimeter := 0.0
var accumulator := 0.0
var pressure := 1.0
var acceleration := Vector3(0, -9.81, 0)
var air_velocity := Vector3.ZERO
var density := 1.225
var ground_normal := Vector3.UP
var ground_offset := -3.1
var grounded := false
# Terrain height above the ground plane, sampled on a grid around the hull, so
# fabric drapes over real relief rather than one tangent plane at the contact.
var relief := PackedFloat32Array()
var relief_size := 0
var relief_u := Vector3.ZERO # Cloth-local axis scaled to grid cells.
var relief_v := Vector3.ZERO
var relief_origin := Vector2.ZERO
var relief_revision := 0
var _rest_relief := -1
var hull_basis := Basis.IDENTITY
var hull_offset := Vector3(0,0.3392,0)
var detached := false
var fabric := MeshInstance3D.new()
var cords := MultiMeshInstance3D.new()
var cord_transforms: Array[Transform3D] = []
var materials: Array[StandardMaterial3D] = []
var sleeping := false
var _rest_probe := PackedVector3Array()
var _rest_clock := 0.0
var _quiet_time := 0.0
var _grounded_time := 0.0
var _rest_basis := Basis.IDENTITY
var _rest_offset := Vector3.ZERO
var _rest_normal := Vector3.UP
var _rest_ground := 0.0
var _rest_acceleration := Vector3.ZERO
var _rest_air := Vector3.ZERO
var _rest_density := 0.0
var _surface_cache: Dictionary = {}
var _edge_cache: Dictionary = {}
var _triangle_cache: Dictionary = {}
var _cord_cache: Dictionary = {}
var _render_environment: Array = []
var _render_revision := 0
var _render_frame := 0
var _redraw_skip := false
# Grounded particles that stay still clear of the hull are parked: skipped by
# integration and collision until a constraint moves them. Collision is most
# of the landed cloth cost.
const PARK_SPEED_SQUARED := 0.00000025 # 0.5 mm per step, 3 cm/s.
const PARK_SECONDS := 0.25
const PARK_WAKE_SQUARED := 0.000001 # 1 mm of constraint motion.
var _parked := PackedByteArray()
var _park_time := PackedFloat32Array()
var _park_spot := PackedVector3Array()
const RENDER_TOLERANCE_SQUARED := 0.0001 # 1 cm, below hull/ground clearances.
# Grounded fabric is drawn above its 35 mm contact height: clear of the 8 mm
# cords resting at that height, and of terrain depth precision between particles.
const FABRIC_RENDER_CLEARANCE := 0.15
# Cords drawn against the hull stay inside the fabric's 65 mm render shell.
const CORD_HULL_MARGIN := 0.022
const FABRIC_HULL_MARGIN := 0.035

func _ready() -> void:
	for color in [Color("d6d5ce"), Color("dc943d")]:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.94
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials.append(material)
	add_child(fabric)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.008
	cylinder.bottom_radius = 0.008
	cylinder.height = 1
	cylinder.radial_segments = 4
	cords.multimesh = MultiMesh.new()
	cords.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	cords.multimesh.mesh = cylinder
	cords.multimesh.instance_count = SIDES * CORD_STEPS
	var cord_material := StandardMaterial3D.new()
	cord_material.albedo_color = Color("99988d")
	cords.material_override = cord_material
	add_child(cords)
	for ring in range(RINGS):
		var t := lerpf(0.065, PI / 2, float(ring) / (RINGS - 1))
		for side in range(SIDES):
			var a := TAU * side / SIDES
			var bulge := pow(sin(a * 12), 2)
			rest.append(Vector3(4 * sin(t) * sin(a), 5 + 2.1 * cos(t) + 0.1 * bulge * sin(t), 4 * sin(t) * cos(a)))
	for side in range(SIDES):
		for segment in range(CORD_STEPS):
			rest.append(Vector3(0, 0.28, 0).lerp(rest[(RINGS - 1) * SIDES + side], float(segment) / CORD_STEPS))
	for ring in range(RINGS):
		for side in range(SIDES):
			var i := ring * SIDES + side
			_link(i, ring * SIDES + (side + 1) % SIDES, 0.00003)
			if ring < RINGS - 1:
				_link(i, i + SIDES, 0.00003)
				_link(i, (ring + 1) * SIDES + (side + 1) % SIDES, 0.0001)
				_link(ring * SIDES + (side + 1) % SIDES, i + SIDES, 0.0001)
	for side in range(SIDES):
		for segment in range(CORD_STEPS):
			var i := CLOTH_COUNT + side * CORD_STEPS + segment
			_link(i, i + 1 if segment < CORD_STEPS - 1 else (RINGS - 1) * SIDES + side, 0.0)
	weights.resize(rest.size())
	for i in range(rest.size()): weights[i] = 0.0 if _pinned(i) else 1.0
	for side in range(SIDES): vent_perimeter += rest[side].distance_to(rest[(side + 1) % SIDES])
	lambdas.resize(links.size())
	reset()

func _link(a: int, b: int, compliance: float) -> void:
	var length := rest[a].distance_to(rest[b])
	links.append(Vector4(a, b, length, compliance * length * length))

func reset() -> void:
	detached = false
	for i in range(weights.size()): weights[i] = 0.0 if _pinned(i) else 1.0
	points = rest.duplicate()
	previous = rest.duplicate()
	accumulator = 0
	pressure = 1
	grounded = false
	_grounded_time = 0.0
	_wake()
	redraw()

func _pinned(i: int) -> bool:
	return not detached and i >= CLOTH_COUNT and (i - CLOTH_COUNT) % CORD_STEPS == 0

func release() -> void:
	_wake()
	detached = true
	grounded = true
	pressure = 0.0
	weights.fill(1.0)

func advance(delta: float, landed: bool) -> void:
	grounded = grounded or landed
	if delta <= 0.0: return
	if sleeping:
		if _same_rest_environment(): return
		_wake()
	accumulator += clampf(delta, 0, 0.1)
	while accumulator + 0.0000001 >= STEP:
		accumulator -= STEP
		_step()
		_check_rest()
		if sleeping:
			accumulator = 0.0
			break
	# Grounded fabric moves slowly; rebuilding its mesh every other frame
	# halves the dominant post-touchdown cost with sub-centimetre lag.
	var hull_still: bool = not _render_environment.is_empty() and hull_basis == _render_environment[0] and hull_offset == _render_environment[1]
	_redraw_skip = not _redraw_skip if grounded and hull_still else false
	if delta > 0 and not _redraw_skip: redraw()

func _wake() -> void:
	sleeping = false
	_parked = PackedByteArray()
	_rest_probe = PackedVector3Array()
	_rest_clock = 0.0
	_quiet_time = 0.0

func _same_rest_environment() -> bool:
	return hull_basis.is_equal_approx(_rest_basis) and hull_offset.is_equal_approx(_rest_offset) and ground_normal.is_equal_approx(_rest_normal) and absf(ground_offset-_rest_ground) < 0.001 and acceleration.distance_squared_to(_rest_acceleration) < 0.0025 and air_velocity.distance_squared_to(_rest_air) < 0.0025 and absf(density-_rest_density) < 0.01 and relief_revision == _rest_relief

func _check_rest() -> void:
	if not grounded or pressure > 0.0 or air_velocity.length_squared() > 0.25: return
	_rest_clock += STEP
	_grounded_time += STEP
	if _rest_clock < 0.25: return
	_rest_clock = 0.0
	# A slack fold can sag for many seconds. After the drop, accept slow
	# cosmetic creep so the cloth sleeps instead of simulating it at full cost.
	var tolerance := 0.000025 if _grounded_time < 3.0 else 0.0004
	var quiet := _rest_probe.size() == points.size()
	if quiet:
		for i in range(points.size()):
			if points[i].distance_squared_to(_rest_probe[i]) > tolerance:
				quiet = false
				break
	_quiet_time = _quiet_time+0.25 if quiet else 0.0
	_rest_probe = points.duplicate()
	if _quiet_time < 0.75: return
	sleeping = true
	previous = points.duplicate()
	_rest_basis = hull_basis
	_rest_offset = hull_offset
	_rest_normal = ground_normal
	_rest_ground = ground_offset
	_rest_acceleration = acceleration
	_rest_air = air_velocity
	_rest_density = density
	_rest_relief = relief_revision

func _step() -> void:
	pressure = move_toward(pressure, 0.0 if grounded else 1.0, STEP * 2.5)
	if _parked.size() != points.size():
		_parked.resize(points.size())
		_parked.fill(0)
		_park_time.resize(points.size())
		_park_time.fill(0.0)
		_park_spot.resize(points.size())
	for i in range(points.size()):
		if weights[i] == 0 or _parked[i]: continue
		if not grounded and i >= CLOTH_COUNT: continue
		var velocity := (points[i] - previous[i]) / STEP
		var force := acceleration
		var relative_air := (air_velocity - velocity).limit_length(30)
		force += relative_air * density * (0.65 if i < CLOTH_COUNT else 0.12)
		if i < CLOTH_COUNT:
			# Air pressure supports the inflated shape elastically; it vanishes on contact.
			force += ((rest[i] - points[i]) * 18.0 - acceleration) * pressure
		if grounded and ground_height(points[i]) <= 0.036:
			# Static friction prevents endless submillimetre downhill creep.
			# Constraint pulls and stronger wind can still move resting particles.
			var tangent_velocity := velocity-ground_normal*velocity.dot(ground_normal)
			var tangent_force := force-ground_normal*force.dot(ground_normal)
			var load := maxf(0.0,-force.dot(ground_normal))
			if tangent_velocity.length_squared() < 0.01 and tangent_force.length() <= load*0.8:
				velocity -= tangent_velocity
				force -= tangent_force
		var next := points[i] + velocity * exp(-1.5 * STEP) * STEP + force.limit_length(100) * STEP * STEP
		previous[i] = points[i]
		points[i] = next
	lambdas.fill(0)
	for iteration in range(4):
		for index in range(links.size()):
			var link := links[index]
			var a := int(link.x)
			var b := int(link.y)
			# A suspended vessel loads each entire cord, keeping it straight and taut.
			if not grounded and a >= CLOTH_COUNT: continue
			if _parked[a] and _parked[b]: continue
			var difference := points[b] - points[a]
			var length := difference.length()
			if length < 0.000001: continue
			# Slack tension-only links exert no correction; avoid their array writes.
			if (grounded or a >= CLOTH_COUNT) and length <= link.z and lambdas[index] == 0.0: continue
			var wa := weights[a]
			var wb := weights[b]
			var alpha := link.w / (STEP * STEP)
			var change := (-(length - link.z) - alpha * lambdas[index]) / (wa + wb + alpha)
			# Released fabric buckles under compression instead of acting as a rigid dome.
			# Its tensile limits still prevent stretching; cords carry tension only.
			var updated := minf(0, lambdas[index] + change) if a >= CLOTH_COUNT or grounded else lambdas[index] + change
			change = updated - lambdas[index]
			lambdas[index] = updated
			var correction := difference / length * change
			points[a] -= correction * wa
			points[b] += correction * wb
		# The reinforced vent distributes load around its closed hem.
		var center := Vector3.ZERO
		var perimeter := 0.0
		for side in range(SIDES):
			center += points[side] / SIDES
			perimeter += points[side].distance_to(points[(side + 1) % SIDES])
		if perimeter > vent_perimeter * 1.03:
			for side in range(SIDES):
				points[side] = center + (points[side] - center) * (vent_perimeter * 1.03 / perimeter)
		for i in range(points.size()):
			if weights[i] == 0: continue
			if _parked[i]:
				if points[i].distance_squared_to(_park_spot[i]) <= PARK_WAKE_SQUARED: continue
				_parked[i] = 0
				_park_time[i] = 0.0
				previous[i] = _park_spot[i]
			_collide(i)
		if not grounded: _constrain_loaded_cords()
	if grounded and pressure <= 0.0 and not detached:
		_update_parking()
	if not grounded:
		for side in range(SIDES):
			var skirt := (RINGS - 1) * SIDES + side
			var anchor := CLOTH_COUNT + side * CORD_STEPS
			var axis := (points[skirt] - points[anchor]).normalized()
			var velocity := points[skirt] - previous[skirt]
			# Remove motion along the fixed-length rope rather than storing spring energy.
			previous[skirt] = points[skirt] - (velocity - axis * velocity.dot(axis))
			for segment in range(1, CORD_STEPS):
				previous[anchor + segment] = points[anchor].lerp(previous[skirt], float(segment) / CORD_STEPS)

func _update_parking() -> void:
	var hull_bound := 0.98 + Hull.CLEARANCE + 0.1
	for i in range(points.size()):
		if weights[i] == 0 or _parked[i]: continue
		var p := points[i]
		var q := hull_basis * p + hull_offset
		var near_hull := q.y > Hull.BOTTOM - 0.15 and q.y < Hull.TOP + 0.15 and q.x * q.x + q.z * q.z < hull_bound * hull_bound
		if near_hull or p.distance_squared_to(previous[i]) > PARK_SPEED_SQUARED or ground_height(p) > 0.04:
			_park_time[i] = 0.0
			continue
		_park_time[i] += STEP
		if _park_time[i] >= PARK_SECONDS:
			_parked[i] = 1
			_park_spot[i] = p
			previous[i] = p

func _constrain_loaded_cords() -> void:
	for side in range(SIDES):
		var skirt := (RINGS - 1) * SIDES + side
		var anchor := CLOTH_COUNT + side * CORD_STEPS
		var length := rest[anchor].distance_to(rest[skirt])
		var direction := points[skirt] - points[anchor]
		if direction.length_squared() < 0.000001:
			direction = rest[skirt] - rest[anchor]
		points[skirt] = points[anchor] + direction.normalized() * length
		for segment in range(1, CORD_STEPS):
			points[anchor + segment] = points[anchor].lerp(points[skirt], float(segment) / CORD_STEPS)

func _collide(i: int) -> void:
	var p := points[i]
	# Most grounded fabric lies well clear of the hull; reject it before the
	# per-particle projection call, which dominates landed cloth cost.
	var q := hull_basis * p + hull_offset
	var hull_bound := 0.98 + Hull.CLEARANCE
	if not detached and q.y > Hull.BOTTOM - Hull.CLEARANCE and q.y < Hull.TOP + Hull.CLEARANCE and q.x * q.x + q.z * q.z < hull_bound * hull_bound:
		var corrected := _project_hull(p)
		if not corrected.is_equal_approx(p):
			# Remove velocity into the hull, retaining sliding along its surface.
			var normal := (corrected-p).normalized()
			var velocity := p-previous[i]
			velocity -= normal * minf(velocity.dot(normal),0.0)
			previous[i] = corrected-velocity*0.92
			p = corrected
	if grounded:
		var height := ground_height(p)
		if height < 0.035:
			p += ground_normal * (0.035 - height)
			previous[i] = previous[i].lerp(p, 0.35)
	points[i] = p

## Signed height of a cloth-local point above the terrain, along the ground normal.
func ground_height(p: Vector3) -> float:
	var height := p.dot(ground_normal) - ground_offset
	if relief_size < 2: return height
	var u := clampf(p.dot(relief_u) + relief_origin.x, 0.0, relief_size - 1.001)
	var v := clampf(p.dot(relief_v) + relief_origin.y, 0.0, relief_size - 1.001)
	var i := int(u)
	var j := int(v)
	var fu := u - i
	var fv := v - j
	var row := j * relief_size
	var low := lerpf(relief[row + i], relief[row + i + 1], fu)
	var high := lerpf(relief[row + relief_size + i], relief[row + relief_size + i + 1], fu)
	return height - lerpf(low, high, fv)

func _project_hull(p: Vector3) -> Vector3:
	return hull_basis.transposed() * (Hull.project(hull_basis*p+hull_offset)-hull_offset)

func _project_surface(p: Vector3) -> Vector3:
	if not _surface_cache.has(p): _surface_cache[p] = hull_basis.transposed()*(Hull.project_render(hull_basis*p+hull_offset)-hull_offset)
	return _surface_cache[p]

func _near_hull(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var aa := hull_basis*a+hull_offset
	var bb := hull_basis*b+hull_offset
	var cc := hull_basis*c+hull_offset
	var low := aa.min(bb).min(cc)
	var high := aa.max(bb).max(cc)
	if low.y > Hull.TOP+0.08 or high.y < Hull.BOTTOM-0.08: return false
	# Match the bound to this height slice, so cloth on the surrounding ground
	# and above the narrow housing retains its inexpensive original triangles.
	var radius := maxf(Hull.radius_at(low.y),Hull.radius_at(high.y))+0.08
	if low.y < -2.02 and high.y > -2.02: radius = 1.06
	var nearest := Vector2(clampf(0.0,low.x,high.x),clampf(0.0,low.z,high.z))
	return nearest.length_squared() < radius*radius

func _edge_contact(a: Vector3, b: Vector3) -> float:
	var key := [a,b] if a < b else [b,a]
	if not _edge_cache.has(key):
		_edge_cache[key] = Hull.segment_contact(hull_basis*a+hull_offset,hull_basis*b+hull_offset,FABRIC_HULL_MARGIN)
	return _edge_cache[key]

func _face_contact(a: Vector3, b: Vector3, c: Vector3) -> Vector4:
	for weights in [Vector3(1.0/3,1.0/3,1.0/3),Vector3(0.5,0.25,0.25),Vector3(0.25,0.5,0.25),Vector3(0.25,0.25,0.5)]:
		var p: Vector3 = a*weights.x+b*weights.y+c*weights.z
		if Hull.contains(hull_basis*p+hull_offset,0.0): return Vector4(p.x,p.y,p.z,1)
	return Vector4.ZERO

func _surface_triangle(a: Vector3, b: Vector3, c: Vector3, vertices: PackedVector3Array, normals: PackedVector3Array, depth: int = 0) -> void:
	if not detached and _near_hull(a,b,c):
		# Refine actual contacts rather than every face near the hull.
		a = _project_surface(a)
		b = _project_surface(b)
		c = _project_surface(c)
		# Projection can span opposite sides of a rim or bend. Resolve those
		# remaining face contacts too, rather than drawing a chord through it.
		if depth < 18 and not Hull.triangle_plane_outside(hull_basis*a+hull_offset,hull_basis*b+hull_offset,hull_basis*c+hull_offset):
			var hit := _face_contact(a,b,c)
			if _edge_contact(a,b) >= 0 or _edge_contact(b,c) >= 0 or _edge_contact(c,a) >= 0 or hit.w > 0:
				# Bisect the longest edge to avoid deep, thin contact triangles.
				var ab := a.distance_squared_to(b)
				var bc := b.distance_squared_to(c)
				var ca := c.distance_squared_to(a)
				if ab >= bc and ab >= ca:
					var mid := _project_surface((a+b)*0.5)
					_surface_triangle(a,mid,c,vertices,normals,depth+1)
					_surface_triangle(mid,b,c,vertices,normals,depth+1)
				elif bc >= ca:
					var mid := _project_surface((b+c)*0.5)
					_surface_triangle(a,b,mid,vertices,normals,depth+1)
					_surface_triangle(a,mid,c,vertices,normals,depth+1)
				else:
					var mid := _project_surface((c+a)*0.5)
					_surface_triangle(a,b,mid,vertices,normals,depth+1)
					_surface_triangle(mid,b,c,vertices,normals,depth+1)
				return
	var normal := (c-a).cross(b-a).normalized()
	vertices.append_array(PackedVector3Array([a,b,c]))
	normals.append_array(PackedVector3Array([normal,normal,normal]))

func _cord_segment(a: Vector3, b: Vector3, transforms: Array[Transform3D], depth: int = 0) -> void:
	if depth == 0 and grounded and not detached:
		a = _project_cord(a)
		b = _project_cord(b)
	var mid := (a+b)*0.5
	# Projected cords already lie on the hull; 8 levels follow its curve without
	# the thousands of pieces per segment that 12 levels produced.
	if grounded and not detached and depth < 8 and _near_hull(a,b,b):
		var t := Hull.segment_contact(hull_basis*a+hull_offset,hull_basis*b+hull_offset,0.012)
		if t >= 0:
			mid = _project_cord(mid)
			_cord_segment(a,mid,transforms,depth+1)
			_cord_segment(mid,b,transforms,depth+1)
			return
	var direction := b-a
	var length := maxf(direction.length(),0.00001)
	var basis := Basis(Quaternion(Vector3.UP,direction/length)) if direction.length() > 0.00001 else Basis.IDENTITY
	transforms.append(Transform3D(basis*Basis.from_scale(Vector3(1,length,1)),mid))

## Lays cord points near the hull onto it, beneath fabric draped over the hull.
func _project_cord(p: Vector3) -> Vector3:
	var q := hull_basis*p+hull_offset
	if q.y <= Hull.BOTTOM or q.y >= Hull.TOP: return p
	var radius := maxf(Hull.render_radius(q.y),Hull.radius_at(q.y))+CORD_HULL_MARGIN
	var length := Vector2(q.x,q.z).length()
	if length > radius+0.12: return p
	var direction := Vector2(q.x,q.z)/length if length > 0.000001 else Vector2.RIGHT
	return hull_basis.transposed()*(Vector3(direction.x*radius,q.y,direction.y*radius)-hull_offset)

func _lift_fabric(vertices: PackedVector3Array) -> void:
	for v in range(vertices.size()):
		var height := ground_height(vertices[v])
		if height < FABRIC_RENDER_CLEARANCE:
			vertices[v] += ground_normal * (FABRIC_RENDER_CLEARANCE - height)

func redraw() -> void:
	_surface_cache.clear()
	_edge_cache.clear()
	# Ground contact is already resolved in particle positions. A changing
	# terrain plane must not invalidate every unchanged hull-contact face.
	var environment := [hull_basis,hull_offset,detached,grounded]
	var changed := _render_environment.is_empty()
	if not changed:
		var old_basis: Basis = _render_environment[0]
		# At most 7 mm of hull motion, safely inside its 45 mm clearance.
		changed = hull_basis.x.distance_squared_to(old_basis.x) > 0.000009 or hull_basis.y.distance_squared_to(old_basis.y) > 0.000009 or hull_basis.z.distance_squared_to(old_basis.z) > 0.000009 or hull_offset.distance_squared_to(_render_environment[1]) > 0.000025 or detached != _render_environment[2] or grounded != _render_environment[3]
	if changed:
		var reset_cache := _render_environment.is_empty()
		if not reset_cache:
			var old_basis: Basis = _render_environment[0]
			reset_cache = hull_basis.x.distance_squared_to(old_basis.x) > 0.0004 or hull_basis.y.distance_squared_to(old_basis.y) > 0.0004 or hull_basis.z.distance_squared_to(old_basis.z) > 0.0004 or hull_offset.distance_squared_to(_render_environment[1]) > 0.0001 or detached != _render_environment[2] or grounded != _render_environment[3]
		if reset_cache:
			_triangle_cache.clear()
			_cord_cache.clear()
		_render_revision += 1
		_render_environment = environment
	_render_frame += 1
	var triangle_index := 0
	var mesh := ArrayMesh.new()
	for color in range(2):
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		for ring in range(RINGS - 1):
			for side in range(SIDES):
				if (side / 2) % 2 != color: continue
				var a := ring * SIDES + side
				var b := ring * SIDES + (side + 1) % SIDES
				for triangle in [[a, a + SIDES, b + SIDES], [a, b + SIDES, b]]:
					var pa := points[triangle[0]]
					var pb := points[triangle[1]]
					var pc := points[triangle[2]]
					var cached: Array = _triangle_cache.get(triangle_index,[])
					var motion := INF if cached.is_empty() else maxf(pa.distance_squared_to(cached[0]),maxf(pb.distance_squared_to(cached[1]),pc.distance_squared_to(cached[2])))
					# Spread resting contact refinements over two frames. Fast motion
					# refreshes immediately; lag stays below ground/hull clearance.
					var due := not grounded or triangle_index%2 == _render_frame%2 or motion > 0.0004
					if cached.is_empty() or (due and (motion > RENDER_TOLERANCE_SQUARED or cached[5] != _render_revision or cached[6] != relief_revision)):
						var face_vertices := PackedVector3Array()
						var face_normals := PackedVector3Array()
						_surface_triangle(pa,pb,pc,face_vertices,face_normals)
						if grounded: _lift_fabric(face_vertices)
						cached = [pa,pb,pc,face_vertices,face_normals,_render_revision,relief_revision]
						_triangle_cache[triangle_index] = cached
					vertices.append_array(cached[3])
					normals.append_array(cached[4])
					triangle_index += 1
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(color, materials[color])
	fabric.mesh = mesh
	cord_transforms.clear()
	for side in range(SIDES):
		for segment in range(CORD_STEPS):
			var i := CLOTH_COUNT + side * CORD_STEPS + segment
			var a := points[i]
			var b := points[i + 1 if segment < CORD_STEPS - 1 else (RINGS - 1) * SIDES + side]
			var cached: Array = _cord_cache.get(i,[])
			var motion := INF if cached.is_empty() else maxf(a.distance_squared_to(cached[0]),b.distance_squared_to(cached[1]))
			var due := not grounded or i%2 == _render_frame%2 or motion > 0.0004
			if cached.is_empty() or (due and (motion > RENDER_TOLERANCE_SQUARED or cached[3] != _render_revision)):
				var segments: Array[Transform3D] = []
				_cord_segment(a,b,segments)
				cached = [a,b,segments,_render_revision]
				_cord_cache[i] = cached
			cord_transforms.append_array(cached[2])
	if cords.multimesh.instance_count != cord_transforms.size(): cords.multimesh.instance_count = cord_transforms.size()
	for i in range(cord_transforms.size()): cords.multimesh.set_instance_transform(i,cord_transforms[i])
