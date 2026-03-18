extends Resource
class_name UnlockRequirement

enum UnlockStat {
	HIGHEST_SCORE,
	LONGEST_RUN_SECONDS,
	DEATH_RUNS,
	TOTAL_NANOBOTS_IN_RUN,
	HIGHEST_NANOBOTS_IN_RUN,
	HIGHEST_WAVE_REACHED,
	KILLS,
	DAMAGE_DEALT,
	DAMAGE_TAKEN,
}

enum WeaponContext {
	DIRECT,
	EQUIPPED,
}

@export var stat: UnlockStat = UnlockStat.HIGHEST_WAVE_REACHED
@export_range(0, 1000000000, 1) var minimum_value: int = 1
@export var source_pilot_id: StringName = &""
@export var ship_id: StringName = &""
@export var weapon_id: StringName = &""
@export var weapon_context: WeaponContext = WeaponContext.DIRECT
@export var enemy_id: StringName = &""
@export var faction_id: StringName = &""
@export var role_id: StringName = &""
