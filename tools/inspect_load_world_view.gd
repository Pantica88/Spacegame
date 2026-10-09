extends SceneTree

func _init():
    call_deferred("_run")

func _run():
    var path := "res://scripts/world_view.gd"
    print("Attempting to load: %s" % path)
    var ok := ResourceLoader.exists(path)
    print("exists: %s" % ok)
    var script = load(path)
    if script == null:
        print("load returned null")
    else:
        print("loaded script class: %s" % script.get_class())
    quit()
