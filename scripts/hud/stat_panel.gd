# scripts/hud/stat_panel.gd (godot 4.5)
extends ScrollContainer
class_name StatPanel

const Stat = StatTypes.Stat

# Color constants
const COLOR_BASE: Color = Color.WHITE
const COLOR_NET_POSITIVE: Color = Color(0.4, 1.0, 0.4)  # Green for buffs
const COLOR_NET_NEGATIVE: Color = Color(1.0, 0.4, 0.4)  # Red for debuffs
const COLOR_HEADER: Color = Color(0.7, 0.7, 0.7)
const COLOR_WEAPON_NAME: Color = Color(0.9, 0.8, 0.5)  # Gold for weapon names

@onready var stat_container: VBoxContainer = $StatContainer

var _stat_rows: Dictionary = {}  # stat_id -> { base_label, net_label }
var _turret_sections: Array[Dictionary] = []  # Array of turret UI references
var _ship: Ship = null

# Define which stats to show and their display names
const STAT_DISPLAY_INFO: Array[Dictionary] = [
	# --- Defenses ---
	{ "category": "DEFENSES" },
	{ "stat": Stat.MAX_HULL, "name": "Max Hull", "format": "%.0f" },
	{ "stat": Stat.MAX_SHIELD, "name": "Max Shield", "format": "%.0f" },
	{ "stat": Stat.SHIELD_REGEN, "name": "Shield Regen/s", "format": "%.1f" },
	{ "stat": Stat.EVASION_BASE, "name": "Evasion", "format": "%.0f%%", "is_percent": true },
	{ "stat": Stat.DAMAGE_TAKEN_MULT, "name": "Damage Taken", "format": "%.0f%%", "is_percent": true, "invert": true },
	
	# --- Mobility ---
	{ "category": "MOBILITY" },
	{ "stat": Stat.MAX_SPEED_FORWARD, "name": "Max Speed", "format": "%.0f" },
	{ "stat": Stat.MAX_SPEED_REVERSE, "name": "Reverse Speed", "format": "%.0f" },
	{ "stat": Stat.ACCEL_FORWARD, "name": "Acceleration", "format": "%.0f" },
	{ "stat": Stat.ACCEL_REVERSE, "name": "Reverse Accel", "format": "%.0f" },
	{ "stat": Stat.BOOST_MULT, "name": "Boost Mult", "format": "%.1fx" },
	{ "stat": Stat.DRAG, "name": "Drag", "format": "%.3f", "invert": true },
	
	# --- Rotation ---
	{ "category": "ROTATION" },
	{ "stat": Stat.ANGULAR_RATE_PITCH, "name": "Pitch Rate", "format": "%.0f°/s", "is_radians": true },
	{ "stat": Stat.ANGULAR_RATE_YAW, "name": "Yaw Rate", "format": "%.0f°/s", "is_radians": true },
	{ "stat": Stat.ANGULAR_RATE_ROLL, "name": "Roll Rate", "format": "%.0f°/s", "is_radians": true },
	{ "stat": Stat.ANGULAR_ACCEL_PITCH, "name": "Pitch Accel", "format": "%.0f°/s²", "is_radians": true },
	{ "stat": Stat.ANGULAR_ACCEL_YAW, "name": "Yaw Accel", "format": "%.0f°/s²", "is_radians": true },
	{ "stat": Stat.ANGULAR_ACCEL_ROLL, "name": "Roll Accel", "format": "%.0f°/s²", "is_radians": true },
	
	# --- Utility / Economy ---
	{ "category": "UTILITY" },
	{ "stat": Stat.PICKUP_RANGE, "name": "Pickup Range", "format": "%.0f" },
	{ "stat": Stat.NANOBOT_GAIN_MULT, "name": "Nanobot Gain", "format": "%.0f%%", "is_percent": true },
	{ "stat": Stat.SCORE_GAIN_MULT, "name": "Score Gain", "format": "%.0f%%", "is_percent": true },
]

