extends Control
signal warp_to_requested(epoch: float)
signal cancel_warp_requested
signal plan_edit_started
## Interactive 3D map using the same globe and coast predictor as flight.
const SolarBody = preload("res://scripts/solar_body.gd")
const Surface = preload("res://scripts/planet_surface.gd")
const Physics = preload("res://scripts/physics_math.gd")
const Maneuver = preload("res://scripts/maneuver_plan.gd")
const PlanetList = preload("res://scripts/planet_list.gd")
const PAST_COLOR := Color("efab65")
const FUTURE_COLOR := Color("69c8ff")
const IMPACT_COLOR := Color("ff7882")
const ESCAPE_COLOR := Color("f5d879")
const MAP_HAZE_EXPOSURE := 2.0
var prediction_kind := "Orbit"
var impact_point := Vector3.INF
const CRAFT_COLOR := Color("7ce5c0")
const HISTORY_LIMIT := 4096
var history := PackedVector3Array()
var history_time := 0.0
var history_interval := 0.25
var history_dirty := false
var history_mesh := ImmediateMesh.new()
var history_tail_mesh := ImmediateMesh.new()
var history_node: MeshInstance3D
var history_tail_node: MeshInstance3D
var history_material: StandardMaterial3D
var state: Dictionary = {}
var source_world: Node3D
var viewport: SubViewport
var background_viewport: SubViewport
var background_camera: Camera3D
var render_root: Node3D
var render_origin := Vector3.ZERO
var camera: Camera3D
var local_sun: MeshInstance3D
var globe: MeshInstance3D
var trajectory: MeshInstance3D
var marker: MeshInstance3D
var yaw := 0.5
var pitch := 0.35
var zoom := 1.0
var extent := 100.0
var path_dirty := true
var last_path_position := Vector3.INF
var last_path_velocity := Vector3.INF
var camera_extent := 100.0
var reset_framing := true
var labels: Array[Dictionary] = []
var planet_label_hits: Array[Dictionary] = []
var overlay: Control
var label_style: StyleBoxFlat
var system_root: Node3D
var system_focus := false
var orbit_lines: Array[MeshInstance3D] = []
var home_index := -1
var system_radius := 45000.0
var local_focus_craft := false
var focus_index := -1
var bodies: Array[MeshInstance3D] = []
var planet_definitions: Array[Resource] = []
var body_parents: Array[int] = []
var path_mesh := ImmediateMesh.new()
var path_material: StandardMaterial3D
const MANEUVER_COLOR := Color("d5a0ff")
var maneuver := Maneuver.new()
var maneuver_mesh := ImmediateMesh.new()
var maneuver_material: StandardMaterial3D
var maneuver_panel: PanelContainer
var maneuver_fields: Array[SpinBox] = []
var maneuver_summary: Label
var maneuver_notice: Label
var maneuver_delete: Button
var maneuver_shift_buttons: Array[Button] = []
var maneuver_status := ""
var maneuver_path_note := ""
var maneuver_valid := false
var _maneuver_labels: Array[Dictionary] = []
var _coast_points := PackedVector3Array()
var _maneuver_refresh_time := -INF
var _maneuver_signature := ""
var _maneuver_mesh_dirty := false
var maneuver_gizmo: Control
var orbit_menu: PanelContainer
var orbit_create_button: Button
var orbit_warp_button: Button
var orbit_menu_epoch := -1.0
var precise_values: VBoxContainer
var warp_destination := -1.0
var stop_warp_button: Button

func _home_radius() -> float:
	return float(Surface.home().definition.radius)

func _home_mu() -> float:
	return float(Surface.home().definition.surface_gravity) * pow(_home_radius(), 2.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var background_container := SubViewportContainer.new()
	background_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_container.stretch = true
	background_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background_container)
	background_viewport = SubViewport.new()
	background_viewport.msaa_3d = Viewport.MSAA_4X
	background_container.add_child(background_viewport)
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.own_world_3d = true
	background_viewport.world_3d = viewport.world_3d
	container.add_child(viewport)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("020509")
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	viewport.add_child(environment_node)
	render_root = Node3D.new()
	viewport.add_child(render_root)
	globe = MeshInstance3D.new()
	# The map can zoom in regardless of the vehicle altitude. Use the
	# editor's globe resolution instead of inheriting the flight mesh LOD.
	globe.mesh = Surface.home().preview_mesh()
	globe.scale = Vector3.ONE*0.001
	globe.material_override = source_world._planet.material_override.duplicate()
	# Flight's launch-relative coordinates belong to its camera and metre scale.
	# The map must project the globe with its own transform, like the atmosphere.
	globe.material_override.set_shader_parameter("launch_origin_enabled", false)
	# Orthographic zoom does not change the distant camera position. Flight's
	# distance-based smoothing would hide the real surface even when zoomed in.
	globe.material_override.set_shader_parameter("distant_surface_smoothing_enabled", false)
	globe.material_override.set_shader_parameter("surface_coordinate_scale",1000.0)
	_configure_map_atmosphere(globe.material_override, Surface.home().definition)
	render_root.add_child(globe)
	_add_atmosphere(globe, Surface.home().definition)
	local_sun = MeshInstance3D.new()
	local_sun.name = "PhysicalSun"
	var solar_mesh := source_world._sun_body.mesh.duplicate() as SphereMesh
	solar_mesh.radius = SolarBody.RADIUS * 0.001
	solar_mesh.height = solar_mesh.radius * 2.0
	local_sun.mesh = solar_mesh
	# Share the flight sun's surface, without the flight sky's lens effects.
	local_sun.material_override = source_world._sun_body.material_override.duplicate()
	local_sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	local_sun.position = (SolarBody.POSITION - Physics.PLANET_CENTER) * 0.001
	render_root.add_child(local_sun)
	_add_sun_glow(local_sun)
	trajectory = MeshInstance3D.new()
	path_material = _material(FUTURE_COLOR)
	trajectory.mesh = path_mesh
	render_root.add_child(trajectory)
	var planned := MeshInstance3D.new()
	planned.name = "ManeuverTrajectory"
	planned.mesh = maneuver_mesh
	maneuver_material = _material(MANEUVER_COLOR)
	render_root.add_child(planned)
	history_material = _material(PAST_COLOR)
	history_node = MeshInstance3D.new()
	history_node.mesh = history_mesh
	render_root.add_child(history_node)
	history_tail_node = MeshInstance3D.new()
	history_tail_node.mesh = history_tail_mesh
	render_root.add_child(history_tail_node)
	marker = MeshInstance3D.new()
	render_root.add_child(marker)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.fov = 43.0
	camera.far = 100000.0
	viewport.add_child(camera)
	camera.current = true
	background_camera = Camera3D.new()
	background_camera.cull_mask = 2
	background_viewport.add_child(background_camera)
	background_camera.current = true
	_build_system()
	label_style = _label_style()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	maneuver_gizmo = preload("res://scripts/maneuver_gizmo.gd").new()
	maneuver_gizmo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(maneuver_gizmo)
	maneuver_gizmo.hide()
	maneuver_gizmo.component_changed.connect(func(axis: int, value: float):
		maneuver.components[axis] = value
		maneuver_fields[axis].set_value_no_signal(value)
		_refresh_maneuver(true)
	)
	maneuver_gizmo.drag_started.connect(func(): plan_edit_started.emit())
	_build_maneuver_ui()
	_build_orbit_menu()
	visibility_changed.connect(func():
		if not is_visible_in_tree(): orbit_menu.hide()
	)
	_update_camera()

