extends Node3D
## All visual geometry is generated locally. Flight is rebased around the vehicle.
const PlanetSurface = preload("res://scripts/planet_surface.gd")

var camera: Camera3D
var _rocket: Node3D
var _landscape: Node3D
var _hangar: Node3D
var _planet: MeshInstance3D
var _planet_lod := 0
var _chute: Node3D
var _booster_nodes: Array[Node3D] = []
var _detached_nodes: Array[Node3D] = []
var _lower_parts: Array[Node3D] = []
var _main_flames: Array[Node3D] = []
var _booster_flames: Array[Node3D] = []
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _sun_direction := Vector3(-0.45, 0.42, 0.72).normalized()
var _sky_material: ShaderMaterial
var _environment: Environment
var _design: Dictionary = {"tanks": 2, "engine": "kestrel", "boosters": false, "fins": true}
var _mode := "workshop"
var _height := 11.0
var _yaw := 0.62
var _pitch := 0.22
var _distance := 28.0
var _clock := 0.0
var rendering_suspended := false
var _last_altitude := 0.0
var _camera_focus := Vector3.ZERO
var _surface_up := Vector3.UP
var _capsule: Node3D
var _capsule_only := false
var _chute_open := false
var _paint: StandardMaterial3D
var _teal: StandardMaterial3D
var _orange: StandardMaterial3D
var _metal: StandardMaterial3D
var _dark: StandardMaterial3D
var _glass: StandardMaterial3D
var _ground: StandardMaterial3D
const PLANET_RADIUS := 60000.0
const SOLAR_DAY_SECONDS := 480.0
const PLANET_ROTATION_SECONDS := 1440.0
var _planet_rotation_time := 0.0
const INITIAL_SUN_DIRECTION := Vector3(-0.45, 0.42, 0.72)
const SUN_ENERGY := 1.55
const WORKSHOP_CAMERA_FOCUS_Y := 4.8
var _solar_time := 0.0
var _capsule_center_local := 1.4


func _ready() -> void:
	_make_materials()
	_make_environment()
	_make_planet()
	_make_landscape()
	_make_hangar()
	_rocket = Node3D.new()
	add_child(_rocket)
	camera = Camera3D.new()
	camera.near = 0.5
	camera.far = 220000.0
	camera.fov = 43.0
	camera.current = true
	add_child(camera)
	_build_rocket()
	_update_camera()


func set_design(design: Dictionary) -> void:
	for piece in _detached_nodes:
		if is_instance_valid(piece): piece.queue_free()
	_detached_nodes.clear()
	_design = design.duplicate()
	if is_instance_valid(_rocket):
		_build_rocket()
		_update_camera()

func reload_planet() -> void:
	if not is_instance_valid(_planet):
		return
	_planet_lod = -1
	var material: ShaderMaterial = _planet.material_override
	PlanetSurface.home().configure_surface_material(material)
	_update_planet_lod(_last_altitude)
	_update_atmosphere()

func set_mode(mode: String) -> void:
	_mode = mode
	if not is_instance_valid(_rocket):
		return
	_planet_rotation_time = 0.0
	_planet.basis = Basis.IDENTITY
	_landscape.basis = Basis.IDENTITY
	if mode == "workshop":
		_solar_time = 0.0
		_sun_direction = INITIAL_SUN_DIRECTION.normalized()
		_capsule_only = false
		_chute_open = false
		_rocket.transform = Transform3D.IDENTITY
		_landscape.position = Vector3.ZERO
		_landscape.visible = false
		_hangar.visible = true
		_planet.visible = false
		_planet.position = Vector3(0.0, -PLANET_RADIUS, 0.0)
		_environment.ambient_light_energy = 0.42
		_build_rocket()
		_last_altitude = 0.0
		_surface_up = Vector3.UP
	else:
		_solar_time = 0.0
		_sun_direction = INITIAL_SUN_DIRECTION.normalized()
		_hangar.visible = false
		_landscape.visible = true
		_planet.visible = true
		_distance = maxf(_distance, _height * 2.5)
	_update_camera()


func sync_flight(state: Dictionary, delta: float) -> void:
	if not is_instance_valid(_rocket):
		return
	_clock += delta
	set_planet_time(float(state.get("time",0.0)))
	if rendering_suspended: return
	var flight_position: Vector3 = state.get("position", Vector3.ZERO)
	var orientation: Basis = state.get("orientation", Basis.IDENTITY)
	_rocket.basis = orientation.orthonormalized()
	_rocket.position = Vector3.ZERO
	_landscape.position = -flight_position
	_planet.position = Vector3(0.0, -PLANET_RADIUS, 0.0) - flight_position
	_last_altitude = float(state.get("altitude", 0.0))
	_update_planet_lod(_last_altitude)
	_surface_up = (flight_position+Vector3(0,PLANET_RADIUS,0)).normalized()
	# Ground and ocean share one continuous planet mesh. Only visual density
	# changes with altitude; contact continues to use the full terrain mesh.
	_sync_detached(state, flight_position)
	var attached := bool(state.get("boosters_attached", true))
	var capsule_only := bool(state.get("capsule_only", false))
	_capsule_only = capsule_only
	_chute_open = bool(state.get("chute_deployed", false))
	if _chute_open and str(state.get("status","flying")) == "flying":
		_rocket.basis = Basis(Quaternion(Vector3.UP, _surface_up))
	if capsule_only:
		# The capsule's contact point replaces the bottom of the full stack.
		_rocket.position = -_rocket.basis.y * (_height - 2.8)
	for booster in _booster_nodes:
		booster.visible = attached and not capsule_only
	for piece in _lower_parts:
		piece.visible = not capsule_only
	_chute.visible = bool(state.get("chute_deployed", false))
	if _chute.visible:
		_chute.rotation.z = sin(_clock * 1.7) * 0.03
	var throttle := float(state.get("throttle", 0.0))
	var engine_on := bool(state.get("engine_on", false)) and not capsule_only
	_animate_flames(_main_flames, throttle if engine_on and float(state.get("fuel", 0.0)) > 0.0 else 0.0)
	_animate_flames(_booster_flames, 1.0 if bool(state.get("boosters_on", engine_on)) and attached and float(state.get("booster_fuel", 0.0)) > 0.0 else 0.0)
	_update_camera()


