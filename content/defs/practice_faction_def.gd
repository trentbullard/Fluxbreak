extends Resource
class_name PracticeFactionDef

## Enemy identity used for every wave and boss in a generated practice run.
@export var faction: FactionDef
## Three-wave encounter template, including the faction's short boss tuning.
@export var short_run: RunDefinition
## Full deck; equal introduction tiers provide alternate short-run lessons.
@export var wave_cards: Array[WaveCard] = []
## Highest regular enemy tier currently available for this faction.
@export_range(1, 5, 1) var max_enemy_tier: int = 3
## Optional normal-run boss pool; an empty list reuses the short-run boss.
@export var main_boss_pool: Array[EnemyBossDef] = []
## Counterplay instructions that apply throughout the longer practice run.
@export_multiline var combat_hint: String = ""
