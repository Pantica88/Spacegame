extends Node3D
## Local procedural scenery and authored vehicle assets. Flight is rebased around the vehicle.
const ParachuteModule = preload("res://scenes/parachute_1.tscn")
const ParachuteHousing = preload("res://assets/models/parachute_1/parachute_1.glb")
const ParachuteAsset = preload("res://assets/models/parachute_1/parachute_1_deployed.glb")
const BoosterAsset = preload("res://assets/models/booster_1/booster_1.glb")
const SeparatorAsset = preload("res://assets/models/separator_1/separator_1.glb")
const RadialCraft = preload("res://scripts/craft_model.gd")
const ExplorerCapsule = preload("res://assets/models/explorer_1/explorer_1.glb")
const KestrelEngine = preload("res://assets/models/engine_1/engine_1.glb")
const SparrowEngine = preload("res://assets/models/sparrow_1/sparrow_1.glb")
const CanisterTank = preload("res://assets/models/canister_1/canister_1.glb")
const ReactionWheel = preload("res://assets/models/gyro_1/gyro_1.glb")
const AtlasDecoupler = preload("res://assets/models/atlas_1/atlas_1.glb")
# Shared, material-batched copies retain full detail nearby and have baked LODs.
# Keep authored node hierarchies for small craft and the standalone asset tools.
const BATCHED_MODELS := {
	"canister_1": preload("res://assets/models/flight/canister_1.res"),
	"engine_1": preload("res://assets/models/flight/engine_1.res"),
	"sparrow_1": preload("res://assets/models/flight/sparrow_1.res"),
	"separator_1": preload("res://assets/models/flight/separator_1.res"),
	"gyro_1": preload("res://assets/models/flight/gyro_1.res"),
	"atlas_1": preload("res://assets/models/flight/atlas_1.res"),
	"booster_1": preload("res://assets/models/flight/booster_1.res"),
	"explorer_1": preload("res://assets/models/flight/explorer_1.res"),
}
const BATCHED_MODEL_PART_THRESHOLD := 32

func _vehicle_model(asset: String, source: PackedScene) -> Node3D:
	if _design.get("assembly", {}).get("parts", []).size() < BATCHED_MODEL_PART_THRESHOLD:
		return source.instantiate() as Node3D
	var shared: ArrayMesh = BATCHED_MODELS[asset]
	var model := Node3D.new()
	model.name = shared.get_meta("model_name")
	var visual := MeshInstance3D.new()
	visual.name = "BatchedVisual"
	visual.mesh = shared
	# Shadow passes ignore materials, so one merged surface casts the identical
	# shadow with a fraction of the draw calls (four cascades per frame).
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.set_meta("shadow_proxied", true)
	model.add_child(visual)
	var shadow := MeshInstance3D.new()
	shadow.name = "BatchedShadow"
	shadow.mesh = shared.get_meta("preview_mesh")
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow.set_meta("shadow_proxy", true)
	model.add_child(shadow)
	return model

const SolarBody = preload("res://scripts/solar_body.gd")
var _sun_body: MeshInstance3D
var _sun_physical_position := SolarBody.POSITION
var _flight_position := Vector3.ZERO
var _previous_flight_frame: Dictionary = {}
var _current_flight_frame: Dictionary = {}
var _inside_flight_tick := false

const PlanetSurface = preload("res://scripts/planet_surface.gd")
const AtmosphereQuality = preload("res://scripts/atmosphere_quality.gd")
const SKY_SHADER = preload("res://assets/shaders/sky.gdshader")
static var _half_res_sky_shader: Shader
## Atmospheric rendering preset (AtmosphereQuality.PRESETS); visual only.
var atmosphere_quality: String = AtmosphereQuality.DEFAULT

var camera: Camera3D
var _rocket: Node3D
var _landscape: Node3D
var _flight_location: Node3D
var _hangar: Node3D
var _hangar_floor: Node3D
var _hangar_walls: Array[Node3D] = []
var _planet: MeshInstance3D
var _clouds: MeshInstance3D
var _planet_lod := 0
var _moons: Array[MeshInstance3D] = []
var _moon_parents: Array[int] = []
var _parachute_module: Node3D
var _chute: Node3D
var _booster_nodes: Array[Node3D] = []
var _detached_nodes: Array[Node3D] = []
var _impact_effects: Array[Dictionary] = []
const IMPACT_POOL_SIZE := 16
var _impact_pool: Array[MeshInstance3D] = []
var _impact_mesh: SphereMesh
var _prewarm_chute_transform := Transform3D.IDENTITY
var debris_markers: Array[Dictionary] = []
var _engine_shell: Node3D
var _engine_shells: Dictionary = {}
var _engine_flames: Dictionary = {}
var _lower_parts: Array[Node3D] = []
var _main_flames: Array[Node3D] = []
var _booster_flames: Array[Node3D] = []
var _sun: DirectionalLight3D
var _ocean: OceanPatch
var _fill: DirectionalLight3D
var _sun_direction := Vector3(-0.45, 0.42, 0.72).normalized()
var _sky_material: ShaderMaterial
var _environment: Environment
var _design: Dictionary = {"tanks": 2, "engine": "kestrel", "boosters": false, "fins": true}
var _mode := "workshop"
var _height := 11.0
var _workshop_bounds := AABB(Vector3(-1.5,0,-1.5),Vector3(3,11,3))
var _workshop_has_side_stacks := false
var _yaw := 0.62
var _pitch := 0.22
var _distance := 28.0
var _clock := 0.0
var rendering_suspended := false
var _last_altitude := 0.0
var _camera_focus := Vector3.ZERO
var _workshop_pan := Vector3.ZERO
var _workshop_fit := false
var _surface_up := Vector3.UP
# Smoothed visual heel from the drawn waves while floating (world space).
var _swell_tilt := Quaternion.IDENTITY
# Floating vessel origin's exact height above the sea; NAN when not floating.
var _water_height := NAN
# Water coverage under the vessel (shallows damp the swell); open sea by default.
var _swell_coverage := 1.0
var _capsule: Node3D
var _capsule_only := false
var _paint: StandardMaterial3D
var _teal: StandardMaterial3D
var _orange: StandardMaterial3D
var _metal: StandardMaterial3D
var _dark: StandardMaterial3D
var _glass: StandardMaterial3D
var _ground: StandardMaterial3D
static var PLANET_RADIUS: float:
	get: return PlanetSurface.RADIUS
const SOLAR_DAY_SECONDS := 480.0
var _planet_rotation_time := 0.0
const INITIAL_SUN_DIRECTION := Vector3(-0.45, 0.42, 0.72)
const SUN_ENERGY := 1.55
const WORKSHOP_AMBIENT := Color("8ac2cb")
## Share of the cloud shader's radiance that reaches the vessel as ambient.
const CLOUD_GLOW_GAIN := 0.6
## Seconds (real time) for vessel cloud lighting to settle after a change.
const CLOUD_LIGHT_SMOOTHING := 0.2
var _cloud_light := 1.0
var _cloud_glow := Color(0, 0, 0, 0)
var _cloud_light_clock := 0
var _cloud_light_frame := -1
var _cloud_sun_target := 1.0
var _cloud_glow_target := Color(0, 0, 0, 0)
const WORKSHOP_CAMERA_FOCUS_Y := 4.8
const CAP_TRACKING_SEPARATION_DISTANCE := 12.0
var _solar_time := 0.0
var _capsule_center_local := 1.4
var _capsule_visual_base_local := 0.2


func _ready() -> void:
	_make_materials()
	_make_environment()
	_flight_location = Node3D.new()
	_flight_location.name = "LaunchSiteAndSpace"
	add_child(_flight_location)
	_make_sun_body()
	_make_planet()
	_reload_moons()
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
	set_mode(_mode)
	if _mode == "workshop" and (int(_design.get("tanks", 0)) > 4 or _workshop_has_side_stacks):
		fit_workshop_camera()


func _make_sun_body() -> void:
	_sun_body = MeshInstance3D.new()
	_sun_body.name = "Sun"
	var sphere := SphereMesh.new()
	sphere.radius = SolarBody.RADIUS
	sphere.height = SolarBody.RADIUS * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	_sun_body.mesh = sphere
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/sun.gdshader")
	_sun_body.material_override = material
	_sun_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flight_location.add_child(_sun_body)
	_sun_body.position = SolarBody.POSITION
	_sun_physical_position = SolarBody.POSITION
	_sun_body.hide()


func set_design(design: Dictionary) -> void:
	for piece in _detached_nodes:
		if is_instance_valid(piece): piece.queue_free()
	_detached_nodes.clear()
	debris_markers.clear()
	for effect in _impact_effects: _release_impact(effect.node)
	_impact_effects.clear()
	var previous_tanks := int(_design.get("tanks", 0))
	var previous_bounds := _workshop_bounds
	_design = design.duplicate()
	if is_instance_valid(_rocket):
		_build_rocket()
		if _mode == "workshop" and (int(_design.get("tanks", 0)) > maxi(4, previous_tanks) or (_workshop_has_side_stacks and _workshop_bounds != previous_bounds)):
			fit_workshop_camera()
		_update_camera()

func reload_planet() -> void:
	if not is_instance_valid(_planet):
		return
	_planet_lod = -1
	var material: ShaderMaterial = _planet.material_override
	PlanetSurface.home().configure_surface_material(material)
	if is_instance_valid(_ocean): _ocean.configure(PlanetSurface.home())
	_update_planet_lod(_last_altitude)
	_reload_moons()
	_prepare_atmosphere_tables()
	_update_atmosphere()

func set_mode(mode: String) -> void:
	_previous_flight_frame.clear()
	_current_flight_frame.clear()
	var previous_mode := _mode
	_mode = mode
	_flight_position = Vector3.ZERO
	if is_instance_valid(_flight_location):
		_flight_location.visible = mode != "workshop"
	# The workshop is an indoor location, separate from the outdoor launch site.
	# Its cutaway views also retain an indoor backdrop.
	_environment.background_mode = Environment.BG_COLOR if mode == "workshop" else Environment.BG_SKY
	_environment.background_color = Color("101e25")
	if is_instance_valid(_sun_body):
		_sun_body.visible = mode != "workshop"
		_sun_body.position = SolarBody.POSITION
		_sun_physical_position = SolarBody.POSITION
	if not is_instance_valid(_rocket):
		return
	_planet_rotation_time = 0.0
	_planet.basis = Basis.IDENTITY
	_landscape.basis = Basis.IDENTITY
	if mode == "workshop":
		_clear_aero_glow()
		_solar_time = 0.0
		_sun_direction = INITIAL_SUN_DIRECTION.normalized()
		_capsule_only = false
		_rocket.transform = Transform3D.IDENTITY
		_landscape.position = Vector3.ZERO
		_landscape.visible = false
		_hangar.visible = true
		_planet.visible = false
		_planet.position = Vector3(0.0, -PLANET_RADIUS, 0.0)
		_environment.ambient_light_energy = 0.42
		if previous_mode != mode:
			_workshop_pan = Vector3.ZERO
			_build_rocket()
			if int(_design.get("tanks", 0)) > 4 or _workshop_has_side_stacks: fit_workshop_camera()
		_rocket.position.y = _workshop_root_height() - _capsule_center_local
		_last_altitude = 0.0
		_surface_up = Vector3.UP
	else:
		_solar_time = 0.0
		_sun_direction = INITIAL_SUN_DIRECTION.normalized()
		_hangar.visible = false
		_landscape.visible = true
		_planet.visible = true
		_distance = maxf(_distance, _height * 2.5)
		_prepare_aero_wake()
	_update_camera()


