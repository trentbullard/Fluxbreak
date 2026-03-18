# scripts/hud/poi_list_layer.gd (Godot 4.5)
# Displays a list of spawned POIs with their distances from the player.
extends Control
class_name PoiListLayer

@export var ship_path: NodePath
@export var poi_spawner_path: NodePath
@export var docking_manager_path: NodePath
@export var label_settings: LabelSettings
@export var update_interval: float = 0.25  # How often to update distances (seconds)
@export var max_display_count: int = 5     # Max POIs to show in list

const POI_UNVISITED_COLOR: Color = Color(0.2, 0.95, 1.0, 1.0)
const POI_VISITED_COLOR: Color = Color(1.0, 0.72, 0.2, 1.0)
const POI_INDICATOR_SIZE: Vector2 = Vector2(8.0, 8.0)

var _ship: Node3D
var _poi_spawner: PoiSpawner
var _docking_manager: DockingManager
var _container: VBoxContainer
var _header_label: Label
var _poi_rows: Array[HBoxContainer] = []
var _poi_indicators: Array[ColorRect] = []
var _poi_labels: Array[Label] = []
var _update_timer: float = 0.0

# Type to color/icon mapping
const TYPE_COLORS: Dictionary = {
	PoiDef.PoiType.OFFENSE: Color(1.0, 0.4, 0.3),   # Red
	PoiDef.PoiType.DEFENSE: Color(0.3, 0.9, 0.5),   # Green
	PoiDef.PoiType.UTILITY: Color(1.0, 0.85, 0.3),  # Yellow/Gold
}

const TYPE_ICONS: Dictionary = {
	PoiDef.PoiType.OFFENSE: "⚔",   # Swords
	PoiDef.PoiType.DEFENSE: "🛡",  # Shield
	PoiDef.PoiType.UTILITY: "🔧",  # Wrench
}

const TYPE_NAMES: Dictionary = {
	PoiDef.PoiType.OFFENSE: "ATK",
	PoiDef.PoiType.DEFENSE: "DEF",
	PoiDef.PoiType.UTILITY: "UTL",
}


func _ready() -> void:
	# Get references
	if ship_path != NodePath(""):
		_ship = get_node_or_null(ship_path) as Node3D
	if poi_spawner_path != NodePath(""):
		_poi_spawner = get_node_or_null(poi_spawner_path) as PoiSpawner
	if docking_manager_path != NodePath(""):
		_docking_manager = get_node_or_null(docking_manager_path) as DockingManager
	
	# Build UI
	_build_ui()
	
	# Connect to POI spawner signals
	if _poi_spawner != null:
		_poi_spawner.poi_spawned.connect(_on_poi_spawned)
		_poi_spawner.poi_counts_changed.connect(_on_poi_counts_changed)
	if _docking_manager != null and not _docking_manager.docking_complete.is_connected(_on_docking_complete):
		_docking_manager.docking_complete.connect(_on_docking_complete)
	
	# Initial update
	_update_list()


func _exit_tree() -> void:
	if _poi_spawner != null and is_instance_valid(_poi_spawner):
		if _poi_spawner.poi_spawned.is_connected(_on_poi_spawned):
			_poi_spawner.poi_spawned.disconnect(_on_poi_spawned)
		if _poi_spawner.poi_counts_changed.is_connected(_on_poi_counts_changed):
			_poi_spawner.poi_counts_changed.disconnect(_on_poi_counts_changed)
	if _docking_manager != null and is_instance_valid(_docking_manager):
		if _docking_manager.docking_complete.is_connected(_on_docking_complete):
			_docking_manager.docking_complete.disconnect(_on_docking_complete)


