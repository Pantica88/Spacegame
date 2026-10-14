extends SceneTree
## Rewrite THIRD_PARTY_NOTICES.md's engine sections from the running engine's
## own license data. Run after each engine upgrade:
##   tools/run.sh --headless --script res://tools/third_party_notices.gd
## Text above "## Godot <version> engine license" is kept, with the version
## number replaced; everything from that heading on is regenerated.
const PATH := "res://THIRD_PARTY_NOTICES.md"

func _initialize() -> void:
	var info := Engine.get_version_info()
	var version := "%d.%d.%d" % [info.major, info.minor, info.patch] if info.patch > 0 else "%d.%d" % [info.major, info.minor]
	var existing := FileAccess.get_file_as_string(PATH)
	var marker := RegEx.create_from_string("(?m)^## Godot ([0-9.]+) engine license$")
	var found := marker.search(existing)
	if found == null:
		printerr("No engine license heading in ", PATH)
		quit(1)
		return
	var previous := found.get_string(1)
	var lines := PackedStringArray([existing.substr(0, found.get_start()).replace(previous, version).strip_edges(false, true), ""])
	lines.append("## Godot %s engine license" % version)
	lines.append("")
	_block(lines, Engine.get_license_text())
	lines.append("## Godot %s component copyrights" % version)
	lines.append("")
	for component: Dictionary in Engine.get_copyright_info():
		lines.append("### " + str(component.name))
		lines.append("")
		for part: Dictionary in component.parts:
			var text := PackedStringArray(["Files: " + ", ".join(PackedStringArray(part.files))])
			for holder in part.copyright:
				text.append("Copyright (c) " + str(holder))
			text.append("License: " + str(part.license))
			_block(lines, "\n".join(text))
	lines.append("## Component license texts")
	lines.append("")
	var licenses := Engine.get_license_info()
	var names: Array = licenses.keys()
	names.sort()
	for name in names:
		lines.append("### " + str(name))
		lines.append("")
		_block(lines, str(licenses[name]))
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("\n".join(lines).strip_edges(false, true) + "\n")
	file.close()
	print("Wrote engine notices for Godot %s (previously %s)." % [version, previous])
	quit(0)

func _block(lines: PackedStringArray, text: String) -> void:
	lines.append("```text")
	lines.append(text.strip_edges(false, true))
	lines.append("```")
	lines.append("")
