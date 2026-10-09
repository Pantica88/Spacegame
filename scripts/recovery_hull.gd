extends RefCounted
## Collision envelope in parachute mounting coordinates (capsule base at -2.32 m).
## Radius includes the capsule panels, windows, RCS fittings and docking collar.
const PROFILE: Array[Vector2] = [
	Vector2(0.74,-2.32), Vector2(0.91,-2.22), Vector2(0.98,-2.02),
	Vector2(0.91,-1.72), Vector2(0.64,-0.96), Vector2(0.56,-0.69),
	Vector2(0.37,-0.11), Vector2(0.35,0.0), Vector2(0.30,0.12),
	Vector2(0.25,0.30), Vector2(0.215,0.4505)
]
const CLEARANCE := 0.045
const BOTTOM := -2.32
const TOP := 0.4505

static func radius_at(y: float) -> float:
	# Fixed profile: avoid Variant array traversal in per-particle contact checks.
	if y <= BOTTOM: return 0.74
	if y < -2.22: return 0.74 + (y + 2.32) * 1.7
	if y < -2.02: return 0.91 + (y + 2.22) * 0.35
	if y < -1.72: return 0.98 + (y + 2.02) * (-0.07 / 0.30)
	if y < -0.96: return 0.91 + (y + 1.72) * (-0.27 / 0.76)
	if y < -0.69: return 0.64 + (y + 0.96) * (-0.08 / 0.27)
	if y < -0.11: return 0.56 + (y + 0.69) * (-0.19 / 0.58)
	if y < 0: return 0.37 + (y + 0.11) * (-0.02 / 0.11)
	if y < 0.12: return 0.35 + y * (-0.05 / 0.12)
	if y < 0.3: return 0.3 + (y - 0.12) * (-0.05 / 0.18)
	if y < 0.4505: return 0.25 + (y - 0.3) * (-0.035 / 0.1505)
	return 0.215

static func contains(p: Vector3, margin: float = 0.0) -> bool:
	if p.y <= BOTTOM-margin or p.y >= TOP+margin: return false
	var radius := radius_at(p.y)+margin
	return p.x*p.x+p.z*p.z < radius*radius

static func project(p: Vector3, margin: float = CLEARANCE) -> Vector3:
	if not contains(p,margin): return p
	var radial := Vector2(p.x,p.z)
	var q := Vector2(radial.length(),p.y)
	# Nearest point on the lathed profile, including its top and bottom disks.
	var nearest := Vector2(q.x,TOP+margin)
	var distance := q.distance_squared_to(nearest)
	var bottom := Vector2(q.x,BOTTOM-margin)
	if q.distance_squared_to(bottom) < distance:
		nearest = bottom
		distance = q.distance_squared_to(bottom)
	for i in range(1,PROFILE.size()):
		var a: Vector2 = PROFILE[i-1] + Vector2(margin,0)
		var b: Vector2 = PROFILE[i] + Vector2(margin,0)
		if i == 1: a.y -= margin
		if i == PROFILE.size()-1: b.y += margin
		var vertical_gap := maxf(a.y-q.y,q.y-b.y)
		if vertical_gap > 0 and vertical_gap*vertical_gap >= distance: continue
		var edge := b-a
		var candidate := a + edge * clampf((q-a).dot(edge)/edge.length_squared(),0,1)
		var d := q.distance_squared_to(candidate)
		if d < distance:
			nearest = candidate
			distance = d
	var outward := radial.normalized() if radial.length_squared() > 0.000001 else Vector2.RIGHT
	return Vector3(outward.x*nearest.x,nearest.y,outward.y*nearest.x)

# A conservative four-point envelope for rendering. Its long conical side
# stays outside the detailed hull by at most 2 cm, avoiding ten tests per edge.
const RENDER_PROFILE: Array[Vector2] = [Vector2(0.74,-2.32),Vector2(0.91,-2.22),Vector2(0.98,-2.02),Vector2(0.215,0.4505)]