## Render both local and system materials behind the rollout cover. No maneuver
## is created, and the user's previous camera framing is restored afterwards.
func prewarm_views() -> void:
	var saved_focus := system_focus
	var saved_index := focus_index
	var saved_extent := camera_extent
	var saved_reset := reset_framing
	# The focused view also exercises the separate distant-background viewport.
	for view in range(3):
		system_focus = view > 0
		focus_index = home_index if view == 2 else -1
		reset_framing = true
		_process(0.0)
		maneuver_gizmo.show()
		maneuver_gizmo.set_frame(marker.position, [Vector3.RIGHT, Vector3.UP, Vector3.BACK], camera, Vector3.ZERO, Rect2(Vector2.ZERO, size))
		# Allow viewport containers to settle their size on the first opening.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	system_focus = saved_focus
	focus_index = saved_index
	_process(0.0)
	camera_extent = saved_extent
	reset_framing = saved_reset
	_update_camera()
	maneuver_gizmo.hide()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	background_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _build_system() -> void:
	system_root = Node3D.new()
	render_root.add_child(system_root)
	planet_definitions.clear()
	body_parents.clear()
	var home_path: String = Surface.home().definition.get_meta("source_planet_path", Surface.home().definition.resource_path)
	if home_path.is_empty():
		home_path = Surface.HOME.resource_path
	for saved_planet in PlanetList.load_all():
		var definition: Resource = Surface.home().definition if saved_planet.get_meta("source_planet_path", saved_planet.resource_path) == home_path else saved_planet
		_append_system_body(definition, -1)
	var home: Resource = Surface.home().definition
	var unit_radius := local_sun.position.length() / maxf(float(home.orbit_distance_au), 0.001)
	var radial := -local_sun.position.normalized()
	var tangent := radial.cross(Vector3.UP).normalized()
	for index in range(planet_definitions.size()):
		var definition := planet_definitions[index]
		var parent_index := body_parents[index]
		var radius := float(definition.orbit_distance_au) * unit_radius if parent_index < 0 else float(definition.moon_orbit_distance_km)
		var center := local_sun.position if parent_index < 0 else Vector3.ZERO
		if parent_index < 0:
			system_radius = maxf(system_radius, radius)
		else:
			system_radius = maxf(system_radius, float(planet_definitions[parent_index].orbit_distance_au) * unit_radius + radius)
		var orbit := ImmediateMesh.new()
		var orbit_material := _material(Color(definition.map_color).lightened(0.2))
		orbit.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, orbit_material)
		for step in range(2049):
			var angle := TAU * float(step) / 2048.0
			orbit.surface_add_vertex(center + (radial*cos(angle)+tangent*sin(angle))*radius)
		orbit.surface_end()
		var line := MeshInstance3D.new()
		line.name = str(definition.planet_name) + "Orbit"
		line.mesh = orbit
		line.visible = bool(definition.orbit_enabled)
		system_root.add_child(line)
		orbit_lines.append(line)
		if definition == home:
			home_index = index
			bodies.append(globe)
			continue
		var body := MeshInstance3D.new()
		var terrain := Surface.Terrain.new(definition)
		body.mesh = terrain.preview_mesh()
		body.scale = Vector3.ONE*0.001
		body.set_meta("terrain", terrain)
		var surface_material := ShaderMaterial.new()
		surface_material.shader = preload("res://assets/shaders/terrain.gdshader")
		terrain.configure_surface_material(surface_material)
		surface_material.set_shader_parameter("surface_coordinate_scale", 1000.0)
		surface_material.set_shader_parameter("orthographic_view", true)
		_configure_map_atmosphere(surface_material, definition)
		body.material_override = surface_material
		system_root.add_child(body)
		bodies.append(body)
		_add_atmosphere(body, definition)
	_update_system()

func _configure_map_atmosphere(material: ShaderMaterial, definition: Resource) -> void:
	material.set_shader_parameter("BODY_RADIUS", float(definition.radius) * 0.001)
	material.set_shader_parameter("AIR_RADIUS", (float(definition.radius) + float(definition.atmosphere_height)) * 0.001)
	material.set_shader_parameter("atmosphere_density_scale", float(definition.atmosphere_visual_density))
	# Match surface aerial perspective and the outer limb. The dark map
	# background needs brighter scattering than the exposed flight sky.
	material.set_shader_parameter("atmosphere_scattering_exposure", MAP_HAZE_EXPOSURE)
	# 32 x 6 matched 12 x 3 within 3/255 even at the terminator, for 2.6x the GPU time.
	material.set_shader_parameter("atmosphere_view_samples", 12)
	material.set_shader_parameter("atmosphere_light_samples", 3)

func _add_atmosphere(body: MeshInstance3D, definition: Resource) -> void:
	if float(definition.atmosphere_height) <= 0.0 or float(definition.atmosphere_visual_density) <= 0.0:
		return
	var shell := MeshInstance3D.new()
	shell.name = "MapAtmosphere"
	var sphere := SphereMesh.new()
	sphere.radius = float(definition.radius) + float(definition.atmosphere_height)
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	shell.mesh = sphere
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/map_atmosphere.gdshader")
	_configure_map_atmosphere(material, definition)
	shell.material_override = material
	body.add_child(shell)

func _append_system_body(definition: Resource, parent_index: int) -> void:
	var index := planet_definitions.size()
	planet_definitions.append(definition)
	body_parents.append(parent_index)
	for moon in definition.moons:
		_append_system_body(moon, index)

func _add_sun_glow(sun: MeshInstance3D) -> void:
	var glow := MeshInstance3D.new()
	glow.name = "SunGlow"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * sun.mesh.radius * 12.0
	glow.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/map_sun_glow.gdshader")
	glow.material_override = material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sun.add_child(glow)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func reset_history(position: Vector3) -> void:
	clear_maneuver()
	history = PackedVector3Array([(position-Physics.PLANET_CENTER)*0.001])
	history_time = 0.0
	history_interval = 0.25
	history_dirty = true
	history_mesh.clear_surfaces()
	history_tail_mesh.clear_surfaces()
	path_dirty = true
	reset_framing = true
	local_focus_craft = false

