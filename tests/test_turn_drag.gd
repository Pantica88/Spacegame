extends SceneTree
const Flight = preload("res://scripts/flight_model.gd")
const Surface = preload("res://scripts/planet_surface.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _init() -> void:
	var reference_speed := 0.0
	for rate in [60, 120]:
		var f = Flight.new()
		f.reset({"engine":"sparrow", "tanks":16, "boosters":false})
		f.ignite()
		f.state.fuel = 0.0
		f.state.engine_on = false
		f.state.position = Flight.PLANET_CENTER + Vector3.BACK * (Flight.PLANET_RADIUS + 10000)
		f.state.velocity = f.terrain.surface_velocity(f.state.position - Flight.PLANET_CENTER) + Vector3.FORWARD * 800.0
		f.state.orientation = Surface.LAUNCH_BASIS
		f.step(1.0 / rate, {"throttle":0.0})
		var before: Vector3 = f.state.velocity
		# Deliberately harder than player controls: an entire 90-degree turn.
		f.state.orientation = Basis(Vector3.UP, Vector3.RIGHT, Vector3.FORWARD)
		check(f.state.velocity == before, "Orientation changes preserve inertial momentum")
		f.step(1.0 / rate, {"throttle":0.0})
		var loss: float = (Vector3(f.state.velocity) - before).length()
		check(loss < 8.0 * 60.0 / rate, "Sudden broadside turn cannot shed speed abruptly in one frame")
		check(f.state.side_drag_exposure > 0.0 and f.state.side_drag_exposure < 0.04, "Side resistance builds progressively from airflow")
		for frame in range(rate): f.step(1.0 / rate, {"throttle":0.0})
		check(f.state.side_drag_exposure > 0.8, "Sustained broadside airflow eventually reaches strong drag")
		check(f.state.vertical_speed < 0.0, "Turning does not cancel the fall")
		check(f.state.speed < 790.0, "Broadside drag still dissipates momentum over time")
		if reference_speed > 0: check(absf(reference_speed - f.state.speed) < 5.0, "Turn response is stable at 60 and 120 Hz")
		reference_speed = f.state.speed
		print("TURN %d Hz: first-frame velocity change %.3f m/s; speed after one second %.2f m/s" % [rate, loss, f.state.speed])
		f._advance_side_drag(Vector3.FORWARD * 800.0, Vector3.FORWARD, 1.0, 2.0)
		check(f.state.side_drag_exposure < 0.02, "Resistance fades as the hull realigns with movement")
		f._advance_side_drag(Vector3.FORWARD * 800.0, Vector3.RIGHT, 0.0, 0.1)
		check(f.state.side_drag_exposure == 0.0, "Vacuum clears aerodynamic response")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("PASS: turns preserve momentum and change drag progressively")
	quit(0 if failures.is_empty() else 1)
