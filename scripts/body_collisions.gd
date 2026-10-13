extends RefCounted
## Deterministic rounded-cylinder contacts, shared by debris and the active craft.
## Bodies contain center-of-mass position, inertia, momentum and local shapes.

static func inverse_inertia(body: Dictionary, vector: Vector3) -> Vector3:
	var basis: Basis = body.orientation
	return basis * ((basis.transposed() * vector) / Vector3(body.inertia))

static func omega(body: Dictionary) -> Vector3:
	return inverse_inertia(body,body.angular_momentum)

static func endpoints(body: Dictionary, shape: Dictionary) -> Array[Vector3]:
	var center: Vector3 = body.position + body.orientation * Vector3(shape.offset)
	var arm: Vector3 = body.orientation.y * maxf(0.0,float(shape.length)*.5-float(shape.radius))
	return [center-arm,center+arm]

static func closest(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Array[Vector3]:
	var u := b-a
	var v := d-c
	var r := a-c
	var uu := u.dot(u)
	var vv := v.dot(v)
	var uv := u.dot(v)
	var s := 0.0
	var t := 0.0
	if uu < 0.000001 and vv < 0.000001: return [a,c]
	if uu < 0.000001:
		t = clampf(v.dot(r)/vv,0.0,1.0)
	elif vv < 0.000001:
		s = clampf(-u.dot(r)/uu,0.0,1.0)
	else:
		var denom := uu*vv-uv*uv
		if denom > 0.000001:
			s = clampf((uv*v.dot(r)-u.dot(r)*vv)/denom,0.0,1.0)
		else:
			# Parallel side contacts use the middle of the overlapping span,
			# avoiding artificial end torque on a centered broadside impact.
			var c_on_a := u.dot(c-a)/uu
			var d_on_a := u.dot(d-a)/uu
			var lo := maxf(0.0,minf(c_on_a,d_on_a))
			var hi := minf(1.0,maxf(c_on_a,d_on_a))
			s = clampf((lo+hi)*.5,0.0,1.0)
		t = (uv*s+v.dot(r))/vv
		if t < 0.0:
			t = 0.0
			s = clampf(-u.dot(r)/uu,0.0,1.0)
		elif t > 1.0:
			t = 1.0
			s = clampf((uv-u.dot(r))/uu,0.0,1.0)
	return [a+u*s,c+v*t]

static func contact(a: Dictionary, sa: Dictionary, b: Dictionary, sb: Dictionary) -> Dictionary:
	var ea := endpoints(a,sa)
	var eb := endpoints(b,sb)
	var points := closest(ea[0],ea[1],eb[0],eb[1])
	var delta := points[1]-points[0]
	var distance := delta.length()
	var radii: float = sa.radius+sb.radius
	if distance >= radii: return {}
	var normal := delta/distance if distance > .000001 else (Vector3(b.position)-Vector3(a.position)).normalized()
	if normal.is_zero_approx(): normal = Vector3.RIGHT
	var point := (points[0]+normal*float(sa.radius)+points[1]-normal*float(sb.radius))*.5
	return {"normal":normal,"point":point,"depth":radii-distance}

static func effective_mass(a: Dictionary, b: Dictionary, ra: Vector3, rb: Vector3, direction: Vector3) -> float:
	return 1.0/float(a.mass)+1.0/float(b.mass)+direction.dot(inverse_inertia(a,ra.cross(direction)).cross(ra)+inverse_inertia(b,rb.cross(direction)).cross(rb))

static func apply_impulse(a: Dictionary, b: Dictionary, ra: Vector3, rb: Vector3, impulse: Vector3) -> void:
	a.velocity -= impulse/float(a.mass)
	b.velocity += impulse/float(b.mass)
	a.angular_momentum -= ra.cross(impulse)
	b.angular_momentum += rb.cross(impulse)
	for body in [a,b]:
		body.landed = false
		body.settle_time = 0.0

## Returns whether the contact changed either body: an impulse or an overlap
## correction beyond resting slop.
static func resolve(a: Dictionary, b: Dictionary) -> bool:
	# Most detached stages are far apart. Reject disjoint bounding spheres
	# before allocating shape endpoints and solving individual contacts.
	if a.has("bound") and b.has("bound"):
		var reach: float = a.bound + b.bound
		if Vector3(a.position).distance_squared_to(b.position) > reach * reach:
			return false
	var touched := false
	var basis_a: Basis = a.orientation
	var basis_b: Basis = b.orientation
	for sa in a.shapes:
		# Long stages have large bounds; most of their shapes are still apart.
		var center_a: Vector3 = Vector3(a.position) + basis_a * Vector3(sa.offset)
		var extent_a := maxf(float(sa.length) * .5, float(sa.radius))
		for sb in b.shapes:
			var reach := extent_a + maxf(float(sb.length) * .5, float(sb.radius))
			if center_a.distance_squared_to(Vector3(b.position) + basis_b * Vector3(sb.offset)) > reach * reach: continue
			var hit := contact(a,sa,b,sb)
			if hit.is_empty(): continue
			# Resting contacts keep .0001 of overlap and need no further passes.
			touched = touched or float(hit.depth) > .0002
			var n: Vector3 = hit.normal
			var ra: Vector3 = hit.point-a.position
			var rb: Vector3 = hit.point-b.position
			var relative: Vector3 = b.velocity+omega(b).cross(rb)-a.velocity-omega(a).cross(ra)
			var closing := relative.dot(n)
			if closing < 0.0:
				# Rounding-level closing in a settled pair needs no further passes.
				touched = touched or closing < -.001
				var restitution := .15 if closing < -1.0 else 0.0
				var magnitude := -(1.0+restitution)*closing/effective_mass(a,b,ra,rb,n)
				apply_impulse(a,b,ra,rb,n*magnitude)
				# Friction uses the post-normal contact speed and cannot reverse slip.
				relative = b.velocity+omega(b).cross(rb)-a.velocity-omega(a).cross(ra)
				var tangent := relative-n*relative.dot(n)
				if tangent.length() > .000001:
					var direction := tangent.normalized()
					var friction := minf(.45*magnitude,tangent.length()/effective_mass(a,b,ra,rb,direction))
					apply_impulse(a,b,ra,rb,-direction*friction)
			# Mass-weighted overlap correction does not add kinetic energy.
			var correction := n*maxf(float(hit.depth)-.0001,0.0)/(1.0/float(a.mass)+1.0/float(b.mass))
			a.position -= correction/float(a.mass)
			b.position += correction/float(b.mass)
			if hit.depth > .002:
				a.landed = false
				b.landed = false
	return touched

## Index pairs (as Vector2i) whose bounding spheres lie within margin of each other.
static func candidate_pairs(bodies: Array, margin: float) -> Array[Vector2i]:
	var pairs: Array[Vector2i] = []
	var positions := PackedVector3Array()
	var bounds := PackedFloat64Array()
	for body in bodies:
		positions.append(body.position)
		bounds.append(float(body.bound))
	for i in range(bodies.size()):
		for j in range(i+1,bodies.size()):
			var reach := bounds[i]+bounds[j]+margin
			if positions[i].distance_squared_to(positions[j]) <= reach*reach: pairs.append(Vector2i(i,j))
	return pairs

static func step_limit(bodies: Array, requested: float) -> float:
	var result := requested
	# Per-body values once, not per pair: this runs every craft substep.
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var bounds := PackedFloat64Array()
	var tips := PackedFloat64Array()
	var radii := PackedFloat64Array()
	for body in bodies:
		positions.append(body.position)
		velocities.append(body.velocity)
		bounds.append(float(body.bound))
		tips.append(omega(body).length()*float(body.bound))
		radii.append(float(body.min_radius))
	for i in range(bodies.size()):
		for j in range(i+1,bodies.size()):
			var speed := (velocities[j]-velocities[i]).length()+tips[i]+tips[j]
			if speed < .001: continue
			var reach := bounds[i]+bounds[j]+speed*requested
			var distance_squared := positions[i].distance_squared_to(positions[j])
			if distance_squared > reach*reach: continue
			# Cross empty space before switching to contact-sized steps. Using
			# the tiny contact step for the entire swept reach makes distant
			# debris force thousands of substeps during a single warp tick.
			# Bounds enclose every orientation; including tip speed makes this
			# approach conservative for rotating bodies too.
			var gap := sqrt(distance_squared) - bounds[i] - bounds[j]
			var travel := maxf(gap, .25 * minf(radii[i], radii[j]))
			result = minf(result, travel / speed)
	return result
