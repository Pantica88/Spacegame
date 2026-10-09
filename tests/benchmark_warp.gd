extends SceneTree
## Headless CPU benchmark; excludes rendering and UI. Run with tools/run.sh.
const Flight = preload("res://scripts/flight_model.gd")
const Parts = preload("res://scripts/parts.gd")

func _initialize() -> void:
	var flight := Flight.new()
	for detached in [false, true]:
		for warp in [1, 8, 32, 64, 128]:
			flight.reset(Parts.default_design())
			flight.state.status = "flying"
			flight.state.position = Vector3(0, 30000, 0)
			flight.state.velocity = Vector3(620, 0, 0)
			if detached: flight._separate_core()
			# Warm terrain and resources before measuring steady flight.
			flight.step(1.0 / 60.0, {"throttle": 0.0, "sas": true})
			var start := Time.get_ticks_usec()
			for frame in range(60):
				flight.step(float(warp) / 60.0, {"throttle": 0.0, "sas": true})
			assert(flight.state.status == "flying")
			print("WARP BENCHMARK: %dx, detached=%s, %.3f ms/tick" % [warp, detached, float(Time.get_ticks_usec() - start) / 60000.0])
	quit()