func orbit_camera(relative: Vector2) -> void:
	_yaw -= relative.x * 0.006
	_pitch = clampf(_pitch + relative.y * 0.005, -0.4, 1.2)
	_update_camera()


func zoom_camera(amount: float) -> void:
	_distance = clampf(_distance * exp(amount * 0.12), 8.0, 130.0)
	_update_camera()


func _update_camera() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(_rocket):
		return
	var center := Vector3(0, _height * 0.5, 0)
	if _mode == "workshop":
		center = Vector3(0, WORKSHOP_CAMERA_FOCUS_Y, 0)
	if _capsule_only:
		center.y = _height - 1.2
	if _chute_open:
		center.y = _height + 2.3
	_camera_focus = center if _mode == "workshop" else _rocket.transform * center
	var framing_pitch := _pitch
	if _mode == "flight":
		# Keep the shrinking horizon in frame as the vehicle reaches space.
		framing_pitch = clampf(_pitch+acos(PLANET_RADIUS/(PLANET_RADIUS+maxf(0.0,_last_altitude)))*0.9,-0.4,1.45)
	var offset := Vector3(sin(_yaw) * cos(framing_pitch), sin(framing_pitch), cos(_yaw) * cos(framing_pitch))
	offset = Basis(Quaternion(Vector3.UP,_surface_up))*offset
	camera.position = _camera_focus + offset * _distance * (1.12 if _chute_open else 1.0)
	camera.far = maxf(220000.0, _last_altitude + PLANET_RADIUS * 2.05 + _distance)
	camera.look_at(_camera_focus, _surface_up)
	_update_atmosphere()


func _make_materials() -> void:
	_paint = _material(Color("e6eee9"), 0.15, 0.36)
	_teal = _material(Color("177a7f"), 0.4, 0.36)
	_orange = _material(Color("ff8048"), 0.15, 0.38)
	_metal = _material(Color("6d8284"), 0.65, 0.32)
	_dark = _material(Color("172b36"), 0.5, 0.5)
	_glass = _material(Color("62d6e3"), 0.5, 0.14)
	_glass.emission_enabled = true
	_glass.emission = Color("237b86")
	_glass.emission_energy_multiplier = 0.35
	_ground = _material(Color("263f46"), 0.2, 0.85)


