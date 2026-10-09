extends SceneTree

const PlanetEditor = preload("res://scripts/planet_editor.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Exercise the actual camera without building terrain or running editor setup.
	var editor := PlanetEditor.new()
	var camera := Camera3D.new()
	root.add_child(camera)
	editor.camera = camera
	for yaw: float in [0.0, 0.55, 2.4]:
		editor.yaw = yaw
		for direction: float in [-1.0, 1.0]:
			editor.pitch = 0.0
			editor._update_camera()
			var previous := camera.basis
			for step in range(1, 1441):
				editor.pitch = wrapf(direction * step * TAU / 720.0, -PI, PI)
				editor._update_camera()
				assert(camera.basis.is_finite(), "Camera remains finite at the poles")
				assert(camera.basis.y.dot(previous.y) > 0.999, "Camera up remains continuous across poles and pitch wrapping")
				assert(camera.basis.x.dot(previous.x) > 0.999, "Camera right never flips")
				assert(camera.basis.z.dot(camera.position.normalized()) > 0.99999, "Camera keeps looking at the planet center")
				assert(absf(camera.position.length() - editor.distance) < 0.1, "Orbit preserves zoom distance")
				previous = camera.basis
	print("PASS: planet camera stays continuous through both poles over repeated rotations in both directions.")
	editor.free()
	camera.free()
	quit(0)
