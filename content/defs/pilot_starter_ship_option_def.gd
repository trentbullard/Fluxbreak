extends Resource
class_name PilotStarterShipOptionDef

enum UnlockRequirementMode {
	ALL,
	ANY,
}

@export var ship: ShipDef
@export var sort_order: int = 0
@export var starts_unlocked: bool = true
@export var unlock_requirement_mode: UnlockRequirementMode = UnlockRequirementMode.ALL
@export var unlock_requirements: Array[UnlockRequirement] = []
@export var display_name_override: String = ""

func is_selectable() -> bool:
	return ship != null

func get_ship_id() -> StringName:
	if ship == null:
		return &""
	return ship.get_ship_id()

func get_display_name_or_default() -> String:
	var trimmed: String = display_name_override.strip_edges()
	if trimmed != "":
		return trimmed
	if ship != null:
		return ship.get_display_name_or_default()
	return "Ship"
