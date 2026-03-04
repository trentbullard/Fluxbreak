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

@export var menu_font: FontFile = preload("res://assets/fonts/Oxanium/Oxanium-Regular.ttf")

@onready var stat_container: VBoxContainer = $StatContainer

var _stat_rows: Dictionary = {}  # stat_id -> { base_label, net_label }
var _turret_sections: Array[Dictionary] = []  # Array of turret UI references
var _weapon_ui_nodes: Array[Node] = []  # UI nodes for weapon sections (cleared on rebuild)
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
	{ "stat": Stat.DRAG, "name": "Passive Drag", "format": "%.3f", "invert": true },
	
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

	# --- Pilot ---
	{ "category": "PILOT" },
	{ "stat": Stat.PILOT_G_TOLERANCE, "name": "G Tolerance", "format": "%.1fG" },
	{ "stat": Stat.PILOT_G_HARD_LIMIT, "name": "G Hard Limit", "format": "%.1fG" },
	{ "stat": Stat.PILOT_FORWARD_ACCEL_MIN_SCALE, "name": "Fwd Accel Floor", "format": "%.0f%%", "is_percent": true },
	{ "stat": Stat.PILOT_FORWARD_SPEED_MIN_SCALE, "name": "Fwd Speed Floor", "format": "%.0f%%", "is_percent": true },
	{ "stat": Stat.PILOT_FORWARD_G_FROM_ANG_RATE, "name": "G per Ang Rate", "format": "%.2f", "invert": true },
	{ "stat": Stat.PILOT_FORWARD_G_FROM_ANG_ACCEL, "name": "G per Ang Accel", "format": "%.2f", "invert": true },
	{ "stat": Stat.PILOT_FORWARD_G_SMOOTHING_HZ, "name": "G Smoothing", "format": "%.1fHz" },
	{ "stat": Stat.PILOT_PERCEPTION, "name": "Perception", "format": "%.1f" },
	{ "stat": Stat.PILOT_CHARISMA, "name": "Charisma", "format": "%.1f" },
	{ "stat": Stat.PILOT_INGENUITY, "name": "Ingenuity", "format": "%.1f" },
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
	_apply_menu_font_theme()
	_build_stat_rows()

func _apply_menu_font_theme() -> void:
	if menu_font == null:
		return
	var theme: Theme = Theme.new()
	theme.default_font = menu_font
	self.theme = theme

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
	header.add_theme_font_size_override("font_size", 16)
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
	name_label.add_theme_font_size_override("font_size", 14)
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
		Stat.PILOT_G_TOLERANCE: return _ship.get_pilot_g_tolerance()
		Stat.PILOT_G_HARD_LIMIT: return _ship.get_pilot_g_hard_limit()
		Stat.PILOT_FORWARD_ACCEL_MIN_SCALE: return _ship.get_pilot_forward_accel_min_scale()
		Stat.PILOT_FORWARD_SPEED_MIN_SCALE: return _ship.get_pilot_forward_speed_min_scale()
		Stat.PILOT_FORWARD_G_FROM_ANG_RATE: return _ship.get_pilot_forward_g_from_ang_rate()
		Stat.PILOT_FORWARD_G_FROM_ANG_ACCEL: return _ship.get_pilot_forward_g_from_ang_accel()
		Stat.PILOT_FORWARD_G_SMOOTHING_HZ: return _ship.get_pilot_forward_g_smoothing_hz()
		Stat.PILOT_PERCEPTION: return _ship.get_pilot_perception()
		Stat.PILOT_CHARISMA: return _ship.get_pilot_charisma()
		Stat.PILOT_INGENUITY: return _ship.get_pilot_ingenuity()
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
		Stat.PILOT_G_TOLERANCE: return _ship.get_effective_pilot_g_tolerance()
		Stat.PILOT_G_HARD_LIMIT: return _ship.get_effective_pilot_g_hard_limit()
		Stat.PILOT_FORWARD_ACCEL_MIN_SCALE: return _ship.get_effective_pilot_forward_accel_min_scale()
		Stat.PILOT_FORWARD_SPEED_MIN_SCALE: return _ship.get_effective_pilot_forward_speed_min_scale()
		Stat.PILOT_FORWARD_G_FROM_ANG_RATE: return _ship.get_effective_pilot_forward_g_from_ang_rate()
		Stat.PILOT_FORWARD_G_FROM_ANG_ACCEL: return _ship.get_effective_pilot_forward_g_from_ang_accel()
		Stat.PILOT_FORWARD_G_SMOOTHING_HZ: return _ship.get_effective_pilot_forward_g_smoothing_hz()
		Stat.PILOT_PERCEPTION: return _ship.get_effective_pilot_perception()
		Stat.PILOT_CHARISMA: return _ship.get_effective_pilot_charisma()
		Stat.PILOT_INGENUITY: return _ship.get_effective_pilot_ingenuity()
	return 0.0

