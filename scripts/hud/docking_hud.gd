# scripts/hud/docking_hud.gd (Godot 4.5)
# Displays the docking countdown when player is within range of a POI.
extends Control
class_name DockingHud

@export var docking_manager_path: NodePath
@export var label_settings: LabelSettings

var _docking_manager: DockingManager
var _label: Label
var _is_docking: bool = false


func _ready() -> void:
	# Create the label
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if label_settings != null:
		_label.label_settings = label_settings
	_label.add_theme_font_size_override("font_size", 32)
	add_child(_label)
	
	# Position at center of screen
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.4
	anchor_bottom = 0.4
	offset_left = -150
	offset_right = 150
	offset_top = -30
	offset_bottom = 30
	
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# Hide initially
	visible = false
	
	# Connect to docking manager
	if docking_manager_path != NodePath(""):
		_docking_manager = get_node_or_null(docking_manager_path) as DockingManager
		_connect_signals()


func _connect_signals() -> void:
	if _docking_manager == null:
		return
	
	_docking_manager.docking_started.connect(_on_docking_started)
	_docking_manager.docking_progress.connect(_on_docking_progress)
	_docking_manager.docking_cancelled.connect(_on_docking_cancelled)
	_docking_manager.docking_complete.connect(_on_docking_complete)


func _on_docking_started(poi: PoiInstance) -> void:
	_is_docking = true
	visible = true
	_update_label(poi, _docking_manager.get_docking_timer())


func _on_docking_progress(poi: PoiInstance, time_remaining: float) -> void:
	_update_label(poi, time_remaining)


func _on_docking_cancelled(_poi: PoiInstance) -> void:
	_is_docking = false
	visible = false


func _on_docking_complete(_poi: PoiInstance) -> void:
	_is_docking = false
	visible = false


func _update_label(poi: PoiInstance, time_remaining: float) -> void:
	var seconds: int = ceili(time_remaining)
	var poi_name: String = poi.get_display_name() if poi != null else "POI"
	_label.text = "Docking at %s... %ds" % [poi_name, seconds]
	
	# Color based on time remaining
	if seconds <= 1:
		_label.modulate = Color(0.3, 1.0, 0.4)  # Green when almost done
	else:
		_label.modulate = Color(1.0, 1.0, 1.0)  # White otherwise


## Initialize with external reference
func init(docking_manager: DockingManager) -> void:
	_docking_manager = docking_manager
	_connect_signals()

