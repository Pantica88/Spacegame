extends SceneTree
const Flight = preload("res://scripts/flight_model.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for altitude in [3000000.0, 10000000.0]:
		for warp in [1.0, 32.0]:
			var model := Flight.new()
			model.state.status = "flying"
			model.state.position = Vector3(0, altitude, 0)
			model.state.velocity = Vector3(0, 1776.2, 0)
			model.state.engine_on = false
			model.state.boosters_on = false
			model._separate_core()
			var piece: Dictionary = model.state.detached.back()
			piece.position.y -= 20.0
			var previous := relative_position(model, piece)
			for frame in range(60):
				model.step(warp / 60.0, {"throttle": 0.0})
				var current := relative_position(model, piece)
				var movement := current.y - previous.y
				assert(movement < -0.005 * warp, "Released stage must recede every frame, without pauses")
				assert(movement > -0.025 * warp, "Released stage must not jump between rounded positions")
				previous = current
	print("PASS: continuous released-stage motion at 3,000/10,000 km, at 1x/32x")
	quit()

func relative_position(model, piece: Dictionary) -> Vector3:
	return Vector3(piece.position) - Vector3(model.state.position) + Vector3(piece.get("position_remainder", Vector3.ZERO)) - Vector3(model.state.get("position_remainder", Vector3.ZERO))
