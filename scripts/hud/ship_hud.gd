# ship_hud.gd  (Godot 4.5)
extends Control
class_name ShipHud

const WEAPON_CHIP_FONT: FontFile = preload("res://assets/fonts/Oxanium/Oxanium-Medium.ttf")
const DRONE_CHARGE_VALUES_PER_LINE: int = 4

@export var shield_color: Color = Color(0.2, 0.6, 1.0)
@export var hull_color: Color = Color(1.0, 0.22, 0.22, 1.0)
@export var back_color: Color = Color(0, 0, 0, 0.6)
@export var repair_color: Color = Color(0.95, 0.2, 0.2, 0.95)
@export var ui_hz: float = 20.0

var _ship: Ship
var _accum := 0.0
var _last_weapon_layout_signature: String = ""
var _weapon_chip_nodes: Array[Dictionary] = []

@onready var _shield_bar: ProgressBar = $ShipStatsContainer/ShieldHullContainer/Shield/Bar
@onready var _shield_val: Label = $ShipStatsContainer/ShieldHullContainer/Shield/Value
@onready var _hull_bar: ProgressBar = $ShipStatsContainer/ShieldHullContainer/Hull/Bar
@onready var _hull_val: Label = $ShipStatsContainer/ShieldHullContainer/Hull/Value
@onready var _vel_val: Label = $ShipStatsContainer/VelocityContainer/Label
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

func _ready() -> void:
	_style_bar(_shield_bar, shield_color)
	_style_bar(_hull_bar, hull_color)
	_update_repair_widget_text()
	_update_repair_cooldown_ui()
	_update_repair_hotkey_prompt()
	_refresh_weapons_ui(true)
	if EventBus != null and EventBus.has_signal("weapons_changed"):
		if not EventBus.weapons_changed.is_connected(_on_weapons_changed):
			EventBus.weapons_changed.connect(_on_weapons_changed)

	if Input.has_signal("joy_connection_changed"):
		if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
			Input.joy_connection_changed.connect(_on_joy_connection_changed)

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

	var shield_pair := _read_pair("shield", "eff_max_shield", 100.0, 100.0)
	var shield: float = shield_pair[0]
	var shield_max: float = shield_pair[1]

	var hull_pair := _read_pair("hull", "eff_max_hull", 100.0, 100.0)
	var hull: float = hull_pair[0]
	var hull_max: float = hull_pair[1]
	_update_repair_cooldown_ui()
	
	_apply_bar(_shield_bar, _shield_val, shield, shield_max)
	_apply_bar(_hull_bar, _hull_val, hull, hull_max)
	
	var fwd_speed: float = 0.0
	var max_fwd: float = 100.0
	
	fwd_speed = _ship.linear_velocity.length()
	var caps: Vector2 = _ship.get_speed_caps()
	max_fwd = max(caps.y, 1.0)
	
	_apply_speed(_vel_val, fwd_speed, max_fwd)

func _on_weapons_changed(_weapons: Array[WeaponDef]) -> void:
	_refresh_weapons_ui(true)

func _refresh_weapons_ui(force: bool = false) -> void:
	if _weapons_container == null:
		return

	var entries: Array[Dictionary] = _collect_weapon_entries()
	var layout_signature: String = _build_weapon_layout_signature(entries)
	if force or layout_signature != _last_weapon_layout_signature:
		_last_weapon_layout_signature = layout_signature
		_rebuild_weapon_chips(entries)
	_update_weapon_chip_values(entries)

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
		var chip: Dictionary = _build_weapon_chip(entry.get("weapon", null) as WeaponDef)
		_weapon_chip_nodes.append(chip)
		var panel: PanelContainer = chip.get("panel", null) as PanelContainer
		if panel != null:
			_weapons_container.add_child(panel)

func _build_weapon_chip(weapon: WeaponDef) -> Dictionary:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(138.0, 50.0)

	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.12, 0.16, 0.72)
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.border_color = Color(0.24, 0.62, 0.96, 0.85)
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", bg)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 2)
	panel.add_child(root)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	root.add_child(row)

	var icon: ColorRect = ColorRect.new()
	icon.custom_minimum_size = Vector2(10.0, 10.0)
	icon.color = Color(0.25, 0.82, 1.0, 1.0)
	row.add_child(icon)

	var label: Label = Label.new()
	label.text = _weapon_display_name(weapon)
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if WEAPON_CHIP_FONT != null:
		label.add_theme_font_override("font", WEAPON_CHIP_FONT)
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)

	var charge_label: Label = Label.new()
	charge_label.clip_text = false
	charge_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	charge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	charge_label.modulate = Color(0.7, 0.9, 1.0, 0.95)
	if WEAPON_CHIP_FONT != null:
		charge_label.add_theme_font_override("font", WEAPON_CHIP_FONT)
	charge_label.add_theme_font_size_override("font_size", 12)
	charge_label.text = ""
	root.add_child(charge_label)

	return {
		"panel": panel,
		"name_label": label,
		"charge_label": charge_label,
	}

func _update_weapon_chip_values(entries: Array[Dictionary]) -> void:
	var count: int = min(entries.size(), _weapon_chip_nodes.size())
	for i in range(count):
		var entry: Dictionary = entries[i]
		var nodes: Dictionary = _weapon_chip_nodes[i]
		var weapon: WeaponDef = entry.get("weapon", null) as WeaponDef
		var runtime: WeaponRuntime = entry.get("runtime", null) as WeaponRuntime
		var name_label: Label = nodes.get("name_label", null) as Label
		var charge_label: Label = nodes.get("charge_label", null) as Label

		if name_label != null:
			name_label.text = _weapon_display_name(weapon)
		if charge_label != null:
			var charges_text: String = _format_drone_slot_charges(weapon, runtime)
			charge_label.text = charges_text
			charge_label.visible = charges_text != ""

func _weapon_display_name(weapon: WeaponDef) -> String:
	if weapon == null:
		return "Unknown Weapon"
	if weapon.display_name != "":
		return weapon.display_name
	if weapon.weapon_id != "":
		return weapon.weapon_id
	return "Weapon"

func _format_drone_slot_charges(weapon: WeaponDef, runtime: WeaponRuntime) -> String:
	if weapon == null or runtime == null:
		return ""
	if not (weapon is DroneBayWeaponDef):
		return ""
	var drone_runtime: DroneBayWeaponRuntime = runtime as DroneBayWeaponRuntime
	if drone_runtime == null:
		return ""

	var charges: Array[float] = drone_runtime.get_slot_charge_values()
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
	_repair_label.text = "Hull Repair\n(%d)" % cost

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
