extends Resource
class_name StageModifierDef

enum ModifierKind {
	BONUS,
	DEBUFF,
	MIXED,
}

@export_group("Identity")
@export var modifier_id: StringName = &""
@export var display_name: String = "Stage Modifier"
@export_multiline var description: String = ""
@export var kind: ModifierKind = ModifierKind.BONUS

@export_group("Selection")
@export_range(0.0, 100.0, 0.05) var weight: float = 1.0
@export var tags: PackedStringArray = PackedStringArray()

@export_group("Future Gameplay Hooks")
@export var player_modifiers: Array[StatModifier] = []
@export var enemy_modifiers: Array[StatModifier] = []

func get_modifier_id() -> StringName:
	if modifier_id != &"":
		return modifier_id
	if resource_path != "":
		return StringName(resource_path.get_file().get_basename())
	return &"stage_modifier"

func get_display_name_or_default() -> String:
	var trimmed: String = display_name.strip_edges()
	if trimmed != "":
		return trimmed
	var from_id: String = String(get_modifier_id()).replace("_", " ").strip_edges()
	if from_id != "":
		return from_id.capitalize()
	return "Stage Modifier"
