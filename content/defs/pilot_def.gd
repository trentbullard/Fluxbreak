# content/defs/pilot_def.gd (Godot 4.5)
extends Resource
class_name PilotDef

@export var id: StringName = &""
@export var display_name: String = "Pilot"
@export_multiline var description: String = ""

@export var enabled: bool = true
@export var sort_order: int = 0

@export var ship: ShipDef
@export var loadout_override: ShipLoadoutDef
@export_range(-1, 16, 1) var starting_weapons_override: int = -1
@export var mount_layout_policy_override: MountLayoutPolicy

@export var starting_upgrades: Array[Upgrade] = []
@export var stat_modifiers: Array[StatModifier] = []

func get_pilot_id() -> StringName:
	if id != &"":
		return id
	if resource_path != "":
		return StringName(resource_path.get_file().get_basename())
	return &"pilot"

func get_display_name_or_default() -> String:
	var trimmed: String = display_name.strip_edges()
	if trimmed != "":
		return trimmed
	var from_id: String = String(get_pilot_id()).replace("_", " ").strip_edges()
	if from_id != "":
		return from_id.capitalize()
	return "Pilot"

func get_effective_starting_weapons(base_value: int) -> int:
	if starting_weapons_override >= 0:
		return starting_weapons_override
	return base_value

func is_selectable() -> bool:
	return enabled and ship != null
