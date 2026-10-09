extends Node
## Throttle-selected loops from the user's recording; synthesized UI feedback.
const ROCKET_SOUND = preload("res://assets/audio/rocket_engine.wav")
const TitanAudio = preload("res://scripts/titan_audio.gd")
const SparrowAudio = preload("res://scripts/sparrow_audio.gd")
const SOURCE_END := 7.0
const BAND_COUNT := 15
const WINDOW_SECONDS := 0.5
const CROSSFADE_SECONDS := 0.12
const ATTACK_SECONDS := 0.45
var engine: AudioStreamPlayer
var ui_sound: AudioStreamPlayer
var titan: AudioStreamPlayer
var sparrow: AudioStreamPlayer
var enabled := true
var _players: Array[AudioStreamPlayer] = []
var _streams: Array[AudioStreamWAV] = []
var _level := 0.0
var _throttle := 0.0

func shutdown() -> void:
	_level = 0.0
	if is_instance_valid(titan): titan.shutdown()
	if is_instance_valid(sparrow): sparrow.shutdown()
	for player in _players:
		player.stop()
		player.stream = null
	if is_instance_valid(ui_sound):
		ui_sound.stop()
		ui_sound.stream = null

func _exit_tree() -> void:
	shutdown()

func reset_for_launch() -> void:
	titan.reset_for_launch()
	sparrow.reset_for_launch()

func _ready() -> void:
	titan = TitanAudio.new()
	add_child(titan)
	sparrow = SparrowAudio.new()
	add_child(sparrow)
	_make_streams()
	for stream in _streams:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)
	engine = _players[0]
	ui_sound = AudioStreamPlayer.new()
	add_child(ui_sound)

## Route by the engines actually firing, including independent stage fuel feeds.
func update_engines(state: Dictionary, engines: Array, throttle: float, delta: float, suspended: bool = false) -> void:
	var levels := engine_levels(state, engines, throttle)
	set_thrust(levels.x, delta, suspended)
	if enabled:
		titan.set_thrust(levels.y, suspended)
		sparrow.set_thrust(levels.z, suspended)
	else:
		titan.shutdown()
		sparrow.shutdown()

## Components are legacy engines/boosters, Titan, and Sparrow respectively.
static func engine_levels(state: Dictionary, engines: Array, throttle: float) -> Vector3:
	var levels := Vector3.ZERO
	if state.get("status", "") != "flying": return levels
	if state.get("engine_on", false) and not state.get("capsule_only", false):
		var feeds: Dictionary = state.get("engine_fuel", {})
		var active: Array = state.get("active_engines", [])
		for part in engines:
			if part.id in state.get("removed_parts", []): continue
			if not active.is_empty() and part.id not in active: continue
			var fuel := float(feeds.get(part.id, 0.0)) if not feeds.is_empty() else float(state.get("fuel", 0.0))
			if fuel <= 0.0: continue
			if part.kind == "titan": levels.y = clampf(throttle, 0.0, 1.0)
			elif part.kind == "sparrow": levels.z = clampf(throttle, 0.0, 1.0)
			else: levels.x = clampf(throttle, 0.0, 1.0)
	if state.get("boosters_attached", false) and state.get("boosters_on", false) and state.get("booster_fuel", 0.0) > 0.0:
		levels.x = maxf(levels.x, 0.6)
	return levels

func _source_start(index: int) -> float:
	return float(index) / (BAND_COUNT - 1) * (SOURCE_END - WINDOW_SECONDS)

func _make_streams() -> void:
	var source: PackedByteArray = ROCKET_SOUND.data
	var rate: int = ROCKET_SOUND.mix_rate
	var length := int(WINDOW_SECONDS * rate)
	var fade := int(CROSSFADE_SECONDS * rate)
	for band in range(BAND_COUNT):
		var start := int(_source_start(band) * rate)
		var bytes := source.slice(start * 2, (start + length) * 2)
		# Equal-power overlap avoids a dip when the recorded noise loops.
		for index in range(fade):
			var weight := float(index) / (fade - 1)
			var a := bytes.decode_s16((length - fade + index) * 2)
			var b := bytes.decode_s16(index * 2)
			bytes.encode_s16((length - fade + index) * 2, int(clampf(a * cos(weight * PI * 0.5) + b * sin(weight * PI * 0.5), -32768.0, 32767.0)))
		# Match loop loudness so crossing throttle bands does not jump in volume.
		var power := 0.0
		for index in range(fade, length):
			power += pow(float(bytes.decode_s16(index * 2)) / 32768.0, 2.0)
		var gain := 0.12 / maxf(sqrt(power / (length - fade)), 0.001)
		for index in range(length):
			bytes.encode_s16(index * 2, int(clampf(bytes.decode_s16(index * 2) * gain, -32768.0, 32767.0)))
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = rate
		stream.data = bytes
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = fade
		stream.loop_end = length
		_streams.append(stream)

func set_thrust(value: float, delta: float, suspended: bool = false) -> void:
	if _players.is_empty(): return
	for player in _players:
		player.stream_paused = suspended and enabled
	if not enabled or (not suspended and value <= 0.0):
		for player in _players: player.stop()
		_level = 0.0
		_throttle = 0.0
		return
	if suspended: return
	value = clampf(value, 0.0, 1.0)
	var dt := maxf(delta, 0.0)
	# No one-shot ignition: rise gently from silence on every start.
	_level = move_toward(_level, value, dt / ATTACK_SECONDS)
	_throttle = lerpf(_throttle, value, 1.0 - exp(-dt / 0.15))
	var band := (1.0 - _throttle) * (BAND_COUNT - 1)
	for index in range(_players.size()):
		var weight := maxf(0.0, 1.0 - absf(band - index))
		var player := _players[index]
		if weight <= 0.0:
			player.stop()
			continue
		player.volume_linear = 0.355 * _level * sqrt(weight)
		if not player.playing:
			# Skip the seam pre-roll, including the initial ignition attack.
			player.play(CROSSFADE_SECONDS)

func ping(success: bool = false) -> void:
	if not enabled or ui_sound == null:
		return
	var bytes := PackedByteArray()
	var count := 6500 if success else 1400
	for i in range(count):
		var time := float(i) / 22050.0
		var frequency := (660.0 if i < 2200 else 880.0) if success else 540.0
		var envelope := sin(PI * float(i) / count) * 0.15
		var value := int(sin(time * TAU * frequency) * envelope * 32767.0)
		bytes.append(value & 255)
		bytes.append((value >> 8) & 255)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = bytes
	ui_sound.stream = stream
	ui_sound.play()
