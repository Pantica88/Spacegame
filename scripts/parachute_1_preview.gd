extends "res://scripts/explorer_1_preview.gd"
var deployed := false

func _process(delta: float) -> void:
	super._process(delta)
	var module := get_node_or_null("Parachute1")
	if module != null:
		if "--deployed" in OS.get_cmdline_user_args():
			module.advance(true, 3.0)
			if not module.has_meta("settled_preview"):
				for frame in range(180): module.advance(true, 1.0 / 60.0)
				module.set_meta("settled_preview", true)
		else:
			module.advance(deployed, delta)

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P: deployed = true
		if event.keycode == KEY_R: deployed = false