func record_flight(telemetry: Dictionary) -> void:
	# Called by simulation even when the map is closed; no GPU work here.
	var time := float(telemetry.get("time",0.0))
	var position: Vector3 = telemetry.get("position",Vector3.ZERO)
	if history.is_empty() or time < history_time: reset_history(position)
	var terminal := str(telemetry.get("status","flying")) in ["landed","crashed"]
	if time-history_time < history_interval and not terminal: return
	var point := (position-Physics.PLANET_CENTER)*0.001
	if point == history[history.size()-1]: return
	history.append(point)
	history_time = time
	history_dirty = true
	if history.size() >= HISTORY_LIMIT:
		var reduced := PackedVector3Array()
		for index in range(0,history.size()-1,2): reduced.append(history[index])
		reduced.append(history[history.size()-1])
		history = reduced
		history_interval *= 2.0

func _update_history() -> void:
	if history_dirty:
		history_mesh.clear_surfaces()
		if history.size() > 1:
			history_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,history_material)
			for point in history: history_mesh.surface_add_vertex(point)
			history_mesh.surface_end()
		history_dirty = false
	# Only this short final segment follows the live marker each frame.
	history_tail_mesh.clear_surfaces()
	if not history.is_empty() and history[history.size()-1] != marker.position:
		history_tail_mesh.surface_begin(Mesh.PRIMITIVE_LINES,history_material)
		history_tail_mesh.surface_add_vertex(history[history.size()-1])
		history_tail_mesh.surface_add_vertex(marker.position)
		history_tail_mesh.surface_end()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or state.is_empty():
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		background_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		reset_framing = true
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_refresh_maneuver()
	if _maneuver_mesh_dirty: _update_maneuver_mesh()
	globe.basis = Surface.home().rotation_at(_simulation_time()).scaled(Vector3.ONE*0.001)
	_update_indicators()
	var position: Vector3 = state.get("position",Vector3.ZERO)
	var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
	if path_dirty or position != last_path_position or velocity != last_path_velocity:
		_update_path()
		last_path_position = position
		last_path_velocity = velocity
		path_dirty = false
	_update_indicators()
	_update_history()
	_update_system()
	if system_focus:
		extent = system_radius if focus_index < 0 else maxf(100.0, float(planet_definitions[focus_index].radius)*0.003)
	camera_extent = extent if reset_framing else lerpf(camera_extent,extent,1.0-exp(-delta*12.0))
	reset_framing = false
	_update_camera()
	_update_maneuver_gizmo()
	stop_warp_button.visible = warp_destination >= 0.0
	stop_warp_button.text = "Warp: %.1f s  ·  Stop (1×)" % maxf(0.0, warp_destination - _simulation_time())
	overlay.queue_redraw()

func _simulation_time() -> float:
	return float(state.get("simulation_time", state.get("time", 0.0)))

func _update_system() -> void:
	var home: Resource = Surface.home().definition
	var unit_radius := local_sun.position.length() / maxf(float(home.orbit_distance_au), 0.001)
	var radial := -local_sun.position.normalized()
	var tangent := radial.cross(Vector3.UP).normalized()
	labels.append({"position":local_sun.position,"text":"SUN","color":Color("ffd487"),"body":true})
	for index in range(bodies.size()):
		var definition := planet_definitions[index]
		# The home planet anchors the flight frame; other phases are illustrative.
		var phase := TAU*(float(definition.orbit_phase)-float(home.orbit_phase))
		phase += TAU*_simulation_time()/86400.0*(1.0/float(definition.orbit_period_days)-1.0/float(home.orbit_period_days))
		if index != home_index:
			var terrain: RefCounted = bodies[index].get_meta("terrain")
			bodies[index].basis = terrain.rotation_at(_simulation_time()).scaled(Vector3.ONE*0.001)
			var parent_index := body_parents[index]
			if parent_index >= 0:
				bodies[index].position = bodies[parent_index].position + SolarBody.moon_offset(definition, _simulation_time()) * 0.001
				orbit_lines[index].position = bodies[parent_index].position
			else:
				bodies[index].position = local_sun.position + (radial*cos(phase)+tangent*sin(phase))*float(definition.orbit_distance_au)*unit_radius
		labels.append({"position":bodies[index].position,"text":str(definition.planet_name),"color":Color(definition.map_color),"body":true,"planet_index":index})

func _update_path() -> void:
	var radial: Vector3 = Vector3(state.get("position",Vector3.ZERO))-Physics.PLANET_CENTER
	var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
	var points := Physics.coast_path(radial,velocity,maxf(extent*4000.0,radial.length()*2.0),720,_home_mu(),_home_radius())
	var elements := Physics.orbital_elements(radial,velocity,_home_mu(),_home_radius())
	var will_impact: bool = elements.periapsis < 0.0 and (elements.bound_orbit or radial.dot(velocity) < 0.0)
	prediction_kind = "Impact" if will_impact else ("Orbit" if elements.bound_orbit else "Escape")
	impact_point = Vector3.INF
	# Use the same triangles as flight. This coast overlay samples the current
	# terrain orientation; it is not a rotating-body intercept-time solver.
	var terrain: RefCounted = Surface.home()
	var time := _simulation_time()
	for index in range(1,points.size()):
		var hit: Dictionary = terrain.segment_hit(points[index-1],points[index],time,time)
		if hit.is_empty(): continue
		points[index] = hit.position
		points.resize(index+1)
		impact_point = points[index]*0.001
		prediction_kind = "Impact"
		break
	_coast_points = points
	path_material.albedo_color = _prediction_color()
	path_mesh.clear_surfaces()
	if points.size() > 1:
		path_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,path_material)
		for point in points: path_mesh.surface_add_vertex(point*0.001)
		path_mesh.surface_end()

func _prediction_color() -> Color:
	if prediction_kind == "Impact": return IMPACT_COLOR
	if prediction_kind == "Escape": return ESCAPE_COLOR
	return FUTURE_COLOR

