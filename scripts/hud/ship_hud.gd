# ship_hud.gd  (Godot 4.5)
extends Control
class_name ShipHud

const WEAPON_CHIP_FONT: FontFile = preload("res://assets/fonts/Oxanium/Oxanium-Medium.ttf")
const HUD_FONT_REGULAR: FontFile = preload("res://assets/fonts/Oxanium/Oxanium-Regular.ttf")
const HUD_FONT_MEDIUM: FontFile = preload("res://assets/fonts/Oxanium/Oxanium-Medium.ttf")
const HUD_CENTER_FRAME: Texture2D = preload("res://content/ui/hud/ship_hud_center_frame.svg")
const WEAPON_CHIP_SCENE: PackedScene = preload("res://scenes/hud/weapon_chip.tscn")
const DRONE_CHARGE_VALUES_PER_LINE: int = 4
const HUD_BASE_VIEWPORT_WIDTH: float = 1920.0
const HUD_BASE_VIEWPORT_HEIGHT: float = 1080.0
const HUD_DESIGN_WIDTH: float = 620.0
const HUD_DESIGN_HEIGHT: float = 320.0
const HUD_MIN_HEIGHT: float = 336.0
const HUD_SEGMENT_COUNT: int = 7
const HUD_SPEED_SEGMENTS_REVERSE: int = 4
const HUD_SPEED_SEGMENTS_FORWARD: int = 8
const HUD_SPEED_REVERSE_WIDTH_RATIO: float = 0.3
const HUD_PANEL_BG: Color = Color(0.04, 0.06, 0.09, 0.8)
const HUD_PANEL_STROKE: Color = Color(0.36, 0.42, 0.5, 0.92)
const HUD_TEXT_DIM: Color = Color(0.72, 0.77, 0.85, 0.92)
const HUD_SPEED_REVERSE: Color = Color(1.0, 0.53, 0.24, 0.95)
const HUD_SPEED_FORWARD: Color = Color(0.25, 0.82, 1.0, 0.98)
const HUD_NANOBOT_COLOR: Color = Color(0.76, 0.92, 0.28, 0.98)
const HUD_HULL_TITLE_COLOR: Color = Color(0.28, 1.0, 0.42, 0.98)
const WEAPON_CHIP_WIDTH: float = 148.0
const WEAPON_CHIP_HEIGHT: float = 64.0
const WEAPON_CHIP_MAX_COLUMNS: int = 4
const WEAPON_CHIP_H_SEPARATION: float = 6.0
const WEAPON_CHIP_V_SEPARATION: float = 4.0

@export var shield_color: Color = Color(0.2, 0.6, 1.0)
@export var hull_color: Color = Color(1.0, 0.22, 0.22, 1.0)
@export var back_color: Color = Color(0, 0, 0, 0.6)
@export var repair_color: Color = Color(0.95, 0.2, 0.2, 0.95)
@export var ui_hz: float = 20.0

var _ship: Ship
var _accum: float = 0.0
var _last_weapon_layout_signature: String = ""
var _weapon_chip_nodes: Array[WeaponChip] = []
var _display_hull: float = 100.0
var _display_hull_max: float = 100.0
var _display_shield: float = 100.0
var _display_shield_max: float = 100.0
var _display_forward_speed: float = 0.0
var _display_forward_max: float = 100.0
var _display_reverse_max: float = 60.0
var _display_nanobots: int = 0
var _hud_scale: float = 0.82
var _hud_frame_rect: Rect2 = Rect2()
var _ability_frame_rect: Rect2 = Rect2()
var _weapons_frame_rect: Rect2 = Rect2()
var _hull_title_overlay: Label
var _hull_value_overlay: Label
var _shield_title_overlay: Label
var _shield_value_overlay: Label
var _speed_tag_overlay: Label
var _speed_value_overlay: Label
var _max_tag_overlay: Label
var _max_value_overlay: Label
var _nanobot_tag_overlay: Label
var _nanobot_value_overlay: Label

@onready var _abilities_container: HBoxContainer = $AbilitiesContainer
@onready var _shield_bar: ProgressBar = $ShipStatsContainer/ShieldHullContainer/Shield/Bar
@onready var _shield_val: Label = $ShipStatsContainer/ShieldHullContainer/Shield/Value
@onready var _hull_bar: ProgressBar = $ShipStatsContainer/ShieldHullContainer/Hull/Bar
@onready var _hull_val: Label = $ShipStatsContainer/ShieldHullContainer/Hull/Value
@onready var _vel_val: Label = $ShipStatsContainer/VelocityContainer/Label
@onready var _ship_stats_container: VBoxContainer = $ShipStatsContainer
@onready var _weapons_container: HFlowContainer = $WeaponsContainer
@onready var _repair_label: Label = $AbilitiesContainer/RepairPanel/RepairLabel
@onready var _repair_hotkey_label: Label = $AbilitiesContainer/RepairPanel/HotkeyLabel
@onready var _repair_cooldown_label: Label = $AbilitiesContainer/RepairPanel/CooldownLabel

const ACTION_HULL_REPAIR: StringName = &"hull_repair"

const CONTROLLER_XBOX: StringName = &"xbox"
const CONTROLLER_PLAYSTATION: StringName = &"playstation"
const CONTROLLER_NINTENDO: StringName = &"nintendo"
const CONTROLLER_GENERIC: StringName = &"generic"

