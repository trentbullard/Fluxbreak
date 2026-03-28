extends EnemyDef
class_name EnemyBossDef

@export_group("Boss")
@export_multiline var boss_description: String = ""
@export var boss_theme: AudioStream
@export var movement_def: BossMovementDef

func get_boss_description_or_default() -> String:
	var trimmed: String = boss_description.strip_edges()
	if trimmed != "":
		return trimmed
	return get_display_name_or_default()
