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
@export var wave_card: WaveCard
@export var wave_index: int = 0
@export var stage_index: int = 0
@export var elapsed_sec: float = 0.0
@export var is_elite: bool = false
@export var affix_ids: PackedStringArray = PackedStringArray()

func build_enemy_spawn_context(def_override: EnemyDef = null) -> EnemySpawnContext:
	var resolved_def: EnemyDef = def_override if def_override != null else enemy_def
	var context: EnemySpawnContext = EnemySpawnContext.from_enemy_def(resolved_def)
	context.wave_index = wave_index
	context.stage_index = stage_index
	context.elapsed_sec = elapsed_sec
	context.wave_card = wave_card
	context.is_elite = is_elite
	context.affix_ids = PackedStringArray(affix_ids)
	if wave_card != null:
		context.source_tags = PackedStringArray(wave_card.tags)
	return context