func sync_flight(state: Dictionary, delta: float, visual_delta: float = -1.0) -> void:
	# Explicit syncs (launch, staging, map return) are discontinuities. Only
	# consecutive simulation ticks may share interpolation history.
	if not _inside_flight_tick:
		_previous_flight_frame.clear()
		_current_flight_frame.clear()
	if not is_instance_valid(_rocket):
		return
	_clock += delta
	set_planet_time(float(state.get("simulation_time", state.get("time", 0.0))))
	# Keep the craft attitude current even when the map suspends flight drawing.
	_rocket.visible = not bool(state.get("destroyed", false))
	_rocket.basis = Basis(state.get("orientation", Basis.IDENTITY)).orthonormalized()
	if rendering_suspended: return
	var flight_position: Vector3 = state.get("position", Vector3.ZERO)
	_flight_position = flight_position
	_sun_physical_position = SolarBody.POSITION - flight_position
	var orientation: Basis = state.get("orientation", Basis.IDENTITY)
	_rocket.basis = orientation.orthonormalized()
	_rocket.position = Vector3.ZERO
	_landscape.position = Vector3(0.0, -PLANET_RADIUS, 0.0) - flight_position + _planet.basis * PlanetSurface.LAUNCH_RADIAL
	_planet.position = Vector3(0.0, -PLANET_RADIUS, 0.0) - flight_position
	# Keep the entire home world inside the projection at escape distances.
	# Moon-driven far-plane expansion can otherwise leave the planet itself
	# straddling the far plane as the moon moves, producing rings and fragments.
	var planet_margin := PLANET_RADIUS + float(PlanetSurface.home().definition.relief) * 1.5 + 1000.0
	camera.far = maxf(camera.far, camera.position.distance_to(_planet.position) + planet_margin)
	_last_altitude = float(state.get("altitude", 0.0))
	_update_planet_lod(_last_altitude)
	_surface_up = (flight_position+Vector3(0,PLANET_RADIUS,0)).normalized()
	# Ground and ocean share one continuous planet mesh. Only visual density
	# changes with altitude; contact continues to use the full terrain mesh.
	_sync_detached(state, flight_position)
	var attached := bool(state.get("boosters_attached", true))
	var capsule_only := bool(state.get("capsule_only", false))
	_capsule_only = capsule_only
	if capsule_only:
		# The capsule's contact point replaces the bottom of the full stack.
		_rocket.position = -_rocket.basis.y * (_height - 2.8)
	var floating := bool(state.get("landing_water", false)) and str(state.get("status", "")) in ["landed", "crashed"]
	# Ease into the drawn waves over the last metres of descent; switching on
	# at touchdown dropped (or lifted) the hull by the local wave height.
	var approach := 0.0
	if not floating and str(state.get("status", "")) == "flying":
		approach = 1.0 - smoothstep(0.0, SWELL_APPROACH_HEIGHT, float(state.get("altitude", INF)))
	var coverage := 0.0
	if is_instance_valid(_ocean) and (floating or approach > 0.0):
		var home: RefCounted = PlanetSurface.home()
		var body_up: Vector3 = _planet.global_basis.orthonormalized().inverse() * _surface_up
		coverage = home.color_at(body_up, home.elevation(body_up)).a
		_swell_coverage = coverage
	if floating or (approach > 0.0 and coverage > 0.5):
		_ride_swell(state, delta, 1.0 if floating else approach, floating, coverage)
	else:
		_swell_tilt = Quaternion.IDENTITY
		_water_height = NAN
	for booster in _booster_nodes:
		if not is_instance_valid(booster): continue
		if booster.get_parent() == _rocket:
			booster.visible = attached and not capsule_only
	for piece in _lower_parts:
		if not is_instance_valid(piece): continue
		if piece.get_parent() == _rocket:
			piece.visible = not capsule_only
	for id in _engine_shells.keys():
		if not is_instance_valid(_engine_shells[id]):
			_engine_shells.erase(id)
			continue
		var shell: Node3D = _engine_shells[id]
		if _rocket.is_ancestor_of(shell):
			shell.visible = not id in state.get("released_decouplers", []) and not (id == "engine_decoupler" and state.get("engine_shell_jettisoned",false))
	if is_instance_valid(_parachute_module):
		var local_frame := _parachute_module.global_basis.orthonormalized().inverse()
		var gravity := -_surface_up * float(state.get("gravity", 9.81))
		var acceleration: Vector3 = state.get("acceleration_vector", Vector3.ZERO)
		var air_motion: Vector3 = -Vector3(state.get("air_velocity", Vector3(state.get("velocity", Vector3.ZERO))-PlanetSurface.home().surface_velocity(flight_position+Vector3(0,PLANET_RADIUS,0))))
		var resting: bool = state.get("settled", false) and not state.get("chute_cut", false)
		var terrain_normal: Vector3 = state.get("terrain_normal",_surface_up)
		var ground_normal := local_frame * terrain_normal
		var ground_offset := -_parachute_module.global_position.dot(terrain_normal) - float(state.get("terrain_plane_distance",state.get("terrain_clearance",0.0)))
		# Keep the local environment stable once the hull rests on the terrain.
		# Reprojecting planet-scale coordinates every frame introduces centimetre
		# jitter that continually wakes the cloth and rebuilds its collision mesh.
		if not resting or not _parachute_module.resting:
			_parachute_module.set_air_forces(local_frame * (gravity if resting else gravity - acceleration), Vector3.ZERO if resting else local_frame * air_motion, float(state.get("air_density", 1.225)))
			_parachute_module.set_ground(ground_normal, ground_offset)
		_parachute_module.resting = resting
		if str(state.get("status", "flying")) in ["landed", "crashed"] and bool(state.get("chute_deployed", false)) and not bool(state.get("chute_cut", false)):
			_refresh_chute_relief(state)
		else:
			_chute_relief_anchor = Vector3.INF
		if bool(state.get("chute_cut", false)):
			_parachute_module.cut_away(_landscape, gravity)
		_advance_parachute(state, delta, visual_delta)
	else:
		_chute.visible = bool(state.get("chute_deployed", false)) and str(state.get("status", "flying")) not in ["landed", "crashed"]
	if _chute.visible and not is_instance_valid(_parachute_module):
		_chute.rotation.z = sin(_clock * 1.7) * 0.03
	_update_aero_glow(state, delta)
	var throttle := float(state.get("throttle", 0.0))
	var engine_on := bool(state.get("engine_on", false)) and not capsule_only
	for id in _engine_flames:
		if id in state.get("removed_parts", []): continue
		var active: bool = state.get("active_engines", []).is_empty() or id in state.active_engines
		_animate_flames(_engine_flames[id], throttle if active and engine_on and float(state.get("engine_fuel",{}).get(id,state.get("fuel",0.0))) > 0.0 else 0.0)
	_animate_flames(_booster_flames, 1.0 if bool(state.get("boosters_on", engine_on)) and attached and float(state.get("booster_fuel", 0.0)) > 0.0 else 0.0)
	if is_instance_valid(_parachute_module) and _parachute_module.cap_released:
		var cap: Node3D = _parachute_module.cap_pivot
		var center := cap.to_global(Vector3(0, 0.17, 0))
		var separation := center.distance_to(_rocket.to_global(Vector3(0, _capsule_center_local, 0)))
		if separation > CAP_TRACKING_SEPARATION_DISTANCE:
			debris_markers.append({"position": center, "distance": separation, "radius": 0.34,
				"basis": cap.global_basis, "half_extents": Vector3(0.25, 0.17, 0.25)})
	_update_camera()


# Cosmetic cloth work per rendered frame. Slow frames make Godot run extra
# physics ticks; stepping the cloth fully in each one compounded into a stall.
const CHUTE_FRAME_BUDGET_MS := 6.0
var _chute_frame := -1
var _chute_frame_cost := 0.0
var _chute_pending_visual := 0.0

## Advances the parachute within a per-frame time budget during flight ticks.
## Past the budget, deployment still follows simulation time, while cloth and
## cord motion defer to the next rendered frame.
func _advance_parachute(state: Dictionary, delta: float, visual_delta: float) -> void:
	var landed := str(state.get("status", "flying")) in ["landed", "crashed"]
	var deployed := bool(state.get("chute_deployed", false))
	if not _inside_flight_tick:
		_parachute_module.advance(deployed, delta, landed, visual_delta)
		return
	var frame := Engine.get_process_frames()
	if frame != _chute_frame:
		_chute_frame = frame
		_chute_frame_cost = 0.0
	_chute_pending_visual += delta if visual_delta < 0.0 else visual_delta
	if _chute_frame_cost >= CHUTE_FRAME_BUDGET_MS:
		_parachute_module.advance(deployed, delta, landed, 0.0)
		return
	var start := Time.get_ticks_usec()
	# The cloth accumulator clamps catch-up itself; bound it to two steps.
	_parachute_module.advance(deployed, delta, landed, minf(_chute_pending_visual, 1.0 / 30.0))
	_chute_frame_cost += (Time.get_ticks_usec() - start) / 1000.0
	_chute_pending_visual = 0.0


const CHUTE_RELIEF_SIZE := 17
const CHUTE_RELIEF_SPACING := 1.0
var _chute_relief_anchor := Vector3.INF
var _chute_relief_normal := Vector3.ZERO

## Samples terrain around a landed capsule so its fabric drapes over the real
## relief. Resampled only when the hull moves over the ground, so a resting
## canopy keeps sleeping.
func _refresh_chute_relief(state: Dictionary) -> void:
	var module = _parachute_module
	var anchor: Vector3 = _landscape.to_local(module.global_position)
	var normal: Vector3 = module.surface_normal
	if anchor.distance_to(_chute_relief_anchor) < 0.25 and normal.dot(_chute_relief_normal) > 0.9995: return
	_chute_relief_anchor = anchor
	_chute_relief_normal = normal
	var terrain: RefCounted = PlanetSurface.home()
	var time := float(state.get("simulation_time", state.get("time", 0.0)))
	var tangent := normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD).normalized()
	var axes := Basis(tangent, normal, tangent.cross(normal))
	var to_world: Transform3D = module.global_transform
	var to_module := to_world.affine_inverse().basis
	var half := (CHUTE_RELIEF_SIZE - 1) * 0.5
	var heights := PackedFloat32Array()
	heights.resize(CHUTE_RELIEF_SIZE * CHUTE_RELIEF_SIZE)
	for j in range(CHUTE_RELIEF_SIZE):
		for i in range(CHUTE_RELIEF_SIZE):
			var local: Vector3 = normal * float(module.surface_offset) + (axes.x * (i - half) + axes.z * (j - half)) * CHUTE_RELIEF_SPACING
			var world: Vector3 = to_world * local
			# Planet-centred coordinates; radial distances keep double precision.
			var x := float(world.x) + float(_flight_position.x)
			var y := float(world.y) + float(_flight_position.y) + PLANET_RADIUS
			var z := float(world.z) + float(_flight_position.z)
			var radius := sqrt(x * x + y * y + z * z)
			var up := Vector3(x, y, z) / radius
			var contact: Dictionary = terrain.contact(up * radius, time)
			var rise := float(contact.radius) - radius
			heights[j * CHUTE_RELIEF_SIZE + i] = clampf(rise * (to_module * up).normalized().dot(normal), -4.0, 4.0)
	# The contact plane already touches the ground under the hull.
	var center := heights[int(half) * CHUTE_RELIEF_SIZE + int(half)]
	for index in range(heights.size()): heights[index] -= center
	module.set_relief(heights, CHUTE_RELIEF_SIZE, CHUTE_RELIEF_SPACING, axes)


const FLOAT_SINK := 0.25
const SWELL_APPROACH_HEIGHT := 6.0
# Camera height above the waves, plus a share of the near-plane distance: the
# near plane (metres deep for depth precision) must not cut into the water,
# or the seabed shows through the gap. A smaller near plane is not an option:
# it blanked whole frames at planet-scale far distances.
const CAMERA_WATER_CLEARANCE := 1.0
const CAMERA_NEAR_CLEARANCE := 0.5

