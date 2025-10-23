# systems/spawning/spawn_request.gd (godot 4.5)
extends Resource
class_name SpawnRequest

@export var kind: String = "Enemy"              # "Enemy" | "Target"
@export var enemy_def: EnemyDef
@export var target_def: TargetDef
@export var count: int = 1
@export var batch_size_min: int = 2
@export var batch_size_max: int = 4
@export var inter_batch_sec: float = 0.7