func _update_indicators() -> void:
	var radial: Vector3 = Vector3(state.get("position",Vector3.ZERO))-Physics.PLANET_CENTER
	var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
	var elements := Physics.orbital_elements(radial,velocity,_home_mu(),_home_radius())
	var apo: float = elements.apoapsis
	extent = maxf(100.0,radial.length()*0.001*1.3)
	if is_finite(apo): extent = maxf(extent,minf((apo+_home_radius())*0.001,10000.0))
	marker.position = radial*0.001
	marker.scale = Vector3.ONE*maxf(1.0,extent*zoom/100.0)
	labels = [{"position":marker.position,"text":"CRAFT","color":CRAFT_COLOR}]
	if maneuver_valid:
		labels.append({"position":Vector3(maneuver.result.position)*0.001,"text":"MANEUVER","color":MANEUVER_COLOR})
		labels.append_array(_maneuver_labels)
	if impact_point.is_finite():
		labels.append({"position":impact_point,"text":"IMPACT","color":IMPACT_COLOR})
	var eccentricity: Vector3 = elements.eccentricity_vector
	if eccentricity.length() > 0.00001:
		var peri: float = elements.periapsis
		if peri >= 0.0:
			labels.append({"position":eccentricity.normalized()*(peri+_home_radius())*0.001,"text":"Pe %.1f km" % (peri*0.001),"color":FUTURE_COLOR})
		if is_finite(apo) and apo >= 0.0 and not (prediction_kind == "Impact" and radial.dot(velocity) <= 0.0):
			labels.append({"position":-eccentricity.normalized()*(apo+_home_radius())*0.001,"text":"Ap %.1f km" % (apo*0.001),"color":FUTURE_COLOR})

