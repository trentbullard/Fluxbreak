# content/defs/ship_shield_def.gd (Godot 4.5)
extends Resource
class_name ShipShieldDef

@export var shield_name: StringName = &"Shield"
# Path to a Marker3D (or Node3D) inside ShipVisualDef.layout_scene.
@export var marker_path: NodePath = NodePath("")
@export var radius: float = 7.0
@export var height: float = 16.0

@export_color_no_alpha var color: Color = Color(0.0, 0.78, 1.0, 1.0)
@export_color_no_alpha var emission_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var emission_energy: float = 1.0

# Optional future shader hook. If unset, runtime can keep using default material behavior.
@export var shader_definition: Shader
@export var shader_material: ShaderMaterial
