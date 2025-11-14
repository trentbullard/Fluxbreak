# content/defs/target_def.gd  (Godot 4.5)
extends Resource
class_name TargetDef

@export var id: String = ""                  # "asteroid_small"
@export var display_name: String = "Target"
@export var size_band: int = 1               # 1..3, optional
@export var threat_cost: int = 1
@export var bounty_scrap: int = 1
@export var hazard_tag: String = ""          # "explosive", "radiation", etc.

# --- gameplay knobs ---
@export var max_hull: float = 20.0
@export var max_shield: float = 0.0
@export var shield_regen: float = 0.0
@export var score_on_kill: int = 5
@export var lifetime: float = 0.0            # 0.0 = infinite
@export var angular_spin: Vector3
@export var drift: Vector3

# --- visuals (optional) ---
@export var model_scene: PackedScene         # swap mesh for specific target types
@export var material: StandardMaterial3D     # one-and-done override for all meshes
@export var emission_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var emission_energy: float = 0.0
