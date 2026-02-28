# content/defs/ship_visual_def.gd (Godot 4.5)
extends Resource
class_name ShipVisualDef

@export_category("Layout Scene")
@export var layout_scene: PackedScene
# Path can be direct from layout root (e.g. "ModelSocket").
@export var model_marker_path: NodePath = NodePath("ModelSocket")
# Optional root for turret socket markers. Anchor marker paths can be either:
# 1) direct from layout root, or 2) relative to this root.
@export var anchors_root_path: NodePath = NodePath("Anchors")
# Optional root for thruster socket markers. Thruster marker paths can be either:
# 1) direct from layout root, or 2) relative to this root.
@export var thrusters_root_path: NodePath = NodePath("Thrusters")

@export_category("Model")
@export var model_scene: PackedScene

@export_category("Turret Anchors")
@export var mount_layout_policy: MountLayoutPolicy
@export var stow_anchor_name: StringName = &"StowParking"

@export_category("Shield")
@export var shield: ShipShieldDef

@export_category("Camera")
@export var camera_height: float = 5.0
@export var camera_distance: float = 15.0
@export var camera_angle_deg: float = 0.0
@export var camera_fov: float = 90.0

@export_category("Thrusters")
@export var thrusters: Array[ShipThrusterDef] = []