static func render_radius(y: float) -> float:
	if y < -2.02: return radius_at(y)
	return lerpf(0.98,0.215,clampf((y+2.02)/2.4705,0,1))

static func project_render(p: Vector3, margin: float = 0.065) -> Vector3:
	if p.y <= BOTTOM-margin or p.y >= TOP+margin: return p
	var radius := render_radius(p.y)+margin
	var length := Vector2(p.x,p.z).length()
	if length >= radius: return p
	var gap := radius-length
	if TOP+margin-p.y < gap: return Vector3(p.x,TOP+margin,p.z)
	if p.y-BOTTOM+margin < gap: return Vector3(p.x,BOTTOM-margin,p.z)
	var direction := Vector2(p.x,p.z)/length if length > 0.000001 else Vector2.RIGHT
	return Vector3(direction.x*radius,p.y,direction.y*radius)

static func segment_contact(a: Vector3, b: Vector3, margin: float = 0.015) -> float:
	# Intersect the segment with the filled frusta, including the end disks.
	# Unlike point sampling, cost does not grow with the length of a slack edge.
	var low_y := minf(a.y,b.y)
	var high_y := maxf(a.y,b.y)
	if low_y > TOP+margin or high_y < BOTTOM-margin: return -1.0
	var radius := maxf(render_radius(low_y),render_radius(high_y))+margin
	if low_y < -2.02 and high_y > -2.02: radius = 0.98+margin
	var start := Vector2(a.x,a.z)
	var planar_edge := Vector2(b.x,b.z)-start
	var nearest := start+planar_edge*clampf(-start.dot(planar_edge)/maxf(planar_edge.length_squared(),0.0000001),0,1)
	if nearest.length_squared() >= radius*radius: return -1.0
	var d := b-a
	for i in range(RENDER_PROFILE.size()+1):
		var low := BOTTOM-margin if i == 0 else RENDER_PROFILE[i-1].y
		var high := TOP+margin if i == RENDER_PROFILE.size() else RENDER_PROFILE[i].y
		if maxf(a.y,b.y) < low or minf(a.y,b.y) > high: continue
		var lo := 0.0
		var hi := 1.0
		if absf(d.y) > 0.0000001:
			var t0 := (low-a.y)/d.y
			var t1 := (high-a.y)/d.y
			lo = maxf(0,minf(t0,t1))
			hi = minf(1,maxf(t0,t1))
		if lo >= hi: continue
		var r0 := render_radius(low)+margin
		var slope := (render_radius(high)+margin-r0)/(high-low)
		var r := r0 + (a.y-low)*slope
		var dr := d.y*slope
		var quadratic := d.x*d.x+d.z*d.z-dr*dr
		var linear := 2*(a.x*d.x+a.z*d.z-r*dr)
		var constant := a.x*a.x+a.z*a.z-r*r
		var t := clampf(-linear/(2*quadratic),lo,hi) if quadratic > 0.0000001 else (lo if quadratic*lo*lo+linear*lo < quadratic*hi*hi+linear*hi else hi)
		if quadratic*t*t+linear*t+constant < -0.0000001:
			return clampf(t,0.0001,0.9999)
	return -1.0

static func triangle_plane_outside(a: Vector3, b: Vector3, c: Vector3) -> bool:
	# Separating plane test against the convex lathed envelope. Most refined
	# cloth faces clear the hull entirely and need no edge intersections.
	var normal := (b-a).cross(c-a)
	if normal.length_squared() < 0.000000000001: return false
	var radial := Vector2(normal.x,normal.z).length()
	var low := INF
	var high := -INF
	for p in RENDER_PROFILE:
		low = minf(low,normal.y*p.y-radial*p.x)
		high = maxf(high,normal.y*p.y+radial*p.x)
	var distance := normal.dot(a)
	return distance < low-0.000001 or distance > high+0.000001
