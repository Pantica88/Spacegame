extends Resource
## Generation settings; changing a seed intentionally creates a different world.
@export var planet_name := "Verdant"
@export var terrain_seed := 73129
@export var radius := 60000.0
@export var rotation_seconds := 1440.0
@export_range(1.0,25.0) var surface_gravity := 9.81
@export_range(0.0,3.0) var atmosphere_density := 1.225
@export_range(0.0,80000.0) var atmosphere_height := 18000.0
@export_range(0.0,3.0) var atmosphere_visual_density := 1.0
@export var orbit_enabled := true
@export_range(0.05,40.0) var orbit_distance_au := 1.0
@export_range(1.0,100000.0) var orbit_period_days := 365.26
@export_range(0.0,1.0) var orbit_phase := 0.0
@export var map_color := Color("4d9ed1")
@export var continent_frequency := 2.4
@export_range(0.02,1.0) var continent_edge_smoothness := 0.18
@export var sea_threshold := -0.06
@export var relief := 2800.0
@export var mountain_frequency := 8.0
@export_range(0.02,0.5) var ridge_roundness := 0.20
@export var has_ocean := true
@export var launch_site := true
@export var lowland := Color("477443")
@export var highland := Color("89806a")
@export var dryland := Color("b89b68")
@export var snow := Color("dbe4e1")
@export var ocean := Color("154665")
@export var baked_terrain: Resource
