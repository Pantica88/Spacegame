extends Control
## Flight-only tracking overlay. Mouse events pass through to the flight view.
var world: Node3D
const TINT := Color(0.46, 0.91, 0.79)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

static func distance_text(distance: float) -> String:
	return "%.1f km" % (distance / 1000.0) if distance >= 1000.0 else "%.0f m" % distance

func _draw() -> void:
	if not is_instance_valid(world) or world.rendering_suspended or world._mode != "flight": return
	var camera: Camera3D = world.camera
	var font := ThemeDB.fallback_font
	for marker in world.debris_markers:
		var point: Vector3 = marker.position
		if camera.is_position_behind(point): continue
		# Do not reveal stages through the planet or its moons.
		var ray := point - camera.global_position
		var distance := ray.length()
		var direction := ray / maxf(distance, 0.001)
		var hidden := false
		var bodies: Array = [world._planet]
		bodies.append_array(world._moons)
		for body in bodies:
			var radius: float = world.PLANET_RADIUS if body == world._planet else body.get_meta("terrain").definition.radius
			var offset: Vector3 = body.global_position - camera.global_position
			var along := offset.dot(direction)
			var perpendicular := (offset-direction*along).length_squared()
			if perpendicular < radius*radius and along > 0.0:
				var entry := along-sqrt(radius*radius-perpendicular)
				if entry > 0.0 and entry < distance-float(marker.radius): hidden = true
		if hidden: continue
		var center := get_global_transform_with_canvas().affine_inverse() * camera.unproject_position(point)
		if not Rect2(Vector2.ZERO, size).has_point(center): continue
		var focal := size.y / (2.0*tan(deg_to_rad(camera.fov)*0.5))
		var projected_radius := float(marker.radius)*focal/maxf(distance,1.0)
		if marker.has("half_extents"):
			# Project the oriented bounds instead of using the length as a sphere:
			# a long stage seen end-on needs a much smaller square.
			var extent: Vector3 = marker.half_extents
			var basis: Basis = marker.basis
			projected_radius = 0.0
			for x in [-1.0, 1.0]:
				for y in [-1.0, 1.0]:
					for z in [-1.0, 1.0]:
						var corner := point + basis * (extent * Vector3(x,y,z))
						if camera.is_position_behind(corner): continue
						var screen := get_global_transform_with_canvas().affine_inverse() * camera.unproject_position(corner)
						var offset := (screen-center).abs()
						projected_radius = maxf(projected_radius,maxf(offset.x,offset.y))
		var half_size := clampf(projected_radius+2.0,6.0,120.0)
		# Keep the bright stroke above one pixel even at minimum size. Scaling
		# it below a pixel made the small dashed marker almost disappear.
		var stroke_scale := clampf(half_size/14.0,0.65,1.0)
		var dash_length := clampf(half_size*0.4,2.0,6.0)
		var corners := [center+Vector2(-half_size,-half_size),center+Vector2(half_size,-half_size),center+Vector2(half_size,half_size),center+Vector2(-half_size,half_size)]
		for edge in range(4):
			for stroke in [7.0, 4.0, 1.5]:
				var color := Color(TINT, 0.07 if stroke == 7.0 else (0.18 if stroke == 4.0 else 0.95))
				draw_dashed_line(corners[edge],corners[(edge+1)%4],color,maxf(stroke*stroke_scale,1.5),dash_length)
		var label := distance_text(float(marker.distance))
		var label_size := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,15)
		var label_position := center+Vector2(-label_size.x*0.5,half_size+19.0)
		draw_string_outline(font,label_position,label,HORIZONTAL_ALIGNMENT_LEFT,-1,15,4,Color(0.01,0.025,0.03,0.95))
		draw_string(font,label_position,label,HORIZONTAL_ALIGNMENT_LEFT,-1,15,TINT)
