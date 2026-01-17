# offscreen_icon_registry.gd (Godot 4.5)
# Modular registry that maps object kinds/types to icon drawing callbacks.
# Extend this to add SVG icons or custom textures later.
extends RefCounted
class_name OffscreenIconRegistry

enum IconShape { TRIANGLE, CIRCLE, SQUARE, DIAMOND }

# Entry: defines how a given kind should be displayed
class IconEntry:
	var shape: IconShape = IconShape.TRIANGLE
	var color: Color = Color.WHITE
	var size: float = 16.0
	var outline_color: Color = Color.BLACK
	var outline_width: float = 2.0
	var texture: Texture2D = null  # Future: SVG or custom icon
	
	func _init(p_shape: IconShape = IconShape.TRIANGLE, p_color: Color = Color.WHITE, p_size: float = 16.0) -> void:
		shape = p_shape
		color = p_color
		size = p_size

# kind -> IconEntry mapping
var _entries: Dictionary[String, IconEntry] = {}

# Default fallback
var _default_entry: IconEntry = IconEntry.new(IconShape.CIRCLE, Color(0.6, 0.6, 0.6, 0.8), 12.0)

func _init() -> void:
	_register_defaults()

func _register_defaults() -> void:
	# Enemies - red triangles (hostile, aggressive)
	var enemy_entry := IconEntry.new(IconShape.TRIANGLE, Color(1.0, 0.3, 0.3, 0.9), 14.0)
	enemy_entry.outline_color = Color(0.6, 0.4, 0.4, 1.0)
	register("enemy", enemy_entry)
	
	# Targets (asteroids, wrecks) - orange squares (neutral, destructible)
	var target_entry := IconEntry.new(IconShape.SQUARE, Color(1.0, 0.6, 0.2, 0.9), 12.0)
	target_entry.outline_color = Color(0.3, 0.15, 0.0, 1.0)
	register("target", target_entry)
	
	# Drops/pickups - green diamonds (beneficial)
	var drop_entry := IconEntry.new(IconShape.DIAMOND, Color(0.3, 1.0, 0.4, 0.9), 10.0)
	drop_entry.outline_color = Color(0.0, 0.2, 0.05, 1.0)
	register("drop", drop_entry)
	
	# POI/waypoint - cyan circle (generic fallback)
	var poi_entry := IconEntry.new(IconShape.CIRCLE, Color(0.3, 0.9, 1.0, 0.9), 14.0)
	poi_entry.outline_color = Color(0.0, 0.2, 0.3, 1.0)
	register("poi", poi_entry)
	
	# POI Offense - red/orange circle with larger size
	var poi_offense := IconEntry.new(IconShape.CIRCLE, Color(1.0, 0.4, 0.3, 0.95), 16.0)
	poi_offense.outline_color = Color(0.3, 0.1, 0.05, 1.0)
	poi_offense.outline_width = 2.5
	register("poi_offense", poi_offense)
	
	# POI Defense - green circle
	var poi_defense := IconEntry.new(IconShape.CIRCLE, Color(0.3, 0.9, 0.5, 0.95), 16.0)
	poi_defense.outline_color = Color(0.05, 0.25, 0.1, 1.0)
	poi_defense.outline_width = 2.5
	register("poi_defense", poi_defense)
	
	# POI Utility - yellow/gold circle
	var poi_utility := IconEntry.new(IconShape.CIRCLE, Color(1.0, 0.85, 0.3, 0.95), 16.0)
	poi_utility.outline_color = Color(0.3, 0.25, 0.05, 1.0)
	poi_utility.outline_width = 2.5
	register("poi_utility", poi_utility)

func register(kind: String, entry: IconEntry) -> void:
	_entries[kind] = entry

func unregister(kind: String) -> void:
	_entries.erase(kind)

func get_entry(kind: String) -> IconEntry:
	if _entries.has(kind):
		return _entries[kind]
	return _default_entry

func has_kind(kind: String) -> bool:
	return _entries.has(kind)

