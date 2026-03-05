# scripts/poi/poi_instance.gd (Godot 4.5)
extends Node3D
class_name PoiInstance

## The definition resource for this POI
@export var poi_def: PoiDef

## Runtime POI type (cached from def or overridden)
var poi_type: PoiDef.PoiType = PoiDef.PoiType.OFFENSE

## Unique instance ID assigned at spawn time
var instance_id: int = -1

## Spawn index (0 = first POI, 1 = second, etc.)
var spawn_index: int = 0

## Display name for UI/nameplates
var display_name: String = "POI"

## Optional path to the mesh that receives visual overrides
@export var mesh_instance_path: NodePath = NodePath("MeshInstance3D")

## Reference to mesh instance for visual updates
@onready var _mesh_instance: MeshInstance3D = get_node_or_null(mesh_instance_path) as MeshInstance3D


func _ready() -> void:
	if _mesh_instance == null:
		_mesh_instance = _find_first_mesh_instance(self)

	if poi_def != null:
		poi_type = poi_def.poi_type
		display_name = poi_def.display_name
		_apply_visuals()
	
	# Add to pois group for nameplate and offscreen indicator support
	add_to_group("pois")


## Configure this POI instance with a definition and metadata
func configure(def: PoiDef, id: int, index: int) -> void:
	poi_def = def
	instance_id = id
	spawn_index = index
	if def != null:
		poi_type = def.poi_type
		display_name = def.display_name
	if is_inside_tree():
		_apply_visuals()


## Apply visual properties from the definition
func _apply_visuals() -> void:
	if poi_def == null or _mesh_instance == null:
		return
	
	# Apply material override if provided
	if poi_def.material_override != null:
		_mesh_instance.set_surface_override_material(0, poi_def.material_override)
	else:
		# Create a default emission material based on POI type
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = _get_type_color()
		mat.emission_enabled = true
		mat.emission = poi_def.emission_color
		mat.emission_energy_multiplier = poi_def.emission_energy
		_mesh_instance.set_surface_override_material(0, mat)


## Get a base color based on POI type
func _get_type_color() -> Color:
	match poi_type:
		PoiDef.PoiType.OFFENSE:
			return Color(0.8, 0.2, 0.2, 1.0)  # Red-ish
		PoiDef.PoiType.DEFENSE:
			return Color(0.2, 0.7, 0.3, 1.0)  # Green-ish
		PoiDef.PoiType.UTILITY:
			return Color(0.9, 0.7, 0.1, 1.0)  # Yellow/Gold
		_:
			return Color(0.5, 0.5, 0.5, 1.0)


## Get the display name (from def or fallback)
func get_display_name() -> String:
	if poi_def != null:
		return poi_def.display_name
	return "Unknown POI"


## Get the POI ID (from def or fallback)
func get_poi_id() -> String:
	if poi_def != null:
		return poi_def.poi_id
	return "unknown"


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	for child: Node in node.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh != null:
			return mesh

		var nested_mesh: MeshInstance3D = _find_first_mesh_instance(child)
		if nested_mesh != null:
			return nested_mesh

	return null
