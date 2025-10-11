extends Control
class_name ShipHud

@export var shield_color: Color = Color(0.2, 0.6, 1.0)
@export var hull_color: Color = Color(0.2, 0.9, 0.2)
@export var back_color: Color = Color(0, 0, 0, 0.6)
@export var ui_hz: float = 20.0

var _ship: Node3D
var _accum := 0.0

@onready var _shield_bar: ProgressBar = $VBox/Shield/Bar
@onready var _shield_val: Label = $VBox/Shield/Value
@onready var _hull_bar: ProgressBar = $VBox/Hull/Bar
@onready var _hull_val: Label = $VBox/Hull/Value

func init(ship: Node3D) -> void:
	_ship = ship

func _ready() -> void:
	_style_bar(_shield_bar, shield_color)
	_style_bar(_hull_bar, hull_color)

func _process(delta: float) -> void:
	_accum += delta
	if _accum < 1.0 / max(ui_hz, 1.0):
		return
	_accum = 0.0
	_update_values()

func _update_values() -> void:
	var shield_pair := _read_pair("shield", "shield_max", 100.0, 100.0)
	var shield: float = shield_pair[0]
	var shield_max: float = shield_pair[1]

	var hull_pair := _read_pair("hull", "hull_max", 100.0, 100.0)
	var hull: float = hull_pair[0]
	var hull_max: float = hull_pair[1]
	
	_apply_bar(_shield_bar, _shield_val, shield, shield_max)
	_apply_bar(_hull_bar, _hull_val, hull, hull_max)

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

func _read_pair(component_name: String, component_max: String, def_v: float, def_m: float) -> Array:
	var v := def_v
	var m := def_m
	if _ship != null:
		var got_v = _ship.get(component_name)
		var got_m = _ship.get(component_max)
		if typeof(got_v) in [TYPE_INT, TYPE_FLOAT]: v = float(got_v)
		if typeof(got_m) in [TYPE_INT, TYPE_FLOAT]: m = float(got_m)
	return [v, m]