const BUTTON_LABELS_XBOX: Dictionary = {
	0: "A",
	1: "B",
	2: "X",
	3: "Y",
	4: "LB",
	5: "RB",
	6: "View",
	7: "Menu",
	8: "LS",
	9: "RS",
	10: "Guide",
	11: "D-Up",
	12: "D-Down",
	13: "D-Left",
	14: "D-Right",
}

const BUTTON_LABELS_PLAYSTATION: Dictionary = {
	0: "Cross",
	1: "Circle",
	2: "Square",
	3: "Triangle",
	4: "L1",
	5: "R1",
	6: "Share",
	7: "Options",
	8: "L3",
	9: "R3",
	10: "PS",
	11: "D-Up",
	12: "D-Down",
	13: "D-Left",
	14: "D-Right",
}

const BUTTON_LABELS_NINTENDO: Dictionary = {
	0: "B",
	1: "A",
	2: "Y",
	3: "X",
	4: "L",
	5: "R",
	6: "-",
	7: "+",
	8: "LS",
	9: "RS",
	10: "Home",
	11: "D-Up",
	12: "D-Down",
	13: "D-Left",
	14: "D-Right",
}

const BUTTON_LABELS_GENERIC: Dictionary = {
	0: "South",
	1: "East",
	2: "West",
	3: "North",
	4: "L1",
	5: "R1",
	6: "Back",
	7: "Start",
	8: "LS",
	9: "RS",
	10: "Guide",
	11: "D-Up",
	12: "D-Down",
	13: "D-Left",
	14: "D-Right",
}

var _prefer_controller_prompt: bool = false
var _active_controller_device: int = -1

func init(ship: Node3D) -> void:
	_ship = ship as Ship
	_update_repair_widget_text()
	_update_repair_cooldown_ui()
	_refresh_weapons_ui(true)
	_sync_future_display_state()
	_update_future_labels()
	_layout_future_overlay()
	queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(0.0, HUD_MIN_HEIGHT)
	_style_bar(_shield_bar, shield_color)
	_style_bar(_hull_bar, hull_color)
	_update_repair_widget_text()
	_update_repair_cooldown_ui()
	_update_repair_hotkey_prompt()
	_refresh_weapons_ui(true)
	_ship_stats_container.visible = false
	_ensure_future_overlay_labels()
	_sync_future_display_state()
	_update_future_labels()
	_layout_future_overlay()
	if EventBus != null and EventBus.has_signal("weapons_changed"):
		if not EventBus.weapons_changed.is_connected(_on_weapons_changed):
			EventBus.weapons_changed.connect(_on_weapons_changed)

	if Input.has_signal("joy_connection_changed"):
		if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
			Input.joy_connection_changed.connect(_on_joy_connection_changed)
	
	if RunState != null and RunState.has_signal("nanobots_updated"):
		if not RunState.nanobots_updated.is_connected(_on_nanobots_updated):
			RunState.nanobots_updated.connect(_on_nanobots_updated)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_future_overlay()
		queue_redraw()

func _input(event: InputEvent) -> void:
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null and joy_button.pressed:
		_prefer_controller_prompt = true
		_active_controller_device = joy_button.device
		_update_repair_hotkey_prompt()
		return

	var joy_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if joy_motion != null and absf(joy_motion.axis_value) >= 0.5:
		_prefer_controller_prompt = true
		_active_controller_device = joy_motion.device
		_update_repair_hotkey_prompt()
		return

	var key_event: InputEventKey = event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo:
		if _prefer_controller_prompt:
			_prefer_controller_prompt = false
			_update_repair_hotkey_prompt()
		return

	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button != null and mouse_button.pressed and _prefer_controller_prompt:
		_prefer_controller_prompt = false
		_update_repair_hotkey_prompt()
		return

	var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
	if mouse_motion != null and _prefer_controller_prompt and mouse_motion.relative.length_squared() > 0.0:
		_prefer_controller_prompt = false
		_update_repair_hotkey_prompt()

func _process(delta: float) -> void:
	_accum += delta
	if _accum < 1.0 / max(ui_hz, 1.0):
		return
	_accum = 0.0
	_update_values()

func _update_values() -> void:
	if _ship == null:
		return
	_refresh_weapons_ui()

	var shield_pair: Array = _read_pair("shield", "eff_max_shield", 100.0, 100.0)
	var shield: float = shield_pair[0]
	var shield_max: float = shield_pair[1]

	var hull_pair: Array = _read_pair("hull", "eff_max_hull", 100.0, 100.0)
	var hull: float = hull_pair[0]
	var hull_max: float = hull_pair[1]
	_update_repair_cooldown_ui()
	
	_apply_bar(_shield_bar, _shield_val, shield, shield_max)
	_apply_bar(_hull_bar, _hull_val, hull, hull_max)
	
	var fwd_speed: float = _ship.linear_velocity.dot(-_ship.transform.basis.z)
	var max_fwd: float = 100.0
	var max_rev: float = 60.0
	var caps: Vector2 = _ship.get_speed_caps()
	max_rev = max(caps.x, 1.0)
	max_fwd = max(caps.y, 1.0)
	
	_apply_speed(_vel_val, fwd_speed, max_fwd)
	_display_hull = max(hull, 0.0)
	_display_hull_max = hull_max
	_display_shield = shield
	_display_shield_max = shield_max
	_display_forward_speed = fwd_speed
	_display_forward_max = max_fwd
	_display_reverse_max = max_rev
	_display_nanobots = _ship.get_nanobots()
	_update_future_labels()
	queue_redraw()

