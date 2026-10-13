extends SceneTree
## Cycles the F10 cloud composite variants in the hover view and prints the
## overlay readout for each. Run with --profile-gpu.
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var hover: Node = load("res://scenes/hover_preview.tscn").instantiate()
	root.add_child(hover)
	for i in range(120): await process_frame
	var overlay: Node = hover.find_children("*", "CanvasLayer", true, false).filter(func(n): return n.has_method("_set_variant"))[0]
	for v in [1, 2, 3, 4, 0]:
		overlay._set_variant(v)
		for i in range(90): await process_frame
		print("VARIANT %d %s  %s" % [v, overlay.VARIANT_NAMES[v], overlay._label.text.replace("\n", " | ")])
	quit(0)
