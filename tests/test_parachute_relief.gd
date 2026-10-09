extends SceneTree
## Landed fabric drapes over sampled terrain relief, not only the contact plane.
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var module = load("res://scenes/parachute_1.tscn").instantiate()
	module.fade_after_landing = false
	root.add_child(module)
	module.set_air_forces(Vector3(0,-9.81,0),Vector3.ZERO,1.225)
	var floor_y := -2.6592
	module.set_ground(Vector3.UP,floor_y)
	# A bowl rising 1.5 m around the capsule, where the canopy falls.
	var size := 17
	var heights := PackedFloat32Array()
	heights.resize(size*size)
	for j in range(size):
		for i in range(size):
			heights[j*size+i] = clampf(Vector2(i-8,j-8).length()*0.5-1.0,0.0,1.5)
	module.set_relief(heights,size,1.0,Basis.IDENTITY)
	module.advance(true,3.0)
	for frame in range(600): module.advance(true,1.0/60.0,true)
	var cloth = module.canopy
	var lowest := INF
	var on_ridge := 0
	for i in range(cloth.points.size()):
		if cloth.weights[i] == 0: continue
		var p: Vector3 = cloth.basis*cloth.points[i]+cloth.position
		var ground: float = floor_y+clampf(Vector2(p.x,p.z).length()*0.5-1.0,0.0,1.5)
		lowest = minf(lowest,p.y-ground)
		if ground > floor_y+0.2 and p.y-ground < 0.1: on_ridge += 1
	print("lowest above relief ",lowest," resting on ridge ",on_ridge)
	var ok: bool = lowest > -0.02 and on_ridge > 4
	if ok: print("PASS: landed canopy rests on terrain relief beside the contact plane")
	else: push_error("Canopy sinks into terrain relief")
	module.queue_free()
	await process_frame
	quit(0 if ok else 1)