func _on_weapons_changed(_weapons: Array[WeaponDef]) -> void:
	_refresh_weapons_ui(true)

func _on_nanobots_updated(amount: int) -> void:
	_display_nanobots = amount
	_update_future_labels()
	queue_redraw()

func _refresh_weapons_ui(force: bool = false) -> void:
	if _weapons_container == null:
		return

	var entries: Array[Dictionary] = _collect_weapon_entries()
	var layout_signature: String = _build_weapon_layout_signature(entries)
	if force or layout_signature != _last_weapon_layout_signature:
		_last_weapon_layout_signature = layout_signature
		_rebuild_weapon_chips(entries)
	_update_weapon_chip_values(entries)
	_layout_future_overlay()
	queue_redraw()

func _collect_weapon_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _ship == null or _ship.hardpoint_manager == null:
		return out

	var assemblies: Array[TurretAssembly] = _ship.hardpoint_manager.get_turret_assemblies()
	for assembly in assemblies:
		if assembly == null or assembly.turret == null:
			continue
		var turret: PlayerTurret = assembly.turret
		var weapon: WeaponDef = turret.get_weapon()
		if weapon == null:
			continue
		var runtime: WeaponRuntime = turret.get_runtime()
		out.append({
			"weapon": weapon,
			"runtime": runtime,
			"mount_index": assembly.mount_index,
		})
	return out

func _build_weapon_layout_signature(entries: Array[Dictionary]) -> String:
	if entries.is_empty():
		return ""
	var parts: Array[String] = []
	for entry in entries:
		var weapon: WeaponDef = entry.get("weapon", null) as WeaponDef
		var mount_index: int = int(entry.get("mount_index", -1))
		parts.append("%d:%s" % [mount_index, _weapon_display_name(weapon)])
	return "|".join(parts)

func _rebuild_weapon_chips(entries: Array[Dictionary]) -> void:
	for c in _weapons_container.get_children():
		c.queue_free()
	_weapon_chip_nodes.clear()

	for entry in entries:
		var weapon: WeaponDef = entry.get("weapon", null) as WeaponDef
		var chip: WeaponChip = _build_weapon_chip(weapon)
		if chip == null:
			continue
		_weapon_chip_nodes.append(chip)
		_weapons_container.add_child(chip)

func _build_weapon_chip(weapon: WeaponDef) -> WeaponChip:
	if WEAPON_CHIP_SCENE == null:
		return null
	var chip: WeaponChip = WEAPON_CHIP_SCENE.instantiate() as WeaponChip
	if chip == null:
		return null
	chip.set_weapon_name(_weapon_display_name(weapon))
	chip.set_charge_text("")
	chip.set_accent(HUD_SPEED_FORWARD)
	return chip

func _update_weapon_chip_values(entries: Array[Dictionary]) -> void:
	var count: int = min(entries.size(), _weapon_chip_nodes.size())
	for i in range(count):
		var entry: Dictionary = entries[i]
		var chip: WeaponChip = _weapon_chip_nodes[i]
		var weapon: WeaponDef = entry.get("weapon", null) as WeaponDef
		var runtime: WeaponRuntime = entry.get("runtime", null) as WeaponRuntime

		if chip != null:
			chip.set_weapon_name(_weapon_display_name(weapon))
			var status_text: String = _format_weapon_status_text(weapon, runtime)
			chip.set_charge_text(status_text)

func _weapon_display_name(weapon: WeaponDef) -> String:
	if weapon == null:
		return "Unknown Weapon"
	if weapon.display_name != "":
		return weapon.display_name
	if weapon.weapon_id != "":
		return weapon.weapon_id
	return "Weapon"

func _format_weapon_status_text(weapon: WeaponDef, runtime: WeaponRuntime) -> String:
	if weapon == null or runtime == null:
		return ""
	if weapon is BeamWeaponDef and runtime is BeamWeaponRuntime:
		return _format_beam_status(weapon as BeamWeaponDef, runtime as BeamWeaponRuntime)
	if weapon is DroneBayWeaponDef and runtime is DroneBayWeaponRuntime:
		return _format_drone_slot_charges(runtime as DroneBayWeaponRuntime)
	return ""

func _format_beam_status(weapon: BeamWeaponDef, runtime: BeamWeaponRuntime) -> String:
	if weapon == null or runtime == null:
		return ""

	match runtime.get_lock_state():
		BeamWeaponRuntime.LockState.ACQUIRING:
			var acquire_time: float = runtime.get_effective_lock_acquire_time()
			var lock_progress: float = clamp(runtime.get_lock_progress(), 0.0, 1.0)
			var remaining: float = clamp(acquire_time * (1.0 - lock_progress), 0.0, acquire_time)
			return "LOCK %.2fs" % remaining
		BeamWeaponRuntime.LockState.LOCKED:
			var current_stacks: int = max(0, runtime.get_ramp_stacks())
			var max_stacks: int = max(0, runtime.get_effective_max_ramp_stacks())
			return "STACK %d/%d" % [current_stacks, max_stacks]
		_:
			return ""

