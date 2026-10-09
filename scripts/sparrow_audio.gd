extends "res://scripts/recorded_engine_audio.gd"
const RECORDING = preload("res://assets/audio/sparrow_engine.wav")
const SOURCE_SECONDS := 9.0

func _init() -> void:
	super(RECORDING, SOURCE_SECONDS, 9.0, 1.0)
