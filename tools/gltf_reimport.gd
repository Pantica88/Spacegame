extends SceneTree

func _init():
    call_deferred("_run")

func _run():
    var files = [
        "res://assets/models/engine/base_basic_pbr.glb",
        "res://assets/models/engine/base_basic_shaded.glb",
    ]
    for path in files:
        print("Reimporting: %s" % path)
        var doc = GLTFDocument.new()
        var state = GLTFState.new()
        var err = doc.append_from_file(path, state)
        if err != OK:
            printerr("Failed to open %s: %s" % [path, err])
            continue
        var scene_res = doc.generate_scene(state)
        if scene_res == null:
            printerr("Failed to generate scene for %s" % path)
            continue
        var out_path = path.replace(".glb", ".tscn")
        var packed = PackedScene.new()
        var pack_err = packed.pack(scene_res)
        if pack_err != OK:
            printerr("Failed to pack generated scene for %s: %s" % [path, pack_err])
            continue
        var save_err = ResourceSaver.save(packed, out_path)
        if save_err != OK:
            printerr("Failed to save %s: %s" % [out_path, save_err])
        else:
            print("Saved: %s" % out_path)
    quit()
