extends SceneTree

class TimedCloth extends "res://scripts/parachute_cloth.gd":
	var solver_us := 0
	var mesh_us := 0
	func _step() -> void:
		var start := Time.get_ticks_usec()
		super._step()
		solver_us += Time.get_ticks_usec()-start
	func redraw() -> void:
		var start := Time.get_ticks_usec()
		super.redraw()
		mesh_us += Time.get_ticks_usec()-start

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var cloth := TimedCloth.new()
	root.add_child(cloth)
	cloth.ground_offset = -2.6592
	for phase in ["airborne","landing","settled","resting","asleep"]:
		cloth.solver_us = 0
		cloth.mesh_us = 0
		var frames := 180 if phase == "landing" else (1800 if phase == "resting" else 120)
		var start := Time.get_ticks_usec()
		var maximum := 0
		for frame in range(frames):
			var tick := Time.get_ticks_usec()
			cloth.advance(1.0/60.0,phase != "airborne")
			maximum = maxi(maximum,Time.get_ticks_usec()-tick)
		var elapsed := Time.get_ticks_usec()-start
		var mesh: ArrayMesh = cloth.fabric.mesh
		print("PARACHUTE %s: %.3f ms/frame (solver %.3f, mesh %.3f), max %.3f ms, %d vertices" % [phase,elapsed/1000.0/frames,cloth.solver_us/1000.0/frames,cloth.mesh_us/1000.0/frames,maximum/1000.0,mesh.surface_get_array_len(0)+mesh.surface_get_array_len(1)])
	print("Sleeping: ", cloth.sleeping)
	cloth.free()
	quit()
