# ship_hud.gd  (Godot 4.5)
extends Control
class_name ShipHud

@export var shield_color: Color = Color(0.2, 0.6, 1.0)
@export var hull_color: Color = Color(1.0, 0.22, 0.22, 1.0)
@export var back_color: Color = Color(0, 0, 0, 0.6)
@export var repair_color: Color = Color(0.95, 0.2, 0.2, 0.95)
@export var ui_hz: float = 20.0

var _ship: Ship
var _accum := 0.0

@onready var _shield_bar: ProgressBar = $ShipStatsContainer/ShieldHullContainer/Shield/Bar
@onready var _shield_val: Label = $ShipStatsContainer/ShieldHullContainer/Shield/Value
@onready var _hull_bar: ProgressBar = $ShipStatsContainer/ShieldHullContainer/Hull/Bar
@onready var _hull_val: Label = $ShipStatsContainer/ShieldHullContainer/Hull/Value
@onready var _vel_val: Label = $ShipStatsContainer/VelocityContainer/Label
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

func _ready() -> void:
	_style_bar(_shield_bar, shield_color)
	_style_bar(_hull_bar, hull_color)
	_update_repair_widget_text()
	_update_repair_cooldown_ui()
	_update_repair_hotkey_prompt()

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
