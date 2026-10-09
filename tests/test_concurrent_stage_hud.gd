extends SceneTree
func _initialize():
	run.call_deferred()
func run():
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var design = game.Parts.default_design()
	design.erase("assembly")
	design.boosters = true
	var craft = game.Parts.Craft.migrate(design)
	craft.stages = [["ignite:engine"], ["ignite:boosters"], ["separate:boosters"], ["separate:decoupler"], ["deploy:capsule"]]
	game.design = game.Parts.Craft.project(craft, design)
	await game._roll_out()
	game._stage()
	game._stage()
	await process_frame
	var core = game.flight_stage_list.get_child(0)
	var boosters = game.flight_stage_list.get_child(1)
	if core.custom_minimum_size.x != 216 or boosters.custom_minimum_size.x != 216 or not core.indicators[0].bar.visible or not boosters.indicators[0].bar.visible:
		push_error("Concurrent staging did not retain both fuel panels")
		quit(1)
		return
	print("PASS: actual core ignition followed by booster ignition keeps both fuel panels expanded")
	quit()
