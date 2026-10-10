extends SceneTree
## Scores cloud_fullres_compare.gd captures in $COMPARE_OUT against their
## references: mean RGB error, share of pixels off by more than 8/255, and
## detail (summed luminance gradients) relative to the reference.

func _initialize() -> void:
	var out := OS.get_environment("COMPARE_OUT")
	var names := {}
	for file in DirAccess.get_files_at(out):
		if file.ends_with("-reference.png"):
			names[file.trim_suffix("-reference.png")] = true
	var keys := names.keys()
	keys.sort()
	for name in keys:
		var reference := Image.load_from_file("%s/%s-reference.png" % [out, name])
		var detail := _detail(reference)
		var line := "%-16s" % name
		for mode in ["reference2", "reduced"]:
			var path := "%s/%s-%s.png" % [out, name, mode]
			if not FileAccess.file_exists(path): continue
			var image := Image.load_from_file(path)
			var d := _diff(image, reference)
			line += "  %s: mean %.2f  >8 %.2f%%  detail %.3f" % [mode, d[0], d[1], _detail(image) / detail]
		print(line)
	quit(0)

func _diff(a: Image, b: Image) -> Array:
	var da := a.get_data()
	var db := b.get_data()
	var step := 4 if a.get_format() == Image.FORMAT_RGBA8 else 3
	var total := 0.0
	var large := 0
	for i in range(0, da.size(), step):
		var d := maxi(absi(da[i] - db[i]), maxi(absi(da[i + 1] - db[i + 1]), absi(da[i + 2] - db[i + 2])))
		total += absi(da[i] - db[i]) + absi(da[i + 1] - db[i + 1]) + absi(da[i + 2] - db[i + 2])
		if d > 8: large += 1
	var n := da.size() / step
	return [total / (n * 3.0), 100.0 * large / n]

func _detail(image: Image) -> float:
	var data := image.get_data()
	var step := 4 if image.get_format() == Image.FORMAT_RGBA8 else 3
	var width := image.get_width()
	var row := width * step
	var total := 0.0
	for y in range(image.get_height() - 1):
		for x in range(width - 1):
			var i := y * row + x * step
			var here := data[i] + data[i + 1] * 2 + data[i + 2]
			total += absi(here - (data[i + step] + data[i + step + 1] * 2 + data[i + step + 2])) \
				+ absi(here - (data[i + row] + data[i + row + 1] * 2 + data[i + row + 2]))
	return total
