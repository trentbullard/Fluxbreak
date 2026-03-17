# content/defs/wave_card.gd (godot 4.5)
extends Resource
class_name WaveCard

@export var card_id: String = ""
@export var display_name: String = "Wave"
@export_range(0.0, 10.0, 0.05) var weight: float = 1.0
@export var faction_bias: String = ""           # "" = any
@export var role_bias: String = ""              # primary role bias, "" = any
@export var secondary_role_bias: String = ""
@export var support_role_bias: String = ""
@export_range(0.0, 1.0, 0.01) var primary_budget_share: float = 0.60
@export_range(0.0, 1.0, 0.01) var secondary_budget_share: float = 0.25
@export_range(0.0, 1.0, 0.01) var support_budget_share: float = 0.15
@export_range(0.0, 1.0, 0.01) var in_wave_target_budget_scale: float = 0.20
@export var downtime_target_point_budget: int = 2
@export var pressure_enemy_point_budget: int = 2
@export var pressure_target_point_budget: int = 0
@export var target_size_band_max: int = 2
@export var package_count_min: int = 2
@export var package_count_max: int = 4
@export var batch_size_min: int = 2
@export var batch_size_max: int = 4
@export var inter_batch_sec: float = 0.7
@export var enemy_first_bias: float = 0.65      # 0..1
@export_range(0.2, 1.0, 0.01) var max_primary_budget_share: float = 0.55
@export var anchor_support_cost_threshold: int = 8
@export var allow_swarm_primary: bool = false
@export var allow_pressure_spikes: bool = true
@export var primary_repeat_cooldown: int = 2
@export var card_repeat_cooldown: int = 1
@export var tags: Array[String] = []

func get_card_id() -> StringName:
	var trimmed: String = card_id.strip_edges()
	if trimmed != "":
		return StringName(trimmed)
	var display_trimmed: String = display_name.strip_edges()
	if display_trimmed != "":
		return StringName(display_trimmed.to_lower().replace(" ", "_"))
	if resource_path != "":
		return StringName(resource_path.get_file().get_basename())
	return &"wave_card"

func get_display_name_or_default() -> String:
	var trimmed: String = display_name.strip_edges()
	if trimmed != "":
		return trimmed
	var from_id: String = String(get_card_id()).replace("_", " ").strip_edges()
	if from_id != "":
		return from_id.capitalize()
	return "Wave"

func get_role_biases() -> Array[String]:
	var roles: Array[String] = []
	if role_bias.strip_edges() != "":
		roles.append(role_bias.strip_edges())
	if secondary_role_bias.strip_edges() != "":
		roles.append(secondary_role_bias.strip_edges())
	if support_role_bias.strip_edges() != "":
		roles.append(support_role_bias.strip_edges())
	return roles

func get_budget_shares() -> Array[float]:
	var shares: Array[float] = [
		max(primary_budget_share, 0.0),
		max(secondary_budget_share, 0.0),
		max(support_budget_share, 0.0),
	]
	var total: float = 0.0
	for share in shares:
		total += share
	if total <= 0.0:
		return [1.0, 0.0, 0.0]
	return [
		shares[0] / total,
		shares[1] / total,
		shares[2] / total,
	]

func has_tag(tag: String) -> bool:
	var wanted: String = tag.strip_edges().to_lower()
	if wanted == "":
		return false
	for entry in tags:
		if entry.strip_edges().to_lower() == wanted:
			return true
	return false