## Physics floats on a calm mean sea; the drawn water heaves and slopes. Lift
## the hull with the surface under it and heel it with the local wave slope,
## pivoting at the waterline, so it stays in the water and rocks with it.
## weight: 0..1 share of the wave motion; floating: the hull is in the water
## (heel follows the waves only then).
func _ride_swell(state: Dictionary, delta: float, weight: float, floating: bool, coverage: float) -> void:
	var height := float(state.get("water_height", 0.0)) if floating else float(state.get("altitude", 0.0))
	_water_height = height if floating else NAN
	var up := _surface_up
	var axis := _rocket.basis.y
	var center := _rocket.position + axis * (_capsule_center_local if _capsule_only else _height * 0.5)
	# The world origin is the vessel origin, `height` above the sea.
	var pivot := center - up * (center.dot(up) + height)
	# A hull lying along the water spans more of a wave; sampling across its
	# length lets long hulls ignore ripples that rock a capsule.
	# Shorter spans follow ripples a ~2 m hull would bridge, heeling it 20-30 deg.
	var span := clampf((axis - up * axis.dot(up)).length() * (_height * 0.5 if not _capsule_only else 1.0), 3.0, 8.0)
	var east := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var north := up.cross(east)
	var origin := _rocket.get_parent_node_3d().global_transform if _rocket.get_parent_node_3d() else Transform3D.IDENTITY
	var h0: float = _ocean.surface_height(origin * pivot, coverage)
	var he: float = _ocean.surface_height(origin * (pivot + east * span), coverage)
	var hw: float = _ocean.surface_height(origin * (pivot - east * span), coverage)
	var hn: float = _ocean.surface_height(origin * (pivot + north * span), coverage)
	var hs: float = _ocean.surface_height(origin * (pivot - north * span), coverage)
	var slope := east * (he - hw) / (2.0 * span) + north * (hn - hs) / (2.0 * span)
	var target := Quaternion(up, (up - slope.limit_length(tan(deg_to_rad(12.0)))).normalized()) if floating else Quaternion.IDENTITY
	# Hull inertia lags the surface; ease toward the slope instead of snapping.
	_swell_tilt = _swell_tilt.slerp(target, 1.0 - exp(-clampf(delta, 0.0, 0.1) / 0.45)).normalized()
	# Heave from the water under the hull's own footprint, set a little deeper
	# than the calm-water draft: at the mean of a ripple trough the rim still
	# rose clear of the water and the hull looked to hover.
	var rim := span / 3.0
	var heave := h0
	for k in range(8):
		var angle := TAU * k / 8.0
		heave += _ocean.surface_height(origin * (pivot + (east * cos(angle) + north * sin(angle)) * rim), coverage)
	heave = (heave / 9.0 - FLOAT_SINK) * weight
	_rocket.basis = Basis(_swell_tilt) * _rocket.basis
	_rocket.position = pivot + _swell_tilt * (_rocket.position - pivot) + up * heave


## Height of a point (world view space) above sea level. The world origin is
## the vessel origin; floating vessels know theirs exactly.
func _sea_height_of(point: Vector3) -> float:
	return point.dot(_surface_up) + (_last_altitude if is_nan(_water_height) else _water_height)


## Orbiting low around a vessel near the sea took the camera under the drawn
## waves, and its near plane cut into them, showing the seabed beneath. Limit
## the orbit's pitch so the camera stays above the waves at its distance.
func _limit_pitch_above_water(pitch: float, surface_frame: Basis) -> float:
	if _mode != "flight" or not is_instance_valid(_ocean) or not _ocean.visible: return pitch
	var focus_height := _sea_height_of(_camera_focus)
	var clearance := CAMERA_WATER_CLEARANCE + camera.near * CAMERA_NEAR_CLEARANCE
	if focus_height - _distance > clearance + 6.0: return pitch
	var limited := pitch
	# The waves under the camera move with it; a second pass settles that.
	for i in range(2):
		var offset := surface_frame * Vector3(sin(_yaw) * cos(limited), sin(limited), cos(_yaw) * cos(limited))
		var water: float = _ocean.surface_height(to_global(_camera_focus + offset * _distance), _swell_coverage)
		var lowest_sine := clampf((water + clearance - focus_height) / _distance, -1.0, 1.0)
		if sin(limited) >= lowest_sine: break
		# Allowed pitches run from asin(s) over the top to PI - asin(s); move
		# to whichever edge is nearer the requested angle.
		var low := asin(lowest_sine)
		var high := PI - low
		limited = low if absf(wrapf(limited - low, -PI, PI)) <= absf(wrapf(limited - high, -PI, PI)) else high
	return limited


## Sea level under a floating vessel, from its exact height above the water
## rather than planet-scale coordinates. Null when not floating.
func _floating_sea_point() -> Variant:
	if is_nan(_water_height) or _mode != "flight": return null
	return global_transform * (-_surface_up * _water_height)


func begin_flight_tick() -> void:
	# Cloth, staging and debris must see the last simulation pose, never the
	# interpolated render pose left by the previous display frame.
	if not _current_flight_frame.is_empty():
		_apply_flight_frame(_current_flight_frame, _current_flight_frame, 1.0)
	_inside_flight_tick = true


func end_flight_tick(interpolate: bool = true) -> void:
	_inside_flight_tick = false
	if rendering_suspended or _mode != "flight":
		_previous_flight_frame.clear()
		_current_flight_frame.clear()
		return
	_previous_flight_frame = _current_flight_frame
	var poses := {}
	for node in [_planet, _landscape, _rocket] + _detached_nodes:
		if is_instance_valid(node): poses[node] = node.transform
	_current_flight_frame = {"poses": poses, "position": _flight_position,
		"altitude": _last_altitude, "time": _planet_rotation_time,
		"capsule_center": _capsule_center_local, "capsule_only": _capsule_only}
	if not interpolate or _previous_flight_frame.is_empty() \
		or _previous_flight_frame.capsule_center != _capsule_center_local \
		or _previous_flight_frame.capsule_only != _capsule_only:
		_previous_flight_frame = _current_flight_frame


func present_flight_frame(fraction: float, snap: bool = false) -> void:
	if _mode != "flight" or rendering_suspended or _current_flight_frame.is_empty(): return
	if snap: _previous_flight_frame = _current_flight_frame
	_apply_flight_frame(_previous_flight_frame, _current_flight_frame, clampf(fraction, 0.0, 1.0))
	# Camera input remains immediate. Recompute its framing and all atmospheric
	# uniforms from the same displayed pose, so the sky/cloud edge cannot lag.
	_update_camera()


func _apply_flight_frame(previous: Dictionary, current: Dictionary, fraction: float) -> void:
	for node in current.poses:
		if not is_instance_valid(node): continue
		var target: Transform3D = current.poses[node]
		var source: Transform3D = previous.poses.get(node, target)
		node.transform = target if fraction >= 1.0 else source.interpolate_with(target, fraction)
	_flight_position = current.position if fraction >= 1.0 else Vector3(previous.position).lerp(current.position, fraction)
	_last_altitude = current.altitude if fraction >= 1.0 else lerpf(previous.altitude, current.altitude, fraction)
	_planet_rotation_time = current.time if fraction >= 1.0 else lerpf(previous.time, current.time, fraction)
	_surface_up = (_flight_position + Vector3(0, PLANET_RADIUS, 0)).normalized()
	_sun_physical_position = SolarBody.POSITION - _flight_position


func orbit_camera(relative: Vector2) -> void:
	_yaw = wrapf(_yaw - relative.x * 0.006, -PI, PI)
	var next_pitch := _pitch + relative.y * 0.005
	_pitch = wrapf(next_pitch, -PI, PI)
	_update_camera()


func workshop_camera_view(view: String) -> void:
	if _mode != "workshop": return
	match view:
		"Front": _yaw = 0.0; _pitch = 0.0
		"Back": _yaw = PI; _pitch = 0.0
		"Left": _yaw = -PI / 2.0; _pitch = 0.0
		"Right": _yaw = PI / 2.0; _pitch = 0.0
		"Top": _yaw = 0.0; _pitch = PI / 2.0
		"Bottom": _yaw = 0.0; _pitch = -PI / 2.0
		"Reset":
			_yaw = 0.62
			_pitch = 0.22
			_workshop_pan = Vector3.ZERO
			_workshop_fit = false
			_distance = maxf(28.0, _workshop_bounds.size.length() * 2.3) if _workshop_has_side_stacks else (maxf(28.0, _height * 2.3) if int(_design.get("tanks", 0)) > 4 else 28.0)
	_update_camera()


func fit_workshop_camera() -> void:
	if _mode != "workshop": return
	_workshop_fit = true
	_workshop_pan = Vector3.ZERO
	_distance = maxf(18.0, _workshop_bounds.size.length() * 2.3) if _workshop_has_side_stacks else maxf(18.0, _height * 2.3)
	_update_camera()


func pan_workshop_camera(relative: Vector2) -> void:
	if _mode != "workshop": return
	var units_per_pixel := 2.0 * _distance * tan(deg_to_rad(camera.fov * 0.5)) / maxf(1.0, get_viewport().get_visible_rect().size.y)
	_workshop_pan += (-camera.basis.x * relative.x + camera.basis.y * relative.y) * units_per_pixel
	_workshop_pan = _workshop_pan.limit_length(100.0)
	_update_camera()


func zoom_camera(amount: float) -> void:
	_distance = clampf(_distance * exp(amount * 0.12), 8.0, 130.0)
	_update_camera()


func _update_camera() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(_rocket):
		return
	# Track the control capsule throughout flight, including stage separation.
	# Its mesh offset cancels the physics-origin rebase when the core drops away.
	_camera_focus = Vector3(0, WORKSHOP_CAMERA_FOCUS_Y, 0) if _mode == "workshop" else _rocket.transform * Vector3(0, _capsule_center_local, 0)
	if _mode == "workshop":
		if _workshop_fit or int(_design.get("tanks", 0)) > 4 or _workshop_has_side_stacks:
			_camera_focus = _rocket.position + (_workshop_bounds.get_center() if _workshop_has_side_stacks else Vector3(0, _height * 0.5, 0))
		_camera_focus += _workshop_pan
	var framing_pitch := _pitch
	if _mode == "flight":
		# Keep the shrinking horizon in frame as the vehicle reaches space.
		framing_pitch += acos(PLANET_RADIUS/(PLANET_RADIUS+maxf(0.0,_last_altitude)))*0.9
	var surface_frame := Basis(Quaternion(Vector3.UP,_surface_up))
	var water_pitch := _limit_pitch_above_water(framing_pitch, surface_frame)
	# Hold the player's pitch at the limit so dragging back up responds at once.
	_pitch += water_pitch - framing_pitch
	framing_pitch = water_pitch
	var offset := Vector3(sin(_yaw) * cos(framing_pitch), sin(framing_pitch), cos(_yaw) * cos(framing_pitch))
	offset = surface_frame * offset
	# Rotate camera-up with pitch so crossing a pole never reverses the view.
	var camera_up := surface_frame * Vector3(-sin(_yaw)*sin(framing_pitch), cos(framing_pitch), -cos(_yaw)*sin(framing_pitch))
	# Deployment preserves the player's framing while the cap and canopy move.
	camera.position = _camera_focus + offset * _distance
	camera.far = maxf(220000.0, _last_altitude + PLANET_RADIUS * 2.05 + _distance)
	camera.look_at(_camera_focus, camera_up)
	if _mode == "workshop":
		# Cut away scenery between the camera and the craft, including the floor
		# when inspecting the engine from underneath.
		_hangar_floor.visible = camera.position.y > 0.0
		_hangar_walls[0].visible = camera.position.z > -40.0
		_hangar_walls[1].visible = camera.position.x > -48.0
		_hangar_walls[2].visible = camera.position.x < 48.0
	if is_instance_valid(_ocean):
		if _mode == "workshop": _ocean.visible = false
		else:
			_ocean.follow(_planet, camera.global_position, _rocket.global_position, PlanetSurface.home(), _floating_sea_point())
			# Keep shoreline foam off the hull: its waterline is not a coast.
			var hull_bottom := _height - 2.8 if _capsule_only else 0.0
			_ocean.set_hull(_rocket.to_global(Vector3(0, hull_bottom, 0)), _rocket.to_global(Vector3(0, _height, 0)), 1.6)
		_planet.material_override.set_shader_parameter("water_cutout_radius", _ocean.cutout_radius)
		_planet.material_override.set_shader_parameter("seabed_fade", _ocean.fade)
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
	_environment.ambient_light_color = WORKSHOP_AMBIENT
	_environment.ambient_light_energy = 0.42
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = _half_res_sky() if AtmosphereQuality.settings(atmosphere_quality).half_res_sky else SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	# Forward+ forces realtime skies to a 256 radiance map rebuilt every frame;
	# incremental keeps the small map and spreads its update over frames.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
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


## Takes effect on the next drawn frame; unknown presets are ignored.
func set_atmosphere_quality(preset: String) -> void:
	if not AtmosphereQuality.valid(preset): return
	atmosphere_quality = preset
	_prepare_atmosphere_tables()
	if _sky_material != null:
		# Every sky uniform is set again by _update_atmosphere().
		_sky_material.shader = _half_res_sky() if AtmosphereQuality.settings(preset).half_res_sky else SKY_SHADER
	if is_instance_valid(camera): _update_atmosphere()


## sky.gdshader with its half-resolution scattering pass enabled.
static func _half_res_sky() -> Shader:
	if _half_res_sky_shader == null:
		_half_res_sky_shader = Shader.new()
		_half_res_sky_shader.code = SKY_SHADER.code.replace("shader_type sky;", "shader_type sky;\nrender_mode use_half_res_pass;\n#define SKY_HALF_RES")
	return _half_res_sky_shader


