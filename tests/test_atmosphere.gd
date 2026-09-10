extends SceneTree
## Graphical regression: tools/run.sh --script res://tests/test_atmosphere.gd
const World = preload("res://scripts/world_view.gd")
var world: Node3D
var failures: Array[String] = []
var output_dir := "/tmp/aphelion-atmosphere"

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Atmosphere rendering checks require a graphical display.")
		quit(1)
		return
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	world = World.new()
	root.add_child(world)
	world.set_mode("flight")
	var initial_sun: Vector3 = world._sun_direction
	world.advance_solar_time(World.SOLAR_DAY_SECONDS * 0.25)
	check(world._sun_direction.distance_to(initial_sun) > 0.5, "Sun advances with simulation time")
	var quarter_sun: Vector3 = world._sun_direction
	world.advance_solar_time(-1.0)
	check(world._sun_direction.is_equal_approx(quarter_sun), "Invalid or negative time does not reverse the sun")
	world.set_mode("flight")
	world.advance_solar_time(World.PLANET_ROTATION_SECONDS*0.25)
	check(world._planet.basis.x.distance_to(Vector3.RIGHT) > 1.0, "Planet rotates a quarter turn with simulation time")
	check(world._planet.basis.is_equal_approx(world._landscape.basis), "Launch structures follow the rotating surface")
	check((world._planet.basis*Vector3.UP).is_equal_approx(Vector3.UP), "Polar launchpad remains attached to its surface position")
	world.advance_solar_time(World.PLANET_ROTATION_SECONDS*0.75)
	check(world._planet.basis.is_equal_approx(Basis.IDENTITY), "Planet rotation wraps continuously after a full turn")
	world.set_mode("flight")
	world._rocket.hide()
	_pose(Vector3(0,160000,0))
	world._landscape.hide()
	world.camera.position = Vector3.ZERO
	world.camera.far = 500000.0
	world.camera.look_at(world._planet.position, Vector3.FORWARD)
	world.set_sun_direction(Vector3.UP)
	var day := await capture("orbital-day")
	check(world._sun.global_basis.z.dot(Vector3.UP) > 0.9999, "Sky and scene light share the same sunlight direction")
	world.set_sun_direction(Vector3(1,-0.18,0))
	var dusk := await capture("orbital-sunset")
	check(difference(day,dusk) > 0.015, "Sun incidence changes atmosphere and planet lighting")
	world.set_sun_direction(Vector3.DOWN)
	var night := await capture("orbital-night")
	check(brightness(night) < brightness(day)*0.35, "Night hemisphere and atmosphere are dimmer than daylight")
	check(world._sun.light_energy < 0.001, "Planet eclipses direct sunlight on the craft at night")
	world.set_sun_direction(Vector3.UP)
	# Look toward the low sun from just above the launch site.
	_pose(Vector3(0,30,0))
	world._landscape.hide()
	world.camera.position = Vector3(0,10,0)
	world.camera.look_at(Vector3(0,40,-1000),Vector3.UP)
	world.set_sun_direction(Vector3(0,0.025,-1))
	var ground_sunset := await capture("ground-sunset")
	world.set_sun_direction(Vector3(0,0.8,-0.6))
	var ground_day := await capture("ground-day")
	check(warmth(ground_sunset) > warmth(ground_day)+0.025, "Low-angle sun produces warmer sky light than daytime")
	world.set_mode("workshop")
	var workshop_sun: Vector3 = world._sun_direction
	world.advance_solar_time(World.SOLAR_DAY_SECONDS * 0.25)
	check(world._sun_direction.is_equal_approx(workshop_sun), "Workshop keeps its fixed studio sunlight")
	check(not world._planet.visible and world._sky_material.get_shader_parameter("workshop"), "Workshop hides the planetary weather and restores indoor sky")
	check(is_equal_approx(world._sun.light_energy,1.15) and is_equal_approx(world._fill.light_energy,0.22), "Workshop restores its lighting after a night-side flight")
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: moving sunlight, alignment, sunset/night lighting, eclipse and workshop reset. Captures: " + output_dir)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _pose(position: Vector3) -> void:
	world.sync_flight({"position":position,"altitude":(position+Vector3(0,60000,0)).length()-60000.0,"orientation":Basis.IDENTITY,"engine_on":false,"fuel":0.0,"boosters_attached":false,"capsule_only":false,"chute_deployed":false},0.0)

func capture(label: String) -> Image:
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	check(result.save_png(output_dir.path_join(label+".png")) == OK, "Save " + label)
	return result

func brightness(frame: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0,frame.get_height(),8):
		for x in range(0,frame.get_width(),8):
			var color := frame.get_pixel(x,y)
			total += color.r*0.2126+color.g*0.7152+color.b*0.0722
			count += 1
	return total/float(count)

func warmth(frame: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0,int(frame.get_height()*0.45),8):
		for x in range(0,frame.get_width(),8):
			var color := frame.get_pixel(x,y)
			total += color.r-color.b
			count += 1
	return total/float(count)

func difference(first: Image, second: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0,first.get_height(),8):
		for x in range(0,first.get_width(),8):
			var a := first.get_pixel(x,y)
			var b := second.get_pixel(x,y)
			total += (absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b))/3.0
			count += 1
	return total/float(count)
