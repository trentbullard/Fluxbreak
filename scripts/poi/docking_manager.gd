# scripts/poi/docking_manager.gd (Godot 4.5)
# Manages docking interactions between the player ship and POIs.
# Detects when player is within docking range, manages countdown, and triggers upgrade menu.
extends Node
class_name DockingManager

signal docking_started(poi: PoiInstance)
signal docking_progress(poi: PoiInstance, time_remaining: float)
signal docking_cancelled(poi: PoiInstance)
signal docking_complete(poi: PoiInstance)

@export var ship_path: NodePath
@export var poi_spawner_path: NodePath
@export var upgrade_menu_path: NodePath
@export var docking_time: float = 3.0  # Default docking countdown time
@export var revisit_docking_time: float = 5.0  # Docking time for POIs already visited

var _ship: Node3D
var _poi_spawner: PoiSpawner
var _upgrade_menu: UpgradeMenu

## Currently docking POI (null if not docking)
var _docking_poi: PoiInstance = null

## Time remaining in docking countdown
var _docking_timer: float = 0.0

## POIs that have been visited (opened menu but didn't purchase)
var _visited_pois: Array[int] = []  # Stores instance_ids

## POIs that are completed (purchased upgrade, should not allow re-docking)
var _completed_pois: Array[int] = []  # Stores instance_ids

## Whether upgrade menu is currently open (pause docking detection)
var _menu_open: bool = false


func _ready() -> void:
	if ship_path != NodePath(""):
		_ship = get_node_or_null(ship_path) as Node3D
	if poi_spawner_path != NodePath(""):
		_poi_spawner = get_node_or_null(poi_spawner_path) as PoiSpawner
	if upgrade_menu_path != NodePath(""):
		_upgrade_menu = get_node_or_null(upgrade_menu_path) as UpgradeMenu
		if _upgrade_menu != null:
			_upgrade_menu.menu_closed.connect(_on_upgrade_menu_closed)
			_upgrade_menu.upgrade_selected.connect(_on_upgrade_purchased)
			_upgrade_menu.weapon_selected.connect(_on_weapon_purchased)


func _process(delta: float) -> void:
	if _ship == null or _poi_spawner == null:
		return
	
	# Don't process docking if game is paused or menu is open
	if get_tree().paused or _menu_open:
		return
	
	var ship_pos: Vector3 = _ship.global_position
	var closest_poi: PoiInstance = null
	var closest_distance: float = INF
	
	# Find the closest POI within docking range (exclude completed POIs)
	for poi: PoiInstance in _poi_spawner.get_active_pois():
		if not is_instance_valid(poi):
			continue
		# Skip completed POIs (player already purchased from them)
		if poi.get_instance_id() in _completed_pois:
			continue
		
		var docking_radius: float = _get_docking_radius(poi)
		var distance: float = ship_pos.distance_to(poi.global_position)
		
		if distance <= docking_radius and distance < closest_distance:
			closest_poi = poi
			closest_distance = distance
	
	# Handle docking state
	if _docking_poi != null:
		# Currently docking - check if still in range
		if closest_poi == _docking_poi:
			# Still in range, continue countdown
			_docking_timer -= delta
			docking_progress.emit(_docking_poi, _docking_timer)
			
			if _docking_timer <= 0.0:
				# Docking complete!
				_complete_docking()
		else:
			# Left docking range, cancel
			_cancel_docking()
	else:
		# Not docking - check if we should start
		if closest_poi != null:
			_start_docking(closest_poi)


func _start_docking(poi: PoiInstance) -> void:
	_docking_poi = poi
	_docking_timer = _get_docking_time(poi)
	docking_started.emit(poi)


func _cancel_docking() -> void:
	var poi: PoiInstance = _docking_poi
	_docking_poi = null
	_docking_timer = 0.0
	docking_cancelled.emit(poi)


func _complete_docking() -> void:
	var poi: PoiInstance = _docking_poi
	# Mark as visited (but not completed - can still re-dock)
	if poi.get_instance_id() not in _visited_pois:
		_visited_pois.append(poi.get_instance_id())
	_docking_poi = null
	_docking_timer = 0.0
	_menu_open = true  # Pause docking detection while menu is open
	docking_complete.emit(poi)
	
	# Show upgrade menu
	if _upgrade_menu != null:
		_upgrade_menu.show_for_poi(poi)


func _get_docking_radius(poi: PoiInstance) -> float:
	if poi.poi_def != null:
		return poi.poi_def.docking_radius
	return 200.0  # Default


func _get_docking_time(poi: PoiInstance) -> float:
	# Use longer docking time for revisits
	if poi.get_instance_id() in _visited_pois:
		return revisit_docking_time
	if poi.poi_def != null:
		return poi.poi_def.docking_time
	return docking_time


func _on_upgrade_menu_closed() -> void:
	_menu_open = false


func _on_upgrade_purchased(_upgrade: Upgrade) -> void:
	# Mark the POI as completed (will be destroyed by upgrade menu)
	# This prevents any edge cases with re-docking
	pass


func _on_weapon_purchased(_weapon: WeaponDef) -> void:
	# Mark the POI as completed (will be destroyed by upgrade menu)
	pass


## Check if a POI has been visited
func is_poi_visited(poi: PoiInstance) -> bool:
	return poi.get_instance_id() in _visited_pois


## Get the currently docking POI (or null)
func get_docking_poi() -> PoiInstance:
	return _docking_poi


## Get the current docking timer value
func get_docking_timer() -> float:
	return _docking_timer


## Initialize with external references
func init(ship: Node3D, poi_spawner: PoiSpawner) -> void:
	_ship = ship
	_poi_spawner = poi_spawner
