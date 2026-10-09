extends SceneTree
const Cloth = preload("res://scripts/parachute_cloth.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var cloth := Cloth.new()
	root.add_child(cloth)
	cloth.ground_offset = -2.6592
	for frame in range(2400):
		cloth.advance(1.0/60.0,true)
		if cloth.sleeping: break
	check(cloth.sleeping,"Landed cloth enters rest without disabling collision")
	var settled := cloth.points.duplicate()
	var mesh := cloth.fabric.mesh
	for frame in range(120): cloth.advance(1.0/60.0,true)
	check(cloth.points == settled and cloth.fabric.mesh == mesh,"Resting cloth reuses its simulation and rendered mesh")
	# Each environment change must invalidate rest independently.
	for change in range(6):
		cloth.sleeping = true
		cloth._rest_basis = cloth.hull_basis
		cloth._rest_offset = cloth.hull_offset
		cloth._rest_normal = cloth.ground_normal
		cloth._rest_ground = cloth.ground_offset
		cloth._rest_acceleration = cloth.acceleration
		cloth._rest_air = cloth.air_velocity
		cloth._rest_density = cloth.density
		match change:
			0: cloth.air_velocity += Vector3.RIGHT
			1: cloth.hull_basis = Basis(Vector3.FORWARD,0.1)
			2: cloth.hull_offset += Vector3(0.1,0,0)
			3: cloth.ground_offset += 0.1
			4: cloth.ground_normal = Vector3(0.1,1,0).normalized()
			5: cloth.acceleration += Vector3.RIGHT
		cloth.advance(1.0/60.0,true)
		check(not cloth.sleeping,"Environment change %d wakes cloth" % change)
	cloth.sleeping = true
	cloth.release()
	check(not cloth.sleeping and cloth.detached,"Cutaway wakes resting cloth")
	cloth.sleeping = true
	cloth.reset()
	check(not cloth.sleeping and not cloth.grounded and cloth.pressure == 1,"Repacking resets rest state")
	cloth.free()
	if failures.is_empty(): print("PASS: landed cloth sleeps, reuses its mesh, and wakes for motion, wind, ground and cutaway")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