# --- Weapon Stats Collection ---

## Collected weapon stats for each turret. Populated by _rebuild_turret_sections().
## Each entry is a Dictionary with:
##   - weapon: WeaponDef (or null)
##   - display_name: String
##   - mount_index: int
##   - base: Dictionary of base stat values from WeaponDef
##   - effective: Dictionary of effective stat values from PlayerTurret
var _collected_weapon_stats: Array[Dictionary] = []

func get_collected_weapon_stats() -> Array[Dictionary]:
	"""Returns the collected weapon stats for external use (e.g., UI building)."""
	return _collected_weapon_stats.duplicate()

func _rebuild_turret_sections() -> void:
	"""Collects weapon stats from all turrets on the player ship and builds UI."""
	_collected_weapon_stats.clear()
	_turret_sections.clear()
	
	# Clear previous weapon UI nodes
	for node in _weapon_ui_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_weapon_ui_nodes.clear()
	
	if _ship == null:
		return
	
	var hpm: TurretHardpointManager = _ship.hardpoint_manager
	if hpm == null:
		return
	
	var assemblies: Array[TurretAssembly] = hpm.get_turret_assemblies()
	
	# Add weapons header
	if not assemblies.is_empty():
		_add_weapons_header()
	
	for assembly in assemblies:
		if assembly == null or not assembly.has_weapon():
			continue
		
		var turret: PlayerTurret = assembly.turret
		if turret == null:
			continue
		
		var weapon: WeaponDef = turret.get_weapon()
		if weapon == null:
			continue
		
		var weapon_data: Dictionary = _collect_weapon_stats(weapon, turret, assembly.mount_index)
		_collected_weapon_stats.append(weapon_data)
		
		# Build UI for this weapon
		_add_weapon_section(weapon_data)

		# Store reference for potential UI updates later
		_turret_sections.append({
			"assembly": assembly,
			"turret": turret,
			"weapon": weapon,
			"data": weapon_data,
		})

func _add_weapons_header() -> void:
	"""Adds a 'WEAPONS' category header."""
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	stat_container.add_child(spacer)
	_weapon_ui_nodes.append(spacer)
	
	var header := Label.new()
	header.text = "WEAPONS"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", COLOR_HEADER)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stat_container.add_child(header)
	_weapon_ui_nodes.append(header)

func _add_weapon_section(weapon_data: Dictionary) -> void:
	"""Adds UI elements for a single weapon's stats."""
	var display_name: String = weapon_data["display_name"]
	var base: Dictionary = weapon_data["base"]
	var effective: Dictionary = weapon_data["effective"]
	
	# Weapon name sub-header
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	stat_container.add_child(spacer)
	_weapon_ui_nodes.append(spacer)
	
	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", COLOR_WEAPON_NAME)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stat_container.add_child(name_label)
	_weapon_ui_nodes.append(name_label)
	
	# Add stat rows for each turret stat
	for info in TURRET_STAT_INFO:
		var row: HBoxContainer = _create_weapon_stat_row(info, base, effective)
		stat_container.add_child(row)
		_weapon_ui_nodes.append(row)

