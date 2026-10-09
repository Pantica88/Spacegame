extends AudioStreamPlayer
## One sustained recording loop at original pitch; throttle changes only gain.
const RESTART_SECONDS := 1.0
const CROSSFADE_SECONDS := 0.16
const BUFFER_SECONDS := 0.12
const ATTACK_SECONDS := 0.18
const RELEASE_SECONDS := 0.12
const MASTER_GAIN := 0.55

var recording: AudioStreamWAV
var source_seconds: float
var loop_end_seconds: float
var loop_start_seconds: float

var _samples := PackedFloat32Array()
var _window := PackedFloat32Array()
var _position := 0
var _restart_position := 0
var _loop_start := 0
var _loop_end := 0
var _fade_frames := 0
var _target := 0.0
var _gain := 0.0
var _silent_seconds := 0.0
var _buffer_capacity := 0
var _playback: AudioStreamGeneratorPlayback
var _launch_pending := true

func _init(clip: AudioStreamWAV, source_length: float, sustain_end: float, sustain_start: float = 1.0) -> void:
	recording = clip
	source_seconds = source_length
	loop_end_seconds = sustain_end
	loop_start_seconds = sustain_start

func _ready() -> void:
	assert(recording.format == AudioStreamWAV.FORMAT_16_BITS and not recording.stereo)
	assert(is_equal_approx(recording.get_length(), source_seconds))
	var bytes: PackedByteArray = recording.data
	_samples.resize(bytes.size() / 2)
	for index in range(_samples.size()):
		_samples[index] = float(bytes.decode_s16(index * 2)) / 32768.0
	_restart_position = int(RESTART_SECONDS * recording.mix_rate)
	_loop_start = int(loop_start_seconds * recording.mix_rate)
	_loop_end = int(loop_end_seconds * recording.mix_rate)
	_position = _restart_position
	_fade_frames = int(CROSSFADE_SECONDS * recording.mix_rate)
	_window.resize(_fade_frames)
	for index in range(_fade_frames):
		_window[index] = sin(PI * 0.5 * float(index) / (_fade_frames - 1))
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = recording.mix_rate
	generator.buffer_length = BUFFER_SECONDS
	stream = generator
	set_process(false)

func reset_for_launch() -> void:
	shutdown()
	_launch_pending = true

func set_thrust(value: float, suspended: bool = false) -> void:
	stream_paused = suspended
	if suspended: return
	_target = clampf(value, 0.0, 1.0)
	if _target > 0.0:
		_silent_seconds = 0.0
		if not playing:
			# Preserve the recorded ignition on the first firing of each flight.
			# Later throttle restarts fade into sustained combustion at second 1.
			_position = 0 if _launch_pending else _restart_position
			_gain = _target if _launch_pending else 0.0
			_launch_pending = false
			play()
			_playback = get_stream_playback()
			_buffer_capacity = _playback.get_frames_available()
			set_process(true)
			_fill_buffer()

func shutdown() -> void:
	stop()
	_playback = null
	_target = 0.0
	_gain = 0.0
	stream_paused = false
	set_process(false)

func _process(delta: float) -> void:
	if stream_paused or _playback == null: return
	_fill_buffer()
	if _target == 0.0:
		_silent_seconds += delta
		# Let the queued release finish before stopping the device stream.
		if _silent_seconds >= BUFFER_SECONDS + RELEASE_SECONDS:
			shutdown()

func _fill_buffer() -> void:
	var available := _playback.get_frames_available()
	# Godot rounds the ring buffer size; bound the queued time explicitly.
	var queued := _buffer_capacity - available
	var count := mini(available, int(BUFFER_SECONDS * recording.mix_rate) - queued)
	if count > 0:
		_playback.push_buffer(_render_frames(count))

func _loop_sample() -> float:
	var sample := _samples[_position]
	var overlap := _position - (_loop_end - _fade_frames)
	if overlap >= 0:
		sample = sample * _window[_fade_frames - 1 - overlap] + _samples[_loop_start + overlap] * _window[overlap]
	_position += 1
	if _position >= _loop_end:
		# The incoming head has already played the overlap. Skip it on wrap.
		_position = _loop_start + _fade_frames
	return sample

func _render_frames(count: int) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(count)
	var gain_step := 1.0 / (recording.mix_rate * (ATTACK_SECONDS if _target > _gain else RELEASE_SECONDS))
	for index in range(count):
		# Throttle never seeks, restarts, changes pitch, or changes loop length.
		var sample := _loop_sample()
		_gain = move_toward(_gain, _target, gain_step)
		sample *= _gain * MASTER_GAIN
		frames[index] = Vector2(sample, sample)
	return frames
