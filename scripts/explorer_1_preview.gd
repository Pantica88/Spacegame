extends Node3D
## Standalone asset turntable: drag to orbit, wheel to zoom, Space to rotate.
@export var asset: PackedScene = preload("res://assets/models/explorer_1/explorer_1.glb")
@export var target := Vector3(0,1.23,0)
@export_multiline var caption := "EXPLORER–1  /  CREW CAPSULE\nExterior asset • 39k triangles"
@export var screenshot_path := "res://assets/models/explorer_1/preview.png"
@export var initial_pitch := 0.18
@export var initial_distance := 5.2
var camera: Camera3D
var yaw := 0.58
var pitch := 0.18
var distance := 5.2
var rotating := false

func _ready() -> void:
	pitch = initial_pitch
	distance = initial_distance
	var capsule := asset.instantiate()
	add_child(capsule)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("192530")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b6c8dc")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	for item in [[Vector3(-45,-35,0),1.8,Color("fff0da")],[Vector3(-20,130,0),1.2,Color("c5ddff")]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = item[0]
		light.light_energy = item[1]
		light.light_color = item[2]
		add_child(light)
	camera = Camera3D.new()
	camera.fov = 37
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = caption + "\n\nDrag to orbit · Scroll to zoom · Space to rotate"
	label.position = Vector2(32,28)
	label.add_theme_font_size_override("font_size",20)
	layer.add_child(label)
	_update_camera()
	if "--asset-screenshot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		get_tree().quit()

func _process(delta: float) -> void:
	if rotating:
		yaw += delta * 0.25
		_update_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.008, -1.2, 1.2)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(2.8,distance-0.3)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(maxf(9.0,initial_distance*1.6),distance+0.3)
		_update_camera()
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		rotating = not rotating

func _update_camera() -> void:
	camera.position = target + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.look_at(target)
