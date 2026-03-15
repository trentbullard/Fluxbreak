# content/defs/pilot_def.gd (Godot 4.5)
extends Resource
class_name PilotDef

enum UnlockRequirementMode {
	ALL,
	ANY,
}

@export var id: StringName = &""
@export var display_name: String = "Pilot"
@export_multiline var description: String = ""

@export var enabled: bool = true
@export var sort_order: int = 0
@export var starts_unlocked: bool = true
@export var unlock_requirement_mode: UnlockRequirementMode = UnlockRequirementMode.ALL
@export var unlock_requirements: Array[PilotUnlockRequirement] = []

@export var ship: ShipDef
@export var starter_ship_options: Array[PilotStarterShipOptionDef] = []
@export var loadout_override: ShipLoadoutDef
@export var mount_layout_policy_override: MountLayoutPolicy

# Forward-load tolerance (pilot physiology / training).
# These values limit forward accel and forward max speed while turning hard.
@export var forward_g_tolerance: float = 6.0
@export var forward_g_hard_limit: float = 10.0
@export_range(0.0, 1.0, 0.01) var forward_accel_min_scale: float = 0.35
@export_range(0.0, 1.0, 0.01) var forward_speed_min_scale: float = 0.55
@export var forward_g_from_ang_rate: float = 3.0
@export var forward_g_from_ang_accel: float = 3.0
@export var forward_g_smoothing_hz: float = 8.0

@export var perception: float = 5.0
@export var charisma: float = 5.0
@export var ingenuity: float = 5.0

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

func is_selectable() -> bool:
	return enabled and ship != null
