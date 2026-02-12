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
@onready var _repair_cooldown_label: Label = $AbilitiesContainer/RepairPanel/CooldownLabel

func init(ship: Node3D) -> void:
	_ship = ship as Ship
	_update_repair_widget_text()
	_update_repair_cooldown_ui()

func _ready() -> void:
	_style_bar(_shield_bar, shield_color)
	_style_bar(_hull_bar, hull_color)
	_update_repair_widget_text()
	_update_repair_cooldown_ui()

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
