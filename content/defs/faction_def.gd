extends Resource
class_name FactionDef

@export_group("Identity")
@export var faction_id: StringName = &""
@export var display_name: String = "Faction"
@export_multiline var description: String = ""
@export var tags: PackedStringArray = PackedStringArray()

func get_faction_id() -> StringName:
	if faction_id != &"":
		return faction_id
	if resource_path != "":
		return StringName(resource_path.get_file().get_basename())
	return &"faction"

func get_display_name_or_default() -> String:
	var trimmed: String = display_name.strip_edges()
	if trimmed != "":
		return trimmed
	var from_id: String = String(get_faction_id()).replace("_", " ").strip_edges()
	if from_id != "":
		return from_id.capitalize()
	return "Faction"
