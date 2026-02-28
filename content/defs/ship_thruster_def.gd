# content/defs/ship_thruster_def.gd (Godot 4.5)
extends Resource
class_name ShipThrusterDef

@export var thruster_name: StringName = &""
# Path to a Marker3D (or Node3D) inside ShipVisualDef.layout_scene.
@export var marker_path: NodePath = NodePath("")
@export var scale_multiplier: float = 1.0
@export var mesh: Mesh
@export var material: Material
@export var particles_scene: PackedScene

@export_color_no_alpha var color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_color_no_alpha var emission_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var emission_energy: float = 1.0
