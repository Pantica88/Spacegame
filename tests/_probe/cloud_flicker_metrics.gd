extends SceneTree
## Scores cloud_flicker.gd captures in $COMPARE_OUT. For each mode: how much
## the image changes between consecutive frames (share of pixels changing by
## more than 24/255; a vanishing cloud patch shows as a spike), and its error
## against the reference frame. FLICKER_MODES picks the modes to score.

func _initialize() -> void:
	var out := OS.get_environment("COMPARE_OUT")
	var modes: Array = Array(OS.get_environment("FLICKER_MODES").split(",")) if OS.get_environment("FLICKER_MODES") != "" else ["reference", "reduced"]
	for mode in modes:
		var changes: Array[float] = []
		var errors: Array[float] = []
		var previous := PackedByteArray()
		for frame in range(10000):
			var path := "%s/f%03d-%s.png" % [out, frame, mode]
			if not FileAccess.file_exists(path): break
			var data := Image.load_from_file(path).get_data()
			if not previous.is_empty():
				changes.append(_share(data, previous, 24))
			previous = data
			var reference := "%s/f%03d-reference.png" % [out, frame]
			if mode != "reference" and FileAccess.file_exists(reference):
				errors.append(_share(data, Image.load_from_file(reference).get_data(), 16))
		if changes.is_empty(): continue
		var order := range(changes.size())
		order.sort_custom(func(a: int, b: int) -> bool: return changes[a] > changes[b])
		var top := []
		for i in order.slice(0, 6): top.append("f%03d %.2f%%" % [i + 1, changes[i]])
		var sorted := changes.duplicate()
		sorted.sort()
		var line := "%-18s change median %.2f%% max %.2f%% (spike %.1fx)  top: %s" % [mode, sorted[sorted.size() / 2], sorted[-1], sorted[-1] / maxf(sorted[sorted.size() / 2], 0.01), ", ".join(top)]
		if not errors.is_empty():
			var total := 0.0
			for e in errors: total += e
			line += "  | vs reference >16: mean %.2f%% max %.2f%%" % [total / errors.size(), errors.max()]
		print(line)
	quit(0)

## Percent of pixels whose largest channel differs by more than threshold.
static func _share(a: PackedByteArray, b: PackedByteArray, threshold: int) -> float:
	var large := 0
	for i in range(0, a.size(), 3):
		if maxi(absi(a[i] - b[i]), maxi(absi(a[i + 1] - b[i + 1]), absi(a[i + 2] - b[i + 2]))) > threshold: large += 1
	return 100.0 * large / (a.size() / 3)