func _update_camera() -> void:
	var framing_distance := camera_extent*3.0*zoom
	var target := _camera_target()
	# A focused body must render near zero: a system-distance camera loses
	# whole pixels of precision when orbiting small moons and planets.
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(1.0, framing_distance * 2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	# Keep the distant sun at 4% of the orthographic view span as the
	# planet zooms. Its physical position still controls lighting and eclipses.
	local_sun.scale = Vector3.ONE * camera.size * 0.02 / (SolarBody.RADIUS * 0.001)
	var distance := maxf(framing_distance, target.distance_to(local_sun.position) + system_radius + 2000.0)
	var system_distance := distance
	camera.near = 0.5
	camera.far = maxf(100000.0, distance * 3.0)
	var focused_body := system_focus and focus_index >= 0
	var focused_craft := not system_focus and local_focus_craft
	render_origin = target if focused_body or focused_craft else Vector3.ZERO
	render_root.position = -render_origin
	if focused_body or focused_craft:
		var definition: Resource = planet_definitions[focus_index] if focused_body else Surface.home().definition
		distance = maxf(framing_distance, (float(definition.radius) + float(definition.atmosphere_height) + float(definition.relief)) * 0.002)
		camera.far = maxf(10000.0, distance * 3.0)
	camera.position = (target-render_origin)+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.look_at(target-render_origin,Vector3.UP)
	_update_background(system_distance)
	var material: ShaderMaterial = globe.material_override
	material.set_shader_parameter("camera_planet_km",camera.position+render_origin)
	material.set_shader_parameter("orthographic_view", true)
	material.set_shader_parameter("camera_forward", -camera.basis.z)
	# Lighting and the visible sun share the map's planet-centered frame.
	# Flight uses a direction from the craft, which diverges near the sun.
	material.set_shader_parameter("sun_direction", (local_sun.position-globe.position).normalized())
	for index in range(bodies.size()):
		var body := bodies[index]
		var atmosphere := body.get_node_or_null("MapAtmosphere") as MeshInstance3D
		if atmosphere != null:
			var atmosphere_material := atmosphere.material_override as ShaderMaterial
			atmosphere_material.set_shader_parameter("camera_forward", -camera.basis.z)
			atmosphere_material.set_shader_parameter("sun_direction", (local_sun.position-body.position).normalized())
		if body == globe: continue
		var surface_material: ShaderMaterial = body.material_override
		surface_material.set_shader_parameter("camera_planet_km", camera.position-(body.position-render_origin))
		surface_material.set_shader_parameter("camera_forward", -camera.basis.z)
		surface_material.set_shader_parameter("sun_direction", (local_sun.position-body.position).normalized())
		var ancestor := body_parents[index]
		if ancestor >= 0:
			while body_parents[ancestor] >= 0:
				ancestor = body_parents[ancestor]
			surface_material.set_shader_parameter("eclipse_center_km", bodies[ancestor].position-body.position)
			surface_material.set_shader_parameter("eclipse_radius_km", float(planet_definitions[ancestor].radius)*0.001)
			surface_material.set_shader_parameter("eclipse_sun_distance_km", local_sun.position.distance_to(body.position))
			surface_material.set_shader_parameter("eclipse_sun_radius_km", SolarBody.RADIUS * 0.001)

# The distant pass shares geometry and the orthographic span, but has its
# own depth range. The close pass retains full precision on the focused body.
func _update_background(system_distance: float) -> void:
	var focused := (system_focus and focus_index >= 0) or (not system_focus and local_focus_craft)
	viewport.transparent_bg = focused
	background_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if focused else SubViewport.UPDATE_DISABLED
	camera.cull_mask = 1
	_set_render_layer(render_root, 2 if focused else 1)
	if not focused:
		return
	_set_render_layer(bodies[focus_index] if system_focus else globe, 1)
	background_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	background_camera.size = camera.size
	background_camera.near = 0.5
	background_camera.far = system_distance * 3.0
	background_camera.basis = camera.basis
	background_camera.position = camera.basis.z * system_distance

func _set_render_layer(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		node.layers = layer
	for child in node.get_children():
		_set_render_layer(child, layer)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		maneuver_gizmo.hovered = maneuver_gizmo.hit_test(event.position)
		maneuver_gizmo.queue_redraw()
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		yaw -= event.relative.x*0.005
		pitch = clampf(pitch+event.relative.y*0.005,-1.45,1.45)
		accept_event()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index != MOUSE_BUTTON_LEFT: orbit_menu.hide()
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit: focus.release_focus()
		if event.button_index == MOUSE_BUTTON_LEFT:
			orbit_menu.hide()
			var handle: int = maneuver_gizmo.hit_test(event.position)
			if handle >= 0:
				maneuver_gizmo.begin_drag(handle)
				accept_event()
				return
			if event.position.y < 70.0 and event.position.x > size.x-310.0:
				system_focus = event.position.x < size.x-160.0
				local_focus_craft = false
				focus_index = -1
				zoom = 1.0
				reset_framing = true
			elif event.position.x < 220.0 and event.position.y >= 155.0 and event.position.y < 155.0 + planet_definitions.size()*26.0:
				_focus_planet(int((event.position.y-155.0)/26.0))
			elif _craft_icon_hit(event.position):
				local_focus_craft = true
				system_focus = false
				zoom = 1.0
				reset_framing = true
			else:
				var node_time := _maneuver_path_hit(event.position)
				if node_time >= 0.0:
					_show_orbit_menu(event.position, node_time)
				else:
					var planet_index := _planet_hit(event.position)
					if planet_index >= 0:
						_focus_planet(planet_index)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom = maxf(0.00003,zoom/1.25)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom = minf(100000.0,zoom*1.25)
		accept_event()

func _focus_planet(index: int) -> void:
	focus_index = index
	system_focus = true
	local_focus_craft = false
	zoom = 1.0
	reset_framing = true

func _planet_hit(screen_position: Vector2) -> int:
	for hit in planet_label_hits:
		if hit.bounds.has_point(screen_position):
			return int(hit.index)
	var nearest := -1
	var nearest_depth := INF
	for index in range(bodies.size()):
		var body := bodies[index]
		if not body.is_visible_in_tree() or _map_position_behind(body.position):
			continue
		var center := _project_map_position(body.position)
		var radius := float(planet_definitions[index].radius)*0.001
		var edge := _project_map_position(body.position+camera.global_basis.x*radius)
		if screen_position.distance_to(center) > maxf(12.0, center.distance_to(edge)):
			continue
		var depth := - (camera.global_transform.affine_inverse()*(body.position-render_origin)).z
		if depth < nearest_depth:
			nearest = index
			nearest_depth = depth
	return nearest

# Simulation positions stay in the home frame; only rendering is rebased.
func _project_map_position(point: Vector3) -> Vector2:
	return camera.unproject_position(point-render_origin)

func _map_position_behind(point: Vector3) -> bool:
	return background_camera.is_position_behind(point-render_origin) if viewport.transparent_bg else camera.is_position_behind(point-render_origin)

func _camera_target() -> Vector3:
	if system_focus:
		return bodies[focus_index].position if focus_index >= 0 else local_sun.position
	if local_focus_craft:
		return marker.position
	return Vector3.ZERO

func _craft_icon_hit(screen_position: Vector2) -> bool:
	if state.is_empty() or _map_position_behind(marker.position):
		return false
	if _point_occluded(marker.position): return false
	var icon_position := _project_map_position(marker.position)
	return screen_position.distance_to(icon_position) <= 18.0

func _point_occluded(point: Vector3) -> bool:
	var end := point.move_toward(camera.position+render_origin,0.004)*1000.0
	var time := _simulation_time()
	return not Surface.home().segment_hit((camera.position+render_origin)*1000.0,end,time,time).is_empty()

func _draw_overlay() -> void:
	planet_label_hits.clear()
	if not is_instance_valid(camera): return
	var font := ThemeDB.fallback_font
	overlay.draw_string(font,Vector2(20,28),"ORBITAL MAP",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("eef2e9"))
	overlay.draw_string(font,Vector2(20,50),"Planet and moon orbits + predicted craft coast • illustrative phases",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("91a8aa"))
	for index in range(2):
		var rect := Rect2(size.x-310.0+index*150.0,12,140,36)
		overlay.draw_style_box(get_theme_stylebox("normal","Button"),rect)
		overlay.draw_string(font,rect.position+Vector2(12,24),"Fit system" if index == 0 else "Focus planet",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("7ce5c0"))
	overlay.draw_string(font,Vector2(20,size.y-20),"Click coast: plan / warp   •   Drag symbols: change burn   •   RMB: orbit   •   Scroll: zoom   •   M: close",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("91a8aa"))
	var legend := [["Past flight",PAST_COLOR],["Craft orbit",FUTURE_COLOR],["Impact",IMPACT_COLOR],["Escape",ESCAPE_COLOR],["Body orbit",Color(Surface.home().definition.map_color).lightened(0.2)]]
	for index in range(legend.size()):
		var x := 20.0+float(index)*132.0
		overlay.draw_line(Vector2(x,82),Vector2(x+22,82),legend[index][1],2,true)
		overlay.draw_string(font,Vector2(x+30,87),legend[index][0],HORIZONTAL_ALIGNMENT_LEFT,-1,13,legend[index][1])
	var status := prediction_kind.to_upper()+"  /  PREDICTED COAST"
	overlay.draw_circle(Vector2(25,115),3,_prediction_color())
	overlay.draw_string(font,Vector2(38,120),status,HORIZONTAL_ALIGNMENT_LEFT,-1,13,_prediction_color())
	for index in range(planet_definitions.size()):
		var definition := planet_definitions[index]
		overlay.draw_string(font,Vector2(20,174+index*26),("    Moon: " if body_parents[index] >= 0 else "") + str(definition.planet_name),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(definition.map_color).lightened(0.2))
	var occupied: Array[Rect2] = []
	for label in labels:
		var point: Vector3 = label.position
		if _map_position_behind(point): continue
		# Hide markers behind the globe, matching depth-tested trajectory lines.
		if not label.get("body", false) and _point_occluded(point): continue
		var screen := _project_map_position(point)
		if not Rect2(Vector2(225,75),size-Vector2(245,115)).has_point(screen): continue
		var text_position := screen+Vector2(10,-8)
		if label.get("body", false) and point == globe.position:
			text_position.x += minf(100.0, float(Surface.home().definition.radius)*0.001/camera.size*size.y)
		var bounds := Rect2(text_position-Vector2(0,14),Vector2(font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x,18))
		if maneuver_panel.visible and bounds.intersects(maneuver_panel.get_rect().grow(8)):
			bounds.position.x = maneuver_panel.position.x - bounds.size.x - 12
			text_position.x = bounds.position.x
		for attempt in range(12):
			var overlaps := false
			for previous in occupied:
				if bounds.intersects(previous): overlaps = true
			if not overlaps: break
			bounds.position.y += 20
			text_position.y += 20
		occupied.append(bounds)
		if label.has("planet_index"):
			planet_label_hits.append({"bounds":bounds.grow(4),"index":label.planet_index})
		if label.text == "CRAFT":
			_draw_craft_icon(screen,label.color,_craft_screen_direction(point,screen))
		elif label.text == "IMPACT":
			overlay.draw_arc(screen,8,0,TAU,32,label.color,1.5,true)
			overlay.draw_line(screen-Vector2(4,4),screen+Vector2(4,4),label.color,1.5,true)
			overlay.draw_line(screen-Vector2(4,-4),screen+Vector2(4,-4),label.color,1.5,true)
		else:
			overlay.draw_circle(screen,3,label.color)
		overlay.draw_style_box(label_style,bounds.grow(4))
		overlay.draw_line(screen,text_position-Vector2(3,4),Color(label.color,0.4),1,true)
		overlay.draw_string(font,text_position,label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,label.color)

func _label_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015,0.035,0.05,0.88)
	style.set_corner_radius_all(4)
	return style

func _craft_screen_direction(point: Vector3, screen: Vector2) -> Vector2:
	if path_mesh.get_surface_count() > 0:
		var vertices: PackedVector3Array = path_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var path_direction := _screen_direction_from_path(point,screen,vertices)
		if path_direction.length() > 0.001:
			return path_direction
	var radial: Vector3 = Vector3(state.get("position",Vector3.ZERO))-Physics.PLANET_CENTER
	var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
	var tangent := velocity-radial.normalized()*velocity.dot(radial.normalized()) if radial.length() > 0.001 else velocity
	if tangent.length() < 0.001:
		tangent = velocity if velocity.length() > 0.001 else Vector3.UP
	var lead := point+tangent.normalized()*maxf(2.0,extent*0.05)
	if _map_position_behind(lead):
		return Vector2.UP
	var projected := _project_map_position(lead)
	var direction := projected-screen
	return direction.normalized() if direction.length() > 0.001 else Vector2.UP

func _screen_direction_from_path(point: Vector3, screen: Vector2, vertices: PackedVector3Array) -> Vector2:
	for index in range(1,vertices.size()):
		var candidate := vertices[index]
		if candidate.distance_squared_to(point) < 0.0001:
			continue
		if _map_position_behind(candidate):
			continue
		var direction := _project_map_position(candidate)-screen
		if direction.length() > 0.001:
			return direction.normalized()
	return Vector2.ZERO

func _craft_icon_point(position: Vector2, direction: Vector2, local: Vector2) -> Vector2:
	var right := Vector2(direction.y,-direction.x)
	return position+right*local.x+direction*local.y

func _draw_craft_icon(position: Vector2, color: Color, direction: Vector2) -> void:
	var shape := PackedVector2Array([
		Vector2(0,11),
		Vector2(-5,-1),
		Vector2(-10,-9),
		Vector2(-3,-6),
		Vector2(0,-12),
		Vector2(3,-6),
		Vector2(10,-9),
		Vector2(5,-1),
	])
	var points := PackedVector2Array()
	for point in shape:
		points.append(_craft_icon_point(position,direction,point))
	overlay.draw_colored_polygon(points,color)
	var outline := points
	outline.append(points[0])
	overlay.draw_polyline(outline,Color.WHITE,1.2,true)
	overlay.draw_line(_craft_icon_point(position,direction,Vector2(-3,0)),_craft_icon_point(position,direction,Vector2(3,0)),Color("052226"),1.0,true)

func _build_maneuver_ui() -> void:
	maneuver_panel = PanelContainer.new()
	maneuver_panel.name = "ManeuverEditor"
	maneuver_panel.anchor_left = 1.0
	maneuver_panel.anchor_right = 1.0
	maneuver_panel.offset_left = -330
	maneuver_panel.offset_right = -16
	maneuver_panel.offset_top = 142
	maneuver_panel.anchor_bottom = 1.0
	maneuver_panel.offset_bottom = -48
	maneuver_panel.add_theme_stylebox_override("panel", _label_style())
	add_child(maneuver_panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 14)
	maneuver_panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "MANEUVER PLANNER"
	title.add_theme_color_override("font_color", MANEUVER_COLOR)
	box.add_child(title)
	var help := Label.new()
	help.text = "Drag a direction symbol outward to add burn, inward to reduce it. Hold Shift for fine adjustment."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 13)
	box.add_child(help)
	var precise_button := Button.new()
	precise_button.text = "Precise values"
	precise_button.toggle_mode = true
	box.add_child(precise_button)
	precise_values = VBoxContainer.new()
	box.add_child(precise_values)
	precise_values.hide()
	precise_button.toggled.connect(func(enabled: bool): precise_values.visible = enabled)
	for index in range(3):
		var row := HBoxContainer.new()
		precise_values.add_child(row)
		var label := Label.new()
		label.text = ["Prograde", "Normal", "Radial out"][index]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = ["Positive: prograde; negative: retrograde", "Positive: normal; negative: anti-normal", "Positive: radial out; negative: radial in"][index]
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = -5000.0
		spin.max_value = 5000.0
		spin.step = 1.0
		spin.suffix = "m/s"
		spin.custom_minimum_size.x = 152
		spin.value_changed.connect(func(value: float):
			plan_edit_started.emit()
			maneuver.components[index] = value
			_refresh_maneuver(true)
		)
		row.add_child(spin)
		spin.get_line_edit().text_submitted.connect(func(_text: String): spin.get_line_edit().release_focus())
		maneuver_fields.append(spin)
	var shifts := HBoxContainer.new()
	box.add_child(shifts)
	for shift in [-10.0, 10.0]:
		var button := Button.new()
		button.text = "%+d s" % shift
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			plan_edit_started.emit()
			maneuver.epoch = clampf(maneuver.epoch + shift, _simulation_time() + 1.0, _simulation_time() + Maneuver.MAX_SECONDS)
			_refresh_maneuver(true)
		)
		shifts.add_child(button)
		maneuver_shift_buttons.append(button)
	maneuver_delete = Button.new()
	maneuver_delete.text = "Delete burn"
	maneuver_delete.pressed.connect(clear_maneuver)
	box.add_child(maneuver_delete)
	maneuver_summary = Label.new()
	maneuver_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	maneuver_summary.add_theme_font_size_override("font_size", 14)
	box.add_child(maneuver_summary)
	maneuver_notice = Label.new()
	maneuver_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	maneuver_notice.add_theme_font_size_override("font_size", 12)
	maneuver_notice.add_theme_color_override("font_color", Color("efab65"))
	box.add_child(maneuver_notice)
	_update_maneuver_ui()

