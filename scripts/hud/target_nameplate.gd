extends MarginContainer
class_name TargetNameplate

const COMBAT_WIDTH: float = 196.0
const SHIELD_COLOR: Color = Color(0.16, 0.57, 1.0, 0.96)
const HULL_COLOR: Color = Color(0.96, 0.2, 0.28, 0.96)
const BAR_OUTLINE: Color = Color(0.008, 0.014, 0.025, 0.98)
const BAR_TRACK: Color = Color(0.025, 0.04, 0.065, 0.91)
const AUXILIARY_COLOR: Color = Color(0.2, 0.95, 1.0, 1.0)

@onready var _auxiliary: HBoxContainer = $HBox
@onready var _indicator: ColorRect = $HBox/StateIndicator
@onready var _auxiliary_label: Label = $HBox/Label
@onready var _combat: VBoxContainer = $Combat
@onready var _faction_label: Label = $Combat/Header/Faction
@onready var _name_label: Label = $Combat/Identity/Name
@onready var _distance_label: Label = $Combat/Header/Distance
@onready var _shield_row: Control = $Combat/Shield
@onready var _shield_caption: Label = $Combat/Shield/Caption
@onready var _hull_row: Control = $Combat/Hull
@onready var _hull_caption: Label = $Combat/Hull/Caption

var _combat_active: bool = false
var _shield_ratio: float = 0.0
var _hull_ratio: float = 0.0

func _ready() -> void:
	resized.connect(_redraw_bars)
	_combat.resized.connect(_redraw_bars)
	_shield_row.resized.connect(_redraw_bars)
	_hull_row.resized.connect(_redraw_bars)
	_shield_row.item_rect_changed.connect(_redraw_bars)
	_hull_row.item_rect_changed.connect(_redraw_bars)
	reset_display()

func show_combat(faction_name: String, unit_name: String, distance_text: String,
		hull: float, max_hull: float, shield: float, max_shield: float) -> void:
	var changed: bool = not _combat_active
	_combat_active = true
	_auxiliary.hide()
	_indicator.hide()
	_combat.show()
	custom_minimum_size = Vector2(COMBAT_WIDTH, 0.0)
	_faction_label.text = faction_name.to_upper()
	_name_label.text = unit_name
	_distance_label.text = distance_text
	var has_shield: bool = is_finite(max_shield) and max_shield > 0.0
	changed = changed or _shield_row.visible != has_shield
	_shield_row.visible = has_shield
	_shield_caption.text = _resource_caption("SHLD", shield, max_shield)
	_hull_caption.text = _resource_caption("HULL", hull, max_hull)
	var next_shield_ratio: float = _resource_ratio(shield, max_shield)
	var next_hull_ratio: float = _resource_ratio(hull, max_hull)
	changed = changed or next_shield_ratio != _shield_ratio or next_hull_ratio != _hull_ratio
	_shield_ratio = next_shield_ratio
	_hull_ratio = next_hull_ratio
	if changed:
		queue_redraw()

func show_auxiliary(text: String, indicator_color: Color, show_indicator: bool = true) -> void:
	if _combat_active:
		reset_display()
	_auxiliary.show()
	_auxiliary_label.text = text
	_indicator.color = indicator_color
	_indicator.visible = show_indicator

func reset_display() -> void:
	scale = Vector2.ONE
	pivot_offset = Vector2.ZERO
	_combat_active = false
	_combat.hide()
	_auxiliary.show()
	_indicator.hide()
	_indicator.color = AUXILIARY_COLOR
	_auxiliary_label.text = ""
	_faction_label.text = ""
	_name_label.text = ""
	_distance_label.text = ""
	_shield_caption.text = ""
	_hull_caption.text = ""
	_shield_row.show()
	_hull_row.show()
	_shield_ratio = 0.0
	_hull_ratio = 0.0
	custom_minimum_size = Vector2.ZERO
	# Detached pooled controls retain their old size until a container sorts them.
	size = get_combined_minimum_size()
	queue_redraw()

