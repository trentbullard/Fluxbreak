extends Control
class_name WeaponChip

const CHIP_FONT: FontFile = preload("res://assets/fonts/Oxanium/Oxanium-Medium.ttf")

@export var accent_color: Color = Color(0.25, 0.82, 1.0, 1.0)
@export var panel_color: Color = Color(0.06, 0.09, 0.13, 0.88)
@export var border_color: Color = Color(0.33, 0.47, 0.62, 0.92)
@export var line_color: Color = Color(0.2, 0.86, 1.0, 0.65)

@onready var _content_margin: MarginContainer = $ContentMargin
@onready var _icon_rect: ColorRect = $ContentMargin/VBox/TopRow/Icon
@onready var _name_label: Label = $ContentMargin/VBox/TopRow/NameLabel
@onready var _charge_label: Label = $ContentMargin/VBox/ChargeLabel

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(148.0, 64.0)
	_apply_fonts()
	_apply_colors()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func set_weapon_name(value: String) -> void:
	if _name_label != null:
		_name_label.text = value

func set_charge_text(value: String) -> void:
	if _charge_label != null:
		_charge_label.text = value
		_charge_label.visible = value != ""

func set_accent(value: Color) -> void:
	accent_color = value
	_apply_colors()
	queue_redraw()

func _apply_fonts() -> void:
	if CHIP_FONT == null:
		return
	_name_label.add_theme_font_override("font", CHIP_FONT)
	_name_label.add_theme_font_size_override("font_size", 12)
	_charge_label.add_theme_font_override("font", CHIP_FONT)
	_charge_label.add_theme_font_size_override("font_size", 12)

func _apply_colors() -> void:
	if _icon_rect != null:
		_icon_rect.color = accent_color
	if _charge_label != null:
		_charge_label.modulate = Color(0.72, 0.9, 1.0, 0.95)

func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var polygon: PackedVector2Array = _make_beveled_polygon(rect, 12.0)
	var closed: PackedVector2Array = polygon.duplicate()
	closed.append(polygon[0])
	draw_colored_polygon(polygon, panel_color)
	draw_polyline(closed, border_color, 2.0, true)

	var mid_y: float = 33.0
	draw_line(Vector2(10.0, mid_y), Vector2(size.x - 10.0, mid_y), Color(0.18, 0.26, 0.35, 0.62), 1.0, true)
	draw_line(Vector2(size.x - 32.0, size.y - 9.0), Vector2(size.x - 10.0, size.y - 9.0), line_color, 2.0, true)

func _make_beveled_polygon(rect: Rect2, bevel: float) -> PackedVector2Array:
	var x: float = rect.position.x
	var y: float = rect.position.y
	var w: float = rect.size.x
	var h: float = rect.size.y
	return PackedVector2Array([
		Vector2(x + bevel, y),
		Vector2(x + w - bevel, y),
		Vector2(x + w, y + bevel),
		Vector2(x + w, y + h - bevel),
		Vector2(x + w - bevel, y + h),
		Vector2(x + bevel, y + h),
		Vector2(x, y + h - bevel),
		Vector2(x, y + bevel),
	])