func _prepare_atmosphere_tables() -> void:
	var definition: Resource = PlanetSurface.home().definition
	AtmosphereQuality.prepare(atmosphere_quality, float(definition.radius) * 0.001, (float(definition.radius) + float(definition.atmosphere_height)) * 0.001)


func set_sun_direction(direction: Vector3) -> void:
	if not direction.is_finite() or direction.length_squared() < 0.000001: return
	_sun_direction = direction.normalized()
	if is_instance_valid(_sun_body):
		_sun_physical_position = _planet.position + _sun_direction * SolarBody.DISTANCE
	if is_instance_valid(camera): _update_atmosphere()


func set_planet_time(time: float) -> void:
	_planet_rotation_time = time
	var spin: Basis = PlanetSurface.home().rotation_at(time)
	_planet.basis = spin
	_landscape.basis = spin * PlanetSurface.LAUNCH_BASIS
	_landscape.position = _planet.position + spin * PlanetSurface.LAUNCH_RADIAL
	if is_instance_valid(camera):
		_update_moons()

func advance_solar_time(simulation_delta: float) -> void:
	if _mode != "flight" or not is_finite(simulation_delta) or simulation_delta <= 0.0:
		return
	_solar_time = fposmod(_solar_time + simulation_delta, SOLAR_DAY_SECONDS)
	_planet_rotation_time = fposmod(_planet_rotation_time + simulation_delta, maxf(float(PlanetSurface.home().definition.rotation_seconds), 1.0))
	var spin: Basis = PlanetSurface.home().rotation_at(_planet_rotation_time)
	_planet.basis = spin
	_landscape.basis = spin * PlanetSurface.LAUNCH_BASIS
	_landscape.position = _planet.position + spin * PlanetSurface.LAUNCH_RADIAL
	_sun_direction = (SolarBody.POSITION - _flight_position).normalized()
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
	_update_moons()
	# Compatibility's far-frustum extraction loses precision when a sub-metre
	# near plane is paired with escape distances. Leave headroom around body
	# bounds and use camera clearance to improve depth precision.
	if _mode == "flight":
		camera.far = maxf(220000.0, camera.position.distance_to(_planet.position) * 2.0 + PLANET_RADIUS * 2.0)
		for moon in _moons:
			var terrain: RefCounted = moon.get_meta("terrain")
			camera.far = maxf(camera.far, camera.position.distance_to(moon.position) * 2.0 + float(terrain.definition.radius) * 2.0)
		camera.near = clampf(camera.far / 100000.0, 0.5, _distance * 0.25)
	else:
		camera.near = 0.5
	var in_workshop := _mode == "workshop"
	var observer := (camera.global_position - _planet.global_position) * 0.001
	if not in_workshop:
		var relative_sun := _sun_physical_position - camera.position
		var visual_scale := minf(1.0, 160000.0 / maxf(relative_sun.length() + SolarBody.RADIUS, 1.0))
		_sun_body.position = camera.position + relative_sun * visual_scale
		_sun_body.scale = Vector3.ONE * visual_scale
		_sun_direction = relative_sun.normalized()
	var sun_height := observer.normalized().dot(_sun_direction)
	var daylight := smoothstep(-0.12, 0.25, sun_height)
	_sky_material.set_shader_parameter("workshop", in_workshop)
	_sky_material.set_shader_parameter("camera_planet_km", observer)
	_sky_material.set_shader_parameter("sun_direction", _sun_direction)
	var definition: Resource = PlanetSurface.home().definition
	_clouds.update_weather(definition, observer, _sun_direction, not in_workshop)
	# Dense lower-air paths are smooth; reserve the long integration for the
	# thin, distant orbital limb instead of paying 64 x 6 samples everywhere.
	# The budgets per altitude band come from the quality preset.
	var body_radius_km := float(definition.radius) * 0.001
	var air_radius_km := (float(definition.radius) + float(definition.atmosphere_height)) * 0.001
	var air_altitude := maxf(observer.length() - body_radius_km, 0.0)
	var samples := AtmosphereQuality.samples(atmosphere_quality, air_altitude, air_radius_km - body_radius_km, body_radius_km)
	var sun_table := AtmosphereQuality.uses_sun_table(atmosphere_quality)
	var air_materials: Array = [_sky_material, _planet.material_override]
	if is_instance_valid(_ocean): air_materials.append(_ocean.material())
	for material in air_materials:
		material.set_shader_parameter("atmosphere_view_samples", samples.x)
		material.set_shader_parameter("atmosphere_light_samples", samples.y)
		material.set_shader_parameter("atmosphere_surface_step", AtmosphereQuality.settings(atmosphere_quality).surface_step)
		material.set_shader_parameter("BODY_RADIUS", body_radius_km)
		material.set_shader_parameter("AIR_RADIUS", air_radius_km)
		material.set_shader_parameter("atmosphere_density_scale", float(definition.atmosphere_visual_density))
		AtmosphereQuality.apply_sun_depth_table(material, body_radius_km, air_radius_km, samples.y, sun_table)
	var planet_material: ShaderMaterial = _planet.material_override
	# The launch datum already lives in the floating-origin frame. Avoid the
	# GPU cancelling a 600 km vertex against a 600 km translation at the deck.
	planet_material.set_shader_parameter("launch_origin_enabled", camera.global_position.distance_squared_to(_landscape.global_position) < 6000.0 * 6000.0)
	planet_material.set_shader_parameter("launch_origin_local", PlanetSurface.LAUNCH_RADIAL)
	planet_material.set_shader_parameter("launch_origin_view", camera.global_transform.affine_inverse() * _landscape.global_position)
	planet_material.set_shader_parameter("camera_planet_km", observer)
	planet_material.set_shader_parameter("sun_direction", _sun_direction)
	if is_instance_valid(_ocean):
		_ocean.material().set_shader_parameter("camera_planet_km", observer)
		_ocean.material().set_shader_parameter("sun_direction", _sun_direction)
	planet_material.set_shader_parameter("atmosphere_density_scale", float(PlanetSurface.home().definition.atmosphere_visual_density))
	var light_up := Vector3.FORWARD if absf(_sun_direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	_sun.look_at(_sun.global_position - _sun_direction, light_up)
	# The nearby shadow map cannot cover an entire planet. Explicitly eclipse
	# the craft/site light while shaders shade the globe using the same sun.
	var horizon := -sqrt(maxf(0.0, 1.0 - pow(body_radius_km / maxf(observer.length(),body_radius_km),2.0)))
	var sun_visible := smoothstep(horizon-0.008, horizon+0.008, sun_height)
	# Keep the surrounding sky glow steady when the rocket crosses the sun.
	# The planet horizon still eclipses it, and the workshop has no sun glow.
	var facing := smoothstep(0.0, 0.25, -camera.global_basis.z.dot(_sun_direction))
	var glow_visibility := 0.0 if in_workshop else sun_visible * facing
	_sky_material.set_shader_parameter("sun_glow_visibility", glow_visibility)
	# The sun light falls on the vessel, so shade it by the clouds between the
	# vessel and the sun.
	var vessel_km := (_rocket.global_position - _planet.global_position) * 0.001
	# Cloud light eases on the real clock: time warp sweeps the sun across the
	# deck faster than the eye should see shading strobe on the hull.
	# Traced once per rendered frame; this runs several times in some frames.
	if in_workshop:
		_cloud_light_clock = 0
		_cloud_light = 1.0
		_cloud_glow = Color(0, 0, 0, 0)
	elif _cloud_light_frame != Engine.get_process_frames() or _cloud_light_clock == 0:
		_cloud_light_frame = Engine.get_process_frames()
		var now := Time.get_ticks_usec()
		var snap := _cloud_light_clock == 0
		var blend := 1.0 if snap else 1.0 - exp(-clampf(float(now - _cloud_light_clock) * 1e-6, 0.0, 0.5) / CLOUD_LIGHT_SMOOTHING)
		_cloud_light_clock = now
		# Sun shading and the surrounding glow trace on alternate frames; the
		# easing hides the half-rate updates.
		var odd := _cloud_light_frame % 2 == 1
		if snap or not odd:
			_cloud_sun_target = _clouds.sun_transmittance(vessel_km)
		if snap or odd:
			# Premultiplied, so thinning cover fades the glow rather than its hue.
			var glow: Color = _clouds.cloud_glow(vessel_km, snap)
			_cloud_glow_target = Color(glow.r * glow.a, glow.g * glow.a, glow.b * glow.a, glow.a)
		_cloud_light = lerpf(_cloud_light, _cloud_sun_target, blend)
		_cloud_glow = _cloud_glow.lerp(_cloud_glow_target, blend)
	var cloud_light := _cloud_light
	_sun.light_energy = 1.15 if in_workshop else SUN_ENERGY*sun_visible*cloud_light
	var warmth_weight := sqrt(clampf(sun_height,0.0,1.0))
	var temperature := lerpf(lerpf(2000.0,6500.0,warmth_weight),6500.0,1.0-air_density_visual(observer.length()))
	_sun.light_color = Color("ffedcc") if in_workshop else kelvin_to_rgb(temperature)
	_fill.light_energy = 0.22 if in_workshop else 0.0
	var air := air_density_visual(observer.length())
	# Surrounding cloud replaces part of the open sky as the vessel's ambient
	# source, in the colour the cloud shader lights it: grey under shaded bases,
	# red and orange beneath a sunset deck, bright beside sunlit towers.
	var ambient := WORKSHOP_AMBIENT * 0.42
	if not in_workshop:
		ambient = WORKSHOP_AMBIENT * lerpf(0.001, lerpf(0.08,0.42,air),daylight*sun_visible)
		ambient = ambient * (1.0 - _cloud_glow.a) + Color(_cloud_glow.r, _cloud_glow.g, _cloud_glow.b) * CLOUD_GLOW_GAIN
	var ambient_energy := maxf(maxf(ambient.r, ambient.g), maxf(ambient.b, 0.0001))
	_environment.ambient_light_color = Color(ambient.r / ambient_energy, ambient.g / ambient_energy, ambient.b / ambient_energy)
	_environment.ambient_light_energy = ambient_energy
	var overcast := lerpf(0.45, 1.0, cloud_light)
	_sky_material.set_shader_parameter("reflection_strength", 1.0 if in_workshop else lerpf(0.002,1.0,sun_visible)*overcast)


func air_density_visual(radius_km: float) -> float:
	var definition: Resource = PlanetSurface.home().definition
	var height := float(definition.atmosphere_height) * 0.001
	if height <= 0.0: return 0.0
	var altitude := maxf(0.0, radius_km - float(definition.radius) * 0.001)
	return exp(-altitude / maxf(height * 0.457, 0.001)) * (1.0 - smoothstep(height * 0.7, height, altitude))


func _reload_moons() -> void:
	for moon in _moons:
		moon.free()
	_moons.clear()
	_moon_parents.clear()
	_add_moons(PlanetSurface.home().definition, -1)

func _add_moons(parent: Resource, parent_index: int) -> void:
	for definition in parent.moons:
		var terrain := PlanetSurface.Terrain.new(definition)
		var moon := MeshInstance3D.new()
		moon.name = definition.planet_name
		moon.mesh = terrain.preview_mesh()
		moon.set_meta("terrain", terrain)
		moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = preload("res://assets/shaders/terrain.gdshader")
		terrain.configure_surface_material(material)
		material.set_shader_parameter("BODY_RADIUS", float(definition.radius) * 0.001)
		material.set_shader_parameter("AIR_RADIUS", (float(definition.radius) + float(definition.atmosphere_height)) * 0.001)
		material.set_shader_parameter("atmosphere_density_scale", float(definition.atmosphere_visual_density))
		moon.material_override = material
		moon.visible = _mode == "flight"
		_flight_location.add_child(moon)
		var index := _moons.size()
		_moons.append(moon)
		_moon_parents.append(parent_index)
		_add_moons(definition, index)

func _update_moons() -> void:
	for index in range(_moons.size()):
		var moon := _moons[index]
		moon.visible = _mode == "flight"
		if not moon.visible:
			continue
		var terrain: RefCounted = moon.get_meta("terrain")
		var definition: Resource = terrain.definition
		var parent_position := _planet.position if _moon_parents[index] < 0 else _moons[_moon_parents[index]].position
		moon.position = parent_position + SolarBody.moon_offset(definition, _planet_rotation_time)
		moon.basis = terrain.rotation_at(_planet_rotation_time)
		var material: ShaderMaterial = moon.material_override
		material.set_shader_parameter("camera_planet_km", (camera.position - moon.position) * 0.001)
		material.set_shader_parameter("sun_direction", (_sun_physical_position - moon.position).normalized())
		material.set_shader_parameter("eclipse_center_km", (_planet.position - moon.position) * 0.001)
		material.set_shader_parameter("eclipse_radius_km", float(PlanetSurface.home().definition.radius) * 0.001)
		material.set_shader_parameter("eclipse_sun_distance_km", _sun_physical_position.distance_to(moon.position) * 0.001)
		material.set_shader_parameter("eclipse_sun_radius_km", SolarBody.RADIUS * 0.001)
		material.set_shader_parameter("foreground_atmosphere_enabled", true)
		material.set_shader_parameter("foreground_camera_planet_km", (camera.position - _planet.position) * 0.001)
		material.set_shader_parameter("foreground_body_center_km", (_planet.position - moon.position) * 0.001)
		material.set_shader_parameter("foreground_body_radius_km", float(PlanetSurface.home().definition.radius) * 0.001)
		material.set_shader_parameter("foreground_air_radius_km", (float(PlanetSurface.home().definition.radius) + float(PlanetSurface.home().definition.atmosphere_height)) * 0.001)
		material.set_shader_parameter("foreground_atmosphere_density", float(PlanetSurface.home().definition.atmosphere_visual_density))
		# The moon's own call has no table match; its foreground haze is the
		# home body's, at the shader's default six light samples.
		var home: Resource = PlanetSurface.home().definition
		AtmosphereQuality.apply_sun_depth_table(material, float(home.radius) * 0.001, (float(home.radius) + float(home.atmosphere_height)) * 0.001, 6, AtmosphereQuality.uses_sun_table(atmosphere_quality))
		camera.far = maxf(camera.far, camera.position.distance_to(moon.position) + float(definition.radius) + float(definition.relief) * 1.5 + 1000.0)

func _make_planet() -> void:
	_planet = MeshInstance3D.new()
	_planet.mesh = PlanetSurface.render_mesh_for_altitude(0.0)
	_planet.position.y = -PLANET_RADIUS
	_planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/terrain.gdshader")
	PlanetSurface.home().configure_surface_material(material)
	material.set_shader_parameter("distant_surface_smoothing_enabled", true)
	_planet.material_override = material
	_prepare_atmosphere_tables()
	_flight_location.add_child(_planet)
	_clouds = preload("res://scripts/cloud_layer.gd").new()
	_planet.add_child(_clouds)
	_ocean = OceanPatch.new()
	_ocean.configure(PlanetSurface.home())
	_flight_location.add_child(_ocean)
	_clouds.add_reflection(_ocean.material())

func _update_planet_lod(altitude: float) -> void:
	# Coarse high-relief triangles can fold into visible speckles when the
	# rebased planet is millions of metres away. Keep enough angular coverage
	# for a continuous disk; this remains modest for one distant body.
	# Sea-level altitude can still put us on a tall mountain. Stay on the
	# physical mesh throughout the terrain envelope, including LOD hysteresis.
	var terrain_altitude := maxf(0.0, altitude - float(PlanetSurface.home().definition.relief) * 1.5)
	var requested_lod := PlanetSurface.render_lod_for_altitude(terrain_altitude, _planet_lod)
	var lod := mini(requested_lod, 1 if altitude > 500000.0 else 2)
	if lod == _planet_lod and _planet.mesh != null:
		return
	_planet_lod = lod
	_planet.mesh = PlanetSurface.home().render_mesh_for_lod(_planet_lod)

func _make_landscape() -> void:
	_landscape = preload("res://assets/models/launch_site/launch_complex.tscn").instantiate()
	_landscape.name = "LaunchPad"
	_flight_location.add_child(_landscape)


func _make_hangar() -> void:
	_hangar = Node3D.new()
	_hangar.name = "WorkshopInterior"
	add_child(_hangar)
	# A spacious 96 x 80 m bay with service galleries and overhead crane rails.
	_hangar_floor = Node3D.new()
	_hangar.add_child(_hangar_floor)
	_box(_hangar_floor, Vector3(96,0.4,80), Vector3(0,-0.35,0), _ground)
	for index in range(3):
		var wall := Node3D.new()
		_hangar.add_child(wall)
		_hangar_walls.append(wall)
	var back := _hangar_walls[0]
	_box(back, Vector3(96,48,0.5), Vector3(0,23.5,-40), _dark)
	for index in range(1,3):
		var x := -48.0 if index == 1 else 48.0
		var wall := _hangar_walls[index]
		_box(wall, Vector3(0.5,48,80), Vector3(x,23.5,0), _dark)
		for z in range(-36,37,12):
			_box(wall, Vector3(0.6,47,0.6), Vector3(x * 0.99,23,z), _teal)
		_box(wall, Vector3(1.8,0.6,78), Vector3(x * 0.94,33,0), _metal)
	for x in range(-42,43,12):
		_box(back, Vector3(0.4,47,0.6), Vector3(x,23,-39.6), _teal)
	for y in [8.0,20.0,32.0,44.0]:
		_box(back, Vector3(95,0.25,0.3), Vector3(0,y,-39.6), _metal)
	# Gantry, illuminated work bays, and raised maintenance gallery.
	var lamp := _material(Color("b8fff0"))
	lamp.emission_enabled = true
	lamp.emission = Color("75ead5")
	lamp.emission_energy_multiplier = 2.0
	_box(back, Vector3(88,1.2,1.2), Vector3(0,34,-28), _orange)
	_box(back, Vector3(7,1.8,3), Vector3(10,33,-28), _metal)
	_box(back, Vector3(90,0.35,3), Vector3(0,8,-37.5), _metal)
	for x in range(-42,43,6):
		_box(back, Vector3(0.1,1.2,0.1), Vector3(x,8.7,-36), _orange)
	_box(back, Vector3(90,0.1,0.1), Vector3(0,9.3,-36), _orange)
	for x in range(-36,37,12):
		_box(back, Vector3(5,0.15,0.8), Vector3(x,18,-38), lamp)
		_box(back, Vector3(4.5,2.4,1.2), Vector3(x,1.1,-38), _teal)
		for y in [0.5,1.2,1.9]:
			_box(back, Vector3(3.9,0.06,0.05), Vector3(x,y,-37.37), _metal)
	# Floor lanes and assembly markings retain a human sense of scale.
	for x in [-18.0,18.0]:
		_box(_hangar_floor, Vector3(0.16,0.035,72), Vector3(x,-0.1,0), _paint)
	for z in range(-32,33,4):
		for x in [-21.0,21.0]:
			_box(_hangar_floor, Vector3(0.3,0.035,1.8), Vector3(x,-0.1,z), _orange)
	for radius in [5.0, 7.0]:
		for segment in range(48):
			var angle := float(segment) * TAU / 48.0
			_box(_hangar_floor, Vector3(0.55,0.035,0.12), Vector3(sin(angle)*radius,-0.1,cos(angle)*radius), _orange if radius > 6 else _paint).rotation.y = angle
	_hangar.visible = true


func _build_rocket() -> void:
	_installed_positions.clear()
	_preview_radial_layout.clear()
	_rocket.show()
	for child in _rocket.get_children():
		child.free()
	_parachute_module = null
	_clear_aero_glow()
	_booster_nodes.clear()
	_lower_parts.clear()
	_engine_shell = null
	_engine_shells.clear()
	_engine_flames.clear()
	_main_flames.clear()
	_booster_flames.clear()
	if _design.has("assembly") and _design.assembly.parts.is_empty():
		_workshop_fit = false
		_workshop_pan = Vector3.ZERO
		_height = 4.0
		_workshop_has_side_stacks = false
		_workshop_bounds = AABB(Vector3(-1.5,0,-1.5),Vector3(3,4,3))
		_capsule_center_local = 1.4
		_capsule_visual_base_local = 0.2
		if _mode == "workshop": _rocket.position.y = _workshop_root_height() - _capsule_center_local
		_distance = 25.0
		return
	var tanks := clampi(int(_design.get("tanks",2)),0 if _design.has("assembly") else 1,RadialCraft.MAX_PARTS if _design.has("assembly") else RadialCraft.MAX_TANKS)
	var engine := str(_design.get("engine","kestrel"))
	var tank_base := 2.0 if not engine.is_empty() else 0.0
	var tank_top := RadialCraft.stack_top(_design)
	_capsule_visual_base_local = 0.2 if _design.get("decoupler", true) else 0.0
	_height = tank_top+2.8
	_capsule_center_local = tank_top + 1.2 + _capsule_visual_base_local
	_update_workshop_bounds()
	if _mode == "workshop":
		# The capsule is the assembly root. New parts extend below it.
		_rocket.position.y = _workshop_root_height() - _capsule_center_local
	var body := Node3D.new()
	_rocket.add_child(body)
	_lower_parts.append(body)
	var tank_nodes: Dictionary = {}
	for index in range(tanks):
		var tank_node := Node3D.new()
		body.add_child(tank_node)
		if _design.has("assembly"):
			var ordered: Array = _design.assembly.parts.filter(func(part): return part.kind == "tank")
			tank_node.set_meta("part_id", ordered[tanks-1-index].id)
			tank_nodes[ordered[tanks-1-index].id] = tank_node
			tank_node.position = RadialCraft.lateral_position(_design,ordered[tanks-1-index].id)
		# Remove any legacy procedural tank meshes that might be present
		_strip_tank_placeholders(tank_node)
		if _design.has("assembly"):
			var tank_parts: Array = _design.assembly.parts.filter(func(part): return part.kind == "tank")
			tank_node.rotation_degrees.y = float(tank_parts[tanks - 1 - index].rotation)
		var y := tank_base+float(index)*2.15
		if _design.has("assembly"):
			var ordered_tanks: Array = _design.assembly.parts.filter(func(part): return part.kind == "tank")
			y = RadialCraft.tank_center(_design, ordered_tanks[tanks - 1 - index].id) - 1.075
		var canister := _make_canister_tank()
		canister.position.y += y + 1.075
		tank_node.add_child(canister)
		print("world_view: added canister at tank slot %d" % index)
		# Ensure the authored canister is visible and remove any direct MeshInstance3D
		for child in tank_node.get_children():
			if child is MeshInstance3D and child.mesh is CylinderMesh:
				child.queue_free()
	for part in _design.get("assembly", {}).get("parts", []):
		if part.kind != "reaction_wheel": continue
		var wheel := _vehicle_model("gyro_1", ReactionWheel)
		wheel.set_meta("part_id", part.id)
		wheel.position.y = RadialCraft.part_base(_design, part.id) + .1
		wheel.rotation_degrees.y = float(part.rotation)
		body.add_child(wheel)
	for installed in RadialCraft.engines(_design):
		var engine_body := Node3D.new()
		engine_body.name = "Installed_" + str(installed.id)
		engine_body.set_meta("part_id", installed.id)
		body.add_child(engine_body)
		engine_body.position = RadialCraft.lateral_position(_design,installed.id) + Vector3(0,RadialCraft.engine_base(_design, installed.id),0)
		var flames: Array[Node3D] = []
		if installed.kind not in ["kestrel", "sparrow"]:
			_cylinder(engine_body,0.85,0.85,0.6,Vector3(0,1.65,0),_teal)
			_cylinder(engine_body,0.76,0.9,0.28,Vector3(0,1.26,0),_metal)
		if installed.kind == "titan":
			for x in [-0.38,0.38]:
				for z in [-0.38,0.38]: _engine(engine_body,Vector3(x,0.8,z),0.42,flames)
		else: _place_engine(engine_body,Vector3(0,0.8,0),0.78,flames,installed.kind)
		_engine_flames[installed.id] = flames
		_main_flames.append_array(flames)
		for part in _design.get("assembly", {}).get("parts", []):
			if part.kind != "decoupler" or part.parent != installed.id: continue
			var enclosure := Node3D.new()
			enclosure.name = "EngineShell"
			enclosure.set_meta("part_id", part.id)
			engine_body.add_child(enclosure)
			_engine_shells[part.id] = enclosure
			if installed.id == "engine": _engine_shell = enclosure
			var shell := _cylinder(enclosure,1.05,1.05,1.94,Vector3(0,1.1,0),_paint)
			shell.mesh.cap_top = false
			var shell_material := _paint.duplicate() as StandardMaterial3D
			shell_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			shell.material_override = shell_material
			var ring := _vehicle_model("atlas_1", AtlasDecoupler)
			ring.position.y = 0.1
			enclosure.add_child(ring)
	for part in _design.get("assembly",{}).get("parts",[]):
		if part.kind != "decoupler" or part.id == "decoupler": continue
		var parents: Array = _design.assembly.parts.filter(func(item): return item.id == part.parent and item.kind in ["tank", "reaction_wheel"])
		if parents.is_empty(): continue
		var ring := _vehicle_model("atlas_1", AtlasDecoupler)
		ring.set_meta("part_id",part.id)
		ring.position = RadialCraft.lateral_position(_design,part.id)+Vector3(0,RadialCraft.part_base(_design,part.id)+.1,0)
		body.add_child(ring)
		# Bare rings also disappear when fired without a massive lower stage.
		_engine_shells[part.id] = ring
	for mount in RadialCraft.radial_instances(_design,"separator"):
		var separator := _radial_visual("separator",mount)
		separator.set_meta("part_id", mount.id)
		body.add_child(separator)
		var parent_id := _part_parent(str(mount.id))
		if tank_nodes.has(parent_id):
			# Preserve the authored mount pose, including a rotated parent tank.
			separator.reparent(tank_nodes[parent_id], true)
	for mount in RadialCraft.radial_instances(_design,"boosters"):
		var booster := _radial_visual("boosters",mount,true)
		_rocket.add_child(booster)
		_booster_nodes.append(booster)
	_capsule = Node3D.new()
	_rocket.add_child(_capsule)
	_capsule.visible = bool(_design.get("capsule", true))
	if _design.get("decoupler", true):
		var decoupler := _vehicle_model("atlas_1", AtlasDecoupler)
		decoupler.position.y = tank_top + 0.1
		body.add_child(decoupler)
	var explorer := _vehicle_model("explorer_1", ExplorerCapsule)
	explorer.position.y = tank_top + _capsule_visual_base_local
	_capsule.add_child(explorer)
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
						if tank_parts[index].id == fin_parent: fin_y = RadialCraft.tank_center(_design, fin_parent) + fin_offset
		for index in range(4):
			var fin := _fin(fin_parent_node, _teal, capsule_fins)
			fin.position.y = fin_y
			fin.rotation.y = float(index)*PI*0.5+PI*0.25
	if _design.get("parachute", false):
		_parachute_module = ParachuteModule.instantiate()
		_capsule.add_child(_parachute_module)
		_parachute_module.position.y = _capsule_center_local + 1.12
		_chute = _parachute_module.canopy
	else:
		_make_chute(_capsule_center_local + 1.3)
	if _mode != "workshop": _distance = maxf(25.0,_height*2.48)
	_animate_flames(_main_flames,0.0)
	_animate_flames(_booster_flames,0.0)
	# Placeholder cleanup is limited to tank nodes; engines and shells use procedural meshes.


func _workshop_root_height() -> float:
	var root_height := 9.0
	if _design.has("assembly"):
		root_height = clampf(float(_design.assembly.get("root_height", 7.5)), 3.5, RadialCraft.MAX_ROOT_HEIGHT)
	if int(_design.get("tanks", 0)) > 4:
		root_height = maxf(root_height, _capsule_center_local + 1.0)
	if _workshop_has_side_stacks:
		root_height = maxf(root_height,_capsule_center_local-_workshop_bounds.position.y+1.0)
	return root_height


func _engine(parent: Node3D, position: Vector3, radius: float, flames: Array[Node3D]) -> void:
	_cylinder(parent,radius*0.48,radius,0.83,position,_dark)
	_cylinder(parent,radius*1.03,radius*1.03,0.11,position+Vector3(0,-0.4,0),_metal)
	_cylinder(parent,radius*0.84,radius*0.84,0.015,position+Vector3(0,-0.464,0),_dark)
	_add_flame(parent, position, radius, flames)


func _animate_flames(flames: Array[Node3D], power: float) -> void:
	power = clampf(power, 0.0, 1.0)
	# Fade the glow and shell roots together over the lowest quarter of thrust.
	var intensity := smoothstep(0.0, 0.25, power)
	for index in range(flames.size()):
		if not is_instance_valid(flames[index]): continue
		var flame := flames[index]
		flame.visible = power > 0.0
		for child in flame.get_children():
			if child is MeshInstance3D and child.material_override is ShaderMaterial:
				child.material_override.set_shader_parameter("thrust_intensity", intensity)
		var pulse := 1.0+sin(_clock*43.0+float(index)*2.7)*0.08+sin(_clock*71.0)*0.03
		flame.scale = Vector3(1.0, maxf(0.01, power * pulse), 1.0)


var _heated_meshes: Array[MeshInstance3D] = []
var aerothermal_effects_enabled := true
var _heat_material: ShaderMaterial
const AerothermalWake = preload("res://scripts/aerothermal_wake.gd")
var _heat_trail: MeshInstance3D
var _exhaust_mesh: ArrayMesh

func _shared_exhaust_mesh() -> ArrayMesh:
	if _exhaust_mesh != null: return _exhaust_mesh
	# Keep the outer four shells, leaving the center of the exhaust open.
	# The outer shell stays inside the measured inner nozzle lip.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in range(4, 8):
		var fill_radius := float(layer + 1) / 8.0
		var layer_length := 10.0 * (1.12 if layer == 7 else 1.0)
		surface.set_color(Color(fill_radius, 0.0, 0.0, 0.30 if layer < 7 else 0.50))
		for ring in range(8):
			for segment in range(24):
				for corner: Vector2 in [Vector2(0,0), Vector2(1,0), Vector2(0,1), Vector2(1,0), Vector2(1,1), Vector2(0,1)]:
					var u := (float(segment) + corner.x) / 24.0
					var t := (float(ring) + corner.y) / 8.0
					var angle := u * TAU
					var shell_radius := fill_radius * (1.0 - smoothstep(0.04, 1.0, t))
					surface.set_uv(Vector2(u, t))
					surface.add_vertex(Vector3(cos(angle) * shell_radius, -t * layer_length, sin(angle) * shell_radius))
	surface.index()
	_exhaust_mesh = surface.commit()
	return _exhaust_mesh


func _add_flame(parent: Node3D, position: Vector3, radius: float, flames: Array[Node3D], mouth_radius: float = -1.0, exit_offset: float = -0.46) -> void:
	var flame := Node3D.new()
	flame.set_meta("engine_exhaust", true)
	parent.add_child(flame)
	flame.position = position + Vector3(0, exit_offset, 0)
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/rocket_exhaust.gdshader")
	# Local transparent effects follow the cloud composite (priority 1).
	# They still depth-test against the opaque hull, terrain and launch pad.
	material.render_priority = 2
	material.set_shader_parameter("phase", float(flames.size()) * 2.7)
	var opening := mouth_radius if mouth_radius > 0.0 else radius * 0.80
	var plume := MeshInstance3D.new()
	plume.mesh = _shared_exhaust_mesh()
	plume.scale = Vector3.ONE * opening
	plume.material_override = material
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.add_child(plume)
	# A glow ring follows the nozzle plane and leaves the removed layers hollow.
	var glow := MeshInstance3D.new()
	var glow_mesh := QuadMesh.new()
	glow_mesh.size = Vector2.ONE * opening * 2.0
	glow.mesh = glow_mesh
	var glow_material := ShaderMaterial.new()
	glow_material.shader = preload("res://assets/shaders/rocket_root_glow.gdshader")
	glow_material.render_priority = 2
	glow.material_override = glow_material
	glow.rotation.x = -PI * 0.5
	glow.position.y = -0.003
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.add_child(glow)
	flames.append(flame)


func _place_engine(parent: Node3D, position: Vector3, radius: float, flames: Array[Node3D], kind: String) -> void:
	if kind in ["kestrel", "sparrow"]:
		var inst := _make_sparrow_engine() if kind == "sparrow" else _make_kestrel_engine()
		inst.position += position
		parent.add_child(inst)
		# The authored nozzle exits at Y=0; fit exhaust inside its inner lip.
		var mouth_radius := 0.454 if kind == "sparrow" else 0.670
		_add_flame(parent, inst.position, radius, flames, mouth_radius * inst.scale.x, 0.0)
		return
	_engine(parent, position, radius, flames)


func _make_kestrel_engine() -> Node3D:
	var inst := _vehicle_model("engine_1", KestrelEngine)
	inst.name = "KestrelEngine1"
	# Fit the existing engine slot: exit at 0.20 m, tank joint at 2.0 m.
	# Preview origins share the installed engine's 0.80 m selection anchor.
	inst.scale = Vector3(0.94 / 0.96, 1.80 / 2.69, 0.94 / 0.96)
	inst.position.y = -0.60
	return inst


func _make_sparrow_engine() -> Node3D:
	var inst := _vehicle_model("sparrow_1", SparrowEngine)
	inst.name = "SparrowEngine1"
	# Keep Kestrel's mounting diameter and tank joint; the shorter bell sits higher.
	inst.scale = Vector3(0.94 / 0.96, 1.80 / 2.69, 0.94 / 0.96)
	inst.position.y = 1.20 - 2.0 * inst.scale.y
	return inst


func _make_chute(anchor: float) -> void:
	_chute = ParachuteAsset.instantiate()
	_rocket.add_child(_chute)
	_chute.position.y = anchor
	_chute.visible = false


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
		elif installed_part_kind(part) == "reaction_wheel": kind = "reaction_wheel"
		elif installed_part_kind(part) == "decoupler": kind = "decoupler"
		elif installed_part_kind(part) in RadialCraft.ENGINE_IDS: kind = installed_part_kind(part)
		var top := RadialCraft.stack_top(_design)
		var installed_position := installed_part_position(part)
		match part:
			"capsule": installed_position.y = _capsule_center_local
			"decoupler": installed_position.y = top + 0.1
			"engine": installed_position.y = RadialCraft.engine_base(_design) + 0.8
			"boosters", "separator": installed_position = installed_part_position(part)
			"fins":
				installed_position = installed_part_position("fins")
			_:
				if part.begins_with("tank_") and _design.has("assembly"):
					var tanks: Array = _design.assembly.parts.filter(func(item): return item.kind == "tank")
					for index in range(tanks.size()):
						if tanks[index].id == part: installed_position.y = RadialCraft.tank_center(_design,part)
		_edit_preview = _make_drag_model(kind, false, part == "fins" and _part_parent("fins") == "capsule")
		_rocket.add_child(_edit_preview)
		_edit_preview.position = installed_position
		var outline := ShaderMaterial.new()
		outline.shader = preload("res://assets/shaders/workshop_outline.gdshader")
		_set_preview_material(_edit_preview, outline)
		return
	# If a tank identifier reached this fallback, use the authored canister
	# model so the preview matches the installed visual rather than a
	# procedural cylinder placeholder.
	if part.begins_with("tank_"):
		var top := RadialCraft.stack_top(_design)
		var y := top + 1.075
		if _design.has("assembly"):
			var tanks: Array = _design.assembly.parts.filter(func(item): return item.kind == "tank")
			for index in range(tanks.size()):
				if tanks[index].id == part:
					y = RadialCraft.tank_center(_design,part)
		_edit_preview = Node3D.new()
		var canister := _make_canister_tank()
		canister.position.y = 0.0
		_edit_preview.add_child(canister)
		_rocket.add_child(_edit_preview)
		_edit_preview.position = Vector3(0.0, y, 0.0)
		# Apply the same translucent preview material used for other parts
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.albedo_color = Color(0.48, 0.9, 0.75, 0.4)
		_set_preview_material(_edit_preview, material)
		_edit_preview.set_meta("glow_material", material)
		# We've finished constructing the canister preview; skip the cylinder fallback.
		return
	else:
		_edit_preview = MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 1.0
		mesh.bottom_radius = 1.0
		mesh.height = 2.15
		var top := RadialCraft.stack_top(_design)
		var y := top + 1.075
		if part == "decoupler":
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
		_edit_preview.position = Vector3(0, snap_anchor.y, 0) if part in ["boosters", "separator", "fins"] else snap_anchor
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
	var outline := ShaderMaterial.new()
	outline.shader = preload("res://assets/shaders/workshop_outline.gdshader")
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
	var model_anchor := Vector3(0, target_anchor.y, 0) if selected_id in ["fins", "boosters", "separator"] else target_anchor
	_edit_preview.position = model_anchor - installed_part_position(selected_id)
	var material: StandardMaterial3D = _edit_preview.get_meta("glow_material")
	material.albedo_color = Color(0.25,1.0,0.53,0.68)


func _make_installed_group(ids: Array[String], glowing: bool = false, fins_capsule_override: int = -1) -> Node3D:
	var group := Node3D.new()
	for id in ids:
		var kind := installed_part_kind(id)
		if kind.is_empty(): continue
		var capsule_fins := id == "fins" and (fins_capsule_override == 1 or (fins_capsule_override < 0 and _part_parent(id) == "capsule"))
		var model := _make_drag_model(id if kind in ["separator","boosters"] else kind, false, capsule_fins)
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


# The workshop model is fixed between rebuilds. Hover/drag outlines share its
# anchors instead of walking every radial branch again for each outlined part.
var _installed_positions: Dictionary = {}
var _preview_radial_layout: Dictionary = {}

func _radial_preview_instances(kind: String) -> Array:
	if not _preview_radial_layout.has(kind):
		_preview_radial_layout[kind] = RadialCraft.radial_instances(_design, kind)
	return _preview_radial_layout[kind]

func installed_part_position(id: String) -> Vector3:
	if not _installed_positions.has(id):
		_installed_positions[id] = _calculate_installed_part_position(id)
	return _installed_positions[id]

func _calculate_installed_part_position(id: String) -> Vector3:
	var top := RadialCraft.stack_top(_design)
	if id == "parachute": return Vector3(0,_capsule_center_local+1.12+0.5,0)
	if id == "capsule": return Vector3(0,_capsule_center_local,0)
	if id == "decoupler": return Vector3(0,top+0.1,0)
	if installed_part_kind(id) == "reaction_wheel": return Vector3(0,RadialCraft.part_base(_design,id)+.1,0)
	if installed_part_kind(id) == "decoupler": return RadialCraft.lateral_position(_design,id)+Vector3(0,RadialCraft.part_base(_design,id)+0.1,0)
	if installed_part_kind(id) in RadialCraft.ENGINE_IDS: return RadialCraft.lateral_position(_design,id) + Vector3(0,RadialCraft.engine_base(_design,id)+0.8,0)
	if id in ["boosters", "separator"] or id.begins_with("boosters_") or id.begins_with("separator_"):
		var kind := "boosters" if id.begins_with("boosters") else "separator"
		var center := Vector3.ZERO
		var count := 0
		for mount in _radial_preview_instances(kind):
			if mount.id == id or id == kind: center += mount.position; count += 1
		return center / maxf(count,1)
	var tanks: Array = _design.assembly.parts.filter(func(item): return item.kind == "tank") if _design.has("assembly") else []
	if id.begins_with("tank_"):
		for index in range(tanks.size()):
			if tanks[index].id == id: return RadialCraft.lateral_position(_design,id) + Vector3(0,RadialCraft.tank_center(_design,id),0)
	if id == "fins" and _design.has("assembly"):
		var fins: Array = _design.assembly.parts.filter(func(item): return item.kind == "fins")
		if not fins.is_empty():
			var offset := float(fins[0].get("surface_offset", 0.0))
			if fins[0].parent == "capsule": return Vector3(0,_capsule_center_local+offset,0)
			for index in range(tanks.size()):
				if tanks[index].id == fins[0].parent:
					var base := 2.0 if not _design.engine.is_empty() else 0.0
					return Vector3(0,RadialCraft.tank_center(_design,tanks[index].id)+offset,0)
	return Vector3.ZERO


func _make_canister_tank() -> Node3D:
	# The reference vessel is taller than the FL-18 attachment envelope.
	# Share the same fitted visual for installed parts, ghosts and outlines.
	var canister := _vehicle_model("canister_1", CanisterTank)
	print("world_view: instantiated CanisterTank resource: %s" % str(CanisterTank))
	canister.name = "Canister1FuelTank"
	# Seat the full-width end collars (authored at +/-2.255 m) on
	# the slot faces. The narrower lids/manifold project into the adjoining
	# part; fitting their total bounds leaves visible gaps at every joint.
	canister.scale.y = 2.15 / 4.51
	return canister


func _normalize_model_lighting(node: Node) -> void:
	for child in node.get_children():
		if child.has_meta("shadow_proxy"): continue
		if child is GeometryInstance3D and not child.has_meta("shadow_proxied"):
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if child is MeshInstance3D:
			_normalize_mesh_materials(child)
		_normalize_model_lighting(child)


func _normalize_mesh_materials(instance: MeshInstance3D) -> void:
	if instance.material_override != null:
		instance.material_override = _lit_material(instance.material_override)
	if instance.mesh == null:
		return
	for surface in range(instance.mesh.get_surface_count()):
		var material := instance.get_surface_override_material(surface)
		if material == null:
			material = instance.mesh.surface_get_material(surface)
		if material != null:
			instance.set_surface_override_material(surface, _lit_material(material))


func _lit_material(material: Material) -> Material:
	if material is StandardMaterial3D:
		var lit := material.duplicate() as StandardMaterial3D
		if lit.albedo_texture == null and lit.emission_texture != null:
			lit.albedo_texture = lit.emission_texture
			lit.albedo_color = Color.WHITE
		lit.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		lit.emission_enabled = false
		return lit
	return material


func _strip_tank_placeholders(node: Node) -> void:
	# Remove simple procedural cylinders or mesh placeholders under a tank
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh: Mesh = child.mesh
			if mesh is CylinderMesh or mesh is BoxMesh or mesh is SphereMesh:
				child.queue_free()
		else:
			_strip_tank_placeholders(child)


func _make_drag_model(part: String, mounted: bool = false, capsule_mounted: bool = false) -> Node3D:
	var root := Node3D.new()
	var unused_flames: Array[Node3D] = []
	match "radial" if part.begins_with("separator_") or part.begins_with("boosters_") else part:
		"parachute":
			var housing := ParachuteHousing.instantiate() as Node3D
			housing.scale = Vector3.ONE * 0.53
			housing.position.y = -0.5
			root.add_child(housing)
		"capsule":
			var explorer := _vehicle_model("explorer_1", ExplorerCapsule)
			explorer.position.y = -1.2
			root.add_child(explorer)
		"reaction_wheel":
			root.add_child(_vehicle_model("gyro_1", ReactionWheel))
		"decoupler":
			root.add_child(_vehicle_model("atlas_1", AtlasDecoupler))
		"tank":
			root.add_child(_make_canister_tank())
		"kestrel":
			root.add_child(_make_kestrel_engine())
		"sparrow":
			root.add_child(_make_sparrow_engine())
		"boosters", "separator", "radial":
			root.add_child(_make_radial_pair("boosters" if part.begins_with("boosters") else "separator",part))
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
	if node.has_meta("shadow_proxy"):
		# Previews cast no shadow; a proxy left visible would draw a second copy.
		node.queue_free()
		return
	if node is MeshInstance3D:
		if node.mesh != null and node.mesh.has_meta("preview_mesh"):
			node.mesh = node.mesh.get_meta("preview_mesh")
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _set_preview_material(child, material)


func _sync_detached(state: Dictionary, origin: Vector3) -> void:
	debris_markers.clear()
	var frustum := camera.get_frustum()
	var pieces: Array = state.get("detached", [])
	_sync_surface_impacts(state, origin)
	var live_ids: Array = pieces.map(func(piece): return piece.get("id", -1))
	for old in _detached_nodes.duplicate():
		if old.get_meta("debris_id", -1) not in live_ids:
			_detached_nodes.erase(old)
			old.hide()
			old.queue_free()
	for index in range(pieces.size()):
		var piece: Dictionary = pieces[index]
		var node: Node3D
		for candidate in _detached_nodes:
			if candidate.get_meta("debris_id", -1) == piece.get("id", -1):
				node = candidate
				break
		if node == null:
			var root := Node3D.new()
			add_child(root)
			root.set_meta("debris_id", piece.get("id", -1))
			node = root
			var sources: Array[Node3D] = _booster_nodes if piece.kind == "boosters" else _lower_parts
			if piece.get("carries_boosters", false):
				sources = sources.duplicate()
				sources.append_array(_booster_nodes)
			if piece.kind == "boosters" and int(piece.get("source_index", -1)) >= 0:
				sources = [_booster_nodes[int(piece.source_index)]]
			if piece.kind == "stack":
				sources = []
				for candidate in _rocket.find_children("*", "Node3D", true, false):
					if not candidate.get_meta("part_id", "") in piece.get("part_ids", []): continue
					if sources.any(func(source): return source.is_ancestor_of(candidate)): continue
					sources.append(candidate)
			# Transfer the already-loaded stage instead of cloning its detailed meshes.
			for source in sources:
				var local_transform := _rocket.global_transform.affine_inverse() * source.global_transform
				source.reparent(root, false)
				if piece.kind == "stack": source.transform = local_transform
				source.position -= Vector3(piece.get("local_center", Vector3.ZERO))
				source.visible = true
			var flames: Array[Node3D] = []
			for flame in _main_flames + _booster_flames:
				if root.is_ancestor_of(flame):
					if flame in _booster_flames: flame.set_meta("engine_id", "boosters")
					flames.append(flame)
			# Only the detached body now owns these exhaust animations/materials.
			for flame in flames:
				_main_flames.erase(flame)
				_booster_flames.erase(flame)
			# Transfer ownership of engine lookups as well as the scene nodes.
			# The active craft must not animate or retain handles to discarded parts.
			for id in _engine_flames.keys():
				if _engine_flames[id].any(func(flame): return is_instance_valid(flame) and root.is_ancestor_of(flame)):
					for flame in _engine_flames[id]: flame.set_meta("engine_id", id)
					_engine_flames.erase(id)
			for id in _engine_shells.keys():
				if not is_instance_valid(_engine_shells[id]) or root.is_ancestor_of(_engine_shells[id]):
					_engine_shells.erase(id)
			if is_instance_valid(_engine_shell) and root.is_ancestor_of(_engine_shell):
				_engine_shell = null
			root.set_meta("exhaust_nodes", flames)
			_detached_nodes.append(root)
		var relative_position: Vector3 = piece.position - origin
		# Subtract large coordinates first, then restore the small integration
		# remainders in camera-local space where Vector3 can represent them.
		relative_position += Vector3(piece.get("position_remainder", Vector3.ZERO)) - Vector3(state.get("position_remainder", Vector3.ZERO))
		var global_center := to_global(relative_position)
		debris_markers.append({"position": global_center, "distance": relative_position.length(), "radius": maxf(float(piece.radius), float(piece.length) * 0.5),
			"basis": global_basis * Basis(piece.orientation), "half_extents": Vector3(float(piece.radius), float(piece.length)*0.5, float(piece.radius))})
		# Include the nozzle plume in the culling sphere. Hidden stages retain
		# their models but skip transforms and all exhaust animation/uniform work.
		var radius := maxf(float(piece.length), float(piece.radius)) + 12.0
		var distance_to_camera := camera.global_position.distance_to(global_center)
		var burning: bool = piece.thrust > 0.0 and piece.fuel > 0.0 and not piece.landed
		# Cull spent stages by their apparent cross section as well as distance.
		# The plume margin is only for frustum bounds; it must not keep a tiny
		# unpowered part visible as a persistent sparkling dot.
		var pixels_per_radian := get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
		var diameter_pixels := 2.0 * float(piece.radius) * pixels_per_radian / maxf(distance_to_camera, 0.01)
		var low_altitude := _last_altitude < float(PlanetSurface.home().definition.atmosphere_height)
		var visible_debris := low_altitude or (distance_to_camera <= 2000.0 + radius and (burning or diameter_pixels >= 4.0))
		if visible_debris:
			for plane in frustum:
				if plane.distance_to(global_center) > radius:
					visible_debris = false
					break
		node.visible = visible_debris
		if not visible_debris: continue
		node.position = relative_position
		node.basis = piece.orientation
		var flames: Array[Node3D] = node.get_meta("exhaust_nodes")
		if piece.has("engines"):
			for flame in flames:
				var active: bool = piece.engines.any(func(engine): return engine.id == flame.get_meta("engine_id", "") and engine.fuel > 0.0 and engine.thrust > 0.0)
				_animate_flames([flame], float(piece.get("throttle", 1.0)) if burning and active else 0.0)
		else:
			_animate_flames(flames, float(piece.get("throttle", 1.0)) if burning else 0.0)


func _make_booster(side: float, flames: Array[Node3D]) -> Node3D:
	var root := Node3D.new()
	root.name = "Booster1Left" if side < 0 else "Booster1Right"
	root.position.x = side * 1.96
	var model := _vehicle_model("booster_1", BoosterAsset)
	model.position.y = -2.63
	root.add_child(model)
	for index in range(4):
		var angle := float(index) * TAU / 4.0
		_add_flame(root, Vector3(sin(angle)*0.345,-2.63,cos(angle)*0.345),0.225,flames,0.207,0.0)
	return root


func _make_radial_pair(kind: String, id: String = "") -> Node3D:
	var root := Node3D.new()
	var anchor := installed_part_position(id if not id.is_empty() else kind)
	for mount in _radial_preview_instances(kind):
		if not id.is_empty() and id != kind and mount.id != id: continue
		var visual := _radial_visual(kind,mount)
		visual.position -= anchor
		root.add_child(visual)
	return root


func _radial_visual(kind: String, mount: Dictionary, burning: bool = false) -> Node3D:
	var visual: Node3D
	if kind == "boosters":
		var unused: Array[Node3D] = []
		visual = _make_booster(1.0,_booster_flames if burning else unused)
		for flame in unused: flame.visible = false
	else:
		visual = _vehicle_model("separator_1", SeparatorAsset)
		visual.scale = Vector3(.55,1.0,.55)
	visual.position = mount.position
	visual.rotation.y = mount.angle
	return visual


func preview_radial(kind: String, placements: Array, mouse: Vector2) -> void:
	var key := "surface:"+kind+":"+str(placements.size())
	if key != _preview_key or not is_instance_valid(_edit_preview):
		if is_instance_valid(_edit_preview): _edit_preview.queue_free()
		_edit_preview = Node3D.new()
		_rocket.add_child(_edit_preview)
		_preview_key = key
		for index in range(maxi(1,placements.size())):
			_edit_preview.add_child(_make_drag_model("tank") if kind == "tank" else _radial_visual(kind,{"position":Vector3.ZERO,"angle":0.0}))
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_set_preview_material(_edit_preview,material)
		_edit_preview.set_meta("glow_material",material)
	var material: StandardMaterial3D = _edit_preview.get_meta("glow_material")
	material.albedo_color = Color(.25,1,.53,.62) if not placements.is_empty() else Color(1,.18,.16,.62)
	material.no_depth_test = placements.is_empty()
	for index in range(placements.size()):
		var child := _edit_preview.get_child(index) as Node3D
		child.position = placements[index].position
		child.rotation.y = placements[index].angle
	if placements.is_empty():
		var origin := camera.project_ray_origin(mouse)
		var direction := camera.project_ray_normal(mouse)
		var distance := maxf(1.0,(_camera_focus-origin).dot(-camera.global_basis.z)/direction.dot(-camera.global_basis.z))
		_edit_preview.global_position = origin+direction*distance
	else: _edit_preview.position = Vector3.ZERO


func preview_radial_move(id: String, placement: Dictionary) -> void:
	var key := "move-surface:"+id
	var original := installed_part_position(id)
	var angle := 0.0
	for mount in RadialCraft.radial_instances(_design,"separator"):
		if mount.id == id: angle = mount.angle
	if key != _preview_key or not is_instance_valid(_edit_preview):
		if is_instance_valid(_edit_preview): _edit_preview.queue_free()
		_edit_preview = _make_installed_group(RadialCraft.descendant_ids(_design.assembly,id),true)
		for child in _edit_preview.get_children(): child.position -= original
		_rocket.add_child(_edit_preview)
		_preview_key = key
	_edit_preview.position = placement.position
	_edit_preview.rotation.y = placement.angle-angle
	var material: StandardMaterial3D = _edit_preview.get_meta("glow_material")
	material.albedo_color = Color(.25,1,.53,.62)


func _new_impact() -> MeshInstance3D:
	if _impact_mesh == null:
		_impact_mesh = SphereMesh.new()
		_impact_mesh.radius = 1.0
		_impact_mesh.height = 2.0
	var node := MeshInstance3D.new()
	node.mesh = _impact_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(1.0, 0.3, 0.02)
	material.emission_energy_multiplier = 3.0
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.hide()
	add_child(node)
	return node

func prepare_impact_pool() -> void:
	while _impact_pool.size() < IMPACT_POOL_SIZE:
		_impact_pool.append(_new_impact())

func _release_impact(node: MeshInstance3D) -> void:
	node.hide()
	if _impact_pool.size() < IMPACT_POOL_SIZE:
		_impact_pool.append(node)
	else:
		node.queue_free()

func _sync_surface_impacts(state: Dictionary, origin: Vector3) -> void:
	for impact in state.get("surface_impacts", []):
		var node: MeshInstance3D = _impact_pool.pop_back() if not _impact_pool.is_empty() else _new_impact()
		node.show()
		_impact_effects.append({"node": node, "position": impact.position, "radius": impact.radius, "born": _clock})
	state.get("surface_impacts", []).clear()
	for effect in _impact_effects.duplicate():
		var age: float = (_clock - float(effect.born)) / 0.8
		if age >= 1.0:
			_release_impact(effect.node)
			_impact_effects.erase(effect)
			continue
		var node: MeshInstance3D = effect.node
		node.position = Vector3(effect.position) - origin
		node.scale = Vector3.ONE * float(effect.radius) * (0.15 + age)
		var material: StandardMaterial3D = node.material_override
		material.albedo_color = Color(1.0, lerpf(0.8, 0.12, age), 0.02, 1.0 - age)


## Draws every flight effect while a loading cover hides the view, so the
## driver compiles their shaders now rather than stalling the first ignition,
## reentry or deployment. A following sync_flight restores the real state.
func prewarm_effects(on: bool, opaque_chute: bool = false) -> void:
	_animate_flames(_main_flames, 1.0 if on else 0.0)
	if is_instance_valid(_parachute_module):
		_parachute_module.prewarm_fade(on, opaque_chute)
	_animate_flames(_booster_flames, 1.0 if on else 0.0)
	if is_instance_valid(_chute):
		if on:
			_prewarm_chute_transform = _chute.transform
			_chute.scale = Vector3.ONE
		else:
			_chute.transform = _prewarm_chute_transform
		_chute.visible = on
	if not _impact_pool.is_empty():
		var impact := _impact_pool[0]
		impact.visible = on
		impact.global_position = _rocket.global_position
		impact.scale = Vector3.ONE * 2.0
		impact.material_override.albedo_color = Color(1.0, 0.5, 0.02, 0.8)
	if on:
		# Zero delta leaves the wake's animation phase where it was.
		_update_aero_glow({"heat_glow": 1.0, "heating_rate": 180.0, "status": "flying", "velocity": Vector3(0, -1000, 0)}, 0.0)
	else:
		_clear_aero_glow()


func _clear_aero_glow() -> void:
	if is_instance_valid(_heat_trail): _heat_trail.hide()
	for mesh in _heated_meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = mesh.get_meta("pre_heat_overlay", null)
			mesh.remove_meta("pre_heat_overlay")
	_heated_meshes.clear()


func _collect_heated_meshes(node: Node) -> void:
	# Include the parachute housing and nose cap in the hot hull, but not its fabric.
	if node.has_meta("engine_exhaust") or node.has_meta("heat_trail") or node.has_meta("shadow_proxy") or node == _chute:
		return
	if node is MeshInstance3D:
		node.set_meta("pre_heat_overlay", node.material_overlay)
		node.material_overlay = _heat_material
		_heated_meshes.append(node)
	for child in node.get_children():
		_collect_heated_meshes(child)


func _update_aero_glow(state: Dictionary, delta: float) -> void:
	if not aerothermal_effects_enabled:
		_clear_aero_glow()
		return
	var retained_heat := float(state.get("heat_glow", 0.0))
	var heating := maxf(float(state.get("heating_rate", 0.0)), 0.0)
	var flow_strength := clampf(heating / 180.0, 0.0, 1.0)
	# Use one intensity for hull color and wake. Fast ascent must not leave silver metal under entry fire.
	# Retained heat preserves the glow as airflow fades; physics is unchanged.
	var airflow_heat := float(state.get("plasma_glow", smoothstep(40.0, 180.0, heating)))
	var intensity := clampf(maxf(retained_heat, airflow_heat), 0.0, 1.0)
	var active := intensity > 0.001 and str(state.get("status", "ready")) == "flying"
	if not active:
		if not _heated_meshes.is_empty(): _clear_aero_glow()
		return
	if _heat_material == null:
		_heat_material = ShaderMaterial.new()
		_heat_material.shader = preload("res://assets/shaders/aerothermal.gdshader")
		_heat_material.render_priority = 2
	if _heated_meshes.is_empty(): _collect_heated_meshes(_rocket)
	# Staged parts must stop borrowing the controlled vessel's heat state.
	for index in range(_heated_meshes.size() - 1, -1, -1):
		var mesh := _heated_meshes[index]
		if not is_instance_valid(mesh):
			_heated_meshes.remove_at(index)
		elif not _rocket.is_ancestor_of(mesh):
			mesh.material_overlay = mesh.get_meta("pre_heat_overlay", null)
			mesh.remove_meta("pre_heat_overlay")
			_heated_meshes.remove_at(index)
	var flow: Vector3 = state.get("air_velocity", state.get("velocity", Vector3.ZERO))
	var direction := flow.normalized() if flow.length_squared() > 0.01 else Vector3.ZERO
	_heat_material.set_shader_parameter("intensity", intensity)
	_heat_material.set_shader_parameter("air_direction", direction)
	# Residual hot metal remains luminous in vacuum; airflow flames do not.
	_update_heat_trail(direction, flow.length(), intensity * flow_strength, delta)



func _prepare_aero_wake() -> void:
	# Pay hull sampling and mesh upload during rollout, before high-speed flight.
	if not is_instance_valid(_heat_trail):
		_heat_trail = AerothermalWake.new()
		_rocket.add_child(_heat_trail)
	if _heated_meshes.is_empty():
		_collect_heated_meshes(_rocket)
		_heat_trail.prepare_hull(_heated_meshes, _rocket)
		_clear_aero_glow()
	else:
		_heat_trail.prepare_hull(_heated_meshes, _rocket)


func _update_heat_trail(direction: Vector3, speed: float, strength: float, delta: float) -> void:
	if not is_instance_valid(_heat_trail):
		if strength <= 0.005: return
		_heat_trail = AerothermalWake.new()
		_rocket.add_child(_heat_trail)
	_heat_trail.update_flow(_heated_meshes, _rocket, direction, speed, strength, delta)

func preview_stack_parts(kind: String, placements: Array) -> void:
	var key := "side-stack:"+kind+":"+str(placements.size())
	if key != _preview_key or not is_instance_valid(_edit_preview):
		if is_instance_valid(_edit_preview): _edit_preview.queue_free()
		_edit_preview = Node3D.new()
		_rocket.add_child(_edit_preview)
		_preview_key = key
		for placement in placements:
			_edit_preview.add_child(_make_drag_model(kind,kind in RadialCraft.ENGINE_IDS))
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(.25,1,.53,.62)
		_set_preview_material(_edit_preview,material)
		_edit_preview.set_meta("glow_material",material)
	for index in range(placements.size()): _edit_preview.get_child(index).position = placements[index].position

# Include side-stage geometry and the space needed to mount an engine on a
# bare tank. Flight dimensions remain independent of workshop framing.
func _update_workshop_bounds() -> void:
	_workshop_bounds = AABB(Vector3(-1.5,0,-1.5),Vector3(3,_height,3))
	_workshop_has_side_stacks = false
	var parts: Array = _design.get("assembly",{}).get("parts",[])
	for part in parts:
		if part.kind not in ["tank","decoupler","reaction_wheel"] + RadialCraft.ENGINE_IDS: continue
		if RadialCraft.radial_mount(_design.assembly,part.id).is_empty(): continue
		_workshop_has_side_stacks = true
		var position := RadialCraft.lateral_position(_design,part.id)
		var bottom := RadialCraft.part_base(_design,part.id)
		var top := bottom + (2.15 if part.kind == "tank" else 2.0)
		if part.kind == "tank" and not parts.any(func(child): return child.parent == part.id and child.port == "bottom"):
			bottom -= 2.4
		_workshop_bounds = _workshop_bounds.expand(position+Vector3(-1.1,bottom,-1.1))
		_workshop_bounds = _workshop_bounds.expand(position+Vector3(1.1,top,1.1))
