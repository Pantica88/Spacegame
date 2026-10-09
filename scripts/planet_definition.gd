extends Resource
## Generation settings; changing a seed intentionally creates a different world.
@export var planet_name := "Verdant"
@export var terrain_seed := 73129
@export var radius := 600000.0
@export var rotation_seconds := 21600.0
@export_range(1.0,25.0) var surface_gravity := 9.81
@export_range(0.0,3.0) var atmosphere_density := 1.225
@export_range(0.0,200000.0) var atmosphere_height := 90000.0
@export_range(0.0,3.0) var atmosphere_visual_density := 1.0
@export var orbit_enabled := true
@export_range(0.05,40.0) var orbit_distance_au := 1.0
@export_range(0.001,100000.0,0.001) var orbit_period_days := 365.26
@export_range(0.0,1.0) var orbit_phase := 0.0
@export var map_color := Color("4d9ed1")
@export var continent_frequency := 2.4
@export_range(0.02,1.0) var continent_edge_smoothness := 0.18
@export var sea_threshold := -0.06
@export var relief := 2800.0
@export var mountain_frequency := 8.0
@export_range(0.02,0.5) var ridge_roundness := 0.20
## Optional shaping layers preserve existing geography at their neutral values.
@export_range(0.0,1.0) var coastline_irregularity := 0.0
@export_range(0.0,2.0) var mountain_height := 1.0
@export_range(0.0,1.0) var erosion := 0.0
@export_range(0.0,1.0) var terrain_detail := 0.0
@export_range(12.0,96.0) var detail_frequency := 24.0
@export var has_ocean := true
@export var launch_site := true
@export var launch_central_hill := false
@export var launch_apron := true
@export var launch_coast := true
@export var launch_rings := true
@export var lowland := Color("477443")
@export var highland := Color("89806a")
@export var dryland := Color("b89b68")
@export var has_snow := true
@export var snow := Color("dbe4e1")
@export var ocean := Color("154665")
@export var baked_terrain: Resource
## Optional authored cloud formations; null keeps the planet's procedural weather.
@export var cloud_weather: Resource
## Sky dynamics: the weather pattern drifts rigidly with the wind while the
## billows themselves slowly boil and reform. Zero wind/evolution is static.
@export_range(0.0,120.0) var cloud_wind_speed := 18.0
@export_range(-180.0,180.0) var cloud_wind_heading := 90.0
@export_range(0.0,1.0) var cloud_evolution := 0.35
@export_range(0.0,1.0) var cloud_coverage := 0.56
@export_range(0.2,2.5) var cloud_density := 1.0

## Moons are owned by this planet and use the same independent terrain settings.
@export var moons: Array[Resource] = []
@export_range(1.0, 100000.0) var moon_orbit_distance_km := 400.0