# Turret stat display info
const TURRET_STAT_INFO: Array[Dictionary] = [
	{ "key": "damage", "name": "Damage", "format": "%.0f - %.0f", "is_range": true },
	{ "key": "fire_rate", "name": "Fire Rate", "format": "%.2fs", "invert": true },
	{ "key": "accuracy", "name": "Accuracy", "format": "%.0f%%", "is_percent": true },
	{ "key": "range", "name": "Range", "format": "%.0f" },
	{ "key": "falloff", "name": "Range Falloff", "format": "%.0f%%", "is_percent": true, "invert": true },
	{ "key": "crit_chance", "name": "Crit Chance", "format": "%.0f%%", "is_percent": true },
	{ "key": "crit_mult", "name": "Crit Mult", "format": "%.1fx" },
	{ "key": "graze_mult", "name": "Graze Mult", "format": "%.0f%%", "is_percent": true },
]

func _ready() -> void:
	_build_stat_rows()

func refresh() -> void:
	_ship = get_tree().get_first_node_in_group("player") as Ship
	if _ship == null:
		return
	_update_all_stats()
	_rebuild_turret_sections()

func _build_stat_rows() -> void:
	for child in stat_container.get_children():
		child.queue_free()
	_stat_rows.clear()
	_turret_sections.clear()
	
	for info in STAT_DISPLAY_INFO:
		if info.has("category"):
			_add_category_header(info["category"])
		elif info.has("stat"):
			_add_stat_row(info)

func _add_category_header(title: String) -> void:
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	# Add some top margin except for first header
	if stat_container.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 8)
		stat_container.add_child(spacer)
	
	stat_container.add_child(header)

func _add_stat_row(info: Dictionary) -> void:
	var stat_id: int = info["stat"]
	var stat_name: String = info["name"]
	
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Stat name label
	var name_label := Label.new()
	name_label.text = stat_name
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_label)
	
	# Base value label (white)
	var base_label := Label.new()
	base_label.add_theme_font_size_override("font_size", 12)
	base_label.add_theme_color_override("font_color", COLOR_BASE)
	base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	base_label.custom_minimum_size = Vector2(60, 0)
	row.add_child(base_label)
	
	# Arrow separator
	var arrow := Label.new()
	arrow.text = " → "
	arrow.add_theme_font_size_override("font_size", 12)
	arrow.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	row.add_child(arrow)
	
	# Net value label (colored based on buff/debuff)
	var net_label := Label.new()
	net_label.add_theme_font_size_override("font_size", 12)
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	net_label.custom_minimum_size = Vector2(60, 0)
	row.add_child(net_label)
	
	stat_container.add_child(row)
	
	_stat_rows[stat_id] = {
		"base_label": base_label,
		"net_label": net_label,
		"info": info,
	}

func _update_all_stats() -> void:
	if _ship == null:
		return
	
	for stat_id in _stat_rows.keys():
		var row_data: Dictionary = _stat_rows[stat_id]
		var info: Dictionary = row_data["info"]
		var base_label: Label = row_data["base_label"]
		var net_label: Label = row_data["net_label"]
		
		var base_value: float = _get_base_value(stat_id)
		var net_value: float = _get_net_value(stat_id)
		
		var format_str: String = info.get("format", "%.1f")
		var is_percent: bool = info.get("is_percent", false)
		var is_radians: bool = info.get("is_radians", false)
		var invert: bool = info.get("invert", false)
		
		var display_base: float = base_value
		var display_net: float = net_value
		
		if is_radians:
			display_base = rad_to_deg(base_value)
			display_net = rad_to_deg(net_value)
		elif is_percent:
			display_base = base_value * 100.0
			display_net = net_value * 100.0
		
		base_label.text = format_str % display_base
		net_label.text = format_str % display_net
		
		# Determine color based on whether this is a buff or debuff
		var color: Color = COLOR_BASE
		if not is_equal_approx(base_value, net_value):
			var is_buff: bool = net_value > base_value
			if invert:
				is_buff = not is_buff  # For stats like "damage taken" or "drag", lower is better
			color = COLOR_NET_POSITIVE if is_buff else COLOR_NET_NEGATIVE
		
		net_label.add_theme_color_override("font_color", color)