func clear_maneuver() -> void:
	if is_instance_valid(maneuver_gizmo): maneuver_gizmo.hide()
	maneuver.clear()
	maneuver_valid = false
	maneuver_status = ""
	maneuver_path_note = ""
	_maneuver_labels.clear()
	maneuver_mesh.clear_surfaces()
	_maneuver_mesh_dirty = false
	_maneuver_refresh_time = -INF
	for field in maneuver_fields: field.set_value_no_signal(0.0)
	if is_instance_valid(maneuver_summary): _update_maneuver_ui()
	if is_instance_valid(overlay): overlay.queue_redraw()

func _planning_block() -> String:
	if state.is_empty() or str(state.get("status", "flying")) != "flying": return "Launch and coast in space to plan a burn."
	if str(state.get("reference_body", Surface.home().definition.planet_name)) != str(Surface.home().definition.planet_name): return "Planning currently supports the home planet only."
	if float(state.get("throttle", 0.0)) > 0.0 or (state.get("boosters_on", false) and state.get("boosters_attached", false) and float(state.get("booster_fuel", 0.0)) > 0.0): return "Cut throttle and wait for booster burnout to predict a coast."
	return ""

func place_maneuver(seconds_from_now: float) -> bool:
	if not is_finite(seconds_from_now) or seconds_from_now <= 0.0 or seconds_from_now > Maneuver.MAX_SECONDS: return false
	maneuver.epoch = _simulation_time() + seconds_from_now
	_refresh_maneuver(true)
	return maneuver_valid

