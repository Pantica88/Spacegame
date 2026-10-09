extends SceneTree
const Craft = preload("res://scripts/craft_model.gd")
const Parts = preload("res://scripts/parts.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.design = Craft.project(Craft.migrate(Parts.default_design()), Parts.default_design())
	game._refresh_design(false)
	await process_frame
	var original: Array = game.design.assembly.stages.duplicate(true)
	game._move_action("ignite:engine", 1)
	check(game.design.assembly.stages.size() == original.size() - 1, "Moving sole item removes its source block")
	check(game.design.assembly.stages[0].has("ignite:engine") and game.design.assembly.stages[0].has("separate:decoupler"), "Destination survives source removal before its index")
	await process_frame
	game._undo_edit()
	check(game.design.assembly.stages == original, "Undo restores item and removed block together")
	game._move_action("deploy:capsule", 0)
	check(game.design.assembly.stages.size() == original.size() - 1, "Moving from later block also removes empty source")
	await process_frame
	var split_target = game.stage_preview.get_child(1 + game.design.assembly.stages.size())
	check(split_target._can_drop_data(Vector2.ZERO, {"stage_action":"deploy:capsule"}), "Split target accepts an item in a combined block")
	split_target._drop_data(Vector2.ZERO, {"stage_action":"deploy:capsule"})
	check(game.design.assembly.stages[1] == ["deploy:capsule"], "Item can be split back into its own block")
	check(game.design.assembly.stages.all(func(group): return not group.is_empty()), "Splitting creates no empty blocks")
	await process_frame
	game._move_stage(1, 0)
	check(game.design.assembly.stages[0] == ["deploy:capsule"], "Dragging a block changes activation order")
	await process_frame
	check(Craft.load_craft(game.design).stages == game.design.assembly.stages, "Arranged blocks survive serialization")
	var block = game.stage_preview.get_child(1)
	check(block._can_drop_data(Vector2.ZERO, {"stage_action":"ignite:engine"}), "Block accepts another activation item")
	check(not block._can_drop_data(Vector2.ZERO, {"stage_action":"ignite:missing"}), "Unknown items cannot corrupt staging")
	check(not block._can_drop_data(Vector2.ZERO, {"installed_part":"tank_1"}), "Passive tanks do not create activation items")
	# Eight-way copies must move atomically, including copies already at the target.
	var craft := Craft.migrate(Parts.default_design())
	var engines: Array[String] = []
	for index in range(8):
		Craft.add_part(craft, "separator", "tank_2")
		var mount: String = craft.parts[-1].id
		craft.parts[-1].rotation = 45.0 * index
		Craft.add_part(craft, "tank", mount)
		var tank: String = craft.parts[-1].id
		Craft.add_part(craft, "sparrow", tank)
		engines.append("ignite:" + str(craft.parts[-1].id))
	game.design = Craft.project(craft, Parts.default_design())
	game.radial_symmetry = 8
	game._refresh_design(false)
	await process_frame
	check(game._stage_drag_actions(engines[0]).size() == 8, "Eight matching engines form one drag payload")
	var before: Array = game.design.assembly.stages.duplicate(true)
	var destination := Craft._stage_index(game.design.assembly, engines[7])
	game._move_action(engines[0], destination)
	var merged := Craft._stage_index(game.design.assembly, engines[0])
	check(game.design.assembly.stages[merged].size() == 8, "Eight-way drop includes target copy without duplication")
	check(game.design.assembly.stages.size() == before.size() - 7, "All emptied source blocks disappear")
	check(Craft.valid(game.design.assembly), "Eight-item stage is saveable")
	await process_frame
	game._undo_edit()
	check(game.design.assembly.stages == before, "One undo restores entire symmetry move")
	game._move_action(engines[0], Craft._stage_index(game.design.assembly, "ignite:engine"), false)
	check(game.design.assembly.stages[0].size() == 2, "Single-item drag leaves symmetry partners in place")
	await process_frame
	game._split_stage_action(engines[0])
	merged = Craft._stage_index(game.design.assembly, engines[0])
	check(game.design.assembly.stages[merged].size() == 8, "New-block drop gathers all symmetry copies")
	check(game.design.assembly.stages[0] == ["ignite:engine"], "Unrelated core remains in original block")
	await process_frame
	check(Craft.load_craft(game.design).stages == game.design.assembly.stages, "Symmetry block survives save and reload")
	game.radial_symmetry = 1
	var display: Array = game._stage_display_groups(game.design.assembly.stages[merged])
	check(display.size() == 1 and display[0].size() == 8, "Display combines eight actual symmetry engines independently of selected count")
	check(game._stage_drag_actions(engines[0]).size() == 8, "Dragging displayed group preserves all eight members")
	await game._roll_out()
	game._update_flight_ui()
	await process_frame
	var staging_panel = game.flight_stage_list.get_parent().get_parent().get_parent()
	check(staging_panel.get_global_rect().end.y <= game.stage_button.get_parent().get_parent().get_global_rect().position.y, "Staging stays above activation controls")
	var flight_block = game.flight_stage_list.get_child(merged)
	check(flight_block.indicators.size() == 1, "Flight uses a single symmetry icon")
	check(not flight_block._can_drop_data(Vector2.ZERO, {"stage_action":"ignite:engine"}), "Flight staging rejects individual action drops")
	var gauge: Dictionary = flight_block.indicators[0]
	check(is_equal_approx(gauge.bar.value, 100.0), "Grouped fuel starts full")
	for member in engines:
		game.flight.state.engine_fuel[member.get_slice(":", 1)] *= 0.5
	game._update_flight_ui()
	check(is_equal_approx(gauge.bar.value, 50.0), "Grouped fuel reflects all engine reserves")
	var simultaneous: Dictionary = game.flight.telemetry().duplicate(true)
	simultaneous.stage_index = game.flight.staging_groups().size()
	simultaneous.engine_on = true
	simultaneous.active_engines = ["engine"]
	for member in engines: simultaneous.active_engines.append(member.get_slice(":", 1))
	var core_block = game.flight_stage_list.get_child(0)
	core_block.update_flight(simultaneous)
	flight_block.update_flight(simultaneous)
	check(core_block.custom_minimum_size.x == 216 and flight_block.custom_minimum_size.x == 216, "Concurrent active stages both expand")
	check(core_block.indicators[0].bar.visible and gauge.bar.visible and gauge.fuel.visible, "Concurrent stages both show fuel indicators")
	for member in engines: simultaneous.engine_fuel[member.get_slice(":", 1)] = 0.0
	flight_block.update_flight(simultaneous)
	check(flight_block.custom_minimum_size.x == 72 and not gauge.bar.visible, "Spent stage collapses while other stage remains active")
	game._update_flight_ui()
	var chute: Dictionary = {}
	for stage_card in game.flight_stage_list.get_children():
		for item in stage_card.indicators:
			if item.members[0] == "deploy:capsule": chute = item
	check(not chute.is_empty(), "Parachute has its own staging icon")
	if not chute.is_empty():
		var chute_block = game.flight_stage_list.get_child(Craft._stage_index(game.design.assembly, "deploy:capsule"))
		chute_block.update_flight({"status":"ready"})
		check(chute.icon.tint == Color("c4cece"), "Idle chute is neutral")
		chute_block.update_flight({"status":"flying", "chute_safe":false})
		check(chute.icon.tint == Color("ef746f"), "Unsafe chute is red")
		chute_block.update_flight({"status":"flying", "chute_safe":true})
		check(chute.icon.tint == Color("c4cece"), "Safe undeployed chute remains neutral")
		chute_block.update_flight({"status":"flying", "chute_deployed":true})
		check(chute.icon.tint == Color("8be0c5"), "Deployed chute is green")
	var workshop_order: Array = game.design.assembly.stages.duplicate(true)
	var flight_order: Array = game.flight.staging_groups().duplicate(true)
	var last: int = flight_order.size() - 1
	check(game.flight_stage_list.get_child(last)._can_drop_data(Vector2.ZERO, {"stage_group":0}), "Flight headers accept stage reordering")
	game._move_stage(last, 0)
	game._update_flight_ui()
	check(game.flight.staging_groups()[0] == flight_order[last], "Flight reorder changes the executable plan")
	check(game.design.assembly.stages == workshop_order, "Flight reorder preserves workshop design")
	game._move_stage(0, last)
	game.flight.execute_stage()
	check(not game.flight.can_reorder_stage(0, 1), "Completed stages cannot be moved or rearmed")
	var detached_actions: Array = game.flight.staging_groups()[merged].duplicate()
	game.flight.state.removed_parts.append(detached_actions[0].get_slice(":", 1))
	game._update_flight_ui()
	var remaining_cards: Array = game.flight_stage_list.get_children().filter(func(card): return card.index == merged)
	var remaining_count := 0
	for item in remaining_cards[0].indicators: remaining_count += item.members.size()
	check(remaining_count == detached_actions.size() - 1, "Mixed block keeps attached items and removes only the separated member")
	for action in detached_actions:
		if action.get_slice(":", 1) not in game.flight.state.removed_parts: game.flight.state.removed_parts.append(action.get_slice(":", 1))
	game._update_flight_ui()
	check(game.flight_stage_list.get_children().all(func(card): return card.index != merged), "Detached engine block is removed from flight display")
	game.flight.state.stage_index = merged
	game.flight.skip_detached_stages()
	check(game.flight.state.stage_index > merged, "Space skips blocks with no attached parts")
	game.flight.state.capsule_only = true
	game.flight.state.boosters_attached = false
	game._update_flight_ui()
	check(game.flight_stage_list.get_children().all(func(card): return card.indicators.all(func(item): return item.members[0] == "deploy:capsule")), "Capsule separation removes all discarded hardware blocks")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PASS: stage blocks, merging, splitting, reordering, undo and persistence" if failures.is_empty() else "FAIL: stage blocks")
	quit(0 if failures.is_empty() else 1)
