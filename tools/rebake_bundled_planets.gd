extends SceneTree
## Re-bake every bundled planet and its moons for the running engine. The bake
## signature includes the engine version, so run this once after each engine
## upgrade (docs/FOUNDATION_REVIEW.md, entry 1):
##   tools/run.sh --headless --script res://tools/rebake_bundled_planets.gd
## Writes new bakes to assets/planets/{,moons/}baked/ (ignored by git) and
## updates the .tres references, which are committed. Old bakes stay on disk
## for branches and rollbacks still on the old engine;
## tools/cleanup_planet_bakes.gd lists them. The player's saved planets in
## user://planets are not touched; re-save those from the planet editor.
const Baker = preload("res://scripts/planet_baker.gd")
const Terrain = preload("res://scripts/planet_terrain.gd")
const PLANETS := ["res://assets/planets/verdant.tres", "res://assets/planets/ochre.tres"]

func _initialize() -> void:
	print("Engine: ", Engine.get_version_info().string)
	for path in PLANETS:
		# load(), not preload(): see planet_surface.gd (preload-order engine bug).
		var settings: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if settings == null:
			printerr("Cannot load ", path)
			quit(1)
			return
		var started := Time.get_ticks_msec()
		# _save_planet, not save_planet: skip its orphan cleanup, which would
		# delete the previous engine's bakes that other branches still use.
		var error := Baker._save_planet(settings, path, PackedStringArray())
		if error != OK:
			printerr("Bake failed for %s: %s" % [path, error_string(error)])
			quit(1)
			return
		var saved: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var current: bool = saved.baked_terrain != null and saved.baked_terrain.signature == Terrain.bake_signature(saved)
		print("%s: %s in %.1f s, signature %s" % [path, "baked" if current else "STALE", (Time.get_ticks_msec() - started) / 1000.0, saved.baked_terrain.signature if saved.baked_terrain else "none"])
		if not current:
			quit(1)
			return
		for moon in saved.moons:
			var moon_current: bool = moon.baked_terrain != null and moon.baked_terrain.signature == Terrain.bake_signature(moon)
			print("  moon %s: %s" % [moon.planet_name, "baked" if moon_current else "STALE"])
			if not moon_current:
				quit(1)
				return
	quit(0)
