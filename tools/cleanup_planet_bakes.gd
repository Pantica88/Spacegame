extends SceneTree
## Run with tools/run.sh --headless --script res://tools/cleanup_planet_bakes.gd
## Add -- --delete to delete the listed orphans; the default only reports them.
const BakeStorage = preload("res://scripts/planet_bake_storage.gd")

func _initialize() -> void:
	var delete_files := false
	for argument in OS.get_cmdline_user_args():
		if argument == "--delete":
			delete_files = true
		elif argument != "--dry-run":
			printerr("Usage: tools/run.sh --headless --script res://tools/cleanup_planet_bakes.gd [-- --dry-run|--delete]")
			quit(1)
			return
	if OS.get_cmdline_user_args().has("--dry-run") and delete_files:
		printerr("Choose either --dry-run or --delete.")
		quit(1)
		return
	var report := BakeStorage.cleanup(BakeStorage.PLANETS, [], delete_files)
	if report.error != OK:
		printerr("Bake cleanup failed: %s (%s); %d files deleted." % [report.message, error_string(report.error), report.deleted])
		quit(1)
		return
	for candidate: Dictionary in report.files:
		print("%s %s (%.2f MiB)" % ["Deleted" if delete_files else "Would delete", candidate.path, float(candidate.bytes) / 1048576.0])
	print("%s: %d orphaned bakes, %d bytes (%.2f MiB)." % ["Deleted" if delete_files else "Dry run", report.files.size(), report.bytes, float(report.bytes) / 1048576.0])
	if not delete_files:
		print("No files deleted. Add -- --delete to remove these orphans.")
	quit(0)