func _create_weapon_stat_row(info: Dictionary, base: Dictionary, effective: Dictionary) -> HBoxContainer:
	"""Creates a single stat row for weapon stats."""
	var key: String = info["key"]
	var stat_name: String = info["name"]
	var format_str: String = info.get("format", "%.1f")
	var is_percent: bool = info.get("is_percent", false)
	var is_range: bool = info.get("is_range", false)
	var invert: bool = info.get("invert", false)
	
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Stat name label (indented)
	var name_label := Label.new()
	name_label.text = "  " + stat_name
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_label)
	
	# Get base and effective values
	var base_val_1: float = 0.0
	var base_val_2: float = 0.0
	var eff_val_1: float = 0.0
	var eff_val_2: float = 0.0
	
	if is_range:
		# Damage range uses min/max
		base_val_1 = base.get("damage_min", 0.0)
		base_val_2 = base.get("damage_max", 0.0)
		eff_val_1 = effective.get("damage_min", 0.0)
		eff_val_2 = effective.get("damage_max", 0.0)
	else:
		base_val_1 = base.get(key, 0.0)
		eff_val_1 = effective.get(key, 0.0)
	
	# Apply percent conversion
	if is_percent:
		base_val_1 *= 100.0
		base_val_2 *= 100.0
		eff_val_1 *= 100.0
		eff_val_2 *= 100.0
	
	# Base value label
	var base_label := Label.new()
	base_label.add_theme_font_size_override("font_size", 12)
	base_label.add_theme_color_override("font_color", COLOR_BASE)
	base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	base_label.custom_minimum_size = Vector2(70, 0)
	if is_range:
		base_label.text = format_str % [base_val_1, base_val_2]
	else:
		base_label.text = format_str % base_val_1
	row.add_child(base_label)
	
	# Arrow separator
	var arrow := Label.new()
	arrow.text = " → "
	arrow.add_theme_font_size_override("font_size", 12)
	arrow.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	row.add_child(arrow)
	
	# Net value label
	var net_label := Label.new()
	net_label.add_theme_font_size_override("font_size", 12)
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	net_label.custom_minimum_size = Vector2(70, 0)
	if is_range:
		net_label.text = format_str % [eff_val_1, eff_val_2]
	else:
		net_label.text = format_str % eff_val_1
	
	# Determine color based on buff/debuff
	var color: Color = COLOR_BASE
	var base_compare: float = base_val_1 if not is_range else (base_val_1 + base_val_2)
	var eff_compare: float = eff_val_1 if not is_range else (eff_val_1 + eff_val_2)
	
	if not is_equal_approx(base_compare, eff_compare):
		var is_buff: bool = eff_compare > base_compare
		if invert:
			is_buff = not is_buff
		color = COLOR_NET_POSITIVE if is_buff else COLOR_NET_NEGATIVE
	
	net_label.add_theme_color_override("font_color", color)
	row.add_child(net_label)
	
	return row

func _collect_weapon_stats(weapon: WeaponDef, turret: PlayerTurret, mount_index: int) -> Dictionary:
	"""Collects base and effective stats for a single weapon/turret pair."""
	var base_stats: Dictionary = _get_weapon_base_stats(weapon)
	var effective_stats: Dictionary = _get_turret_effective_stats(turret)
	
	return {
		"weapon": weapon,
		"display_name": weapon.display_name if weapon.display_name != "" else weapon.weapon_id,
		"mount_index": mount_index,
		"base": base_stats,
		"effective": effective_stats,
	}

func _get_weapon_base_stats(weapon: WeaponDef) -> Dictionary:
	"""Extracts base stat values directly from the WeaponDef."""
	return {
		"damage_min": weapon.damage_min,
		"damage_max": weapon.damage_max,
		"fire_rate": weapon.fire_rate,
		"accuracy": weapon.base_accuracy,
		"range": weapon.base_range,
		"falloff": weapon.accuracy_range_falloff,
		"crit_chance": weapon.crit_chance,
		"crit_mult": weapon.crit_mult,
		"graze_on_hit": weapon.graze_on_hit,
		"graze_on_miss": weapon.graze_on_miss,
		"graze_mult": weapon.graze_mult,
	}

func _get_turret_effective_stats(turret: PlayerTurret) -> Dictionary:
	"""Extracts effective (modified) stat values from the PlayerTurret."""
	return {
		"damage_min": turret.eff_damage_min,
		"damage_max": turret.eff_damage_max,
		"fire_rate": turret.eff_fire_rate,
		"accuracy": turret.eff_base_accuracy,
		"range": turret.eff_base_range,
		"falloff": turret.eff_range_falloff,
		"crit_chance": turret.eff_crit_chance,
		"crit_mult": turret.eff_crit_mult,
		"graze_on_hit": turret.eff_graze_on_hit,
		"graze_on_miss": turret.eff_graze_on_miss,
		"graze_mult": turret.eff_graze_mult,
		"range_bonus": turret.eff_range_bonus_add,
		"systems_bonus": turret.eff_systems_bonus_add,
		"projectile_speed": turret.eff_projectile_speed,
		"projectile_life": turret.eff_projectile_life,
		"projectile_spread": turret.eff_projectile_spread_deg,
	}
