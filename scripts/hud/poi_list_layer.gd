# scripts/hud/poi_list_layer.gd (Godot 4.5)
# Displays a list of spawned POIs with their distances from the player.
extends Control
class_name PoiListLayer

@export var ship_path: NodePath
@export var poi_spawner_path: NodePath
@export var label_settings: LabelSettings
@export var update_interval: float = 0.25  # How often to update distances (seconds)
@export var max_display_count: int = 5     # Max POIs to show in list

var _ship: Node3D
var _poi_spawner: PoiSpawner
var _container: VBoxContainer
var _header_label: Label
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
	
	# Build UI
	_build_ui()
	
	# Connect to POI spawner signals
	if _poi_spawner != null:
		_poi_spawner.poi_spawned.connect(_on_poi_spawned)
		_poi_spawner.poi_counts_changed.connect(_on_poi_counts_changed)
	
	# Initial update
	_update_list()


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
		var lbl: Label = Label.new()
		lbl.visible = false
		if label_settings != null:
			lbl.label_settings = label_settings
		_container.add_child(lbl)
		_poi_labels.append(lbl)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_update_list()


func _update_list() -> void:
	if _poi_spawner == null:
		return
	
	var pois: Array[PoiInstance] = _poi_spawner.get_active_pois()
	
	# Sort by distance from player (closest first)
	if _ship != null:
		var ship_pos: Vector3 = _ship.global_position
		pois.sort_custom(func(a: PoiInstance, b: PoiInstance) -> bool:
			if not is_instance_valid(a):
				return false
			if not is_instance_valid(b):
				return true
			return a.global_position.distance_to(ship_pos) < b.global_position.distance_to(ship_pos)
		)
	
	# Update header
	var total: int = pois.size()
	if total == 0:
		_header_label.text = "— POIs —"
	else:
		_header_label.text = "— POIs (%d) —" % total
	
	# Update labels
	for i in max_display_count:
		var lbl: Label = _poi_labels[i]
		
		if i < pois.size():
			var poi: PoiInstance = pois[i]
			if not is_instance_valid(poi):
				lbl.visible = false
				continue
			
			lbl.visible = true
			
			# Calculate distance
			var distance: float = 0.0
			if _ship != null:
				distance = poi.global_position.distance_to(_ship.global_position)
			
			# Format: [TYPE] Name - 1234m
			var type_name: String = TYPE_NAMES.get(poi.poi_type, "???")
			var display_name: String = poi.get_display_name()
			var distance_str: String = _format_distance(distance)
			
			lbl.text = "[%s] %s - %s" % [type_name, display_name, distance_str]
			
			# Apply color based on type
			var color: Color = TYPE_COLORS.get(poi.poi_type, Color.WHITE)
			lbl.modulate = color
		else:
			lbl.visible = false


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
