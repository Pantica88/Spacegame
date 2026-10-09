extends SceneTree
const Craft = preload("res://scripts/craft_model.gd")
const Fixture = preload("res://tests/large_craft_fixture.gd")
func _initialize() -> void:
	var design := Fixture.design()
	var initial := Craft.geometry(design)
	var mounts: Array = design.assembly.parts.filter(func(part): return part.kind == "separator")
	var mount: Dictionary = mounts[0]
	var tank: Dictionary = design.assembly.parts.filter(func(part): return part.kind == "tank" and part.parent == mount.id)[0]
	var position: Vector3 = Craft.lateral_position(design, tank.id)
	mount.rotation += 90.0
	assert(Craft.lateral_position(design, tank.id).is_equal_approx(position.rotated(Vector3.UP, PI/2)), "In-place rotations invalidate geometry")
	var base: float = Craft.part_base(design, tank.id)
	mount.surface_offset += 0.25
	assert(is_equal_approx(Craft.part_base(design, tank.id), base+0.25), "Offset edits invalidate geometry")
	var clone: Dictionary = design.duplicate(true)
	var cloned_mount: Dictionary = Craft.radial_mount(clone.assembly, tank.id)
	assert(is_same(cloned_mount, clone.assembly.parts.filter(func(part): return part.id == mount.id)[0]), "Lookups return the caller's own parts")
	cloned_mount.rotation += 90.0
	assert(not Craft.lateral_position(clone, tank.id).is_equal_approx(Craft.lateral_position(design, tank.id)), "Clone mutations remain isolated")
	for i in range(20):
		Craft.geometry(design.duplicate(true))
	assert(Craft._geometry_cache.size() <= Craft.GEOMETRY_CACHE_LIMIT, "Cached craft count is bounded")
	assert(not is_same(initial, Craft.geometry(design)), "Old computed positions are not reused after mutation")
	print("PASS: geometry invalidation, clone ownership and bounded retention")
	quit()
