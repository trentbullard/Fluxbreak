# content/defs/poi_def.gd (Godot 4.5)
extends Resource
class_name PoiDef

## Enumeration of POI types affecting gameplay behavior
enum PoiType {
	OFFENSE = 0,    # Damage/weapon upgrades
	DEFENSE = 1,    # Shield/hull upgrades
	UTILITY = 2,    # Utility/misc upgrades
}

@export_group("Identity")
@export var poi_id: String = ""                  # e.g. "station_offense_mk1"
@export var display_name: String = "Unknown POI"
@export var poi_type: PoiType = PoiType.OFFENSE

@export_group("Spawning")
## Relative chance for this definition to be selected
@export_range(0.0, 100.0, 0.05) var spawn_weight: float = 1.0
## Base spawn distance from origin/player for this POI type
@export var spawn_distance: float = 3000.0
## Minimum distance this POI must be from other POIs
@export var min_separation: float = 800.0

@export_group("Visual")
## Optional custom scene override for this POI type
@export var scene_override: PackedScene
## Optional material override for placeholder mesh
@export var material_override: StandardMaterial3D
## Emission color for visibility
@export var emission_color: Color = Color(0.2, 0.6, 1.0, 1.0)
## Emission intensity
@export var emission_energy: float = 2.0

@export_group("Future - Docking")
## Radius at which docking begins (not implemented yet)
@export var docking_radius: float = 200.0
## Time in seconds to dock (not implemented yet)
@export var docking_time: float = 3.0

@export_group("Future - Upgrades")
## Number of upgrade choices offered (not implemented yet)
@export var upgrade_choices: int = 3
## Tags for filtering upgrade pools (not implemented yet)
@export var upgrade_tags: Array[String] = []

