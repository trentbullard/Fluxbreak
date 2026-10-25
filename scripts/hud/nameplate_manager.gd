# Screen-space identities and live durability for visible combatants and salvage.
extends Control
class_name NameplateManager

## Pooled view shared by combat, POI and gateway nameplates.
@export var nameplate_scene: PackedScene
## Maximum range at which a nameplate can be displayed.
@export var show_within_meters: int = 30000
## Gap between the projected object position and its nameplate's lower edge.
@export var pixel_offset_up: int = 35
## Combat plates retain their normal size within this camera-relative distance.
@export_range(1.0, 5000.0, 25.0) var combat_full_size_distance: float = 400.0
## Small distant plates retain health awareness without filling the screen.
@export_range(0.05, 1.0, 0.05) var combat_min_scale: float = 0.2
## Existing docking state used to distinguish visited POIs.
@export var docking_manager_path: NodePath

const POI_UNVISITED_COLOR: Color = Color(0.2, 0.95, 1.0, 1.0)
const POI_VISITED_COLOR: Color = Color(1.0, 0.72, 0.2, 1.0)

var _camera: Camera3D
var _ship: Node3D
var _docking_manager: DockingManager
var _pool: Array[TargetNameplate] = []
var _map: Dictionary[Node3D, TargetNameplate] = {}

func _ready() -> void:
	_resolve_docking_manager()

func _exit_tree() -> void:
	for target: Node3D in _map:
		_disconnect_target(target)
	_map.clear()
	# Views still attached to this manager are freed with their parent.
	for ui: TargetNameplate in _pool:
		if is_instance_valid(ui):
			ui.free()
	_pool.clear()

func init(cam: Camera3D, ship: Node3D) -> void:
	_camera = cam
	_ship = ship
	_resolve_docking_manager()

func _process(_dt: float) -> void:
	if not is_instance_valid(_camera) or nameplate_scene == null:
		return
	_sync_targets()

func _sync_targets() -> void:
	if not is_instance_valid(_camera) or nameplate_scene == null:
		return
	var candidates: Array[Node] = get_tree().get_nodes_in_group("targets")
	candidates.append_array(get_tree().get_nodes_in_group("pois"))
	candidates.append_array(get_tree().get_nodes_in_group("boss_gateways"))
	var visible_targets: Dictionary[Node3D, float] = {}
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var ship_pos: Vector3 = _ship.global_position if is_instance_valid(_ship) else _camera.global_position
	var range_m: float = float(maxi(show_within_meters, 0))
	for candidate: Node in candidates:
		var target: Node3D = candidate as Node3D
		if target == null or target.is_queued_for_deletion() or not target.is_visible_in_tree() or visible_targets.has(target):
			continue
		var pos3: Vector3 = target.global_position
		var distance_sq: float = pos3.distance_squared_to(ship_pos)
		if distance_sq > range_m * range_m or not _camera.is_position_in_frustum(pos3):
			continue
		visible_targets[target] = distance_sq
	# Recycle departing views before allocating arrivals, even during a full turn.
	for target: Node3D in _map.keys():
		if not visible_targets.has(target):
			_release_target(target)
	for target: Node3D in visible_targets:
		if not _map.has(target):
			var created: TargetNameplate = _pool_take()
			if created == null:
				continue
			add_child(created)
			_map[target] = created
			target.tree_exited.connect(_on_target_tree_exited.bind(target), CONNECT_ONE_SHOT)
		var ui: TargetNameplate = _map[target]
		_update_nameplate(ui, target, HudDistanceFormatter.format_distance(sqrt(visible_targets[target])))
		var view_scale: float = 1.0
		if target is Enemy or target is TargetObject:
			view_scale = _combat_scale_for_distance_squared(target.global_position.distance_squared_to(_camera.global_position))
		ui.pivot_offset = Vector2.ZERO
		ui.scale = Vector2.ONE * view_scale
		ui.show()
		_place_center_bottom(ui, _camera.unproject_position(target.global_position), vp_size)