## Called even with the map closed, so passed nodes and thrust remove guidance.
func set_flight_state(telemetry: Dictionary) -> void:
	state = telemetry
	_refresh_maneuver()

func _refresh_maneuver(force: bool = false) -> void:
	var now := _simulation_time()
	var block := _planning_block()
	var signature := block + str(state.get("stage_index", 0)) + str(state.get("removed_parts", [])) + str(_home_mu())
	if not force and now >= _maneuver_refresh_time and now - _maneuver_refresh_time < 0.25 and signature == _maneuver_signature:
		if maneuver.epoch >= 0.0 and maneuver.epoch < now and maneuver_valid:
			force = true
		else: return
	_maneuver_refresh_time = now
	_maneuver_signature = signature
	maneuver_valid = false
	maneuver.result.clear()
	maneuver_path_note = ""
	maneuver_status = block
	_maneuver_mesh_dirty = true
	if maneuver.epoch >= 0.0 and block.is_empty():
		if maneuver.epoch < now:
			maneuver_status = "Burn time passed. Click the coast to place a new burn."
		else:
			var radial: Vector3 = Vector3(state.position) - Physics.PLANET_CENTER
			var velocity: Vector3 = state.velocity
			var approach := Maneuver.timed_path(radial, velocity, _home_mu(), _home_radius(), maneuver.epoch - now)
			if approach.points.is_empty():
				maneuver_status = "This radial or near-parabolic coast has no supported maneuver frame."
			else:
				var limit := _path_limit(approach.points, approach.times, now)
				if not limit.reason.is_empty():
					maneuver_status = "Before burn: " + str(limit.reason)
				else:
					var prediction := maneuver.evaluate(radial, velocity, now, _home_mu(), _home_radius())
					maneuver_valid = not prediction.is_empty()
					if not maneuver_valid: maneuver_status = "Move the burn onto a future coast within six hours."
	if is_instance_valid(maneuver_summary): _update_maneuver_ui()

## Stop estimates before atmosphere/terrain or appreciable moon perturbation.
## This is deliberately a two-body planner, not an encounter predictor.
func _path_limit(points: PackedVector3Array, times: PackedFloat64Array, start: float) -> Dictionary:
	var definition: Resource = Surface.home().definition
	var floor_radius := _home_radius() + maxf(float(definition.atmosphere_height), float(definition.relief) * 2.0 + 100.0)
	for index in range(points.size()):
		var nearest := points[index]
		if index > 0:
			nearest = Geometry3D.get_closest_point_to_segment(Vector3.ZERO, points[index - 1], points[index])
		if nearest.length() <= floor_radius:
			return {"index": index, "reason": "Atmosphere or terrain ahead; coast prediction stops here."}
		if _moon_influence(points[index], start + times[index]):
			return {"index": index, "reason": "Moon encounter region; encounter prediction is not available."}
	return {"index": points.size(), "reason": ""}

func _moon_influence(point: Vector3, time: float) -> bool:
	var centers: Dictionary = {home_index: Vector3.ZERO}
	for index in range(planet_definitions.size()):
		var parent: int = body_parents[index]
		if parent < 0 or not centers.has(parent): continue
		var definition: Resource = planet_definitions[index]
		var center: Vector3 = centers[parent] + SolarBody.moon_offset(definition, time)
		centers[index] = center
		var moon_mu := float(definition.surface_gravity) * pow(float(definition.radius), 2.0)
		var distance_squared := maxf(point.distance_squared_to(center), 1.0)
		if moon_mu / distance_squared > 0.01 * _home_mu() / maxf(point.length_squared(), 1.0): return true
	return false

func _update_maneuver_mesh() -> void:
	_maneuver_mesh_dirty = false
	maneuver_mesh.clear_surfaces()
	_maneuver_labels.clear()
	if not maneuver_valid: return
	var prediction: Dictionary = maneuver.result
	var path := Maneuver.timed_path(prediction.position, prediction.after_velocity, _home_mu(), _home_radius())
	if path.points.size() < 2:
		maneuver_path_note = "Post-burn trajectory is radial or near-parabolic; preview unavailable."
		_update_maneuver_ui()
		return
	var limit := _path_limit(path.points, path.times, maneuver.epoch)
	maneuver_path_note = limit.reason
	var count := mini(int(limit.index), path.points.size())
	if count > 1:
		maneuver_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, maneuver_material)
		for index in range(count): maneuver_mesh.surface_add_vertex(path.points[index] * 0.001)
		maneuver_mesh.surface_end()
		if not maneuver_path_note.is_empty():
			_maneuver_labels.append({"position":path.points[count-1]*0.001,"text":"PREVIEW LIMIT","color":MANEUVER_COLOR})
		else:
			var elements: Dictionary = prediction.elements
			if float(elements.eccentricity) > 0.00001:
				var direction: Vector3 = Vector3(elements.eccentricity_vector).normalized()
				for entry in [["Planned Pe", float(elements.periapsis), direction], ["Planned Ap", float(elements.apoapsis), -direction]]:
					if not is_finite(entry[1]) or entry[1] < 0.0: continue
					var point: Vector3 = entry[2] * (entry[1] + _home_radius())
					var arrival := Maneuver.time_to_point(prediction.position, prediction.after_velocity, point, _home_mu(), _home_radius())
					if arrival < 0.0 or arrival > float(path.times[count-1]): continue
					_maneuver_labels.append({"position":point*0.001,"text":"%s %.1f km" % [entry[0], entry[1]*0.001],"color":MANEUVER_COLOR})
	_update_maneuver_ui()

func maneuver_direction() -> Vector3:
	if not maneuver_valid or maneuver.epoch < _simulation_time() or not _planning_block().is_empty(): return Vector3.ZERO
	return Vector3(maneuver.result.get("burn", Vector3.ZERO)).normalized()

