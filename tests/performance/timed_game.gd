extends "res://scripts/main.gd"
## Test-only instrumentation; production callbacks and native physics scheduling.
var perf_scenario := ""
var perf_running := false
var perf_tick := 0
var perf_target_ticks := 180
var perf_physics_us := 0
var perf_process_us := 0
var perf_ticks_this_frame := 0
var perf_events: Array[Dictionary] = []
var perf_seen := {"thrust": false, "detached": false, "heat": false, "canopy": false}

func _physics_process(delta: float) -> void:
	if perf_running and perf_tick >= perf_target_ticks:
		return
	var started := Time.get_ticks_usec()
	if perf_running:
		perf_tick += 1
		if perf_scenario == "launch" and perf_tick == 1:
			_stage()
			perf_events.append({"tick": perf_tick, "name": "Ignition", "at_us": Time.get_ticks_usec()})
		elif perf_scenario == "staging" and perf_tick == 60:
			_stage()
			perf_events.append({"tick": perf_tick, "name": "Eight-booster separation", "at_us": Time.get_ticks_usec()})
		elif perf_scenario == "parachute" and perf_tick == 1:
			_chute()
			perf_events.append({"tick": perf_tick, "name": "Parachute deployment", "at_us": Time.get_ticks_usec()})
	super._physics_process(delta)
	perf_physics_us += Time.get_ticks_usec() - started
	perf_ticks_this_frame += 1
	if perf_running:
		perf_seen.thrust = perf_seen.thrust or float(flight.state.get("thrust", 0.0)) > 0.0
		perf_seen.detached = perf_seen.detached or not flight.state.get("detached", []).is_empty()
		perf_seen.heat = perf_seen.heat or (is_instance_valid(world._heat_trail) and world._heat_trail.visible)
		perf_seen.canopy = perf_seen.canopy or (is_instance_valid(world._parachute_module) and world._parachute_module.canopy.is_visible_in_tree())

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	if perf_running and perf_scenario == "map":
		# Rotation depends on simulation ticks, not the machine's rendering speed.
		map_instrument.yaw = 0.35 + float(perf_tick) / 60.0 * 0.12
	super._process(delta)
	perf_process_us += Time.get_ticks_usec() - started

func perf_take_counters() -> Dictionary:
	var result := {"game_physics_ms": perf_physics_us / 1000.0,
		"game_process_ms": perf_process_us / 1000.0, "physics_ticks": perf_ticks_this_frame}
	perf_physics_us = 0
	perf_process_us = 0
	perf_ticks_this_frame = 0
	return result
