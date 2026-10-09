extends SceneTree
## Run on a graphical display; validates rendering and actual keyboard movement.
func _initialize() -> void:
 run.call_deferred()

func run() -> void:
 var world = load("res://scripts/hover_preview.gd").new()
 root.add_child(world)
 for frame in range(15): await process_frame
 assert(not world._rocket.visible)
 assert(world.camera.far / world.camera.near <= 4000001.0)
 var initial_position: Vector3 = world.hover_position
 var initial_sun: Vector3 = world.camera.basis.inverse() * world._sun_direction
 var wheel := InputEventMouseButton.new()
 wheel.button_index = MOUSE_BUTTON_WHEEL_UP
 wheel.pressed = true
 for notch in range(24): world._unhandled_input(wheel)
 world._update_camera()
 assert(world.hover_time > 0.0)
 assert(world.hover_position == initial_position, "Time scrubbing must preserve local position")
 var later_sun: Vector3 = world.camera.basis.inverse() * world._sun_direction
 assert(initial_sun.distance_to(later_sun) > 0.5, "Scrubbing must change local sunlight")
 assert(world.hover_speed == 50.0, "Wheel must not change movement speed")
 wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
 for notch in range(24): world._unhandled_input(wheel)
 world._update_camera()
 assert(absf(world.hover_time) < 0.001, "Wheel must scrub back to the original time")
 assert(initial_sun.distance_to(world.camera.basis.inverse() * world._sun_direction) < 0.001)
 if DisplayServer.get_name() != "headless":
  DisplayServer.window_move_to_foreground()
  for frame in range(5): await process_frame
  var start: Vector3 = world.hover_position
  var key := InputEventKey.new()
  key.physical_keycode = KEY_E
  key.pressed = true
  Input.parse_input_event(key)
  Input.flush_buffered_events()
  for frame in range(10): await process_frame
  key.pressed = false
  Input.parse_input_event(key)
  Input.flush_buffered_events()
  assert(world.hover_position.y > start.y, "E must move the camera upwards")
  var stopped: Vector3 = world.hover_position
  for frame in range(3): await process_frame
  assert(world.hover_position.is_equal_approx(stopped), "Camera must hover when keys are released")
  await RenderingServer.frame_post_draw
  var shot := root.get_texture().get_image()
  shot.save_png("/tmp/aphelion-hover-fixed.png")
  var center := shot.get_pixel(shot.get_width()/2, shot.get_height()/2)
  assert(maxf(center.r, maxf(center.g, center.b)) > 0.05, "Launch scenery must not render black")
 print("PASS: hover preview, camera frustum, and available graphical checks")
 quit()