func _update_maneuver_ui() -> void:
	var exists := maneuver.epoch >= 0.0
	maneuver_panel.visible = exists
	for field in maneuver_fields: field.editable = exists
	for button in maneuver_shift_buttons: button.disabled = not exists
	maneuver_delete.disabled = not exists
	maneuver_notice.text = "Instantaneous burn • manual execution\nFull-throttle estimate for ignited liquid engines. No staging, drag or moon gravity."
	if not exists:
		maneuver_summary.text = _planning_block() if not _planning_block().is_empty() else "No burn planned. Signed values select the opposite direction."
		return
	if not maneuver_valid:
		maneuver_summary.text = maneuver_status
		return
	var delta_v := maneuver.components.length()
	var burn := Maneuver.burn_estimate(float(state.get("mass", 0.0)), state.get("maneuver_engines", []), delta_v)
	var elements: Dictionary = maneuver.result.elements
	var apo := "Escape" if not is_finite(elements.apoapsis) else "%.1f km" % (float(elements.apoapsis) * 0.001)
	var duration := "%.1f s" % burn.duration if burn.sufficient else "Unavailable"
	maneuver_summary.text = "Burn in %.1f s  ·  Δv %.1f m/s\nPlanned Ap: %s\nPlanned Pe: %.1f km\nBurn duration: %s\nAvailable Δv: %.1f m/s" % [maxf(0.0, maneuver.epoch - _simulation_time()), delta_v, apo, float(elements.periapsis) * 0.001, duration, burn.available]
	if burn.sufficient and delta_v > 0.0:
		maneuver_summary.text += "\nFuel needed: %.1f kg\nStart burn in %.1f s" % [burn.fuel, maneuver.epoch - _simulation_time() - float(burn.duration) * 0.5]
	elif not burn.sufficient:
		maneuver_notice.text = "Insufficient usable fuel or no ignited liquid engine.\n" + maneuver_notice.text
	if not maneuver_path_note.is_empty(): maneuver_notice.text += "\n" + maneuver_path_note

func _maneuver_path_hit(screen: Vector2) -> float:
	if _coast_points.size() < 2: return -1.0
	var best := 12.0
	var selected := Vector3.INF
	for index in range(1, _coast_points.size()):
		var from := _coast_points[index - 1] * 0.001
		var to := _coast_points[index] * 0.001
		if _map_position_behind(from) or _map_position_behind(to): continue
		var a := _project_map_position(from)
		var b := _project_map_position(to)
		var closest := Geometry2D.get_closest_point_to_segment(screen, a, b)
		var distance := screen.distance_to(closest)
		if distance >= best: continue
		var fraction := clampf((closest - a).dot(b - a) / maxf(a.distance_squared_to(b), 0.0001), 0.0, 1.0)
		var point := from.lerp(to, fraction)
		if _point_occluded(point): continue
		best = distance
		selected = point * 1000.0
	if not selected.is_finite(): return -1.0
	var seconds := Maneuver.time_to_point(Vector3(state.position) - Physics.PLANET_CENTER, state.velocity, selected, _home_mu(), _home_radius())
	return seconds if seconds >= 1.0 and seconds <= Maneuver.MAX_SECONDS else -1.0

func _build_orbit_menu() -> void:
	orbit_menu = PanelContainer.new()
	orbit_menu.name = "OrbitContextMenu"
	var style := _label_style()
	style.bg_color = Color("101c30")
	style.set_content_margin_all(6)
	orbit_menu.add_theme_stylebox_override("panel", style)
	add_child(orbit_menu)
	var items := VBoxContainer.new()
	orbit_menu.add_child(items)
	orbit_create_button = Button.new()
	orbit_create_button.text = "Create plan"
	orbit_create_button.custom_minimum_size = Vector2(206, 40)
	items.add_child(orbit_create_button)
	orbit_create_button.pressed.connect(_create_context_plan)
	orbit_warp_button = Button.new()
	orbit_warp_button.text = "Warp here"
	orbit_warp_button.custom_minimum_size = Vector2(206, 40)
	items.add_child(orbit_warp_button)
	orbit_warp_button.pressed.connect(func():
		orbit_menu.hide()
		if orbit_menu_epoch > _simulation_time(): warp_to_requested.emit(orbit_menu_epoch)
	)
	orbit_menu.hide()
	stop_warp_button = Button.new()
	stop_warp_button.anchor_left = 1.0
	stop_warp_button.anchor_right = 1.0
	stop_warp_button.anchor_top = 1.0
	stop_warp_button.anchor_bottom = 1.0
	stop_warp_button.offset_left = -330
	stop_warp_button.offset_right = -16
	stop_warp_button.offset_top = -40
	stop_warp_button.offset_bottom = -8
	stop_warp_button.add_theme_font_size_override("font_size", 12)
	stop_warp_button.pressed.connect(func(): cancel_warp_requested.emit())
	add_child(stop_warp_button)
	stop_warp_button.hide()

func _show_orbit_menu(point: Vector2, seconds: float) -> void:
	orbit_menu_epoch = _simulation_time() + seconds
	orbit_menu.position = Vector2(clampf(point.x + 12, 4, size.x - 230), clampf(point.y + 12, 4, size.y - 110))
	orbit_create_button.disabled = not _planning_block().is_empty()
	orbit_create_button.tooltip_text = _planning_block()
	orbit_warp_button.disabled = not _planning_block().is_empty() or float(state.get("warp_limit", 1.0)) <= 1.0
	orbit_warp_button.tooltip_text = "Time warp requires a safe unpowered coast." if orbit_warp_button.disabled else "Advance to this predicted time and return to 1×."
	orbit_menu.show()

func _create_context_plan() -> void:
	orbit_menu.hide()
	if orbit_menu_epoch <= _simulation_time(): return
	plan_edit_started.emit()
	# A new plan replaces the previous one; moving time via ±10s keeps its burn.
	maneuver.components = Vector3.ZERO
	for field in maneuver_fields: field.set_value_no_signal(0.0)
	place_maneuver(orbit_menu_epoch - _simulation_time())
	_update_maneuver_mesh()
	_update_maneuver_gizmo()

func _update_maneuver_gizmo() -> void:
	var show_handles := maneuver_valid
	if show_handles:
		var point: Vector3 = Vector3(maneuver.result.position) * 0.001
		show_handles = not _map_position_behind(point) and not _point_occluded(point) and Rect2(Vector2.ZERO, size).has_point(_project_map_position(point))
		if show_handles:
			var basis := Physics.orbital_elements(maneuver.result.position, maneuver.result.velocity, _home_mu(), _home_radius())
			var available := Rect2(Vector2(230, 125), Vector2(maxf(260, size.x - 575), maxf(260, size.y - 170)))
			maneuver_gizmo.set_frame(point-render_origin, [basis.prograde, basis.normal, basis.radial_out], camera, maneuver.components, available)
	maneuver_gizmo.visible = show_handles
	if orbit_menu.visible:
		var passed := orbit_menu_epoch <= _simulation_time()
		orbit_create_button.disabled = passed or not _planning_block().is_empty()
		orbit_warp_button.disabled = orbit_create_button.disabled or float(state.get("warp_limit", 1.0)) <= 1.0
		orbit_create_button.tooltip_text = "This point has passed. Click the orbit again." if passed else _planning_block()
		orbit_warp_button.tooltip_text = "Time warp requires a safe unpowered coast." if orbit_warp_button.disabled else "Advance to this predicted time and return to 1×."
