extends Resource
class_name EnemyRoleDef

@export_group("Identity")
@export var role_id: StringName = &""
@export var display_name: String = "Role"
@export_multiline var description: String = ""
@export var tags: PackedStringArray = PackedStringArray()

func get_role_id() -> StringName:
	if role_id != &"":
		return role_id
	if resource_path != "":
		return StringName(resource_path.get_file().get_basename())
	return &"enemy_role"

func get_display_name_or_default() -> String:
	var trimmed: String = display_name.strip_edges()
	if trimmed != "":
		return trimmed
	var from_id: String = String(get_role_id()).replace("_", " ").strip_edges()
	if from_id != "":
		return from_id.capitalize()
	return "Role"
