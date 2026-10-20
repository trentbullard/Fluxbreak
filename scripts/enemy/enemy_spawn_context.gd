extends RefCounted
class_name EnemySpawnContext

var wave_index: int = 0
var stage_index: int = 0
var elapsed_sec: float = 0.0
var wave_card: WaveCard = null
var faction: FactionDef = null
var role: EnemyRoleDef = null
var enemy_combat_scaling: EnemyCombatScalingSnapshot = null
var is_elite: bool = false
var affix_ids: PackedStringArray = PackedStringArray()
var source_tags: PackedStringArray = PackedStringArray()
## Spawned brood never creates another generation of summoners.
var is_summoned: bool = false
## Whether death grants nanobots, score, and progression kill credit.
var grants_kill_rewards: bool = true
## Whether a kill contributes to adaptive wave pressure measurements.
var contributes_to_pressure: bool = true

static func from_enemy_def(def: EnemyDef) -> EnemySpawnContext:
	var context: EnemySpawnContext = EnemySpawnContext.new()
	if def == null:
		return context
	context.faction = def.faction
	context.role = def.role
	return context

func duplicate_context() -> EnemySpawnContext:
	var context: EnemySpawnContext = EnemySpawnContext.new()
	context.wave_index = wave_index
	context.stage_index = stage_index
	context.elapsed_sec = elapsed_sec
	context.wave_card = wave_card
	context.faction = faction
	context.role = role
	context.enemy_combat_scaling = enemy_combat_scaling
	context.is_elite = is_elite
	context.affix_ids = PackedStringArray(affix_ids)
	context.source_tags = PackedStringArray(source_tags)
	context.is_summoned = is_summoned
	context.grants_kill_rewards = grants_kill_rewards
	context.contributes_to_pressure = contributes_to_pressure
	return context
