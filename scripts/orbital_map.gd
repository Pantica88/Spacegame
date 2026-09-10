extends Control
## Interactive 3D map using the same globe and coast predictor as flight.
const Surface = preload("res://scripts/planet_surface.gd")
const Physics = preload("res://scripts/physics_math.gd")
const PlanetList = preload("res://scripts/planet_list.gd")
const PAST_COLOR := Color("efab65")
const FUTURE_COLOR := Color("69c8ff")
const IMPACT_COLOR := Color("ff7882")
const ESCAPE_COLOR := Color("f5d879")
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
var camera: Camera3D
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
var overlay: Control
var label_style: StyleBoxFlat
var system_root: Node3D
var system_mode := false
var local_focus_craft := false
var focus_index := -1
var bodies: Array[MeshInstance3D] = []
var planet_definitions: Array[Resource] = []
var path_mesh := ImmediateMesh.new()
var path_material: StandardMaterial3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.own_world_3d = true
	container.add_child(viewport)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("020509")
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	viewport.add_child(environment_node)
	globe = MeshInstance3D.new()
	# The map can zoom in regardless of the vehicle altitude. Use the
	# editor's globe resolution instead of inheriting the flight mesh LOD.
	globe.mesh = Surface.home().preview_mesh()
	globe.scale = Vector3.ONE*0.001
	globe.material_override = source_world._planet.material_override.duplicate()
	globe.material_override.set_shader_parameter("surface_coordinate_scale",1000.0)
	globe.material_override.set_shader_parameter("atmosphere_view_samples",12)
	globe.material_override.set_shader_parameter("atmosphere_light_samples",3)
	viewport.add_child(globe)
	trajectory = MeshInstance3D.new()
	path_material = _material(FUTURE_COLOR)
	trajectory.mesh = path_mesh
	viewport.add_child(trajectory)
	history_material = _material(PAST_COLOR)
	history_node = MeshInstance3D.new()
	history_node.mesh = history_mesh
	viewport.add_child(history_node)
	history_tail_node = MeshInstance3D.new()
	history_tail_node.mesh = history_tail_mesh
	viewport.add_child(history_tail_node)
	marker = MeshInstance3D.new()
	viewport.add_child(marker)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.fov = 43.0
	camera.far = 100000.0
	viewport.add_child(camera)
	camera.current = true
	_build_system()
	label_style = _label_style()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	_update_camera()

func _build_system() -> void:
	system_root = Node3D.new()
	viewport.add_child(system_root)
	planet_definitions = PlanetList.load_all().filter(func(definition: Resource): return bool(definition.orbit_enabled))
	var sun := MeshInstance3D.new()
	var sun_mesh := SphereMesh.new()
	sun_mesh.radius = 8.0
	sun_mesh.height = 16.0
	sun.mesh = sun_mesh
	sun.material_override = _material(Color("ffd487"))
	system_root.add_child(sun)
	for index in range(planet_definitions.size()):
		var definition := planet_definitions[index]
		var orbit := ImmediateMesh.new()
		orbit.surface_begin(Mesh.PRIMITIVE_LINE_STRIP,_material(Color(definition.map_color).darkened(0.65)))
		for step in range(257):
			var angle := TAU*float(step)/256.0
			orbit.surface_add_vertex(Vector3(cos(angle),0,sin(angle))*float(definition.orbit_distance_au)*100.0)
		orbit.surface_end()
		var line := MeshInstance3D.new()
		line.mesh = orbit
		system_root.add_child(line)
		var body := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = clampf(float(definition.radius) / 16000.0, 1.5, 6.0)
		sphere.height = sphere.radius*2.0
		body.mesh = sphere
		body.material_override = _material(Color(definition.map_color))
		system_root.add_child(body)
		bodies.append(body)
	system_root.hide()

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func reset_history(position: Vector3) -> void:
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
		reset_framing = true
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	globe.basis = Surface.home().rotation_at(float(state.get("time",0.0))).scaled(Vector3.ONE*0.001)
	if system_mode: _update_system()
	else: _update_indicators()
	if not system_mode:
		var position: Vector3 = state.get("position",Vector3.ZERO)
		var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
		if path_dirty or position != last_path_position or velocity != last_path_velocity:
			_update_path()
			last_path_position = position
			last_path_velocity = velocity
			path_dirty = false
		_update_indicators()
		_update_history()
	camera_extent = extent if reset_framing else lerpf(camera_extent,extent,1.0-exp(-delta*12.0))
	reset_framing = false
	_update_camera()
	overlay.queue_redraw()