func _build_ui() -> void:
	# Create container for the list
	_container = VBoxContainer.new()
	_container.add_theme_constant_override("separation", 2)
	add_child(_container)
	
	# Create header label
	_header_label = Label.new()
	_header_label.text = "— POIs —"
	if label_settings != null:
		_header_label.label_settings = label_settings
	_container.add_child(_header_label)
	
	# Pre-create pool of labels for POI entries
	for i in max_display_count:
		var row: HBoxContainer = HBoxContainer.new()
		row.visible = false
		row.add_theme_constant_override("separation", 6)
		var indicator: ColorRect = ColorRect.new()
		indicator.custom_minimum_size = POI_INDICATOR_SIZE
		indicator.size = POI_INDICATOR_SIZE
		indicator.color = POI_UNVISITED_COLOR
		row.add_child(indicator)
		var lbl: Label = Label.new()
		if label_settings != null:
			lbl.label_settings = label_settings
		row.add_child(lbl)
		_container.add_child(row)
		_poi_rows.append(row)
		_poi_indicators.append(indicator)
		_poi_labels.append(lbl)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_update_list()


func _update_list() -> void:
	if _poi_spawner == null or not is_instance_valid(_poi_spawner):
		return

	var pois: Array[PoiInstance] = []
	for poi: PoiInstance in _poi_spawner.get_active_pois():
		if _can_use_poi(poi):
			pois.append(poi)

	# Sort by distance from player (closest first)
	var has_ship: bool = _can_use_node_3d(_ship)
	var ship_pos: Vector3 = Vector3.ZERO
	if has_ship:
		ship_pos = _ship.global_position
		pois.sort_custom(func(a: PoiInstance, b: PoiInstance) -> bool:
			if not _can_use_poi(a):
				return false
			if not _can_use_poi(b):
				return true
			return a.global_position.distance_squared_to(ship_pos) < b.global_position.distance_squared_to(ship_pos)
		)
	
	# Update header
	var total: int = pois.size()
	if total == 0:
		_header_label.text = "— POIs —"
	else:
		_header_label.text = "— POIs (%d) —" % total
	
	# Update labels
	for i in max_display_count:
		var row: HBoxContainer = _poi_rows[i]
		var indicator: ColorRect = _poi_indicators[i]
		var lbl: Label = _poi_labels[i]
		
		if i < pois.size():
			var poi: PoiInstance = pois[i]
			if not _can_use_poi(poi):
				row.visible = false
				continue
			
			row.visible = true
			
			# Calculate distance
			var distance: float = 0.0
			if has_ship:
				distance = sqrt(poi.global_position.distance_squared_to(ship_pos))
			
			# Format: [TYPE] Name - 1234m
			var type_name: String = TYPE_NAMES.get(poi.poi_type, "???")
			var display_name: String = poi.get_display_name()
			var distance_str: String = _format_distance(distance)
			
			lbl.text = "[%s] %s - %s" % [type_name, display_name, distance_str]
			var is_visited: bool = _docking_manager != null and _docking_manager.is_poi_visited(poi)
			indicator.color = POI_VISITED_COLOR if is_visited else POI_UNVISITED_COLOR
			
			# Apply color based on type
			var color: Color = TYPE_COLORS.get(poi.poi_type, Color.WHITE)
			lbl.modulate = color
		else:
			row.visible = false
			indicator.color = POI_UNVISITED_COLOR


func _format_distance(distance: float) -> String:
	if distance < 1000.0:
		return "%dm" % int(round(distance))
	else:
		return "%.1fkm" % (distance / 1000.0)


func _on_poi_spawned(_poi: PoiInstance) -> void:
	# Force immediate update when a new POI spawns
	_update_list()


func _on_poi_counts_changed(_offense: int, _defense: int, _utility: int, _total: int) -> void:
	# Force update on count change (handles removals too)
	_update_list()


func _on_docking_complete(_poi: PoiInstance) -> void:
	_update_list()


## Initialize with external references (called by HUD manager if needed)
func init(ship: Node3D, poi_spawner: PoiSpawner) -> void:
	_ship = ship
	_poi_spawner = poi_spawner
	
	if _poi_spawner != null:
		if not _poi_spawner.poi_spawned.is_connected(_on_poi_spawned):
			_poi_spawner.poi_spawned.connect(_on_poi_spawned)
		if not _poi_spawner.poi_counts_changed.is_connected(_on_poi_counts_changed):
			_poi_spawner.poi_counts_changed.connect(_on_poi_counts_changed)
	
	_update_list()


func _can_use_node_3d(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return node.is_inside_tree()


func _can_use_poi(poi: PoiInstance) -> bool:
	if poi == null or not is_instance_valid(poi):
		return false
	return poi.is_inside_tree()
