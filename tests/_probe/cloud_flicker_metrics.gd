extends SceneTree
## Per-frame error of cloud_flicker.gd captures against the reference frame,
## for spotting frames where clouds vanish. Reads $COMPARE_OUT.
func _initialize() -> void:
	var out := OS.get_environment("COMPARE_OUT")
	for frame in range(1000):
		var reference_path := "%s/f%03d-reference.png" % [out, frame]
		if not FileAccess.file_exists(reference_path): break
		var reference := Image.load_from_file(reference_path).get_data()
		var line := "f%03d" % frame
		for mode in ["compute", "reduced"]:
			var path := "%s/f%03d-%s.png" % [out, frame, mode]
			if not FileAccess.file_exists(path): continue
			var data := Image.load_from_file(path).get_data()
			var total := 0
			var large := 0
			for i in range(0, data.size(), 3):
				var d := maxi(absi(data[i] - reference[i]), maxi(absi(data[i + 1] - reference[i + 1]), absi(data[i + 2] - reference[i + 2])))
				total += d
				if d > 16: large += 1
			line += "  %s mean %.2f >16 %.2f%%" % [mode, float(total) / (data.size() / 3), 100.0 * large / (data.size() / 3)]
		print(line)
	quit(0)
