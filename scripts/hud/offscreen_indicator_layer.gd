# scripts/hud/offscreen_indicator_layer.gd (Godot 4.5)
# Manages off-screen indicators that show direction to objects not currently visible.
# Icons rotate around the screen edge to indicate the 3D direction to turn.
extends Control
class_name OffscreenIndicatorLayer

@export var ship_path: NodePath
@export var edge_margin: float = 10.0  # Distance from screen edge for icons
@export var min_distance: float = 50.0  # Don't show indicators for very close objects
@export var max_distance: float = 30000.0  # Don't show indicators beyond this range
@export var fade_near_edge: bool = true  # Fade icons as they approach screen edge
@export var show_distance_text: bool = true
@export var distance_font_size: int = 10

var _camera: Camera3D
var _ship: Node3D
var _registry: OffscreenIconRegistry

# Tracked objects cache: node -> kind string
var _tracked: Dictionary[Node3D, String] = {}

func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_registry = OffscreenIconRegistry.new()
	
	if ship_path != NodePath(""):
		_ship = get_node_or_null(ship_path) as Node3D

func init(cam: Camera3D, ship: Node3D) -> void:
	_camera = cam
	_ship = ship

func _process(_dt: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	queue_redraw()

func _draw() -> void:
	if _camera == null:
		return
	
	_sync_tracked_objects()
	
	var vp_size: Vector2 = get_viewport_rect().size
	var screen_center: Vector2 = vp_size * 0.5
	var ship_pos: Vector3 = _ship.global_position if _ship != null else _camera.global_position
	var min_distance_sq: float = min_distance * min_distance
	var max_distance_sq: float = max_distance * max_distance
	
	for obj in _tracked.keys():
		if not is_instance_valid(obj):
			continue
		
		var kind: String = _tracked[obj]
		var obj_pos: Vector3 = obj.global_position
		var distance_sq: float = obj_pos.distance_squared_to(ship_pos)
		
		# Skip if too close or too far
		if distance_sq < min_distance_sq or distance_sq > max_distance_sq:
			continue
		
		var distance: float = sqrt(distance_sq)
		
		# Check if object is on screen (in frustum and in front)
		var is_in_frustum: bool = _camera.is_position_in_frustum(obj_pos)
		var is_behind: bool = _is_behind_camera(obj_pos)
		
		# If visible on screen, don't show indicator
		if is_in_frustum and not is_behind:
			var screen_pos: Vector2 = _camera.unproject_position(obj_pos)
			if _is_on_screen(screen_pos, vp_size):
				continue
		
		# Calculate screen-space direction
		var indicator_data: Dictionary = _calculate_indicator_position(obj_pos, vp_size, screen_center)
		var edge_pos: Vector2 = indicator_data["position"]
		var rotation_angle: float = indicator_data["angle"]
		
		# Get icon entry
		var entry: OffscreenIconRegistry.IconEntry = _registry.get_entry(kind)
		
		# Apply distance-based alpha fade
		var alpha_mult: float = _get_distance_alpha(distance)
		var adjusted_entry: OffscreenIconRegistry.IconEntry = _create_faded_entry(entry, alpha_mult)
		
		# Draw the icon
		OffscreenIconRegistry.draw_icon(self, adjusted_entry, edge_pos, rotation_angle)
		
		# Draw distance text if enabled
		if show_distance_text:
			_draw_distance_label(edge_pos, distance, rotation_angle, entry.size)

func _sync_tracked_objects() -> void:
	# Clear stale entries
	var to_remove: Array[Node3D] = []
	for obj in _tracked.keys():
		if not is_instance_valid(obj):
			to_remove.append(obj)
	for obj in to_remove:
		_tracked.erase(obj)
	
	# Add objects from relevant groups
	_sync_group("targets", "")  # Will auto-detect enemy vs target via meta
	_sync_group("drops", "drop")  # Nanobot swarms and other drops
	_sync_group("poi", "")       # Points of interest - auto-detect type
	_sync_group("boss_gateways", "boss_gateway")

func _sync_group(group_name: String, forced_kind: String) -> void:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)
	for node in nodes:
		var obj: Node3D = node as Node3D
		if obj == null:
			continue
		if obj == _ship:
			continue
		
		if not _tracked.has(obj):
			var kind: String = forced_kind
			if kind == "":
				kind = _detect_kind(obj)
			_tracked[obj] = kind
			
			# Connect to tree_exited for cleanup
			if not obj.tree_exited.is_connected(_on_object_removed):
				obj.tree_exited.connect(_on_object_removed.bind(obj))

func _detect_kind(obj: Node3D) -> String:
	if obj is Enemy:
		return "enemy"
	if obj is TargetObject:
		return "target"
	if obj is PoiInstance:
		var poi: PoiInstance = obj as PoiInstance
		match poi.poi_type:
			PoiDef.PoiType.OFFENSE:
				return "poi_offense"
			PoiDef.PoiType.DEFENSE:
				return "poi_defense"
			PoiDef.PoiType.UTILITY:
				return "poi_utility"
			_:
				return "poi"
	if obj is BossGateway:
		return "boss_gateway"
	if obj.has_meta("kind"):
		var kind_meta: String = String(obj.get_meta("kind"))
		if kind_meta != "":
			return kind_meta
	return "unknown"

func _on_object_removed(obj: Node3D) -> void:
	_tracked.erase(obj)

func _is_behind_camera(world_pos: Vector3) -> bool:
	var cam_transform: Transform3D = _camera.global_transform
	var to_obj: Vector3 = world_pos - cam_transform.origin
	var cam_forward: Vector3 = -cam_transform.basis.z
	return to_obj.dot(cam_forward) < 0.0