func _material(color: Color, metallic: float = 0.0, roughness: float = 0.7) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _make_environment() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("8ac2cb")
	_environment.ambient_light_energy = 0.42
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = preload("res://assets/shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	_environment.sky = sky
	var world := WorldEnvironment.new()
	world.environment = _environment
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color("ffedcc")
	_sun.light_energy = SUN_ENERGY
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 180.0
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.rotation_degrees = Vector3(-20, 150, 0)
	_fill.light_color = Color("73c5d6")
	_fill.light_energy = 0.22
	add_child(_fill)


func set_sun_direction(direction: Vector3) -> void:
	if not direction.is_finite() or direction.length_squared() < 0.000001: return
	_sun_direction = direction.normalized()
	if is_instance_valid(camera): _update_atmosphere()


func set_planet_time(time: float) -> void:
	_planet_rotation_time = time
	var spin: Basis = PlanetSurface.home().rotation_at(time)
	_planet.basis = spin
	_landscape.basis = spin

func advance_solar_time(simulation_delta: float) -> void:
	if _mode != "flight" or not is_finite(simulation_delta) or simulation_delta <= 0.0:
		return
	_solar_time = fposmod(_solar_time + simulation_delta, SOLAR_DAY_SECONDS)
	_planet_rotation_time = fposmod(_planet_rotation_time + simulation_delta, PLANET_ROTATION_SECONDS)
	var spin := Basis(Vector3.UP, TAU * _planet_rotation_time / PLANET_ROTATION_SECONDS)
	_planet.basis = spin
	_landscape.basis = spin
	var angle := TAU * _solar_time / SOLAR_DAY_SECONDS
	_sun_direction = (Basis(Vector3.FORWARD, angle) * INITIAL_SUN_DIRECTION).normalized()
	if is_instance_valid(camera):
		_update_atmosphere()


static func kelvin_to_rgb(temp_kelvin: float) -> Color:
	var temperature := clampf(temp_kelvin, 1000.0, 40000.0) / 100.0
	var red := 255.0 if temperature <= 66.0 else 329.698727446 * pow(temperature - 60.0, -0.1332047592)
	var green := 99.4708025861 * log(temperature) - 161.1195681661 if temperature <= 66.0 else 288.1221695283 * pow(temperature - 60.0, -0.0755148492)
	var blue := 255.0 if temperature >= 66.0 else (0.0 if temperature <= 19.0 else 138.5177312231 * log(temperature - 10.0) - 305.0447927307)
	return Color(clampf(red,0.0,255.0)/255.0, clampf(green,0.0,255.0)/255.0, clampf(blue,0.0,255.0)/255.0)


func _update_atmosphere() -> void:
	if rendering_suspended: return
	var in_workshop := _mode == "workshop"
	var observer := (camera.global_position - _planet.global_position) * 0.001
	var sun_height := observer.normalized().dot(_sun_direction)
	var daylight := smoothstep(-0.12, 0.25, sun_height)
	_sky_material.set_shader_parameter("workshop", in_workshop)
	_sky_material.set_shader_parameter("camera_planet_km", observer)
	_sky_material.set_shader_parameter("sun_direction", _sun_direction)
	var planet_material: ShaderMaterial = _planet.material_override
	planet_material.set_shader_parameter("camera_planet_km", observer)
	planet_material.set_shader_parameter("sun_direction", _sun_direction)
	planet_material.set_shader_parameter("atmosphere_density_scale", float(PlanetSurface.home().definition.atmosphere_visual_density))
	var light_up := Vector3.FORWARD if absf(_sun_direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	_sun.look_at(_sun.global_position - _sun_direction, light_up)
	# The nearby shadow map cannot cover an entire planet. Explicitly eclipse
	# the craft/site light while shaders shade the globe using the same sun.
	var horizon := -sqrt(maxf(0.0, 1.0 - pow(60.0 / maxf(observer.length(),60.0),2.0)))
	var sun_visible := smoothstep(horizon-0.008, horizon+0.008, sun_height)
	_sun.light_energy = 1.15 if in_workshop else SUN_ENERGY*sun_visible
	var warmth_weight := sqrt(clampf(sun_height,0.0,1.0))
	var temperature := lerpf(lerpf(2000.0,6500.0,warmth_weight),6500.0,1.0-air_density_visual(observer.length()))
	_sun.light_color = Color("ffedcc") if in_workshop else kelvin_to_rgb(temperature)
	_fill.light_energy = 0.22 if in_workshop else 0.0
	var air := exp(-maxf(0.0, observer.length()*1000.0 - PLANET_RADIUS)/14000.0)
	_environment.ambient_light_energy = 0.42 if in_workshop else lerpf(0.001, lerpf(0.08,0.42,air),daylight*sun_visible)
	_sky_material.set_shader_parameter("reflection_strength", 1.0 if in_workshop else lerpf(0.002,1.0,sun_visible))


func air_density_visual(radius_km: float) -> float:
	return exp(-maxf(0.0,radius_km-60.0)/8.0)


func _make_planet() -> void:
	_planet = MeshInstance3D.new()
	_planet.mesh = PlanetSurface.render_mesh_for_altitude(0.0)
	_planet.position.y = -PLANET_RADIUS
	_planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/terrain.gdshader")
	PlanetSurface.home().configure_surface_material(material)
	_planet.material_override = material
	add_child(_planet)

func _update_planet_lod(altitude: float) -> void:
	var lod := PlanetSurface.render_lod_for_altitude(altitude, _planet_lod)
	if lod == _planet_lod and _planet.mesh != null:
		return
	_planet_lod = lod
	_planet.mesh = PlanetSurface.home().render_mesh_for_lod(_planet_lod)

func _make_landscape() -> void:
	_landscape = Node3D.new()
	add_child(_landscape)
	# Concrete apron with an etched metric grid.
	var apron := _cylinder(_landscape, 42.0, 42.0, 0.3, Vector3(0,-0.14,0), _ground, 96)
	var grid_shader := Shader.new()
	grid_shader.code = """
shader_type spatial;
varying vec2 ground_xy;
void vertex() { ground_xy = VERTEX.xz; }
void fragment() {
	vec2 g = abs(fract(ground_xy/3.0+0.5)-0.5);
	float line = 1.0-smoothstep(0.006,0.018,min(g.x,g.y));
	ALBEDO = mix(vec3(0.08,0.14,0.16),vec3(0.18,0.28,0.29),line*0.7);
	ROUGHNESS = 0.88;
}
"""
	var grid_material := ShaderMaterial.new()
	grid_material.shader = grid_shader
	apron.material_override = grid_material
	_cylinder(_landscape, 9.2, 9.5, 0.25, Vector3(0,-0.1,0), _dark, 64)
	_cylinder(_landscape, 7.5, 7.5, 0.025, Vector3(0,0.04,0), _ground, 64)
	_ring(_landscape, 8.25, 8.38, Vector3(0,0.06,0), _orange)
	_ring(_landscape, 6.8, 6.87, Vector3(0,0.07,0), _paint)
	for index in range(12):
		var angle := float(index) * TAU / 12.0
		var stripe := _box(_landscape, Vector3(0.12,0.04,0.7),Vector3(sin(angle)*7.7,0.07,cos(angle)*7.7),_paint)
		stripe.rotation.y = angle
	for x in [-2.0, 2.0]:
		for z in [-2.0, 2.0]:
			_box(_landscape, Vector3(0.45,0.28,0.9),Vector3(x,0.19,z),_metal)
	# Open steel service gantry, kept behind the vehicle silhouette.
	for x in [-8.7, -6.7]:
		for z in [-5.7, -3.7]:
			_box(_landscape,Vector3(0.22,18,0.22),Vector3(x,9,z),_teal)
	for y in range(1,18,3):
		_box(_landscape,Vector3(2.5,0.2,2.5),Vector3(-7.7,y,-4.7),_metal)
		_beam(_landscape, Vector3(-8.7,y,-3.7),Vector3(-6.7,y+3,-3.7),0.06,_metal)
		_beam(_landscape, Vector3(-6.7,y,-5.7),Vector3(-6.7,y+3,-3.7),0.06,_metal)
	_box(_landscape,Vector3(4.3,0.24,1.0),Vector3(-5.6,9.7,-4.0),_teal)
	_box(_landscape,Vector3(4.3,0.24,1.0),Vector3(-5.6,15.7,-4.0),_teal)
	_box(_landscape,Vector3(2.8,0.5,2.8),Vector3(-7.7,18.2,-4.7),_paint)
	for y in range(0,35):
		_box(_landscape,Vector3(0.7,0.04,0.08),Vector3(-7.7,float(y)*0.5,-3.42),_orange)
	# Service buildings, storage tanks, painted access road and perimeter lamps.
	_box(_landscape,Vector3(8,0.06,80),Vector3(17,0.01,47),_dark)
	for z in range(12,87,8):
		_box(_landscape,Vector3(0.13,0.07,3),Vector3(17,0.05,z),_paint)
	for index in range(4):
		var p := Vector3(30+float(index%2)*13,2.1,12+float(index/2)*19)
		_box(_landscape,Vector3(10,4.2,13),p,_paint)
		_box(_landscape,Vector3(10.3,0.5,13.3),p+Vector3(0,2.3,0),_teal)
		_box(_landscape,Vector3(6,2.3,0.08),p+Vector3(0,-0.7,-6.54),_dark)
		for n in range(4):
			_box(_landscape,Vector3(1,0.65,0.1),p+Vector3(-3+float(n)*2,1,-6.6),_glass)
	for index in range(3):
		var p := Vector3(-26-float(index)*5,3,-20)
		_cylinder(_landscape,1.7,1.7,6,p,_paint,24)
		_cylinder(_landscape,1.8,1.8,0.45,p+Vector3(0,1.7,0),_teal,24)
		_sphere(_landscape,1.68,Vector3(p.x,6,p.z),_paint,Vector3(1,0.35,1))
	var lamp_material := _material(Color("91f9e2"))
	lamp_material.emission_enabled = true
	lamp_material.emission = Color("42d9cf")
	lamp_material.emission_energy_multiplier = 1.5
	for index in range(8):
		var angle := float(index)*TAU/8
		var p := Vector3(sin(angle)*12,0.6,cos(angle)*12)
		_box(_landscape,Vector3(0.3,1.2,0.3),p,_dark)
		_box(_landscape,Vector3(0.42,0.15,0.42),p+Vector3(0,0.65,0),lamp_material)
	# A small dish and its pedestal give the launch site a recognizable silhouette.
	_cylinder(_landscape,0.5,1,5,Vector3(-25,2.5,16),_metal)
	var dish := _sphere(_landscape,3.0,Vector3(-25,6.8,16),_paint,Vector3(1,0.18,1))
	dish.rotation_degrees.z = -24
	_beam(_landscape,Vector3(-25,6.8,16),Vector3(-23,9,16),0.08,_orange)


func _make_hangar() -> void:
	_hangar = Node3D.new()
	add_child(_hangar)
	# A dedicated indoor assembly bay, visually separate from the launch site.
	_box(_hangar, Vector3(42,0.4,34), Vector3(0,-0.35,0), _ground)
	_box(_hangar, Vector3(42,22,0.5), Vector3(0,10.5,-17), _dark)
	_box(_hangar, Vector3(0.5,22,34), Vector3(-21,10.5,0), _dark)
	_box(_hangar, Vector3(0.5,22,34), Vector3(21,10.5,0), _dark)
	for x in range(-18,19,6):
		_box(_hangar, Vector3(0.16,20,0.25), Vector3(x,9.5,-16.65), _teal)
	for z in range(-14,15,7):
		_box(_hangar, Vector3(41,0.16,0.2), Vector3(0,5.0 + float((z+14)/7)*3.2,-16.6), _metal)
	for x in [-13.0,-6.5,0.0,6.5,13.0]:
		var lamp := _material(Color("b8fff0"))
		lamp.emission_enabled = true
		lamp.emission = Color("75ead5")
		lamp.emission_energy_multiplier = 2.0
		_box(_hangar, Vector3(4.0,0.12,0.6), Vector3(x,15,-4), lamp)
	# Assembly markings and tool cabinets sell the indoor scale.
	for radius in [5.0, 7.0]:
		for segment in range(48):
			var angle := float(segment) * TAU / 48.0
			_box(_hangar, Vector3(0.55,0.035,0.12), Vector3(sin(angle)*radius,-0.1,cos(angle)*radius), _orange if radius > 6 else _paint).rotation.y = angle
	for x in [-16.0, 16.0]:
		for y in [1.0, 2.4, 3.8]:
			_box(_hangar, Vector3(3.5,1.1,0.7), Vector3(x,y,-15.8), _teal)
	_hangar.visible = true


func _build_rocket() -> void:
	for child in _rocket.get_children():
		child.free()
	_booster_nodes.clear()
	_lower_parts.clear()
	_main_flames.clear()
	_booster_flames.clear()
	if _design.has("assembly") and _design.assembly.parts.is_empty():
		_height = 4.0
		_capsule_center_local = 1.4
		if _mode == "workshop": _rocket.position.y = _workshop_root_height() - _capsule_center_local
		_distance = 25.0
		return
	var tanks := clampi(int(_design.get("tanks",2)),0 if _design.has("assembly") else 1,4)
	var engine := str(_design.get("engine","kestrel"))
	var tank_base := 2.0 if not engine.is_empty() else 0.0
	var tank_top := tank_base+float(tanks)*2.15
	_height = tank_top+2.8
	_capsule_center_local = tank_top + 1.4
	if _mode == "workshop":
		# The capsule is the assembly root. New parts extend below it.
		_rocket.position.y = _workshop_root_height() - _capsule_center_local
	var body := Node3D.new()
	_rocket.add_child(body)
	_lower_parts.append(body)
	if not engine.is_empty():
		_cylinder(body,0.85,0.85,0.6,Vector3(0,1.65,0),_teal)
		_cylinder(body,0.76,0.9,0.28,Vector3(0,1.26,0),_metal)
	for index in range(tanks):
		var tank_node := Node3D.new()
		body.add_child(tank_node)
		if _design.has("assembly"):
			var tank_parts: Array = _design.assembly.parts.filter(func(part): return part.kind == "tank")
			tank_node.rotation_degrees.y = float(tank_parts[tanks - 1 - index].rotation)
		var y := tank_base+float(index)*2.15
		_cylinder(tank_node,0.91,0.91,2.12,Vector3(0,y+1.06,0),_paint)
		_cylinder(tank_node,0.932,0.932,0.095,Vector3(0,y+0.08,0),_metal)
		_cylinder(tank_node,0.935,0.935,0.15,Vector3(0,y+1.88,0),_teal)
		for side in range(4):
			var angle := float(side)*TAU/4.0
			var panel := _box(tank_node,Vector3(0.16,0.64,0.018),Vector3(sin(angle)*0.922,y+0.9,cos(angle)*0.922),_orange if index%2 == 0 else _teal)
			panel.rotation.y = angle
			var seam := _box(tank_node,Vector3(0.018,1.9,0.018),Vector3(sin(angle+0.65)*0.91,y+1,cos(angle+0.65)*0.91),_metal)
			seam.rotation.y = angle+0.65
	# A narrow feed line and two clipped identification panels.
	if tanks > 0:
		_cylinder(body,0.055,0.055,maxf(0.1,tank_top-1.8),Vector3(-0.67,(tank_top+1.8)/2,-0.66),_teal,12)
	for side in [-1.0,1.0]:
		_box(body,Vector3(0.4,0.62,0.035),Vector3(0,tank_top-0.65,side*0.933),_dark)
		_box(body,Vector3(0.07,0.35,0.045),Vector3(-0.1,tank_top-0.65,side*0.96),_paint)
		_box(body,Vector3(0.07,0.35,0.045),Vector3(0.1,tank_top-0.65,side*0.96),_paint)
	if engine == "titan":
		for x in [-0.38,0.38]:
			for z in [-0.38,0.38]:
				_engine(body,Vector3(x,0.8,z),0.42,_main_flames)
	elif engine == "sparrow":
		_engine(body,Vector3(0,0.82,0),0.57,_main_flames)
	elif not engine.is_empty():
		_engine(body,Vector3(0,0.78,0),0.78,_main_flames)
	if bool(_design.get("boosters",false)):
		for side in [-1.0,1.0]:
			var booster := Node3D.new()
			booster.position = Vector3(side*1.63,0.0,0.0)
			_rocket.add_child(booster)
			_booster_nodes.append(booster)
			_cylinder(booster,0.5,0.5,4.5,Vector3(0,3.25,0),_paint)
			_cylinder(booster,0.02,0.5,1.15,Vector3(0,6.05,0),_orange)
			for y in [1.3,3.5,5.1]:
				_cylinder(booster,0.52,0.52,0.17,Vector3(0,y,0),_teal)
			_box(booster,Vector3(0.75,0.2,0.32),Vector3(-side*0.5,2.3,0),_metal)
			_box(booster,Vector3(0.75,0.2,0.32),Vector3(-side*0.5,4.8,0),_metal)
			_engine(booster,Vector3(0,0.65,0),0.47,_booster_flames)
	_capsule = Node3D.new()
	_rocket.add_child(_capsule)
	_capsule.visible = bool(_design.get("capsule", true))
	if _design.get("decoupler", true):
		_cylinder(body,0.94,0.94,0.22,Vector3(0,tank_top+0.1,0),_orange)
	_cylinder(_capsule,0.58,0.91,1.6,Vector3(0,tank_top+1.0,0),_paint)
	_cylinder(_capsule,0.18,0.58,0.9,Vector3(0,tank_top+2.25,0),_teal)
	_sphere(_capsule,0.2,Vector3(0,tank_top+2.7,0),_paint,Vector3(1,0.8,1))
	# Portholes are shallow inset discs, with a dark bezel and blue glass.
	for index in range(4):
		var angle := float(index)*TAU/4.0
		var port := Node3D.new()
		_capsule.add_child(port)
		port.position = Vector3(sin(angle)*0.748,tank_top+1.12,cos(angle)*0.748)
		port.rotation = Vector3(PI*0.5-0.18,angle,0)
		_cylinder(port,0.255,0.255,0.05,Vector3.ZERO,_dark,24)
		_cylinder(port,0.188,0.188,0.057,Vector3(0,0.03,0),_glass,24)
	if bool(_design.get("fins",true)):
		var fin_y := 0.0
		var capsule_fins := false
		var fin_parent_node: Node3D = body
		if _design.has("assembly"):
			var installed_fins: Array = _design.assembly.parts.filter(func(part): return part.kind == "fins")
			if not installed_fins.is_empty():
				var fin_parent: String = installed_fins[0].parent
				var fin_offset := float(installed_fins[0].get("surface_offset", 0.0))
				if fin_parent == "capsule":
					fin_y = _capsule_center_local + fin_offset
					fin_parent_node = _capsule
					capsule_fins = true
				else:
					var tank_parts: Array = _design.assembly.parts.filter(func(part): return part.kind == "tank")
					for index in range(tank_parts.size()):
						if tank_parts[index].id == fin_parent: fin_y = tank_base + float(tanks - 1 - index) * 2.15 + 1.075 + fin_offset
		for index in range(4):
			var fin := _fin(fin_parent_node, _teal, capsule_fins)
			fin.position.y = fin_y
			fin.rotation.y = float(index)*PI*0.5+PI*0.25
	_make_chute(tank_top+2.7)
	if _mode != "workshop": _distance = maxf(25.0,_height*2.48)
	_animate_flames(_main_flames,0.0)
	_animate_flames(_booster_flames,0.0)


func _workshop_root_height() -> float:
	if _design.has("assembly"):
		return clampf(float(_design.assembly.get("root_height", 7.5)), 3.5, 13.0)
	return 9.0


func _engine(parent: Node3D, position: Vector3, radius: float, flames: Array[Node3D]) -> void:
	_cylinder(parent,radius*0.48,radius,0.83,position,_dark)
	_cylinder(parent,radius*1.03,radius*1.03,0.11,position+Vector3(0,-0.4,0),_metal)
	_cylinder(parent,radius*0.84,radius*0.84,0.015,position+Vector3(0,-0.464,0),_dark)
	var flame := Node3D.new()
	parent.add_child(flame)
	flame.position = position+Vector3(0,-0.46,0)
	var fire := _material(Color("ff9a42"))
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.emission_enabled = true
	fire.emission = Color("ff792b")
	fire.emission_energy_multiplier = 2.0
	var core := _material(Color("b9f6ff"))
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.emission_enabled = true
	core.emission = Color("82e4ff")
	core.emission_energy_multiplier = 3.0
	_cylinder(flame,radius*0.78,0.015,3.8,Vector3(0,-1.9,0),fire,20)
	_cylinder(flame,radius*0.48,0.018,2.4,Vector3(0,-1.2,0.005),core,20)
	flames.append(flame)


func _animate_flames(flames: Array[Node3D], power: float) -> void:
	for index in range(flames.size()):
		var flame := flames[index]
		flame.visible = power > 0.005
		var pulse := 1.0+sin(_clock*43.0+float(index)*2.7)*0.08+sin(_clock*71.0)*0.03
		flame.scale = Vector3(0.8+power*0.2,maxf(0.01,power*pulse),0.8+power*0.2)


func _make_chute(anchor: float) -> void:
	_chute = Node3D.new()
	_rocket.add_child(_chute)
	_chute.position.y = anchor
	_chute.visible = false
	var canopy_material := StandardMaterial3D.new()
	canopy_material.vertex_color_use_as_albedo = true
	canopy_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	canopy_material.roughness = 0.9
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(24):
		var color := Color("f2844e") if segment%4 < 2 else Color("eef0db")
		for ring in range(8):
			var corners: Array[Vector2] = [Vector2(segment,ring),Vector2(segment+1,ring),Vector2(segment,ring+1),Vector2(segment+1,ring),Vector2(segment+1,ring+1),Vector2(segment,ring+1)]
			for corner in corners:
				var angle := corner.x*TAU/24.0
				var latitude := corner.y*PI/16.0
				surface.set_color(color)
				surface.add_vertex(Vector3(sin(angle)*sin(latitude)*4.0,5.0+cos(latitude)*2.1,cos(angle)*sin(latitude)*4.0))
		surface.set_color(color)
		if segment%2 == 0:
			var angle := float(segment)*TAU/24.0
			_beam(_chute,Vector3(0,0.1,0),Vector3(sin(angle)*4,5,cos(angle)*4),0.013,_paint)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = canopy_material
	_chute.add_child(mesh)


func _fin(parent: Node3D, material: Material, capsule_profile: bool = false) -> MeshInstance3D:
	var vertices: Array[Vector3] = [Vector3(0.78,1.1,-0.07),Vector3(2.0,0.42,-0.07),Vector3(0.9,3.0,-0.07),Vector3(0.78,1.1,0.07),Vector3(2.0,0.42,0.07),Vector3(0.9,3.0,0.07)]
	# All fin models use the attachment height as their origin.
	for index in range(vertices.size()):
		vertices[index].y -= 1.7
	if capsule_profile:
		# Center and shorten the fin for the capsule without mirroring it: the
		# pointed end remains upward while its inner edge follows the cone radius.
		for index in range(vertices.size()):
			vertices[index].y = vertices[index].y * 0.65
			if vertices[index].x < 1.0:
				# Sink the mounting edge into the shell slightly; normal depth
				# occlusion trims it precisely at the curved hull from every view.
				vertices[index].x = 0.54 - vertices[index].y * 0.30
	var triangles := [0,2,1,3,4,5,0,1,4,0,4,3,1,2,5,1,5,4,2,0,3,2,3,5]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in triangles:
		surface.add_vertex(vertices[index])
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh


func _box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return _mesh(parent,shape,position,material)


func _cylinder(parent: Node3D, top: float, bottom: float, height: float, position: Vector3, material: Material, segments: int = 48) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = top
	shape.bottom_radius = bottom
	shape.height = height
	shape.radial_segments = segments
	return _mesh(parent,shape,position,material)


func _sphere(parent: Node3D, radius: float, position: Vector3, material: Material, size: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius*2
	shape.radial_segments = 24
	shape.rings = 12
	var mesh := _mesh(parent,shape,position,material)
	mesh.scale = size
	return mesh


func _ring(parent: Node3D, inner: float, outer: float, position: Vector3, material: Material) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = inner
	shape.outer_radius = outer
	shape.rings = 96
	shape.ring_segments = 8
	var mesh := _mesh(parent,shape,position,material)
	mesh.scale.y = 0.25
	return mesh


func _beam(parent: Node3D, from: Vector3, to: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var direction := to-from
	var mesh := _cylinder(parent,radius,radius,direction.length(),(from+to)/2,material,8)
	var up := direction.normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	if right.length_squared() < 0.1:
		right = up.cross(Vector3.RIGHT).normalized()
	mesh.basis = Basis(right,up,right.cross(up).normalized())
	return mesh


func _mesh(parent: Node3D, shape: Mesh, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = shape
	mesh.position = position
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh


var _edit_preview: Node3D
var _preview_key := ""

func preview_part(part: String, slot: String = "") -> void:
	var key := part + ":" + slot
	if key == _preview_key and is_instance_valid(_edit_preview): return
	_preview_key = key
	if is_instance_valid(_edit_preview): _edit_preview.queue_free()
	if part.is_empty() or _mode != "workshop": return
	if part != "separation":
		var kind := part
		if part.begins_with("tank_"): kind = "tank"
		elif part == "engine": kind = str(_design.get("engine", "kestrel"))
		var top := (2.0 if not _design.engine.is_empty() else 0.0) + float(_design.tanks) * 2.15
		var installed_position := Vector3.ZERO
		match part:
			"capsule": installed_position.y = _capsule_center_local
			"decoupler": installed_position.y = top + 0.1
			"engine": installed_position.y = 0.8
			"boosters": installed_position.y = 3.25
			"fins":
				installed_position = installed_part_position("fins")
			_:
				if part.begins_with("tank_") and _design.has("assembly"):
					var tanks: Array = _design.assembly.parts.filter(func(item): return item.kind == "tank")
					for index in range(tanks.size()):
						if tanks[index].id == part: installed_position.y = top - float(index)*2.15 - 1.075
		_edit_preview = _make_drag_model(kind, false, part == "fins" and _part_parent("fins") == "capsule")
		_rocket.add_child(_edit_preview)
		_edit_preview.position = installed_position
		var outline_shader := Shader.new()
		outline_shader.code = "shader_type spatial; render_mode unshaded, cull_front; uniform vec4 edge_color : source_color = vec4(0.2,1.0,0.72,0.92); uniform float width = 0.045; void vertex(){ float camera_scale = clamp(abs((MODELVIEW_MATRIX * vec4(VERTEX,1.0)).z) * 0.055, 1.0, 3.2); VERTEX += NORMAL * width * camera_scale; } void fragment(){ ALBEDO = edge_color.rgb; ALPHA = edge_color.a; }"
		var outline := ShaderMaterial.new()
		outline.shader = outline_shader
		_set_preview_material(_edit_preview, outline)
		return
	_edit_preview = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 2.15
	var top := (2.0 if not _design.engine.is_empty() else 0.0) + float(_design.tanks) * 2.15
	var y := top + 1.075
	if part.begins_with("tank_") and _design.has("assembly"):
		var tanks: Array = _design.assembly.parts.filter(func(item): return item.kind == "tank")
		for index in range(tanks.size()):
			if tanks[index].id == part: y = top - float(index)*2.15 - 1.075
	elif part == "decoupler":
		mesh.height = 0.22
		y = top + 0.1
	elif part == "engine":
		mesh.height = 1.4
		mesh.top_radius = 0.35
		y = 0.8
	elif part == "boosters":
		mesh.height = 6.0
		mesh.top_radius = 0.6
		mesh.bottom_radius = 0.6
		y = 3.5
	elif part == "fins":
		mesh.height = 1.5
		mesh.top_radius = 1.0
		mesh.bottom_radius = 2.0
		y = 1.7
	elif part == "capsule":
		mesh.height = 2.8
		mesh.top_radius = 0.05
		y = top + 1.4
	elif part == "separation":
		mesh.height = top
		mesh.top_radius = 2.25 if _design.boosters else 1.12
		mesh.bottom_radius = mesh.top_radius
		y = top * 0.5
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.48, 0.9, 0.75, 0.4) if part != "separation" else Color(1.0, 0.55, 0.25, 0.45)
	_edit_preview.mesh = mesh
	_edit_preview.material_override = material
	_edit_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rocket.add_child(_edit_preview)
	_edit_preview.position = Vector3(-1.63 if part == "boosters" else 0.0, y, 0.0)


func preview_drag(part: String, snap_anchor: Vector3, valid: bool, screen_position: Vector2, capsule_mounted: bool = false) -> void:
	if part.is_empty() or _mode != "workshop":
		_preview_key = ""
		if is_instance_valid(_edit_preview): _edit_preview.queue_free()
		return
	# Use the part's actual procedural silhouette instead of a placeholder volume.
	var engine_part := part in ["sparrow", "kestrel", "titan"]
	var preview_key := "drag:" + part + (":mounted" if engine_part and valid else (":capsule" if part == "fins" and valid and capsule_mounted else ":free"))
	if _preview_key != preview_key or not is_instance_valid(_edit_preview):
		if is_instance_valid(_edit_preview): _edit_preview.queue_free()
		_edit_preview = _make_drag_model(part, engine_part and valid, capsule_mounted)
		_rocket.add_child(_edit_preview)
		_preview_key = preview_key
	if not is_instance_valid(_edit_preview): return
	if valid:
		_edit_preview.position = Vector3(0, snap_anchor.y, 0) if part in ["boosters", "fins"] else snap_anchor
	else:
		var origin := camera.project_ray_origin(screen_position)
		var direction := camera.project_ray_normal(screen_position)
		var normal := -camera.global_basis.z
		var denominator := direction.dot(normal)
		if absf(denominator) > 0.0001:
			var distance := (_camera_focus - origin).dot(normal) / denominator
			_edit_preview.global_position = origin + direction * maxf(distance, 1.0)
	var material: StandardMaterial3D = _edit_preview.get_meta("glow_material")
	# A valid snap must preview only the geometry that will remain visible after
	# placement. Free ghosts stay x-rayed so they cannot disappear behind the craft.
	material.no_depth_test = not valid
	material.albedo_color = Color(0.25, 1.0, 0.53, 0.62) if valid else Color(1.0, 0.18, 0.16, 0.62)


func preview_removal_drag(part: String, screen_position: Vector2, over_catalogue: bool) -> void:
	if part.is_empty() or _mode != "workshop":
		preview_drag("", Vector3.ZERO, false, Vector2.ZERO)
		return
	if _preview_key != "return:" + part or not is_instance_valid(_edit_preview):
		if is_instance_valid(_edit_preview): _edit_preview.queue_free()
		_edit_preview = _make_drag_model(part)
		_rocket.add_child(_edit_preview)
		_preview_key = "return:" + part
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var normal := -camera.global_basis.z
	var denominator := direction.dot(normal)
	if absf(denominator) > 0.0001:
		var distance := (_camera_focus - origin).dot(normal) / denominator
		_edit_preview.global_position = origin + direction * maxf(distance, 1.0)
	var material: StandardMaterial3D = _edit_preview.get_meta("glow_material")
	material.albedo_color = Color(0.25,1.0,0.53,0.68) if over_catalogue else Color(1.0,0.62,0.18,0.68)


func preview_subassembly(ids: Array[String], selected: bool) -> void:
	var key := ("selected:" if selected else "hovered:") + ",".join(ids)
	if key == _preview_key and is_instance_valid(_edit_preview): return
	if is_instance_valid(_edit_preview): _edit_preview.queue_free()
	_preview_key = key
	if ids.is_empty() or _mode != "workshop": return
	_edit_preview = _make_installed_group(ids)
	_rocket.add_child(_edit_preview)
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_front; uniform vec4 edge_color : source_color; uniform float width = 0.045; void vertex(){ float camera_scale = clamp(abs((MODELVIEW_MATRIX * vec4(VERTEX,1.0)).z) * 0.055, 1.0, 3.2); VERTEX += NORMAL * width * camera_scale; } void fragment(){ ALBEDO = edge_color.rgb; ALPHA = edge_color.a; }"
	var outline := ShaderMaterial.new()
	outline.shader = shader
	outline.set_shader_parameter("edge_color", Color(1.0,0.48,0.14,0.96) if selected else Color(0.2,1.0,0.72,0.92))
	_set_preview_material(_edit_preview, outline)


func preview_subassembly_drag(ids: Array[String], selected_id: String, screen_position: Vector2, over_catalogue: bool) -> void:
	var key := "return-group:" + ",".join(ids)
	if key != _preview_key or not is_instance_valid(_edit_preview):
		if is_instance_valid(_edit_preview): _edit_preview.queue_free()
		_edit_preview = _make_installed_group(ids, true)
		_rocket.add_child(_edit_preview)
		_preview_key = key
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var normal := -camera.global_basis.z
	var denominator := direction.dot(normal)
	if absf(denominator) > 0.0001:
		var distance := (_camera_focus - origin).dot(normal) / denominator
		var pointer_world := origin + direction * maxf(distance, 1.0)
		_edit_preview.global_position = pointer_world - _rocket.global_basis * installed_part_position(selected_id)
	var material: StandardMaterial3D = _edit_preview.get_meta("glow_material")
	material.albedo_color = Color(0.25,1.0,0.53,0.68) if over_catalogue else Color(1.0,0.62,0.18,0.68)


func preview_subassembly_snap(ids: Array[String], selected_id: String, target_anchor: Vector3, capsule_mounted: bool = false) -> void:
	var key := "return-group:" + ",".join(ids) + (":capsule" if capsule_mounted else "")
	if key != _preview_key or not is_instance_valid(_edit_preview):
		if is_instance_valid(_edit_preview): _edit_preview.queue_free()
		_edit_preview = _make_installed_group(ids, true, 1 if selected_id == "fins" and capsule_mounted else (0 if selected_id == "fins" else -1))
		_rocket.add_child(_edit_preview)
		_preview_key = key
	var model_anchor := Vector3(0, target_anchor.y, 0) if selected_id in ["fins", "boosters"] else target_anchor
	_edit_preview.position = model_anchor - installed_part_position(selected_id)
	var material: StandardMaterial3D = _edit_preview.get_meta("glow_material")
	material.albedo_color = Color(0.25,1.0,0.53,0.68)


func _make_installed_group(ids: Array[String], glowing: bool = false, fins_capsule_override: int = -1) -> Node3D:
	var group := Node3D.new()
	for id in ids:
		var kind := installed_part_kind(id)
		if kind.is_empty(): continue
		var capsule_fins := id == "fins" and (fins_capsule_override == 1 or (fins_capsule_override < 0 and _part_parent(id) == "capsule"))
		var model := _make_drag_model(kind, false, capsule_fins)
		model.position = installed_part_position(id)
		group.add_child(model)
	if glowing:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.albedo_color = Color(1.0,0.62,0.18,0.68)
		_set_preview_material(group, material)
		group.set_meta("glow_material", material)
	return group


func installed_part_kind(id: String) -> String:
	if not _design.has("assembly"): return id
	for part in _design.assembly.parts:
		if part.id == id: return str(part.kind)
	return ""

func _part_parent(id: String) -> String:
	if _design.has("assembly"):
		for part in _design.assembly.parts:
			if part.id == id: return str(part.parent)
	return ""


func installed_part_position(id: String) -> Vector3:
	var top := (2.0 if not _design.engine.is_empty() else 0.0) + float(_design.tanks) * 2.15
	if id == "capsule": return Vector3(0,_capsule_center_local,0)
	if id == "decoupler": return Vector3(0,top+0.1,0)
	if id == "engine": return Vector3(0,0.8,0)
	if id == "boosters": return Vector3(0,3.25,0)
	var tanks: Array = _design.assembly.parts.filter(func(item): return item.kind == "tank") if _design.has("assembly") else []
	if id.begins_with("tank_"):
		for index in range(tanks.size()):
			if tanks[index].id == id: return Vector3(0,top-float(index)*2.15-1.075,0)
	if id == "fins" and _design.has("assembly"):
		var fins: Array = _design.assembly.parts.filter(func(item): return item.kind == "fins")
		if not fins.is_empty():
			var offset := float(fins[0].get("surface_offset", 0.0))
			if fins[0].parent == "capsule": return Vector3(0,_capsule_center_local+offset,0)
			for index in range(tanks.size()):
				if tanks[index].id == fins[0].parent:
					var base := 2.0 if not _design.engine.is_empty() else 0.0
					return Vector3(0,base+float(tanks.size()-1-index)*2.15+1.075+offset,0)
	return Vector3.ZERO


func _make_drag_model(part: String, mounted: bool = false, capsule_mounted: bool = false) -> Node3D:
	var root := Node3D.new()
	var unused_flames: Array[Node3D] = []
	match part:
		"capsule":
			_cylinder(root, 0.58, 0.91, 1.6, Vector3(0,-0.4,0), _paint)
			_cylinder(root, 0.18, 0.58, 0.9, Vector3(0,0.85,0), _teal)
			_sphere(root, 0.2, Vector3(0,1.35,0), _paint, Vector3(1,0.8,1))
			for index in range(4):
				var angle := float(index) * TAU / 4.0
				var port := Node3D.new()
				root.add_child(port)
				port.position = Vector3(sin(angle)*0.748,-0.28,cos(angle)*0.748)
				port.rotation = Vector3(PI*0.5-0.18,angle,0)
				_cylinder(port,0.255,0.255,0.05,Vector3.ZERO,_dark,24)
		"decoupler":
			_cylinder(root,0.94,0.94,0.22,Vector3.ZERO,_orange)
		"tank":
			_cylinder(root,0.91,0.91,2.12,Vector3.ZERO,_paint)
			_cylinder(root,0.932,0.932,0.095,Vector3(0,-0.98,0),_metal)
			_cylinder(root,0.935,0.935,0.15,Vector3(0,0.82,0),_teal)
		"boosters":
			for side in [-1.0,1.0]:
				var booster := Node3D.new()
				booster.position.x = side * 1.63
				root.add_child(booster)
				_cylinder(booster,0.5,0.5,4.5,Vector3.ZERO,_paint)
				_cylinder(booster,0.02,0.5,1.15,Vector3(0,2.8,0),_orange)
				_engine(booster,Vector3(0,-2.6,0),0.47,unused_flames)
		"fins":
			for index in range(4):
				var fin := _fin(root,_teal,capsule_mounted)
				fin.rotation.y = float(index)*PI*0.5+PI*0.25
		_:
			var radius := 0.57 if part == "sparrow" else (0.78 if part == "kestrel" else 0.42)
			# The free-drag silhouette is the engine itself. At a valid snap,
			# include the feed skirt and mounting collar seen on the assembled core.
			if mounted and part in ["sparrow", "kestrel", "titan"]:
				_cylinder(root,0.85,0.85,0.6,Vector3(0,0.85,0),_teal)
				_cylinder(root,0.76,0.9,0.28,Vector3(0,0.46,0),_metal)
			if part == "titan":
				for x in [-0.38,0.38]:
					for z in [-0.38,0.38]: _engine(root,Vector3(x,0,z),radius,unused_flames)
			else:
				_engine(root,Vector3.ZERO,radius,unused_flames)
	# Drag and selection models never show powered exhaust. Flames belong only
	# to the live flight model and are hidden even before the next animation tick.
	for flame in unused_flames:
		flame.visible = false
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0,0.18,0.16,0.62)
	material.no_depth_test = true
	_set_preview_material(root, material)
	root.set_meta("glow_material", material)
	return root


func _set_preview_material(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _set_preview_material(child, material)


func _sync_detached(state: Dictionary, origin: Vector3) -> void:
	var pieces: Array = state.get("detached", [])
	for index in range(pieces.size()):
		var piece: Dictionary = pieces[index]
		if index >= _detached_nodes.size():
			var root := Node3D.new()
			add_child(root)
			var sources: Array[Node3D] = _booster_nodes if piece.kind == "boosters" else _lower_parts
			for source in sources:
				var copy := source.duplicate() as Node3D
				root.add_child(copy)
				copy.visible = true
			_detached_nodes.append(root)
		var node := _detached_nodes[index]
		node.position = piece.position - origin
		node.basis = piece.orientation
		# Snapshot flames reflect the engine at separation; hide them at burnout.
		if piece.fuel <= 0.0 or piece.landed:
			for child in node.find_children("*", "MeshInstance3D", true, false):
				var material = child.material_override
				if material is StandardMaterial3D and material.emission_enabled: child.hide()
