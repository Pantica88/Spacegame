extends SceneTree
## CPU check of ocean.gdshader mirrored_clouds(): for mirrored rays at each
## elevation, compares its single base sample with a fine march through the
## deck (what the sky draws along that line). Uses cloud_layer.gd's CPU field.
const HOVER = preload("res://scenes/hover_preview.tscn")
var hover

func _initialize() -> void: _run.call_deferred()

func _p(name: String) -> Variant:
	return (hover._clouds.material_override as ShaderMaterial).get_shader_parameter(name)

func _run() -> void:
	hover = HOVER.instantiate()
	root.add_child(hover)
	hover.set_process_unhandled_input(false)
	hover.set_process(false)
	for i in range(120): await process_frame
	while not hover._clouds._noise_ready(): await process_frame
	hover._update_camera()
	for i in range(10): await process_frame
	var clouds = hover._clouds
	var authored: bool = _p("authored_weather")
	var body_r: float = _p("BODY_RADIUS")
	var h_km: float = _p("cloud_height_km")
	var thick: float = _p("cloud_thickness_km")
	var deck: float = _p("cloud_deck_fraction")
	var dscale: float = _p("cloud_density_scale")
	var opscale := 1.2 if authored else 3.0
	var bottom := body_r + h_km - thick * 0.5
	var observer: Vector3 = _p("camera_planet_km")
	var up := observer.normalized()
	var origin := up * body_r
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := east.cross(up)
	print("authored=%s bottom_alt=%.2f km thick=%.2f km deck=%.2f density_scale=%.2f" % [authored, bottom - body_r, thick, deck, dscale])
	print("elev | real%  mirror% | agree: now  boost1 boost2 march3 | mean alpha err: now boost1 march3")
	for elev_deg in [1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0, 35.0, 60.0]:
		var e := deg_to_rad(elev_deg)
		var n := 0
		var real_c := 0
		var mir_c := 0
		var agree := 0
		var fix_agree := 0
		var agree1 := 0
		var agree2 := 0
		var err1 := 0.0
		var err3 := 0.0
		var err := 0.0
		var offsets: Array[float] = []
		for k in range(180):
			var az := TAU * k / 180.0
			var ray := (up * sin(e) + (east * cos(az) + north * sin(az)) * cos(e)).normalized()
			var enter: float = clouds._sphere_exit(origin, ray, bottom)
			var top_exit: float = clouds._sphere_exit(origin, ray, bottom + thick)
			# Real: fine march through the whole deck along this line.
			var remaining := 1.0
			var hit := -1.0
			var t: float = enter
			while t < top_exit and remaining > 0.02:
				var q: Vector3 = origin + ray * (t + 0.025)
				var hh: float = (q.length() - bottom) / thick
				var f: Vector3 = clouds._formation(q, hh, authored)
				remaining *= exp(-f.x * dscale * 0.05 * opscale)
				if hit < 0.0 and remaining < 0.5: hit = t
				t += 0.05
			var a_real: float = 1.0 - remaining
			# Mirror: ocean.gdshader's single sample, with its density boost (4).
			var step_km: float = 0.35 / maxf(ray.dot((origin + ray * enter).normalized()), 0.15)
			var p: Vector3 = origin + ray * (enter + step_km * 0.5)
			var fm: Vector3 = clouds._formation(p, (p.length() - bottom) / thick, authored)
			var a_m: float = 1.0 - exp(-fm.x * dscale * step_km * opscale)
			a_m = 1.0 - pow(1.0 - a_m, 4.0)
			var a_m1: float = 1.0 - exp(-fm.x * dscale * step_km * opscale)
			var a_m2: float = 1.0 - pow(1.0 - a_m1, 2.0)
			# Three samples through the deck along the ray, front to back.
			var rem3 := 1.0
			var span: float = minf(top_exit - enter, 3.0 * step_km)
			for s3 in range(3):
				var d3: float = enter + span * (s3 + 0.5) / 3.0
				var q3: Vector3 = origin + ray * d3
				var f3: Vector3 = clouds._formation(q3, (q3.length() - bottom) / thick, authored)
				rem3 *= exp(-f3.x * dscale * span / 3.0 * opscale)
			var a6: float = 1.0 - rem3
			agree1 += int((a_real > 0.5) == (a_m1 > 0.5))
			agree2 += int((a_real > 0.5) == (a_m2 > 0.5))
			err1 += absf(a_real - a_m1)
			err3 += absf(a_real - a6)
			n += 1
			var rc := a_real > 0.5
			var mc := a_m > 0.5
			real_c += int(rc)
			mir_c += int(mc)
			agree += int(rc == mc)
			fix_agree += int(rc == (a6 > 0.5))
			err += absf(a_real - a_m)
			if hit >= 0.0: offsets.append(hit - (enter + step_km * 0.5))
		offsets.sort()
		var med: float = offsets[offsets.size() / 2] if offsets.size() > 0 else 0.0
		print("%4.0f° | %3d%% %3d%% | %3d%% %3d%% %3d%% %3d%% | %.2f %.2f %.2f" % [elev_deg, real_c * 100 / n, mir_c * 100 / n, agree * 100 / n, agree1 * 100 / n, agree2 * 100 / n, fix_agree * 100 / n, err / n, err1 / n, err3 / n])
	quit(0)
