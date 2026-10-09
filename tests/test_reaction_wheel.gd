extends SceneTree
const Parts = preload("res://scripts/parts.gd")
const Craft = Parts.Craft
const Flight = preload("res://scripts/flight_model.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func flying(design: Dictionary):
	var flight = Flight.new()
	flight.reset(design)
	flight.state.status = "flying"
	flight.state.position = Vector3(0,Flight.PLANET_RADIUS+150000,0)
	flight.state.velocity = Vector3.ZERO
	return flight

func _run() -> void:
	var craft := Craft.migrate({"tanks":2,"engine":"sparrow","fins":false,"parachute":false})
	var bare := Craft.project(craft,Parts.default_design())
	var baseline := Parts.stats(bare)
	Craft.add_part(craft,"reaction_wheel")
	var first := Parts.reaction_wheels(Craft.project(craft,Parts.default_design()))[0].id as String
	Craft.add_part(craft,"reaction_wheel")
	check(Craft.valid(craft),"Multiple wheels form a valid assembly")
	var design := Craft.project(craft,Parts.default_design())
	var restored := Craft.load_craft({"assembly":JSON.parse_string(JSON.stringify(craft))})
	check(Craft.valid(restored) and restored.parts == Craft.load_craft({"assembly":craft}).parts and restored.stages == craft.stages,"Wheels survive JSON save/load")
	check(craft.stages == bare.assembly.stages,"Passive wheels need no staging action")
	check(is_equal_approx(Craft.stack_top(design)-Craft.stack_top(bare),.4),"Two 20 cm wheels occupy their own stack space")
	check(is_equal_approx(Parts.stats(design).wet_mass-baseline.wet_mass,100.0),"Two wheels add 100 kg")
	check(Parts.stats(design).cost-baseline.cost == 1300,"Wheel cost is included")
	check(is_equal_approx(Parts.mass_properties(design,1440,0,false).mass,Parts.stats(design).wet_mass),"Flight mass agrees with builder stats")
	for axis in ["pitch","yaw","roll"]:
		var normal = flying(bare)
		var nimble = flying(design)
		var controls := {"throttle":0.0,"sas":true,axis:1.0}
		normal.step(.2,controls)
		nimble.step(.2,controls)
		check(nimble.state.angular_velocity.length() > normal.state.angular_velocity.length()*1.4,axis+" responds faster with wheels")
		print("%s: %.3f -> %.3f rad/s" % [axis,normal.state.angular_velocity.length(),nimble.state.angular_velocity.length()])
	var idle = flying(design)
	idle.step(.1,{"throttle":0.0})
	check(idle.state.angular_velocity.is_zero_approx(),"Wheels do not spin craft without an input")
	var separated = flying(design)
	separated.execute_stage() # ignition
	separated.execute_stage() # capsule separation
	check(separated.state.capsule_only,"Capsule separates above the wheel stack")
	separated.state.angular_velocity = Vector3.ZERO
	var reference = flying(bare)
	reference.execute_stage()
	reference.execute_stage()
	reference.state.angular_velocity = Vector3.ZERO
	for f in [separated,reference]: f.step(.1,{"pitch":1.0,"throttle":0.0})
	check(separated.state.angular_velocity.is_equal_approx(reference.state.angular_velocity),"Detached wheels supply no capsule torque")
	check(is_equal_approx(separated._current_mass(),Parts.CAPSULE_MASS),"Separated capsule sheds wheel mass")
	var removed := craft.duplicate(true)
	Craft.remove_part(removed,first)
	check(Craft.valid(removed) and Parts.reaction_wheels(Craft.project(removed,{})).is_empty(),"Removing the wheel returns its connected subassembly")
	var empty := {"parts":[],"stages":[],"next_id":1}
	Craft.add_part(empty,"capsule")
	Craft.add_part(empty,"reaction_wheel")
	Craft.add_part(empty,"tank")
	Craft.add_part(empty,"sparrow")
	Craft.add_part(empty,"decoupler")
	check(Craft.valid(empty),"Wheel-first build accepts tank, engine and later decoupler")
	# A ring beneath the gyro releases only the lower stage and retains control.
	var retained_craft := Craft.seed()
	Craft.add_part(retained_craft,"capsule")
	Craft.add_part(retained_craft,"reaction_wheel")
	var retained_id: String = retained_craft.parts[-1].id
	Craft.add_part(retained_craft,"tank")
	Craft.add_part(retained_craft,"sparrow")
	var before_ring := Craft.project(retained_craft,Parts.default_design())
	Craft.add_part(retained_craft,"decoupler",retained_id)
	var rings: Array = retained_craft.parts.filter(func(part): return part.kind == "decoupler")
	check(rings.size() == 1 and rings[0].parent == retained_id,"Decoupler inserts beneath an existing gyro")
	var retained_design := Craft.project(retained_craft,Parts.default_design())
	check(Craft.valid(retained_craft),"Gyro-mounted decoupler saves as a valid assembly")
	check(is_equal_approx(Craft.stack_top(retained_design)-Craft.stack_top(before_ring),.2),"Lower decoupler reserves its own 20 cm slot")
	check(is_equal_approx(Craft.part_base(retained_design,retained_id),Craft.part_base(retained_design,rings[0].id)+.2),"Gyro and lower decoupler meet without overlapping")
	var retained = flying(retained_design)
	retained.execute_stage()
	retained.execute_stage()
	check(not retained.state.capsule_only and retained_id not in retained.state.removed_parts,"Separation keeps the gyro on the capsule")
	check(rings[0].id in retained.state.removed_parts and "engine" in retained.state.removed_parts,"Separation sheds the ring and lower engine")
	check(is_equal_approx(retained._current_mass(),Parts.CAPSULE_MASS+Parts.REACTION_WHEEL_MASS),"Retained vehicle includes gyro mass")
	retained.step(.1,{"pitch":1.0,"throttle":0.0})
	check(retained.state.angular_velocity.length() > .5,"Retained gyro supplies torque after staging")
	var wheel_model := (load("res://assets/models/gyro_1/gyro_1.glb") as PackedScene).instantiate()
	var bounds := AABB()
	for mesh in wheel_model.find_children("*","MeshInstance3D",true,false): bounds = bounds.merge(mesh.get_aabb())
	check(bounds.size.y <= .22 and bounds.size.x <= 2.05 and bounds.size.x >= 1.89,"Wheel fits the Atlas decoupler envelope")
	wheel_model.free()
	var baked: ArrayMesh = load("res://assets/models/flight/gyro_1.res")
	check(baked.get_meta("source_sha256") == FileAccess.get_sha256("res://assets/models/gyro_1/gyro_1.glb"),"Large-craft wheel mesh matches authored source")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.design = bare.duplicate(true)
	game._refresh_design()
	await process_frame
	check(game._part_available("reaction_wheel"),"Wheel catalogue unlocks with capsule")
	var anchor: Vector3 = game.world._rocket.to_global(Vector3(0,game.world._capsule_center_local,0))
	var snap: Vector3 = game.world._rocket.to_global(game._snap_candidates("reaction_wheel")[0][1])
	game._attach_part("reaction_wheel","reaction_wheel")
	await process_frame
	await process_frame
	var installed: String = Parts.reaction_wheels(game.design)[0].id
	check(game.world._rocket.to_global(game.world.installed_part_position(installed)).is_equal_approx(snap),"Drag preview aligns with installed wheel")
	check(game.world._rocket.to_global(Vector3(0,game.world._capsule_center_local,0)).is_equal_approx(anchor),"Wheel insertion keeps capsule fixed")
	check(game.attachment_layer.get_children().any(func(p): return p.get("part_id") == installed),"Installed wheel has selection handle")
	game.world.preview_part(installed)
	check(game.world._edit_preview.get_child_count() > 0,"Wheel selection uses its model")
	var lower_slot := "decoupler@"+installed
	check(game._can_attach("decoupler",lower_slot),"Workshop accepts decoupler below gyro")
	var targets: Array = game._snap_candidates("decoupler").filter(func(candidate): return candidate[0] == lower_slot)
	check(targets.size() == 1,"Lower gyro connection is exposed to dragging")
	var target: Vector3 = game.world._rocket.to_global(targets[0][1])
	var pointer: Vector2 = game.world.camera.unproject_position(target)
	check(game._update_build_drag("decoupler",pointer) and game.drag_snap_slot == lower_slot,"Dragging targets the lower gyro socket")
	game._finish_build_drag("decoupler",pointer)
	await process_frame
	await process_frame
	var lower: Dictionary = game.design.assembly.parts.filter(func(part): return part.parent == installed and part.kind == "decoupler")[0]
	check(game.world._rocket.to_global(game.world.installed_part_position(lower.id)).is_equal_approx(target),"Lower ring preview matches final position")
	check(not game._can_attach("decoupler",lower_slot),"An occupied gyro socket rejects a second decoupler")
	check(game.world._rocket.find_children("*","Node3D",true,false).any(func(n): return n.get_meta("part_id","") == lower.id),"Gyro-mounted ring has a rendered model")
	game._remove_attachment(installed)
	await process_frame
	check(Parts.reaction_wheels(game.design).is_empty(),"Delete removes wheel")
	game._undo_edit()
	await process_frame
	check(Parts.reaction_wheels(game.design).size() == 1 and game.design.tanks == 2,"Undo restores wheel and connected stack")
	game._redo_edit()
	await process_frame
	check(Parts.reaction_wheels(game.design).is_empty(),"Redo reapplies wheel removal")
	game.sound.shutdown()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("PASS: reaction wheel assembly, saves, mass, torque, staging and workshop")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
