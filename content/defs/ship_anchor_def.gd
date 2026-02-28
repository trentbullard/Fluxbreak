# content/defs/ship_anchor_def.gd (Godot 4.5)
extends Resource
class_name ShipAnchorDef

@export var anchor_name: StringName = &""
# Path to a Marker3D (or Node3D) inside ShipVisualDef.layout_scene.
@export var marker_path: NodePath = NodePath("")
