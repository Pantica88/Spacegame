extends SceneTree
## Captures the clouds mid-motion, where temporal reprojection shows its
## faults: a rocket-speed climb through the deck, fast level flight just
## under and over it, and a quick turn. Every CLOUD_EVERY-th frame of each
## run is saved to CLOUD_SHOTS as <run>_<frame>.png, and the same pose is
## then held still for comparison (<run>_<frame>_still.png).
const HOVER = preload("res://scenes/hover_preview.tscn")
const PlanetSurface = preload("res://scripts/planet_surface.gd")

# run: [start position, velocity (m/s, launch frame), yaw, pitch, yaw rate (rad/s)]
const RUNS := {
	"climb": [Vector3(0, 300, 0), Vector3(0, 450, 0), 0.6, 0.15, 0.0],
	"under": [Vector3(0, 1500, 0), Vector3(250, 0, -250), 0.8, 0.12, 0.0],
	"over": [Vector3(0, 5200, 0), Vector3(400, 0, -400), 0.8, -0.1, 0.0],
	"turn": [Vector3(0, 5200, 0), Vector3.ZERO, 0.0, -0.1, 0.9],
}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var out := OS.get_environment("CLOUD_SHOTS")
	if out.is_empty(): out = "/tmp/aphelion-cloud-motion"
	DirAccess.make_dir_recursive_absolute(out)
	var every := int(OS.get_environment("CLOUD_EVERY")) if OS.get_environment("CLOUD_EVERY") != "" else 20
	var frames := int(OS.get_environment("CLOUD_FRAMES")) if OS.get_environment("CLOUD_FRAMES") != "" else 60
	var hover = HOVER.instantiate()
	root.add_child(hover)
	await process_frame
	hover.hover_hud.visible = false
	hover._clouds.time_scale = 0.0
	var names: PackedStringArray = OS.get_environment("CLOUD_RUNS").split(",", false)
	if names.is_empty(): names = PackedStringArray(RUNS.keys())
	# A fixed step, so runs repeat exactly whatever the frame rate.
	var dt := 1.0 / 60.0
	for run_name in names:
		var run: Array = RUNS[run_name]
		hover.hover_position = run[0]
		hover.hover_yaw = run[2]
		hover.hover_pitch = run[3]
		for i in 20: await process_frame
		for frame in range(1, frames + 1):
			hover.hover_position += Vector3(run[1]) * dt
			hover.hover_yaw += float(run[4]) * dt
			await process_frame
			if frame % every == 0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%s_%03d.png" % [out, run_name, frame])
				var moving: Vector3 = hover.hover_position
				var yaw: float = hover.hover_yaw
				for hold in 40: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%s_%03d_still.png" % [out, run_name, frame])
				hover.hover_position = moving
				hover.hover_yaw = yaw
		print("RUN %s done at %.0f m" % [run_name, hover._last_altitude])
	quit(0)
