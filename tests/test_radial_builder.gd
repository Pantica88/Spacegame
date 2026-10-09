extends SceneTree
const Craft = preload("res://scripts/craft_model.gd")
const Parts = preload("res://scripts/parts.gd")
var game: Node
var failures: Array[String] = []
func check(ok: bool, label: String):
	if not ok: failures.append(label)
func _initialize(): call_deferred("run")
func run():
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	for count in [1,2,4,6,8]:
		game.design = Craft.project(Craft.migrate(Parts.default_design()),Parts.default_design())
		game.radial_symmetry = count
		game._refresh_design(false)
		await process_frame
		var camera_local: Vector3 = game.world._rocket.to_local(game.world.camera.global_position)
		var angle := atan2(camera_local.x,camera_local.z)+.20
		var point := Vector3(sin(angle)*.94,Craft.tank_center(game.design,"tank_2")+.23,cos(angle)*.94)
		var screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(point))
		check(game._update_build_drag("separator",screen),"Tank surface drag valid %d"%count)
		check(game.radial_snap.get("placements",[]).size() == count,"Symmetry preview %d"%count)
		game._finish_build_drag("separator",screen)
		await process_frame
		await process_frame
		var mounts := Craft.radial_instances(game.design,"separator")
		check(mounts.size() == count,"Installed mount count %d"%count)
		if mounts.size() != count: continue
		check(absf(mounts[0].position.y-point.y) < .002,"Continuous vertical placement %d"%count)
		check(absf(angle_difference(mounts[0].angle,angle)) < .002,"Continuous angle placement %d"%count)
		check(not game._update_build_drag("separator",screen),"Duplicate overlap rejected %d"%count)
		game._clear_build_drag()
		var target: Vector3 = mounts[0].position
		target.x *= 1.96/1.17; target.z *= 1.96/1.17
		var booster_screen: Vector2 = game.world.camera.unproject_position(game.world._rocket.to_global(target))
		game._finish_build_drag("boosters",booster_screen)
		await process_frame
		await process_frame
		check(Craft.radial_instances(game.design,"boosters").size() == count,"Booster symmetry snap %d"%count)
		check(game.world._booster_flames.size() == count*4,"Four flames per installed booster %d"%count)
		check(Craft.valid(game.design.assembly),"Serialized UI graph %d"%count)
		check(game.world.installed_part_position(mounts[0].id).distance_to(mounts[0].position) < .001,"Picker tracks arbitrary surface position %d"%count)
		if count == 4 and DisplayServer.get_name() != "headless":
			game.selected_part = ""
			game.highlight_action = ""
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/radial-symmetry-four.png")
		var first: String = mounts[0].id
		game._checkpoint()
		Craft.remove_part(game.design.assembly,first)
		game._refresh_design(false)
		check(Craft.radial_instances(game.design,"separator").size() == count-1,"Remove individual mount %d"%count)
		check(Craft.radial_instances(game.design,"boosters").size() == count-1,"Remove attached child %d"%count)
		game._undo_edit()
		await process_frame
		check(Craft.radial_instances(game.design,"boosters").size() == count,"Undo whole child attachment %d"%count)
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: Single/2/4/6/8 surface placement, previews, boosters, removal and undo" if failures.is_empty() else "FAIL: radial builder")
	quit(0 if failures.is_empty() else 1)