func _update_nameplate(ui: TargetNameplate, target: Node3D, distance_text: String) -> void:
	if target is Enemy:
		var enemy: Enemy = target as Enemy
		var faction_name: String = enemy.get_faction_display_name().strip_edges()
		if faction_name.is_empty():
			faction_name = String(enemy.get_faction_id()).replace("_", " ").capitalize()
		if faction_name.is_empty():
			faction_name = "Unknown"
		ui.show_combat(faction_name, enemy.display_name if not enemy.display_name.is_empty() else "Enemy", distance_text, enemy.hull, enemy.eff_max_hull, enemy.shield, enemy.eff_max_shield)
	elif target is TargetObject:
		var salvage: TargetObject = target as TargetObject
		ui.show_combat("Neutral", salvage.display_name if not salvage.display_name.is_empty() else "Target", distance_text, salvage.hull, salvage.max_hull, salvage.shield, salvage.max_shield)
	elif target is PoiInstance:
		var poi: PoiInstance = target as PoiInstance
		ui.show_auxiliary("%s [%s]\n%s" % [poi.display_name, _get_poi_type_tag(poi), distance_text], _poi_indicator_color(poi))
	elif target is BossGateway:
		var gateway: BossGateway = target as BossGateway
		ui.show_auxiliary("%s\n%s  •  Dock to inspect" % [gateway.get_display_name(), distance_text], gateway.get_marker_color())
	else:
		ui.show_auxiliary("%s\n%s" % [target.name, distance_text], Color.WHITE, false)

func _pool_take() -> TargetNameplate:
	if _pool.is_empty():
		return nameplate_scene.instantiate() as TargetNameplate
	return _pool.pop_back()

func _pool_release(ui: TargetNameplate) -> void:
	ui.reset_display()
	ui.hide()
	if ui.get_parent() != null:
		ui.get_parent().remove_child(ui)
	_pool.push_back(ui)

func _on_target_tree_exited(target: Node3D) -> void:
	_release_target(target)

func _disconnect_target(target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	var callback: Callable = _on_target_tree_exited.bind(target)
	if target.tree_exited.is_connected(callback):
		target.tree_exited.disconnect(callback)

func _release_target(target: Node3D) -> void:
	if not _map.has(target):
		return
	var ui: TargetNameplate = _map[target]
	_map.erase(target)
	_disconnect_target(target)
	_pool_release(ui)

func _place_center_bottom(ui: Control, screen_pos: Vector2, vp_size: Vector2) -> void:
	ui.size = ui.get_combined_minimum_size()
	var s: Vector2 = ui.size * ui.scale
	var pos: Vector2 = screen_pos - Vector2(s.x * 0.5, s.y) - Vector2(0.0, float(pixel_offset_up) * ui.scale.y)
	pos.x = clampf(pos.x, 0.0, maxf(vp_size.x - s.x, 0.0))
	pos.y = clampf(pos.y, 0.0, maxf(vp_size.y - s.y, 0.0))
	ui.position = pos

func _combat_scale_for_distance_squared(distance_sq: float) -> float:
	var near_distance: float = maxf(combat_full_size_distance, 1.0)
	var minimum: float = clampf(combat_min_scale, 0.05, 1.0)
	if distance_sq <= near_distance * near_distance:
		return 1.0
	var floor_distance: float = near_distance / minimum
	if distance_sq >= floor_distance * floor_distance:
		return minimum
	return near_distance / sqrt(distance_sq)

func _get_poi_type_tag(poi: PoiInstance) -> String:
	match poi.poi_type:
		PoiDef.PoiType.OFFENSE:
			return "ATK"
		PoiDef.PoiType.DEFENSE:
			return "DEF"
		PoiDef.PoiType.UTILITY:
			return "UTL"
	return "POI"

func _resolve_docking_manager() -> void:
	if docking_manager_path != NodePath(""):
		_docking_manager = get_node_or_null(docking_manager_path) as DockingManager

func _poi_indicator_color(poi: PoiInstance) -> Color:
	var is_visited: bool = is_instance_valid(_docking_manager) and _docking_manager.is_poi_visited(poi)
	return POI_VISITED_COLOR if is_visited else POI_UNVISITED_COLOR