func _draw() -> void:
	if not _combat_active:
		return
	var bar_rect: Rect2 = Rect2(_combat.position + _hull_row.position, _hull_row.size)
	if _shield_row.visible:
		bar_rect = bar_rect.merge(Rect2(_combat.position + _shield_row.position, _shield_row.size))
	if bar_rect.size.x < 4.0 or bar_rect.size.y < 4.0:
		return
	# Both resources share one outer silhouette and one continuous dark track.
	draw_colored_polygon(_clipped_rect(bar_rect, 5.0), BAR_OUTLINE)
	var track_rect: Rect2 = bar_rect.grow(-1.0)
	draw_colored_polygon(_clipped_rect(track_rect, 4.0), BAR_TRACK)
	var inner: Rect2 = bar_rect.grow(-2.0)
	if _shield_row.visible:
		var half_size: Vector2 = Vector2(inner.size.x, inner.size.y * 0.5)
		_draw_resource_section(Rect2(inner.position, half_size), _shield_ratio, SHIELD_COLOR, true, false)
		_draw_resource_section(Rect2(inner.position + Vector2(0.0, half_size.y), half_size), _hull_ratio, HULL_COLOR, false, true)
		var middle: float = inner.position.y + half_size.y
		draw_line(Vector2(inner.position.x, middle), Vector2(inner.end.x, middle), BAR_OUTLINE, 1.0)
	else:
		_draw_resource_section(inner, _hull_ratio, HULL_COLOR, true, true)
	for tick: int in range(1, 5):
		var tick_x: float = bar_rect.position.x + bar_rect.size.x * float(tick) / 5.0
		draw_line(Vector2(tick_x, bar_rect.position.y + 3.0),
			Vector2(tick_x, bar_rect.end.y - 2.0), Color(0.01, 0.02, 0.035, 0.45), 1.0)

func _draw_resource_section(section: Rect2, ratio: float, tint: Color, clip_top: bool, clip_bottom: bool) -> void:
	if ratio > 0.0:
		var fill_rect: Rect2 = section
		fill_rect.size.x *= ratio
		# Only corners on the outside of the shared bar receive an angled cut.
		var cut: float = minf(3.0, minf(fill_rect.size.x * 0.5, fill_rect.size.y * 0.5))
		var top_cut: float = cut if clip_top else 0.0
		var bottom_cut: float = cut if clip_bottom else 0.0
		var points: PackedVector2Array = PackedVector2Array([fill_rect.position])
		points.append(Vector2(fill_rect.end.x - top_cut, fill_rect.position.y))
		if top_cut > 0.0:
			points.append(Vector2(fill_rect.end.x, fill_rect.position.y + top_cut))
		points.append(fill_rect.end)
		points.append(Vector2(fill_rect.position.x + bottom_cut, fill_rect.end.y))
		if bottom_cut > 0.0:
			points.append(Vector2(fill_rect.position.x, fill_rect.end.y - bottom_cut))
		draw_colored_polygon(points, tint)
		if clip_top and fill_rect.size.x > 6.0:
			draw_line(fill_rect.position + Vector2(1.0, 0.5),
				fill_rect.position + Vector2(fill_rect.size.x - 3.0, 0.5),
				tint.lightened(0.55), 1.0)

func _clipped_rect(rect: Rect2, cut: float) -> PackedVector2Array:
	var corner: float = minf(cut, minf(rect.size.x * 0.5, rect.size.y * 0.5))
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x - corner, rect.position.y),
		Vector2(rect.end.x, rect.position.y + corner),
		rect.end,
		Vector2(rect.position.x + corner, rect.end.y),
		Vector2(rect.position.x, rect.end.y - corner),
	])

func _resource_ratio(value: float, capacity: float) -> float:
	if not is_finite(value) or not is_finite(capacity) or capacity <= 0.0:
		return 0.0
	return clampf(value / capacity, 0.0, 1.0)

func _resource_caption(resource_name: String, value: float, capacity: float) -> String:
	var safe_value: float = maxf(value, 0.0) if is_finite(value) else 0.0
	var safe_capacity: float = maxf(capacity, 0.0) if is_finite(capacity) else 0.0
	return "%s  %d / %d" % [resource_name, int(ceil(safe_value)), int(ceil(safe_capacity))]

func _redraw_bars() -> void:
	if _combat_active:
		queue_redraw()
