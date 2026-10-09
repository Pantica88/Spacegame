extends SceneTree
const Craft = preload("res://scripts/craft_model.gd")
const Parts = preload("res://scripts/parts.gd")
const World = preload("res://scripts/world_view.gd")

func _initialize() -> void:
	run.call_deferred()

func lowest_mesh(node: Node3D, parent_transform: Transform3D = Transform3D.IDENTITY) -> float:
	if not node.visible or node.has_meta("engine_exhaust") or node.has_meta("heat_trail"):
		return INF
	var transform := parent_transform * node.transform
	var bottom := INF
	if node is MeshInstance3D and node.mesh != null:
		bottom = (transform * node.get_aabb()).position.y
	for child in node.get_children():
		if child is Node3D:
			bottom = minf(bottom, lowest_mesh(child, transform))
	return bottom

func run() -> void:
	var world := World.new()
	root.add_child(world)
	world.set_mode("flight")
	for engine in ["sparrow", "kestrel", "titan"]:
		for side_stage in ["none", "tank", "boosters"]:
			var craft := Craft.seed()
			Craft.add_part(craft, "capsule")
			Craft.add_part(craft, "tank")
			Craft.add_part(craft, engine)
			if side_stage != "none":
				var tank: String = craft.parts.filter(func(part): return part.kind == "tank")[0].id
				Craft.add_part(craft, "separator", tank)
				var mount: String = craft.parts[-1].id
				Craft.add_part(craft, side_stage, mount)
				if side_stage == "tank":
					Craft.add_part(craft, "sparrow", craft.parts[-1].id)
			var design := Craft.project(craft, Parts.default_design())
			world.set_design(design)
			world.sync_flight({"position":Vector3.ZERO,"orientation":Basis.IDENTITY}, 0.0)
			var bottom := lowest_mesh(world._rocket)
			assert(absf(bottom) < 0.002, "%s side=%s: visible hull touches launch datum, got %f" % [engine, side_stage, bottom])
	world.free()
	print("PASS: Sparrow, Kestrel and Titan hulls meet ground datum with and without side stages")
	quit()
