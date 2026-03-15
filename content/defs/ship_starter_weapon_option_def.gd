extends Resource
class_name ShipStarterWeaponOptionDef

enum UnlockRequirementMode {
	ALL,
	ANY,
}

@export var weapon: WeaponDef
@export var sort_order: int = 0
@export var starts_unlocked: bool = true
@export var unlock_requirement_mode: UnlockRequirementMode = UnlockRequirementMode.ALL
@export var unlock_requirements: Array[UnlockRequirement] = []
@export var display_name_override: String = ""

func is_selectable() -> bool:
	return weapon != null

func get_weapon_id() -> StringName:
	if weapon == null:
		return &""
	return weapon.get_weapon_id()

func get_display_name_or_default() -> String:
	var trimmed: String = display_name_override.strip_edges()
	if trimmed != "":
		return trimmed
	if weapon != null:
		return weapon.get_display_name_or_default()
	return "Weapon"
