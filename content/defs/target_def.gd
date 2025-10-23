# content/defs/enemy_def.gd (godot 4.5)
extends Resource
class_name TargetDef

@export var id: String = ""                         # e.g. "asteroid_small"
@export var display_name: String = "Small Asteroid"
@export var size_band: int = 1                      # 1=small, 2=med, 3=large
@export var threat_cost: int = 1                    # budget for targets use these too
@export var bounty_scrap: int = 1                   # economy faucet
@export var hazard_tag: String = ""                 # optional: "explosive", etc.