func _format_drone_slot_charges(runtime: DroneBayWeaponRuntime) -> String:
	if runtime == null:
		return ""

	var charges: Array[float] = runtime.get_slot_charge_values()
	if charges.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for c in charges:
		parts.append(_format_charge_value(c))

	var lines: PackedStringArray = PackedStringArray()
	var i: int = 0
	while i < parts.size():
		var line_parts: PackedStringArray = PackedStringArray()
		for j in range(i, min(i + DRONE_CHARGE_VALUES_PER_LINE, parts.size())):
			line_parts.append(parts[j])
		lines.append(" ".join(line_parts))
		i += DRONE_CHARGE_VALUES_PER_LINE
	return "\n".join(lines)

func _format_charge_value(value: float) -> String:
	return "%.1f" % value

func _update_repair_cooldown_ui() -> void:
	if _repair_cooldown_label == null:
		return
	if _ship == null:
		_repair_cooldown_label.text = ""
		return

	var remaining: float = max(_ship.get_hull_repair_cooldown_remaining(), 0.0)

	if remaining <= 0.0:
		_repair_cooldown_label.text = ""
		return

	_repair_cooldown_label.text = "%.2f" % remaining

func _sync_future_display_state() -> void:
	if _ship == null:
		return
	_display_hull = max(_ship.hull, 0.0)
	_display_hull_max = max(_ship.eff_max_hull, 1.0)
	_display_shield = _ship.shield
	_display_shield_max = max(_ship.eff_max_shield, 1.0)
	_display_forward_speed = _ship.linear_velocity.dot(-_ship.transform.basis.z)
	var caps: Vector2 = _ship.get_speed_caps()
	_display_reverse_max = max(caps.x, 1.0)
	_display_forward_max = max(caps.y, 1.0)
	_display_nanobots = _ship.get_nanobots()