func _is_on_screen(screen_pos: Vector2, vp_size: Vector2) -> bool:
	var margin: float = edge_margin
	return screen_pos.x >= margin and screen_pos.x <= vp_size.x - margin and \
		   screen_pos.y >= margin and screen_pos.y <= vp_size.y - margin

func _calculate_indicator_position(world_pos: Vector3, vp_size: Vector2, screen_center: Vector2) -> Dictionary:
	# Project the 3D position to screen space, handling behind-camera cases
	var cam_transform: Transform3D = _camera.global_transform
	var to_obj: Vector3 = world_pos - cam_transform.origin
	
	# Get local-space direction (relative to camera orientation)
	var local_dir: Vector3 = cam_transform.basis.inverse() * to_obj.normalized()
	
	# Project to 2D screen space direction
	# X = right, Y = up, Z = forward in camera space
	# Screen: x = right, y = down
	var screen_dir: Vector2 = Vector2(local_dir.x, -local_dir.y).normalized()
	
	# If object is behind, we still use the screen direction
	# (the direction already accounts for this naturally)
	
	# Calculate the angle for icon rotation (pointing toward the object)
	var angle: float = atan2(screen_dir.y, screen_dir.x)
	
	# Find intersection with screen edge
	var edge_pos: Vector2 = _ray_to_edge(screen_center, screen_dir, vp_size)
	
	return {"position": edge_pos, "angle": angle}

func _ray_to_edge(origin: Vector2, direction: Vector2, vp_size: Vector2) -> Vector2:
	# Cast a ray from center and find where it hits the screen edge (with margin)
	var margin: float = edge_margin
	var min_x: float = margin
	var max_x: float = vp_size.x - margin
	var min_y: float = margin
	var max_y: float = vp_size.y - margin
	
	if direction.length_squared() < 0.0001:
		return origin
	
	direction = direction.normalized()
	
	# Calculate intersection with each edge
	var t_values: Array[float] = []
	
	# Left edge (x = min_x)
	if abs(direction.x) > 0.0001:
		var t: float = (min_x - origin.x) / direction.x
		if t > 0.0:
			var y: float = origin.y + direction.y * t
			if y >= min_y and y <= max_y:
				t_values.append(t)
	
	# Right edge (x = max_x)
	if abs(direction.x) > 0.0001:
		var t: float = (max_x - origin.x) / direction.x
		if t > 0.0:
			var y: float = origin.y + direction.y * t
			if y >= min_y and y <= max_y:
				t_values.append(t)
	
	# Top edge (y = min_y)
	if abs(direction.y) > 0.0001:
		var t: float = (min_y - origin.y) / direction.y
		if t > 0.0:
			var x: float = origin.x + direction.x * t
			if x >= min_x and x <= max_x:
				t_values.append(t)
	
	# Bottom edge (y = max_y)
	if abs(direction.y) > 0.0001:
		var t: float = (max_y - origin.y) / direction.y
		if t > 0.0:
			var x: float = origin.x + direction.x * t
			if x >= min_x and x <= max_x:
				t_values.append(t)
	
	if t_values.is_empty():
		return origin + direction * 100.0  # Fallback
	
	# Use the smallest positive t
	t_values.sort()
	var t_min: float = t_values[0]
	
	return origin + direction * t_min

func _get_distance_alpha(distance: float) -> float:
	# Fade out at far distances
	var fade_start: float = max_distance * 0.7
	if distance > fade_start:
		var fade_range: float = max_distance - fade_start
		return 1.0 - clamp((distance - fade_start) / fade_range, 0.0, 1.0)
	return 1.0

func _create_faded_entry(entry: OffscreenIconRegistry.IconEntry, alpha_mult: float) -> OffscreenIconRegistry.IconEntry:
	var faded: OffscreenIconRegistry.IconEntry = OffscreenIconRegistry.IconEntry.new(entry.shape, entry.color, entry.size)
	faded.color.a *= alpha_mult
	faded.outline_color = entry.outline_color
	faded.outline_color.a *= alpha_mult
	faded.outline_width = entry.outline_width
	faded.texture = entry.texture
	return faded

func _draw_distance_label(pos: Vector2, distance: float, angle: float, icon_size: float) -> void:
	var distance_text: String = HudDistanceFormatter.format_distance(distance)
	
	# Position text slightly offset from the icon, opposite the direction it points
	var offset_dir: Vector2 = Vector2(cos(angle), sin(angle))
	var text_offset: Vector2 = -offset_dir * (icon_size + 8.0)
	var text_pos: Vector2 = pos + text_offset
	
	# Simple text draw - use default font
	var font: Font = ThemeDB.fallback_font
	var font_size: int = distance_font_size
	
	# Draw with outline for readability
	draw_string_outline(font, text_pos, distance_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, 3, Color.BLACK)
	draw_string(font, text_pos, distance_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.9, 0.9, 0.9, 0.9))

# Public API for manual registration (e.g., for POIs or quest markers)
func register_icon_type(kind: String, shape: OffscreenIconRegistry.IconShape, color: Color, font_size: float = 14.0) -> void:
	var entry: OffscreenIconRegistry.IconEntry = OffscreenIconRegistry.IconEntry.new(shape, color, font_size)
	_registry.register(kind, entry)

func track_object(obj: Node3D, kind: String) -> void:
	if obj != null and not _tracked.has(obj):
		_tracked[obj] = kind
		if not obj.tree_exited.is_connected(_on_object_removed):
			obj.tree_exited.connect(_on_object_removed.bind(obj))

func untrack_object(obj: Node3D) -> void:
	_tracked.erase(obj)