func _update_system() -> void:
	extent = 3200.0 if focus_index < 0 else maxf(15.0,float(planet_definitions[focus_index].orbit_distance_au)*40.0)
	labels = [{"position":Vector3.ZERO,"text":"SUN","color":Color("ffd487")}]
	for index in range(bodies.size()):
		var definition := planet_definitions[index]
		var phase := TAU*float(definition.orbit_phase)+TAU*float(state.get("time",0.0))/(float(definition.orbit_period_days)*86400.0)
		bodies[index].position = Vector3(cos(phase),0,sin(phase))*float(definition.orbit_distance_au)*100.0
		bodies[index].scale = Vector3.ONE*maxf(1.0,zoom*6.0)
		labels.append({"position":bodies[index].position,"text":str(definition.planet_name)+"  %.2f AU" % float(definition.orbit_distance_au),"color":Color(definition.map_color)})

func _update_path() -> void:
	var radial: Vector3 = Vector3(state.get("position",Vector3.ZERO))-Physics.PLANET_CENTER
	var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
	var points := Physics.coast_path(radial,velocity,maxf(extent*4000.0,radial.length()*2.0))
	var elements := Physics.orbital_elements(radial,velocity)
	var will_impact: bool = elements.periapsis < 0.0 and (elements.bound_orbit or radial.dot(velocity) < 0.0)
	prediction_kind = "Impact" if will_impact else ("Orbit" if elements.bound_orbit else "Escape")
	impact_point = Vector3.INF
	# Use the same triangles as flight. This coast overlay samples the current
	# terrain orientation; it is not a rotating-body intercept-time solver.
	var terrain: RefCounted = Surface.home()
	var time := float(state.get("time",0.0))
	for index in range(1,points.size()):
		var hit: Dictionary = terrain.segment_hit(points[index-1],points[index],time,time)
		if hit.is_empty(): continue
		points[index] = hit.position
		points.resize(index+1)
		impact_point = points[index]*0.001
		prediction_kind = "Impact"
		break
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
	var elements := Physics.orbital_elements(radial,velocity)
	var apo: float = elements.apoapsis
	extent = maxf(100.0,radial.length()*0.001*1.3)
	if is_finite(apo): extent = maxf(extent,minf((apo+Physics.PLANET_RADIUS)*0.001,10000.0))
	marker.position = radial*0.001
	marker.scale = Vector3.ONE*maxf(1.0,extent*zoom/100.0)
	labels = [{"position":marker.position,"text":"CRAFT","color":CRAFT_COLOR}]
	if impact_point.is_finite():
		labels.append({"position":impact_point,"text":"IMPACT","color":IMPACT_COLOR})
	var eccentricity: Vector3 = elements.eccentricity_vector
	if eccentricity.length() > 0.00001:
		var peri: float = elements.periapsis
		if peri >= 0.0:
			labels.append({"position":eccentricity.normalized()*(peri+Physics.PLANET_RADIUS)*0.001,"text":"Pe %.1f km" % (peri*0.001),"color":FUTURE_COLOR})
		if is_finite(apo) and apo >= 0.0 and not (prediction_kind == "Impact" and radial.dot(velocity) <= 0.0):
			labels.append({"position":-eccentricity.normalized()*(apo+Physics.PLANET_RADIUS)*0.001,"text":"Ap %.1f km" % (apo*0.001),"color":FUTURE_COLOR})

