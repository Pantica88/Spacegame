extends "res://scripts/world_view.gd"
## Rocket-free visual inspection using the production world renderer.
var hover_position := Vector3(0, 35, 100)
var hover_yaw := 0.0
var hover_pitch := -0.2
var hover_speed := 50.0
var hover_time := 0.0
var hover_hud: Label
# N cycles the mirrored clouds' density (ocean.gdshader) for tuning.
const CLOUD_DENSITIES: Array[float] = [1.0, 1.5, 2.0, 3.0, 4.0]
# TEMPORARY A/B: J cycles the mirrored clouds' sun shadow (ocean.gdshader).
const CLOUD_SHADINGS: Array[String] = ["current", "sky column", "sky tap", "full deck"]
var cloud_shading := 3
# O cycles the ocean patch's colours for tuning: albedo, albedo2, color_deep, color_shallow.
const OCEAN_PRESETS := [
	["tutorial", Color(0.0, 0.32, 0.43), Color(0.0, 0.47, 0.76), Color(0.11, 0.29, 0.33), Color(0.0, 0.47, 0.76)],
	["navy A", Color(0.0, 0.10, 0.20), Color(0.0, 0.16, 0.32), Color(0.02, 0.06, 0.12), Color(0.0, 0.16, 0.32)],
	["navy B", Color(0.0, 0.08, 0.17), Color(0.0, 0.14, 0.30), Color(0.01, 0.05, 0.10), Color(0.0, 0.14, 0.30)],
	["navy C", Color(0.0, 0.06, 0.14), Color(0.0, 0.12, 0.26), Color(0.01, 0.04, 0.09), Color(0.0, 0.12, 0.26)],
	["deep D", Color(0.0, 0.04, 0.10), Color(0.0, 0.08, 0.18), Color(0.005, 0.025, 0.06), Color(0.0, 0.08, 0.18)],
]
var ocean_preset := 4  # deep D, the default in ocean_patch.gd


func _ready() -> void:
	super._ready()
	set_mode("flight")
	_rocket.hide()
	camera.fov = 70.0
	var layer := CanvasLayer.new()
	add_child(layer)
	hover_hud = Label.new()
	hover_hud.position = Vector2(20, 20)
	hover_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hover_hud.add_theme_constant_override("shadow_offset_x", 2)
	hover_hud.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(hover_hud)
	var cost_overlay := preload("res://scripts/render_cost_overlay.gd").new()
	cost_overlay.world = self
	add_child(cost_overlay)
	_update_camera()