func _ensure_future_overlay_labels() -> void:
	_hull_title_overlay = _create_overlay_label("HullTitle", 18, Color(1.0, 0.88, 0.78, 0.94), HORIZONTAL_ALIGNMENT_CENTER)
	_hull_value_overlay = _create_overlay_label("HullValue", 19, hull_color.lightened(0.4), HORIZONTAL_ALIGNMENT_CENTER)
	_shield_title_overlay = _create_overlay_label("ShieldTitle", 18, Color(0.84, 0.93, 1.0, 0.94), HORIZONTAL_ALIGNMENT_CENTER)
	_shield_value_overlay = _create_overlay_label("ShieldValue", 19, shield_color.lightened(0.45), HORIZONTAL_ALIGNMENT_CENTER)
	_speed_tag_overlay = _create_overlay_label("SpeedTag", 17, Color(0.95, 0.82, 0.47, 0.96), HORIZONTAL_ALIGNMENT_LEFT)
	_speed_value_overlay = _create_overlay_label("SpeedValue", 26, Color(1.0, 0.9, 0.54, 0.98), HORIZONTAL_ALIGNMENT_LEFT)
	_max_tag_overlay = _create_overlay_label("MaxTag", 16, HUD_TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_max_value_overlay = _create_overlay_label("MaxValue", 25, Color(0.86, 0.94, 1.0, 0.98), HORIZONTAL_ALIGNMENT_LEFT)
	_nanobot_tag_overlay = _create_overlay_label("NanobotTag", 16, HUD_TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_nanobot_value_overlay = _create_overlay_label("NanobotValue", 26, HUD_NANOBOT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)

func _create_overlay_label(label_name: String, font_size: int, font_color: Color, alignment: int) -> Label:
	var existing: Node = get_node_or_null(label_name)
	var label: Label = existing as Label
	if label == null:
		label = Label.new()
		label.name = label_name
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(label)
		move_child(label, get_child_count() - 1)
	if HUD_FONT_MEDIUM != null:
		label.add_theme_font_override("font", HUD_FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.horizontal_alignment = alignment as HorizontalAlignment
	label.visible = true
	return label

func _hud_point(x: float, y: float) -> Vector2:
	return _hud_frame_rect.position + Vector2(x, y) * _hud_scale

func _hud_rect(x: float, y: float, width: float, height: float) -> Rect2:
	return Rect2(_hud_point(x, y), Vector2(width, height) * _hud_scale)

func _set_overlay_font_size(label: Label, base_size: int) -> void:
	if label == null:
		return
	var scaled_size: int = max(int(round(float(base_size) * _hud_scale)), 11)
	label.add_theme_font_size_override("font_size", scaled_size)

func _layout_future_overlay() -> void:
	if not is_node_ready():
		return

	var viewport_scale: float = min(size.x / HUD_BASE_VIEWPORT_WIDTH, size.y / HUD_BASE_VIEWPORT_HEIGHT)
	_hud_scale = clamp(viewport_scale * 0.82, 0.62, 0.92)
	var frame_size: Vector2 = Vector2(HUD_DESIGN_WIDTH, HUD_DESIGN_HEIGHT) * _hud_scale
	var frame_x: float = max((size.x - frame_size.x) * 0.5, 16.0)
	var frame_y: float = max(size.y - frame_size.y - 8.0, 0.0)
	_hud_frame_rect = Rect2(Vector2(frame_x, frame_y), frame_size)

	if _abilities_container != null:
		_abilities_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_ability_frame_rect = Rect2(
			max(_hud_frame_rect.position.x - 176.0 * _hud_scale, 12.0),
			_hud_frame_rect.position.y + 176.0 * _hud_scale,
			118.0 * _hud_scale,
			118.0 * _hud_scale
		)
		var ability_content_size: Vector2 = _abilities_container.get_combined_minimum_size()
		_abilities_container.position = _ability_frame_rect.get_center() - ability_content_size * 0.5
		_abilities_container.size = ability_content_size

	if _weapons_container != null:
		_weapons_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var chip_count: int = max(_weapons_container.get_child_count(), 1)
		var column_count: int = min(chip_count, WEAPON_CHIP_MAX_COLUMNS)
		var row_count: int = int(ceil(float(chip_count) / float(WEAPON_CHIP_MAX_COLUMNS)))
		var inner_width: float = float(column_count) * WEAPON_CHIP_WIDTH + float(max(column_count - 1, 0)) * WEAPON_CHIP_H_SEPARATION
		var inner_height: float = float(row_count) * WEAPON_CHIP_HEIGHT + float(max(row_count - 1, 0)) * WEAPON_CHIP_V_SEPARATION
		var horizontal_padding: float = 32.0 * _hud_scale
		var vertical_padding: float = 28.0 * _hud_scale
		var weapon_width: float = inner_width + horizontal_padding
		var weapon_height: float = inner_height + vertical_padding
		var weapon_x: float = min(_hud_frame_rect.position.x + _hud_frame_rect.size.x + 22.0 * _hud_scale, size.x - weapon_width - 12.0)
		var extra_rows: int = max(row_count - 1, 0)
		var extra_row_lift: float = float(extra_rows) * (WEAPON_CHIP_HEIGHT + WEAPON_CHIP_V_SEPARATION) * 0.9
		var weapon_y: float = _hud_frame_rect.position.y + 188.0 * _hud_scale - extra_row_lift
		_weapons_frame_rect = Rect2(weapon_x, weapon_y, weapon_width, weapon_height)
		_weapons_container.position = _weapons_frame_rect.position + Vector2(16.0, 14.0) * _hud_scale
		_weapons_container.size = Vector2(inner_width, inner_height)
		_weapons_container.custom_minimum_size = Vector2(inner_width, inner_height)

	_update_future_label_layout()

func _update_future_label_layout() -> void:
	if _hull_title_overlay == null:
		return

	_set_overlay_font_size(_hull_title_overlay, 13)
	_set_overlay_font_size(_hull_value_overlay, 14)
	_set_overlay_font_size(_shield_title_overlay, 13)
	_set_overlay_font_size(_shield_value_overlay, 16)
	_set_overlay_font_size(_speed_tag_overlay, 16)
	_set_overlay_font_size(_speed_value_overlay, 24)
	_set_overlay_font_size(_max_tag_overlay, 15)
	_set_overlay_font_size(_max_value_overlay, 23)
	_set_overlay_font_size(_nanobot_tag_overlay, 15)
	_set_overlay_font_size(_nanobot_value_overlay, 24)

	_hull_title_overlay.position = _hud_point(242.0, 44.0)
	_hull_title_overlay.size = Vector2(50.0, 16.0) * _hud_scale
	_hull_value_overlay.position = _hud_point(233.0, 76.0)
	_hull_value_overlay.size = Vector2(64.0, 18.0) * _hud_scale

	_shield_title_overlay.position = _hud_point(330.0, 44.0)
	_shield_title_overlay.size = Vector2(50.0, 16.0) * _hud_scale
	_shield_value_overlay.position = _hud_point(318.0, 76.0)
	_shield_value_overlay.size = Vector2(64.0, 18.0) * _hud_scale

	_speed_tag_overlay.position = _hud_point(150.0, 284.0)
	_speed_tag_overlay.size = Vector2(18.0, 18.0) * _hud_scale
	_speed_value_overlay.position = _hud_point(182.0, 283.0)
	_speed_value_overlay.size = Vector2(58.0, 24.0) * _hud_scale

	_max_tag_overlay.position = _hud_point(420.0, 284.0)
	_max_tag_overlay.size = Vector2(40.0, 18.0) * _hud_scale
	_max_value_overlay.position = _hud_point(465.0, 280.0)
	_max_value_overlay.size = Vector2(74.0, 24.0) * _hud_scale

	_nanobot_tag_overlay.position = _hud_point(420.0, 258.0)
	_nanobot_tag_overlay.size = Vector2(28.0, 18.0) * _hud_scale
	_nanobot_value_overlay.position = _hud_point(460.0, 255.0)
	_nanobot_value_overlay.size = Vector2(58.0, 24.0) * _hud_scale

func _update_future_labels() -> void:
	if _hull_title_overlay == null:
		return

	var hull_bar_color: Color = _get_hull_bar_color()
	_hull_title_overlay.text = "HULL"
	_hull_value_overlay.text = "%d/%d" % [int(round(_display_hull)), int(round(_display_hull_max))]
	_shield_title_overlay.text = "SHLD"
	_shield_value_overlay.text = "%d/%d" % [int(round(_display_shield)), int(round(_display_shield_max))]
	_speed_tag_overlay.text = "V"
	_speed_value_overlay.text = "%d" % int(round(_display_forward_speed))
	_max_tag_overlay.text = "MAX"
	_max_value_overlay.text = "%d" % int(round(_display_forward_max))
	_nanobot_tag_overlay.text = "NB"
	_nanobot_value_overlay.text = "%d" % _display_nanobots

	_hull_title_overlay.add_theme_color_override("font_color", HUD_HULL_TITLE_COLOR)
	_hull_value_overlay.add_theme_color_override("font_color", hull_bar_color)

	var current_speed_color: Color = Color(1.0, 0.9, 0.54, 0.98)
	if _display_forward_speed < -0.5:
		current_speed_color = HUD_SPEED_REVERSE
	_speed_value_overlay.add_theme_color_override("font_color", current_speed_color)

func _draw() -> void:
	if _hud_frame_rect.size == Vector2.ZERO:
		return

	if HUD_CENTER_FRAME != null:
		draw_texture_rect(HUD_CENTER_FRAME, _hud_frame_rect, false, Color(1.0, 1.0, 1.0, 0.98))

	_draw_frame_connectors()
	_draw_ability_wrapper(_ability_frame_rect)
	_draw_segment_column(_hud_rect(242.0, 104.0, 52.0, 135.0), _display_hull, _display_hull_max, _get_hull_bar_color())
	_draw_segment_column(_hud_rect(326.0, 104.0, 52.0, 135.0), _display_shield, _display_shield_max, shield_color)
	_draw_speed_bar(_hud_rect(238.0, 287.0, 146.0, 13.0))

func _draw_frame_connectors() -> void:
	if _ability_frame_rect.size != Vector2.ZERO:
		var left_a: Vector2 = _ability_frame_rect.position + Vector2(_ability_frame_rect.size.x - 10.0 * _hud_scale, _ability_frame_rect.size.y * 0.72)
		var left_b: Vector2 = _hud_point(98.0, 286.0)
		draw_line(left_a, left_b, Color(0.12, 0.15, 0.2, 0.9), 5.0 * _hud_scale, true)
		draw_line(left_a, left_b, Color(1.0, 0.58, 0.24, 0.28), 1.6 * _hud_scale, true)

	if _weapons_frame_rect.size != Vector2.ZERO:
		var right_a: Vector2 = _hud_point(522.0, 286.0)
		var right_b: Vector2 = _weapons_frame_rect.position + Vector2(10.0 * _hud_scale, _weapons_frame_rect.size.y * 0.72)
		draw_line(right_a, right_b, Color(0.12, 0.15, 0.2, 0.9), 5.0 * _hud_scale, true)
		draw_line(right_a, right_b, Color(0.25, 0.86, 1.0, 0.28), 1.6 * _hud_scale, true)

func _draw_ability_wrapper(rect: Rect2) -> void:
	if rect.size == Vector2.ZERO:
		return

	var center: Vector2 = rect.get_center()
	var radius: float = min(rect.size.x, rect.size.y) * 0.48
	draw_circle(center, radius, Color(0.07, 0.02, 0.03, 0.64))
	draw_arc(center, radius - 4.0 * _hud_scale, deg_to_rad(16.0), deg_to_rad(344.0), 44, Color(0.34, 0.08, 0.09, 0.95), 4.0 * _hud_scale, true)
	draw_arc(center, radius - 10.0 * _hud_scale, deg_to_rad(22.0), deg_to_rad(338.0), 44, Color(1.0, 0.42, 0.24, 0.52), 1.8 * _hud_scale, true)
	draw_line(center + Vector2(-radius - 5.0 * _hud_scale, -8.0 * _hud_scale), center + Vector2(-radius + 4.0 * _hud_scale, -8.0 * _hud_scale), Color(1.0, 0.42, 0.24, 0.7), 2.4 * _hud_scale, true)
	draw_line(center + Vector2(radius - 4.0 * _hud_scale, 8.0 * _hud_scale), center + Vector2(radius + 5.0 * _hud_scale, 8.0 * _hud_scale), Color(1.0, 0.42, 0.24, 0.7), 2.4 * _hud_scale, true)

func _make_beveled_polygon(rect: Rect2, bevel: float) -> PackedVector2Array:
	var x: float = rect.position.x
	var y: float = rect.position.y
	var w: float = rect.size.x
	var h: float = rect.size.y
	var bevel_size: float = bevel * _hud_scale
	return PackedVector2Array([
		Vector2(x + bevel_size, y),
		Vector2(x + w - bevel_size, y),
		Vector2(x + w, y + bevel_size),
		Vector2(x + w, y + h - bevel_size),
		Vector2(x + w - bevel_size, y + h),
		Vector2(x + bevel_size, y + h),
		Vector2(x, y + h - bevel_size),
		Vector2(x, y + bevel_size),
	])

func _draw_segment_column(rect: Rect2, value: float, max_value: float, active_color: Color) -> void:
	var gap: float = 4.0 * _hud_scale
	var segment_height: float = (rect.size.y - gap * float(HUD_SEGMENT_COUNT - 1)) / float(HUD_SEGMENT_COUNT)
	var fill_units: float = clamp(value / max(max_value, 1.0), 0.0, 1.0) * float(HUD_SEGMENT_COUNT)
	var segment_border: Color = Color(active_color.r * 0.45, active_color.g * 0.45, active_color.b * 0.55, 0.5)

	for segment_index in range(HUD_SEGMENT_COUNT):
		var y: float = rect.position.y + rect.size.y - segment_height - float(segment_index) * (segment_height + gap)
		var segment_rect: Rect2 = Rect2(rect.position.x, y, rect.size.x, segment_height)
		var fill_amount: float = clamp(fill_units - float(segment_index), 0.0, 1.0)
		draw_rect(segment_rect, Color(0.05, 0.07, 0.11, 0.92))
		draw_rect(segment_rect, segment_border, false, max(1.0, 1.0 * _hud_scale))

		if fill_amount <= 0.0:
			continue

		var inset: float = 2.0 * _hud_scale
		var inner_rect: Rect2 = segment_rect.grow(-inset)
		if fill_amount < 1.0:
			var filled_height: float = inner_rect.size.y * fill_amount
			inner_rect.position.y = inner_rect.end.y - filled_height
			inner_rect.size.y = filled_height
		draw_rect(inner_rect, active_color)
		draw_rect(inner_rect.grow(1.0 * _hud_scale), Color(active_color.r, active_color.g, active_color.b, 0.4), false, max(1.0, 1.0 * _hud_scale))

func _get_hull_bar_color() -> Color:
	var hull_ratio: float = clamp(_display_hull / max(_display_hull_max, 1.0), 0.0, 1.0)
	var danger_color: Color = Color(1.0, 0.24, 0.22, 1.0)
	var caution_color: Color = Color(1.0, 0.84, 0.22, 1.0)
	var safe_color: Color = Color(0.28, 1.0, 0.42, 1.0)

	if hull_ratio >= 0.5:
		var safe_t: float = inverse_lerp(0.5, 1.0, hull_ratio)
		return caution_color.lerp(safe_color, safe_t)

	var danger_t: float = inverse_lerp(0.0, 0.5, hull_ratio)
	return danger_color.lerp(caution_color, danger_t)

func _draw_speed_bar(rect: Rect2) -> void:
	draw_rect(rect, Color(0.04, 0.05, 0.08, 0.92))
	draw_rect(rect, Color(0.18, 0.22, 0.28, 0.9), false, max(1.4, 1.4 * _hud_scale))

	var center_gap: float = 10.0 * _hud_scale
	var segment_gap: float = 3.0 * _hud_scale
	var reverse_width: float = (rect.size.x - center_gap) * HUD_SPEED_REVERSE_WIDTH_RATIO
	var forward_width: float = rect.size.x - center_gap - reverse_width
	var reverse_segment_width: float = (reverse_width - float(HUD_SPEED_SEGMENTS_REVERSE - 1) * segment_gap) / float(HUD_SPEED_SEGMENTS_REVERSE)
	var forward_segment_width: float = (forward_width - float(HUD_SPEED_SEGMENTS_FORWARD - 1) * segment_gap) / float(HUD_SPEED_SEGMENTS_FORWARD)
	var segment_height: float = rect.size.y
	var center_x: float = rect.position.x + reverse_width + center_gap * 0.5
	var reverse_fill: float = clamp(absf(min(_display_forward_speed, 0.0)) / max(_display_reverse_max, 1.0), 0.0, 1.0) * float(HUD_SPEED_SEGMENTS_REVERSE)
	var forward_fill: float = clamp(max(_display_forward_speed, 0.0) / max(_display_forward_max, 1.0), 0.0, 1.0) * float(HUD_SPEED_SEGMENTS_FORWARD)

	for i in range(HUD_SPEED_SEGMENTS_REVERSE):
		var left_x: float = center_x - center_gap * 0.5 - float(i + 1) * reverse_segment_width - float(i) * segment_gap
		var left_rect: Rect2 = Rect2(left_x, rect.position.y, reverse_segment_width, segment_height)
		var left_fill: float = clamp(reverse_fill - float(i), 0.0, 1.0)
		_draw_speed_segment(left_rect, left_fill, HUD_SPEED_REVERSE, -1)

	for i in range(HUD_SPEED_SEGMENTS_FORWARD):
		var right_x: float = center_x + center_gap * 0.5 + float(i) * (forward_segment_width + segment_gap)
		var right_rect: Rect2 = Rect2(right_x, rect.position.y, forward_segment_width, segment_height)
		var right_fill: float = clamp(forward_fill - float(i), 0.0, 1.0)
		_draw_speed_segment(right_rect, right_fill, HUD_SPEED_FORWARD, 1)

	draw_line(Vector2(center_x, rect.position.y - 2.0 * _hud_scale), Vector2(center_x, rect.end.y + 2.0 * _hud_scale), Color(0.9, 0.95, 1.0, 0.45), max(1.4, 1.4 * _hud_scale), true)

func _draw_speed_segment(rect: Rect2, fill_amount: float, active_color: Color, direction: int) -> void:
	var polygon: PackedVector2Array = _make_speed_segment_polygon(rect, direction)
	if polygon.size() < 3:
		return
	draw_colored_polygon(polygon, Color(0.07, 0.09, 0.13, 0.92))
	var closed: PackedVector2Array = polygon.duplicate()
	closed.append(polygon[0])
	draw_polyline(closed, Color(0.22, 0.27, 0.35, 0.9), max(1.6, 1.6 * _hud_scale), true)

	if fill_amount <= 0.0:
		return

	var fill_rect: Rect2 = rect.grow(-1.0 * _hud_scale)
	if fill_rect.size.x <= 1.0 or fill_rect.size.y <= 1.0:
		return
	if fill_amount < 1.0:
		if direction < 0:
			fill_rect.position.x = fill_rect.end.x - fill_rect.size.x * fill_amount
		fill_rect.size.x *= fill_amount
	if fill_rect.size.x <= 1.0 or fill_rect.size.y <= 1.0:
		return
	var fill_polygon: PackedVector2Array = _make_speed_segment_polygon(fill_rect, direction)
	if fill_polygon.size() < 3:
		return
	draw_colored_polygon(fill_polygon, active_color)

func _make_speed_segment_polygon(rect: Rect2, direction: int) -> PackedVector2Array:
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return PackedVector2Array()

	var max_slant: float = rect.size.x * 0.5 - 0.01
	if max_slant <= 0.0:
		return PackedVector2Array()

	var slant: float = min(rect.size.x * 0.45, 5.0 * _hud_scale, max_slant)
	if direction < 0:
		return PackedVector2Array([
			Vector2(rect.position.x + slant, rect.position.y),
			Vector2(rect.end.x, rect.position.y),
			Vector2(rect.end.x - slant, rect.end.y),
			Vector2(rect.position.x, rect.end.y),
		])
	return PackedVector2Array([
		Vector2(rect.position.x, rect.position.y),
		Vector2(rect.end.x - slant, rect.position.y),
		Vector2(rect.end.x, rect.end.y),
		Vector2(rect.position.x + slant, rect.end.y),
	])

func _apply_bar(bar: ProgressBar, label: Label, val: float, maxv: float) -> void:
	maxv = max(maxv, 1.0)
	val = clamp(val, 0.0, maxv)
	bar.max_value = maxv
	bar.value = val
	label.text = "%d/%d" % [int(round(val)), int(round(maxv))]

func _style_bar(bar: ProgressBar, fill_col: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_col
	fill.corner_radius_top_left = 6
	fill.corner_radius_top_right = 6
	fill.corner_radius_bottom_left = 6
	fill.corner_radius_bottom_right = 6
	var back := StyleBoxFlat.new()
	back.bg_color = back_color
	back.corner_radius_top_left = 6
	back.corner_radius_top_right = 6
	back.corner_radius_bottom_left = 6
	back.corner_radius_bottom_right = 6

	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	bar.step = 1.0

func _apply_speed(label: Label, fwd_speed: float, max_fwd: float) -> void:
	label.text = "v: %dm/s | max: %dm/s" % [int(round(fwd_speed)), int(round(max_fwd))]

func _read_pair(component_name: String, component_max: String, def_v: float, def_m: float) -> Array:
	var v := def_v
	var m := def_m
	if _ship != null:
		var got_v = _ship.get(component_name)
		var got_m = _ship.get(component_max)
		if typeof(got_v) in [TYPE_INT, TYPE_FLOAT]: v = float(got_v)
		if typeof(got_m) in [TYPE_INT, TYPE_FLOAT]: m = float(got_m)
	return [v, m]

func _update_repair_widget_text() -> void:
	if _repair_label == null:
		return
	var cost: int = 500
	if _ship != null and _ship.has_method("get_hull_repair_cost"):
		cost = int(_ship.call("get_hull_repair_cost"))
	_repair_label.text = "(%d)" % cost

func _update_repair_hotkey_prompt() -> void:
	if _repair_hotkey_label == null:
		return

	if _prefer_controller_prompt:
		var button_index: int = _get_action_joy_button_index(ACTION_HULL_REPAIR)
		if button_index >= 0:
			_repair_hotkey_label.text = _get_controller_button_label(button_index, _active_controller_device)
			return

	_repair_hotkey_label.text = _get_action_keyboard_label(ACTION_HULL_REPAIR)

func _get_action_joy_button_index(action_name: StringName) -> int:
	if not InputMap.has_action(action_name):
		return -1
	for event: InputEvent in InputMap.action_get_events(action_name):
		var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
		if joy_button != null:
			return joy_button.button_index
	return -1

func _get_action_keyboard_label(action_name: StringName) -> String:
	if not InputMap.has_action(action_name):
		return "?"
	for event: InputEvent in InputMap.action_get_events(action_name):
		var key_event: InputEventKey = event as InputEventKey
		if key_event == null:
			continue
		var code: int = key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		var key_name: String = OS.get_keycode_string(code)
		if key_name != "":
			return key_name
	return "?"

func _get_controller_button_label(button_index: int, device_id: int) -> String:
	var labels: Dictionary = _get_controller_label_map(device_id)
	if labels.has(button_index):
		return String(labels[button_index])
	return "Btn %d" % button_index

func _get_controller_label_map(device_id: int) -> Dictionary:
	match _detect_controller_family(device_id):
		CONTROLLER_XBOX:
			return BUTTON_LABELS_XBOX
		CONTROLLER_PLAYSTATION:
			return BUTTON_LABELS_PLAYSTATION
		CONTROLLER_NINTENDO:
			return BUTTON_LABELS_NINTENDO
		_:
			return BUTTON_LABELS_GENERIC

func _detect_controller_family(device_id: int) -> StringName:
	var joy_name: String = ""
	if device_id >= 0:
		joy_name = Input.get_joy_name(device_id)
	var id: String = joy_name.to_lower()

	if "xbox" in id or "xinput" in id or "microsoft" in id:
		return CONTROLLER_XBOX
	if "dualsense" in id or "dualshock" in id or "playstation" in id or "wireless controller" in id:
		return CONTROLLER_PLAYSTATION
	if "switch" in id or "nintendo" in id or "joy-con" in id:
		return CONTROLLER_NINTENDO
	return CONTROLLER_GENERIC

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	if device != _active_controller_device:
		return
	var connected_pads: PackedInt32Array = Input.get_connected_joypads()
	if connected_pads.is_empty():
		_prefer_controller_prompt = false
		_active_controller_device = -1
	else:
		_active_controller_device = connected_pads[0]
	_update_repair_hotkey_prompt()
