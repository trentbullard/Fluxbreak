# content/defs/enemy_def.gd (godot 4.5)
extends Resource
class_name EnemyDef

@export_group("Meta Attributes")
@export var id: String = ""               # e.g. "machine_drone_mk1"
@export var display_name: String = ""
@export var faction: String = ""          # see below
@export var role: String = ""             # see below
@export var tier: int = 1                 # 1..5
@export var threat_cost: int = 1
@export var bounty_scrap: int = 1         # economy faucet
@export var can_be_elite: bool = true     # whether to apply an affix
@export var affixes: Array[String] = []   # see below

@export_group("Rewards")
@export var score_on_kill: int = 10

@export_group("Defense")
@export var max_hull: float = 20.0
@export var max_shield: float = 0.0
@export var shield_regen: float = 0.0
@export var evasion: float = 0.10
@export var thrust: float = 40.0

@export_group("Offense")
@export var weapon: WeaponDef
@export var team_id: int = 1              # optional, for IFF/targeting groups

@export_group("Visual")
@export var model_scene: PackedScene      # optional model override
@export var material: StandardMaterial3D  # optional single material to apply to all meshes
