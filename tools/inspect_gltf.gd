extends SceneTree

func _init():
    call_deferred("_run")

func _run():
    var doc = GLTFDocument.new()
    print("GLTFDocument methods:")
    for m in doc.get_method_list():
        if m.name == "append_from_file" or m.name == "generate_scene":
            print(m)
    # print a short sample of all methods
    var count = 0
    for m in doc.get_method_list():
        if count >= 20:
            break
        print(m.name)
        count += 1
    quit()