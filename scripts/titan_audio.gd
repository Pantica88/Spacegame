extends "res://scripts/recorded_engine_audio.gd"
const RECORDING = preload("res://assets/audio/titan_engine.wav")
const SOURCE_SECONDS := 7.0

func _init() -> void:
	super(RECORDING, SOURCE_SECONDS, 3.8)
