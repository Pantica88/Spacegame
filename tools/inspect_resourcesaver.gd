extends SceneTree

func _init():
    call_deferred("_run")

func _run():
    var rs = ResourceSaver
    print("ResourceSaver methods:")
    for m in rs.get_method_list():
        print(m)
    quit()