func _update_camera() -> void:
	var distance := camera_extent*3.0*zoom
	var target := _camera_target()
	camera.position = target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.look_at(target,Vector3.UP)
	var material: ShaderMaterial = globe.material_override
	material.set_shader_parameter("camera_planet_km",camera.position)
	material.set_shader_parameter("sun_direction",source_world._sun_direction)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		yaw -= event.relative.x*0.005
		pitch = clampf(pitch+event.relative.y*0.005,-1.45,1.45)
		accept_event()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not system_mode and _craft_icon_hit(event.position):
			local_focus_craft = true
			reset_framing = true
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and system_mode and event.position.x < 220.0 and event.position.y >= 90.0 and event.position.y < 140.0 + planet_definitions.size() * 30.0:
			focus_index = clampi(int((event.position.y-90.0)/30.0)-1,-1,planet_definitions.size()-1)
			zoom = 1.0
			reset_framing = true
		if event.button_index == MOUSE_BUTTON_LEFT and event.position.y < 70.0:
			if event.position.x > size.x-310.0:
				system_mode = event.position.x < size.x-160.0
				system_root.visible = system_mode
				globe.visible = not system_mode
				trajectory.visible = not system_mode
				history_node.visible = not system_mode
				history_tail_node.visible = not system_mode
				marker.visible = not system_mode
				local_focus_craft = false
				zoom = 1.0
				focus_index = -1
				pitch = 0.6 if system_mode else 0.35
				path_dirty = true
				reset_framing = true
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom = maxf(0.3,zoom/1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom = minf(30.0,zoom*1.15)
		accept_event()

func _camera_target() -> Vector3:
	if system_mode and focus_index >= 0:
		return bodies[focus_index].position
	if not system_mode and local_focus_craft:
		return marker.position
	return Vector3.ZERO

func _craft_icon_hit(screen_position: Vector2) -> bool:
	if state.is_empty() or camera.is_position_behind(marker.position):
		return false
	if _point_occluded(marker.position): return false
	var icon_position := camera.unproject_position(marker.position)
	return screen_position.distance_to(icon_position) <= 18.0

func _point_occluded(point: Vector3) -> bool:
	var end := point.move_toward(camera.position,0.004)*1000.0
	var time := float(state.get("time",0.0))
	return not Surface.home().segment_hit(camera.position*1000.0,end,time,time).is_empty()

func _draw_overlay() -> void:
	if not is_instance_valid(camera): return
	var font := ThemeDB.fallback_font
	overlay.draw_string(font,Vector2(20,28),"SOLAR SYSTEM" if system_mode else "VERDANT / LOCAL ORBIT",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("eef2e9"))
	overlay.draw_string(font,Vector2(20,50),"Mean orbital distances • illustrative phases • bodies enlarged" if system_mode else "Predicted coast • excludes thrust, drag and future terrain rotation",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("91a8aa"))
	for index in range(2):
		var rect := Rect2(size.x-310.0+index*150.0,12,140,36)
		overlay.draw_style_box(get_theme_stylebox("normal","Button"),rect)
		overlay.draw_string(font,rect.position+Vector2(12,24),"Solar System" if index == 0 else "Local orbit",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("7ce5c0"))
	overlay.draw_string(font,Vector2(20,size.y-20),"RMB drag: orbit   •   Scroll: zoom   •   M: close",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("91a8aa"))
	if not system_mode:
		var legend := [["Past flight",PAST_COLOR],["Orbit",FUTURE_COLOR],["Impact",IMPACT_COLOR],["Escape",ESCAPE_COLOR]]
		for index in range(legend.size()):
			var x := 20.0+float(index)*132.0
			overlay.draw_line(Vector2(x,82),Vector2(x+22,82),legend[index][1],2,true)
			overlay.draw_string(font,Vector2(x+30,87),legend[index][0],HORIZONTAL_ALIGNMENT_LEFT,-1,13,legend[index][1])
		var status := prediction_kind.to_upper()+"  /  PREDICTED COAST"
		overlay.draw_circle(Vector2(25,115),3,_prediction_color())
		overlay.draw_string(font,Vector2(38,120),status,HORIZONTAL_ALIGNMENT_LEFT,-1,13,_prediction_color())
	if system_mode:
		overlay.draw_string(font,Vector2(20,110),"Focus: Sun / entire system",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("ffd487"))
		for index in range(planet_definitions.size()):
			var definition := planet_definitions[index]
			overlay.draw_string(font,Vector2(20,140+index*30),str(definition.planet_name)+"  %.2f AU" % float(definition.orbit_distance_au),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(definition.map_color))
	var occupied: Array[Rect2] = []
	for label in labels:
		var point: Vector3 = label.position
		if camera.is_position_behind(point): continue
		# Hide markers behind the globe, matching depth-tested trajectory lines.
		if not system_mode and _point_occluded(point): continue
		var screen := camera.unproject_position(point)
		if not Rect2(Vector2(225,75),size-Vector2(245,115)).has_point(screen): continue
		var text_position := screen+Vector2(10,-8)
		var bounds := Rect2(text_position-Vector2(0,14),Vector2(font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x,18))
		for attempt in range(12):
			var overlaps := false
			for previous in occupied:
				if bounds.intersects(previous): overlaps = true
			if not overlaps: break
			bounds.position.y += 20
			text_position.y += 20
		occupied.append(bounds)
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
	if camera.is_position_behind(lead):
		return Vector2.UP
	var projected := camera.unproject_position(lead)
	var direction := projected-screen
	return direction.normalized() if direction.length() > 0.001 else Vector2.UP

func _screen_direction_from_path(point: Vector3, screen: Vector2, vertices: PackedVector3Array) -> Vector2:
	for index in range(1,vertices.size()):
		var candidate := vertices[index]
		if candidate.distance_squared_to(point) < 0.0001:
			continue
		if camera.is_position_behind(candidate):
			continue
		var direction := camera.unproject_position(candidate)-screen
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
