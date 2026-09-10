extends Node
## Original synthesized audio, generated once rather than per audio sample each frame.
var engine: AudioStreamPlayer
var ui_sound: AudioStreamPlayer
var enabled := true

func shutdown() -> void:
	for player: AudioStreamPlayer in [engine, ui_sound]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null

func _exit_tree() -> void:
	shutdown()

func _ready() -> void:
	engine = AudioStreamPlayer.new()
	engine.stream = _noise_loop()
	engine.volume_db = -60.0
	add_child(engine)
	engine.play()
	ui_sound = AudioStreamPlayer.new()
	add_child(ui_sound)

func _noise_loop() -> AudioStreamWAV:
	var bytes := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 74128
	var smooth := 0.0
	for i in range(22050):
		smooth = lerpf(smooth, rng.randf_range(-1.0, 1.0), 0.18)
		var sample := clampf(smooth * 0.65 + sin(float(i) / 22050.0 * TAU * 48.0) * 0.12, -1.0, 1.0)
		var value := int(sample * 32767.0)
		bytes.append(value & 255)
		bytes.append((value >> 8) & 255)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 22050
	return stream

func set_thrust(value: float, delta: float) -> void:
	if engine == null:
		return
	var target := lerpf(-27.0, -9.0, value) if value > 0.01 and enabled else -60.0
	engine.volume_db = lerpf(engine.volume_db, target, minf(1.0, delta * 8.0))
	engine.pitch_scale = lerpf(0.7, 1.15, value)

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
