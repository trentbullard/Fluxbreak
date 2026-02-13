# content/defs/pilot_unlock_requirement.gd (Godot 4.5)
extends Resource
class_name PilotUnlockRequirement

enum PilotStat {
	HIGHEST_SCORE,
	LONGEST_RUN_SECONDS,
	DEATH_RUNS,
	TOTAL_NANOBOTS_IN_RUN,
	HIGHEST_NANOBOTS_IN_RUN,
	HIGHEST_WAVE_REACHED,
}

@export var stat: PilotStat = PilotStat.HIGHEST_WAVE_REACHED
@export_range(0, 1000000000, 1) var minimum_value: int = 1
@export var source_pilot_id: StringName = &""
