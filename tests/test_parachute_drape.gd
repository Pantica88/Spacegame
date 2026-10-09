extends SceneTree
const Hull = preload("res://scripts/recovery_hull.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	for tilt in [0.0,0.45,PI/2]:
		var module = load("res://scenes/parachute_1.tscn").instantiate()
		module.fade_after_landing = false
		root.add_child(module)
		module.basis = Basis(Vector3.FORWARD,tilt)
		module.set_air_forces(module.basis.transposed()*Vector3(0,-9.81,0),Vector3.ZERO,1.225)
		var normal: Vector3 = module.basis.transposed()*Vector3.UP
		# Place the ground under the collision envelope, including a tipped capsule.
		var floor_y := INF
		for p in Hull.PROFILE:
			floor_y = minf(floor_y,p.y*cos(tilt)-p.x*sin(tilt))
		module.set_ground(normal,floor_y)
		module.advance(true,3.0)
		for frame in range(420):
			module.advance(true,1.0/60.0,true)
			if frame%60 == 59: check_surface(module)
		check(module.canopy.visible and is_zero_approx(module.canopy.pressure), "Landed canopy remains as unpressurized fabric")
		var near_count := 0
		for p in module.canopy.points:
			var hull_point: Vector3 = module.canopy.hull_basis*p+module.canopy.hull_offset
			if hull_point.y > Hull.BOTTOM+0.1 and hull_point.y < Hull.TOP+0.15 and Vector2(hull_point.x,hull_point.z).length() < Hull.radius_at(hull_point.y)+0.2:
				near_count += 1
		check(near_count > 4, "Fabric or slack cords settle against the recovery hull")
		module.queue_free()
		await process_frame
	if failures.is_empty(): print("PASS: cloth drapes outside capsule and shorter housing, including tilted and sideways landings")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check_surface(module) -> void:
	var cloth = module.canopy
	for i in range(cloth.points.size()):
		if cloth.weights[i] == 0: continue
		var p: Vector3 = cloth.points[i]
		check(p.is_finite(), "Draping stays finite")
		check(not Hull.contains(cloth.hull_basis*p+cloth.hull_offset,-0.002), "Simulated fabric and cords remain outside the hull")
		check(p.dot(cloth.ground_normal) >= cloth.ground_offset+0.033, "Draping stays above the ground")
	var mesh: ArrayMesh = cloth.fabric.mesh
	for surface in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for i in range(0,vertices.size(),3):
			# Check triangle interiors and edges, not only collision particles.
			var a: Vector3 = vertices[i]
			var b: Vector3 = vertices[i+1]
			var c: Vector3 = vertices[i+2]
			for sample in [a,b,c,a.lerp(b,0.25),a.lerp(b,0.5),a.lerp(b,0.75),b.lerp(c,0.25),b.lerp(c,0.5),b.lerp(c,0.75),c.lerp(a,0.25),c.lerp(a,0.5),c.lerp(a,0.75),(a+b+c)/3.0,(a*2+b+c)/4.0,(a+b*2+c)/4.0,(a+b+c*2)/4.0]:
				check(not Hull.contains(cloth.hull_basis*sample+cloth.hull_offset,-0.005), "Rendered cloth faces do not cut through the capsule or housing")
	# The headless renderer does not retain MultiMesh instance transforms.
	for transform: Transform3D in cloth.cord_transforms:
		for t in [-0.5,-0.25,0.0,0.25,0.5]:
			var sample := transform*Vector3(0,t,0)
			check(not Hull.contains(cloth.hull_basis*sample+cloth.hull_offset,-0.005), "Visible slack cords stay outside the recovery hull")