func _process(delta: float) -> void:
	var movement := Vector3.ZERO
	if DisplayServer.window_is_focused():
		var forward := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
		var right := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		var up := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
		var local_view: Basis = (PlanetSurface.home().rotation_at(hover_time) * PlanetSurface.LAUNCH_BASIS).inverse() * camera.basis
		movement = -local_view.z * forward + local_view.x * right + Vector3.UP * up
	var boost := 10.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	var precise := 0.1 if Input.is_physical_key_pressed(KEY_CTRL) else 1.0
	hover_position += movement.limit_length() * hover_speed * boost * precise * delta
	_update_camera()
	hover_hud.text = "VISUAL HOVER  |  %.0f FPS  |  %.0f m/s  |  altitude %.0f m\nWASD move · Q/E down/up · Hold right mouse to look\nWheel time back/forward · −/= move speed · Shift fast · Ctrl slow\nTime %+.0f s · T reset time · R reset view · H hide HUD · C copy view · K cloud reflections %s · L sky reflection %s · N cloud density %.1f · J cloud shading %s · O ocean colour %s · Esc quit\n%s" % [Engine.get_frames_per_second(), hover_speed * boost * precise, _last_altitude, hover_time, "on" if _reflection_on("cloud_reflection_strength") else "off", "on" if _reflection_on("sky_reflection_strength") else "off", _cloud_density(), CLOUD_SHADINGS[cloud_shading], OCEAN_PRESETS[ocean_preset][0], _view_state()]
	hover_hud.text += "\n" + _cloud_debug()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scrub_time(1.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scrub_time(-1.0)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		hover_yaw -= event.relative.x * 0.003
		hover_pitch = clampf(hover_pitch - event.relative.y * 0.003, -1.55, 1.55)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_R:
				hover_position = Vector3(0, 35, 100)
				hover_yaw = 0.0
				hover_pitch = -0.2
				hover_speed = 50.0
			KEY_MINUS, KEY_KP_SUBTRACT:
				hover_speed = maxf(hover_speed / 1.5, 0.5)
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				hover_speed = minf(hover_speed * 1.5, 100000.0)
			KEY_T:
				hover_time = 0.0
			KEY_H:
				hover_hud.visible = not hover_hud.visible
			KEY_C:
				DisplayServer.clipboard_set(_view_state())
			KEY_K:
				_toggle_reflection("cloud_reflection_strength")
			KEY_L:
				_toggle_reflection("sky_reflection_strength")
			KEY_N:
				var next := CLOUD_DENSITIES.find(_cloud_density()) + 1
				_ocean.material().set_shader_parameter("cloud_reflection_density", CLOUD_DENSITIES[next % CLOUD_DENSITIES.size()])
			KEY_J:
				cloud_shading = (cloud_shading + 1) % CLOUD_SHADINGS.size()
				_ocean.material().set_shader_parameter("cloud_reflection_shading", cloud_shading)
			KEY_O:
				ocean_preset = (ocean_preset + 1) % OCEAN_PRESETS.size()
				var preset: Array = OCEAN_PRESETS[ocean_preset]
				for i in 4:
					_ocean.material().set_shader_parameter(["albedo", "albedo2", "color_deep", "color_shallow"][i], preset[i + 1])


func _reflection_on(parameter: String) -> bool:
	# Unset until first toggled; the shader default is on.
	var strength: Variant = _ocean.material().get_shader_parameter(parameter)
	return strength == null or float(strength) > 0.0


# TEMP: cloud renderer state, for the limb-staircase investigation.
func _cloud_debug() -> String:
	var view := get_viewport()
	var resolve: ShaderMaterial = _clouds._resolve_materials[_clouds._temporal_frame % 2] if not _clouds._resolve_materials.is_empty() else null
	return "Clouds: view %s x%.2f  scale %.2f  lowres %s  offscreen %s  temporal %s  history %s  blend %.2f" % [
		view.get("size"), view.scaling_3d_scale, _clouds.effective_scale(), _clouds._lowres.size,
		_clouds.integrates_offscreen(), _clouds.temporal,
		resolve.get_shader_parameter("history_valid") if resolve else "-",
		resolve.get_shader_parameter("history_blend") if resolve else 0.0]

func _cloud_density() -> float:
	# Unset until first cycled; matches the shader default.
	var density: Variant = _ocean.material().get_shader_parameter("cloud_reflection_density")
	return 4.0 if density == null else float(density)


func _toggle_reflection(parameter: String) -> void:
	_ocean.material().set_shader_parameter(parameter, 0.0 if _reflection_on(parameter) else 1.0)


# Exact view, so a screenshot can be reproduced.
func _view_state() -> String:
	# Clouds drift on their own clock, so the view also needs weather time.
	return "View: time %.1f  pos %.1f, %.1f, %.1f  yaw %.3f  pitch %.3f  weather %.1f" % [hover_time, hover_position.x, hover_position.y, hover_position.z, hover_yaw, hover_pitch, _clouds.weather_time]


func _scrub_time(direction: float) -> void:
	# One wheel notch is 1/96 of a planetary day, in either direction.
	hover_time += direction * float(PlanetSurface.home().definition.rotation_seconds) / 96.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _update_camera() -> void:
	if not is_instance_valid(camera):
		return
	# Keep the camera at the floating origin, including on long trips to space.
	var spin: Basis = PlanetSurface.home().rotation_at(hover_time)
	var frame := spin * PlanetSurface.LAUNCH_BASIS
	var radial := spin * PlanetSurface.LAUNCH_RADIAL + frame * hover_position
	set_planet_time(hover_time)
	_flight_position = radial - Vector3(0, PLANET_RADIUS, 0)
	_planet.position = -radial
	_landscape.position = -(frame * hover_position)
	_sun_physical_position = SolarBody.POSITION - _flight_position
	_last_altitude = radial.length() - PLANET_RADIUS
	_surface_up = radial.normalized()
	_update_planet_lod(_last_altitude)
	camera.position = Vector3.ZERO
	camera.basis = frame * Basis(Vector3.UP, hover_yaw) * Basis(Vector3.RIGHT, hover_pitch)
	# Keep the whole home world inside the projection at escape distances.
	var planet_margin := PLANET_RADIUS + float(PlanetSurface.home().definition.relief) * 1.5 + 1000.0
	camera.far = maxf(220000.0, radial.length() + planet_margin)
	if is_instance_valid(_ocean):
		# The hidden rocket sits at the origin, so the ocean patch tracks the camera.
		_ocean.follow(_planet, camera.global_position, camera.global_position, PlanetSurface.home())
		_planet.material_override.set_shader_parameter("water_cutout_radius", _ocean.cutout_radius)
		_planet.material_override.set_shader_parameter("seabed_fade", _ocean.fade)
	# Near/far (including moons) are derived in _update_atmosphere().
	_update_atmosphere()