# Utility: draw the icon shape at a given position with rotation
# rotation_angle is in radians, points the icon toward the object
static func draw_icon(canvas: CanvasItem, entry: IconEntry, center: Vector2, rotation_angle: float) -> void:
	if entry.texture != null:
		# Future: draw texture with rotation
		var rect := Rect2(center - Vector2(entry.size, entry.size) * 0.5, Vector2(entry.size, entry.size))
		canvas.draw_texture_rect(entry.texture, rect, false, entry.color)
	else:
		_draw_shape(canvas, entry, center, rotation_angle)

static func _draw_shape(canvas: CanvasItem, entry: IconEntry, center: Vector2, angle: float) -> void:
	var s: float = entry.size
	
	match entry.shape:
		IconShape.TRIANGLE:
			_draw_triangle(canvas, center, s, angle, entry.color, entry.outline_color, entry.outline_width)
		IconShape.CIRCLE:
			_draw_circle(canvas, center, s * 0.5, entry.color, entry.outline_color, entry.outline_width)
		IconShape.SQUARE:
			_draw_square(canvas, center, s, angle, entry.color, entry.outline_color, entry.outline_width)
		IconShape.DIAMOND:
			_draw_diamond(canvas, center, s, angle, entry.color, entry.outline_color, entry.outline_width)

static func _draw_triangle(canvas: CanvasItem, center: Vector2, size: float, angle: float, fill: Color, outline: Color, outline_w: float) -> void:
	# Pointing triangle (arrow-like) - tip points in direction of angle
	var half: float = size * 0.5
	var tip := Vector2(half, 0.0)
	var base_l := Vector2(-half * 0.6, -half * 0.5)
	var base_r := Vector2(-half * 0.6, half * 0.5)
	
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	
	var p1: Vector2 = center + Vector2(tip.x * cos_a - tip.y * sin_a, tip.x * sin_a + tip.y * cos_a)
	var p2: Vector2 = center + Vector2(base_l.x * cos_a - base_l.y * sin_a, base_l.x * sin_a + base_l.y * cos_a)
	var p3: Vector2 = center + Vector2(base_r.x * cos_a - base_r.y * sin_a, base_r.x * sin_a + base_r.y * cos_a)
	
	var points: PackedVector2Array = [p1, p2, p3]
	
	# Fill
	canvas.draw_polygon(points, [fill])
	# Outline
	if outline_w > 0.0:
		canvas.draw_polyline([p1, p2, p3, p1], outline, outline_w, true)

static func _draw_circle(canvas: CanvasItem, center: Vector2, radius: float, fill: Color, outline: Color, outline_w: float) -> void:
	# Outline first (behind)
	if outline_w > 0.0:
		canvas.draw_circle(center, radius + outline_w * 0.5, outline)
	# Fill
	canvas.draw_circle(center, radius, fill)

static func _draw_square(canvas: CanvasItem, center: Vector2, size: float, angle: float, fill: Color, outline: Color, outline_w: float) -> void:
	var half: float = size * 0.5
	var corners: Array[Vector2] = [
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half)
	]
	
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	
	var points: PackedVector2Array = []
	for c in corners:
		var rotated := Vector2(c.x * cos_a - c.y * sin_a, c.x * sin_a + c.y * cos_a)
		points.append(center + rotated)
	
	canvas.draw_polygon(points, [fill])
	if outline_w > 0.0:
		points.append(points[0])  # Close the loop
		canvas.draw_polyline(points, outline, outline_w, true)

static func _draw_diamond(canvas: CanvasItem, center: Vector2, size: float, angle: float, fill: Color, outline: Color, outline_w: float) -> void:
	var half: float = size * 0.5
	var corners: Array[Vector2] = [
		Vector2(0, -half),   # top
		Vector2(half, 0),    # right
		Vector2(0, half),    # bottom
		Vector2(-half, 0)    # left
	]
	
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	
	var points: PackedVector2Array = []
	for c in corners:
		var rotated := Vector2(c.x * cos_a - c.y * sin_a, c.x * sin_a + c.y * cos_a)
		points.append(center + rotated)
	
	canvas.draw_polygon(points, [fill])
	if outline_w > 0.0:
		points.append(points[0])
		canvas.draw_polyline(points, outline, outline_w, true)
