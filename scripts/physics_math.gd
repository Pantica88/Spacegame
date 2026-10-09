extends RefCounted
## SI units; planet-centered inertial vectors unless explicitly stated otherwise.
## Central gravity uses a reference sphere; rotating terrain contacts live in PlanetTerrain.

const STANDARD_GRAVITY: float = 9.80665
const PLANET_RADIUS: float = 600000.0
const PLANET_CENTER := Vector3(0, -PLANET_RADIUS, 0)
const GRAVITATIONAL_CONSTANT: float = 6.67430e-11
const PLANET_MASS: float = 5.292e22
const SURFACE_GRAVITY: float = GRAVITATIONAL_CONSTANT * PLANET_MASS / (PLANET_RADIUS * PLANET_RADIUS)
const MU: float = SURFACE_GRAVITY * PLANET_RADIUS * PLANET_RADIUS
const ATMOSPHERE_HEIGHT: float = 90000.0


static func body_drag_acceleration(air_velocity: Vector3, axis: Vector3, density: float, mass: float, frontal_area: float, side_area: float, dt: float, side_exposure: float = -1.0) -> Vector3:
	if density <= 0.0 or dt <= 0.0 or air_velocity.is_zero_approx():
		return Vector3.ZERO
	var axial := axis * air_velocity.dot(axis)
	var crossflow := air_velocity - axial
	var pressure_per_mass := 0.5 * density / maxf(mass, 1.0)
	var frontal_rate := pressure_per_mass * maxf(frontal_area, 0.0) * air_velocity.length()
	var lateral_speed := crossflow.length() if side_exposure < 0.0 else air_velocity.length() * clampf(side_exposure, 0.0, 1.0)
	var lateral_rate := frontal_rate + pressure_per_mass * maxf(side_area, 0.0) * lateral_speed
	# Integrate dissipative drag separately along the hull and across it.
	# The implicit rates approach rest without reversing either component or
	# deleting all momentum in one frame when a parachute opens at high speed.
	return -axial * (frontal_rate / (1.0 + frontal_rate * dt)) - crossflow * (lateral_rate / (1.0 + lateral_rate * dt))


static func gravity(radial: Vector3, mu: float = MU) -> Vector3:
	var radius := maxf(radial.length(), 1.0)
	return -radial * (mu / (radius * radius * radius))


static func coast_step(radial: Vector3, velocity: Vector3, dt: float, mu: float = MU) -> Array[Vector3]:
	# Velocity Verlet: symmetric gravity kicks conserve orbital energy far better
	# than the former first-order map prediction.
	var half_velocity := velocity + gravity(radial, mu) * (0.5 * dt)
	var next_position := radial + half_velocity * dt
	return [next_position, half_velocity + gravity(next_position, mu) * (0.5 * dt)]


static func orbital_elements(radial: Vector3, velocity: Vector3, mu: float = MU, body_radius: float = PLANET_RADIUS) -> Dictionary:
	# Keep the scalar conic calculation in doubles. Vector cross products and
	# length_squared round before division, moving a circular apsis by decimetres
	# at the current planet radius even when the input state is representable.
	var radius := maxf(sqrt(dot_double(radial, radial)), 1.0)
	var up := radial / radius
	var speed_squared := dot_double(velocity, velocity)
	var radial_speed := dot_double(radial, velocity)
	var hx := float(radial.y) * velocity.z - float(radial.z) * velocity.y
	var hy := float(radial.z) * velocity.x - float(radial.x) * velocity.z
	var hz := float(radial.x) * velocity.y - float(radial.y) * velocity.x
	var momentum := Vector3(hx, hy, hz) # Specific angular momentum, m²/s.
	var momentum_squared := hx * hx + hy * hy + hz * hz
	var eccentricity_vector := Vector3.ZERO
	for axis in range(3):
		eccentricity_vector[axis] = ((speed_squared - mu / radius) * float(radial[axis]) - radial_speed * float(velocity[axis])) / mu
	var eccentricity := eccentricity_vector.length()
	var energy := 0.5 * speed_squared - mu / radius # Specific energy, J/kg.
	# Float32 vectors cannot reliably distinguish an exactly parabolic orbit
	# from tiny positive/negative roundoff at escape speed.
	var parabolic := absf(energy) <= (mu / radius) * 0.000001
	var bound := energy < 0.0 and not parabolic
	var semimajor := INF if parabolic else -mu / (2.0 * energy)
	var semilatus := momentum_squared / mu
	var periapsis := semilatus / (1.0 + eccentricity) - body_radius
	var apoapsis := semimajor * (1.0 + eccentricity) - body_radius if bound else INF
	var period := TAU * sqrt(semimajor * semimajor * semimajor / mu) if bound else INF
	var plane_defined := momentum_squared > radius * radius * maxf(speed_squared, 1.0) * 1e-12
	var prograde := velocity.normalized()
	var normal := momentum.normalized() if plane_defined else Vector3.ZERO
	return {
		"eccentricity": eccentricity, "eccentricity_vector": eccentricity_vector,
		"specific_energy": energy, "specific_angular_momentum": momentum,
		"semi_major_axis": semimajor, "semi_latus_rectum": semilatus,
		"orbital_period": period, "apoapsis": apoapsis, "periapsis": periapsis,
		"bound_orbit": bound, "orbit_plane_defined": plane_defined,
		"circular_speed": sqrt(mu / radius), "escape_speed": sqrt(2.0 * mu / radius),
		"surface_up": up, "prograde": prograde, "retrograde": -prograde,
		"normal": normal, "antinormal": -normal,
		"radial_out": prograde.cross(normal), "radial_in": normal.cross(prograde)
	}

static func dot_double(a: Vector3, b: Vector3) -> float:
	return float(a.x) * b.x + float(a.y) * b.y + float(a.z) * b.z


static func coast_path(radial: Vector3, velocity: Vector3, max_radius: float, samples: int = 720, mu: float = MU, body_radius: float = PLANET_RADIUS) -> PackedVector3Array:
	var points := PackedVector3Array([radial])
	var elements := orbital_elements(radial, velocity, mu, body_radius)
	if not elements.orbit_plane_defined or elements.semi_latus_rectum < body_radius * 0.01:
		# Near-radial suborbital arcs occupy a tiny anomaly range. Predict in
		# time so angular sampling cannot skip the entire climb and descent.
		var position := radial
		var speed := velocity
		for index in range(samples):
			var next := coast_step(position, speed, 2.0, mu)
			position = next[0]
			speed = next[1]
			points.append(position)
			if position.length() <= body_radius or position.length() > max_radius: break
		return points
	var eccentricity: float = elements.eccentricity
	var peri_direction: Vector3 = elements.eccentricity_vector.normalized() if eccentricity > 1e-6 else radial.normalized()
	var sideways: Vector3 = Vector3(elements.normal).cross(peri_direction)
	var start := atan2(radial.dot(sideways), radial.dot(peri_direction))
	for index in range(1, samples + 1):
		var anomaly := start + TAU * float(index) / float(samples)
		var denominator := 1.0 + eccentricity * cos(anomaly)
		if denominator <= 0.0: break # An open conic ends at its asymptote.
		var radius: float = elements.semi_latus_rectum / denominator
		if radius > max_radius: break
		points.append((peri_direction * cos(anomaly) + sideways * sin(anomaly)) * radius)
		if radius <= body_radius: break
	return points
