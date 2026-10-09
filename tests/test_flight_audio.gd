extends SceneTree
const FlightAudio = preload("res://scripts/flight_audio.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var sound := FlightAudio.new()
	root.add_child(sound)
	assert(sound._players.all(func(player): return not player.playing))
	assert(sound._source_start(0) == 0.0)
	assert(is_equal_approx(sound._source_start(FlightAudio.BAND_COUNT - 1) + FlightAudio.WINDOW_SECONDS, 7.0), "Only the uploaded recording's 0–7 second interval is used")
	for stream in sound._streams:
		assert(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
		var bytes := stream.data
		var power := 0.0
		for sample in range(stream.loop_begin, stream.loop_end):
			power += pow(float(bytes.decode_s16(sample * 2)) / 32768.0, 2.0)
		assert(absf(sqrt(power / (stream.loop_end - stream.loop_begin)) - 0.12) < 0.001, "Loop volumes are matched")
	sound.set_thrust(1.0, 1.0 / 60.0)
	assert(sound._level < 0.04, "A jump from zero to full thrust begins quietly")
	for frame in range(120): sound.set_thrust(1.0, 1.0 / 60.0)
	assert(is_equal_approx(sound._level, 1.0) and sound.engine.playing, "Full thrust selects the start of the source interval")
	for thrust in [0.75, 0.5, 0.15, 0.1, 0.01]:
		for frame in range(120): sound.set_thrust(thrust, 1.0 / 60.0)
		assert(sound._players.any(func(player): return player.playing), "Every nonzero throttle remains audible without a shutdown threshold")
		var total_power := 0.0
		for player in sound._players:
			if player.playing: total_power += player.volume_linear * player.volume_linear
		assert(absf(sqrt(total_power) - 0.355 * thrust) < 0.001, "Crossfaded bands preserve throttle volume")
	var level := sound._level
	sound.set_thrust(0.0, 0.1, true)
	assert(sound._level == level and sound._players.any(func(player): return player.stream_paused))
	sound.set_thrust(0.0, 0.1)
	assert(sound._players.all(func(player): return not player.playing))
	sound.set_thrust(1.0, 1.0 / 60.0)
	assert(sound._level < 0.04, "Reopening throttle also has a soft attack")
	sound.enabled = false
	sound.set_thrust(1.0, 0.1)
	assert(sound._players.all(func(player): return not player.playing))
	sound.shutdown()
	_test_recorded_engine(sound, "titan", 7)
	_test_recorded_engine(sound, "sparrow", 9)
	_test_mixed_engines(sound)
	sound.free()
	await create_timer(0.15).timeout
	print("PASS: 0–7 second throttle mapping, matched loops, soft starts, continuous low thrust, pause and mute")
	quit()

func _test_recorded_engine(sound: Node, kind: String, seconds: int) -> void:
	var engine = sound.get(kind)
	var channel := 1 if kind == "titan" else 2
	var core_level := Vector3.ZERO
	core_level[channel] = 0.5
	assert(engine.RECORDING.data.size() == seconds * 44100 * 2, "Asset contains exactly the requested PCM duration")
	var expected_loop_start := 44100
	assert(engine._loop_start == expected_loop_start and engine._loop_end <= seconds * 44100, "The sustain loop uses the selected steady section within the allowed recording")
	var parts := [{"id": "core", "kind": kind}, {"id": "upper", "kind": "kestrel"}]
	var state := {"status": "flying", "engine_on": true, "active_engines": ["core"], "engine_fuel": {"core": 20.0, "upper": 20.0}}
	assert(FlightAudio.engine_levels(state, parts, 0.5) == core_level, "Only firing engines of this kind use the new recording path")
	state.active_engines = ["upper"]
	assert(FlightAudio.engine_levels(state, parts, 0.5) == Vector3(0.5, 0.0, 0.0), "An inactive engine must stay silent")
	state.active_engines = ["core", "upper"]
	assert(FlightAudio.engine_levels(state, parts, 0.5) == Vector3(0.5, 0.0, 0.0) + core_level)
	state.engine_fuel.core = 0.0
	assert(FlightAudio.engine_levels(state, parts, 0.5)[channel] == 0.0, "Another tank's fuel cannot keep an exhausted engine audible")
	state.engine_fuel.core = 20.0
	state.removed_parts = ["core"]
	assert(FlightAudio.engine_levels(state, parts, 0.5)[channel] == 0.0, "A separated engine no longer voices the ship")
	state.removed_parts = []
	state.active_engines = ["core"]
	state.boosters_attached = true
	state.boosters_on = true
	state.booster_fuel = 10.0
	assert(FlightAudio.engine_levels(state, parts, 0.1) == Vector3(0.6, 0.0, 0.0) + core_level * 0.2, "Boosters do not raise the engine's selected thrust")
	state.boosters_on = false
	sound.enabled = true
	sound.update_engines(state, parts, 1.0, 0.016)
	assert(engine.playing and not sound._players.any(func(player): return player.playing))
	var ignition_position: int = engine._position
	assert(ignition_position > 0 and ignition_position <= int(engine.BUFFER_SECONDS * 44100), "Initial launch buffers the recording from second 0")
	assert(engine._gain == 1.0, "Initial launch retains the recording's own ignition envelope")
	var ignition: PackedVector2Array = engine._render_frames(44100)
	for index in range(ignition.size()):
		assert(is_equal_approx(ignition[index].x, engine._samples[ignition_position + index] * engine.MASTER_GAIN), "Launch plays the original ignition without smoothing it away")
	engine._render_frames(44100 * 4)
	assert(engine._position >= expected_loop_start, "Ignition plays only once before the sustained loop")
	# Keep the same long full-thrust texture at every volume.
	engine.shutdown()
	engine.set_thrust(1.0)
	var initial_position: int = engine._position
	assert(initial_position >= 44100 and initial_position <= 44100 + int(engine.BUFFER_SECONDS * 44100), "The startup buffer begins at second 1")
	assert(engine._gain < 0.8, "Full throttle fades in rather than immediately reaching maximum volume")
	var before_seam: int = mini(44100 * 2, engine._loop_end - engine._fade_frames - initial_position)
	var full: PackedVector2Array = engine._render_frames(before_seam)
	assert(engine._position == initial_position + full.size(), "Sustained playback runs forward until its seam")
	for index in range(4410, full.size(), 441):
		assert(is_equal_approx(full[index].x, engine._samples[initial_position + index] * engine.MASTER_GAIN), "Full thrust preserves the sustained recording before the seam")
	var loop_length: int = engine._loop_end - engine._loop_start - engine._fade_frames
	if kind == "titan":
		assert(loop_length >= 44100 * 2.5, "Titan retains its long sustain loop")
	else:
		assert(engine._loop_end == 9 * 44100 and loop_length == 8 * 44100 - engine._fade_frames, "Original Sparrow sustain uses a long eight-second source section")
	# Cross a seam even for long recordings, then stay sample-aligned while
	# the real player's throttle goes up and down.
	engine._position = engine._loop_end - 11025
	var reference = engine.get_script().new()
	root.add_child(reference)
	reference._position = engine._position
	reference._target = 1.0
	reference._gain = 1.0
	for thrust in [0.5, 0.1, 1.0, 0.25, 0.75, 0.01, 1.0]:
		var position: int = engine._position
		engine.set_thrust(thrust)
		assert(engine._position == position, "Thrust adjustment must never seek or restart playback")
		engine._render_frames(8820)
		reference._render_frames(8820)
		var actual: PackedVector2Array = engine._render_frames(22050)
		var expected: PackedVector2Array = reference._render_frames(22050)
		for index in range(actual.size()):
			assert(absf(actual[index].x - expected[index].x * thrust) < 0.000001, "Every thrust level is exactly the full-thrust waveform with volume reduced, including loop seams")
		assert(engine._position == reference._position, "Thrust changes preserve playback phase")
	reference.free()
	var rendered := PackedVector2Array()
	var started := Time.get_ticks_usec()
	for step in range(101):
		engine.set_thrust(1.0 - float(step) / 100.0)
		var frames: PackedVector2Array = engine._render_frames(4410)
		for frame in frames:
			assert(is_finite(frame.x) and absf(frame.x) < 1.0, "Throttle sweep never clips or emits invalid samples")
		assert(engine._position >= expected_loop_start and engine._position < engine._loop_end, "Sustained playback never returns to the rising sound before the loop")
		rendered.append_array(frames)
	print("%s 10-second audio render: %.1f ms" % [kind, (Time.get_ticks_usec() - started) / 1000.0])
	assert(rendered[-1] == Vector2.ZERO, "Zero thrust fades to exact silence")
	engine.set_thrust(0.01)
	var low: PackedVector2Array = engine._render_frames(22050)
	var low_peak := 0.0
	for frame in low: low_peak = maxf(low_peak, absf(frame.x))
	assert(low_peak > 0.00001, "Low nonzero thrust still produces recorded audio")
	var position: int = engine._position
	sound.update_engines(state, parts, 0.0, 0.1, true)
	engine._process(0.5)
	assert(engine.stream_paused and engine._position == position, "Pause freezes sample position")
	sound.update_engines(state, parts, 0.3, 0.1)
	assert(not engine.stream_paused and is_equal_approx(engine._target, 0.3))
	sound.enabled = false
	sound.update_engines(state, parts, 1.0, 0.1, true)
	assert(not engine.playing, "Mute stops the engine even while paused")
	sound.enabled = true
	sound.update_engines(state, parts, 1.0, 0.1)
	sound.update_engines({}, parts, 1.0, 0.1)
	engine._process(0.3)
	assert(not engine.playing, "Leaving flight releases and stops the engine")
	engine.set_thrust(0.5)
	assert(engine._position >= 44100 and engine._position <= 44100 + int(engine.BUFFER_SECONDS * 44100), "Restarting at partial thrust also starts at second 1")
	sound.reset_for_launch()
	sound.update_engines({"status": "ready"}, parts, 1.0, 0.016)
	assert(engine._launch_pending and not engine.playing, "Waiting on the pad preserves the next launch's ignition")
	sound.update_engines(state, parts, 0.0, 0.016)
	assert(engine._launch_pending, "Zero thrust does not consume ignition")
	sound.update_engines(state, parts, 1.0, 0.016)
	assert(engine._position <= int(engine.BUFFER_SECONDS * 44100) and not engine._launch_pending, "Each new flight restores the initial ignition")
	sound.shutdown()
	print("PASS: %s ignition at second 0, restarts at second 1, volume-only thrust, fixed loop, source bounds, routing, fuel, staging, pause and mute" % kind)

func _test_mixed_engines(sound: Node) -> void:
	var parts := [{"id": "t", "kind": "titan"}, {"id": "s", "kind": "sparrow"}]
	var state := {"status": "flying", "engine_on": true, "active_engines": ["s"], "engine_fuel": {"t": 20.0, "s": 20.0}}
	sound.enabled = true
	sound.reset_for_launch()
	sound.update_engines(state, parts, 0.5, 0.016)
	assert(sound.sparrow.playing and not sound.titan.playing, "Sparrow plays its original sound without the Titan or legacy recording")
	assert(not sound._players.any(func(player): return player.playing))
	assert(sound.titan._launch_pending, "Sparrow ignition does not consume Titan's later ignition")
	state.active_engines = ["t", "s"]
	sound.update_engines(state, parts, 0.5, 0.016)
	assert(sound.titan.playing and sound.sparrow.playing, "Mixed engines retain their own independent recordings")
	state.engine_fuel.s = 0.0
	sound.update_engines(state, parts, 0.5, 0.016)
	sound.sparrow._process(0.3)
	assert(not sound.sparrow.playing and sound.titan.playing, "An exhausted Sparrow stops while Titan continues")
	sound.shutdown()
	print("PASS: independent Sparrow/Titan playback, staged ignition and fuel exhaustion")