func _get_base_value(stat_id: int) -> float:
	if _ship == null:
		return 0.0
	
	match stat_id:
		Stat.MAX_HULL: return _ship.max_hull
		Stat.MAX_SHIELD: return _ship.max_shield
		Stat.SHIELD_REGEN: return _ship.shield_regen
		Stat.EVASION_BASE: return _ship.base_evasion
		Stat.DAMAGE_TAKEN_MULT: return 1.0
		Stat.MAX_SPEED_FORWARD: return _ship.max_speed_forward
		Stat.MAX_SPEED_REVERSE: return _ship.max_speed_reverse
		Stat.ACCEL_FORWARD: return _ship.accel_forward
		Stat.ACCEL_REVERSE: return _ship.accel_reverse
		Stat.BOOST_MULT: return _ship.boost_mult
		Stat.DRAG: return _ship.drag
		Stat.ANGULAR_RATE_PITCH: return _ship.max_ang_rate.x
		Stat.ANGULAR_RATE_YAW: return _ship.max_ang_rate.y
		Stat.ANGULAR_RATE_ROLL: return _ship.max_ang_rate.z
		Stat.ANGULAR_ACCEL_PITCH: return _ship.angular_accel.x
		Stat.ANGULAR_ACCEL_YAW: return _ship.angular_accel.y
		Stat.ANGULAR_ACCEL_ROLL: return _ship.angular_accel.z
		Stat.PICKUP_RANGE: return _ship.pickup_range
		Stat.NANOBOT_GAIN_MULT: return _ship.nanobot_gain_mult
		Stat.SCORE_GAIN_MULT: return _ship.score_gain_mult
	return 0.0

func _get_net_value(stat_id: int) -> float:
	if _ship == null:
		return 0.0
	
	match stat_id:
		Stat.MAX_HULL: return _ship.eff_max_hull
		Stat.MAX_SHIELD: return _ship.eff_max_shield
		Stat.SHIELD_REGEN: return _ship.eff_shield_regen
		Stat.EVASION_BASE: return _ship.eff_evasion
		Stat.DAMAGE_TAKEN_MULT: return _ship.eff_damage_taken_mult
		Stat.MAX_SPEED_FORWARD: return _ship.eff_max_speed_forward
		Stat.MAX_SPEED_REVERSE: return _ship.eff_max_speed_reverse
		Stat.ACCEL_FORWARD: return _ship.eff_accel_forward
		Stat.ACCEL_REVERSE: return _ship.eff_accel_reverse
		Stat.BOOST_MULT: return _ship.eff_boost_mult
		Stat.DRAG: return _ship.eff_drag
		Stat.ANGULAR_RATE_PITCH: return _ship.eff_max_ang_rate.x
		Stat.ANGULAR_RATE_YAW: return _ship.eff_max_ang_rate.y
		Stat.ANGULAR_RATE_ROLL: return _ship.eff_max_ang_rate.z
		Stat.ANGULAR_ACCEL_PITCH: return _ship.eff_angular_accel.x
		Stat.ANGULAR_ACCEL_YAW: return _ship.eff_angular_accel.y
		Stat.ANGULAR_ACCEL_ROLL: return _ship.eff_angular_accel.z
		Stat.PICKUP_RANGE: return _ship.eff_pickup_range
		Stat.NANOBOT_GAIN_MULT: return _ship.eff_nanobot_gain_mult
		Stat.SCORE_GAIN_MULT: return _ship.eff_score_gain_mult
	return 0.0
