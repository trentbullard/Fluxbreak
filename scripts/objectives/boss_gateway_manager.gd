extends Node
class_name BossGatewayManager

signal gateway_spawned(gateway: BossGateway)
signal gateway_cleared()
signal docking_started(gateway: BossGateway)
signal docking_progress(gateway: BossGateway, time_remaining: float)
signal docking_cancelled(gateway: BossGateway)
signal docking_complete(gateway: BossGateway)
signal briefing_opened(gateway: BossGateway)
signal briefing_closed()

@export var ship_path: NodePath
@export var wave_director_path: NodePath
@export var poi_spawner_path: NodePath
@export var docking_manager_path: NodePath
@export var gateway_min_distance_from_ship: float = 550.0
## Extra clearance required before a declined gateway can offer its briefing again.
@export var gateway_rearm_margin: float = 60.0

var _ship: Ship
var _wave_director: WaveDirector
var _poi_spawner: PoiSpawner
var _docking_manager: DockingManager
var _active_gateway: BossGateway = null
var _gateways: Array[BossGateway] = []
var _briefing_gateway: BossGateway = null
var _dismissed_gateways: Dictionary = {}
var _gateway_stage: StageDef = null
var _gateway_run: RunDefinition = null
var _docking_timer: float = 0.0
var _transfer_in_progress: bool = false
var _was_paused: bool = false
var _was_mouse_mode: int = Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ship_path != NodePath(""):
		_ship = get_node_or_null(ship_path) as Ship
	if wave_director_path != NodePath(""):
		_wave_director = get_node_or_null(wave_director_path) as WaveDirector
	if poi_spawner_path != NodePath(""):
		_poi_spawner = get_node_or_null(poi_spawner_path) as PoiSpawner
	if docking_manager_path != NodePath(""):
		_docking_manager = get_node_or_null(docking_manager_path) as DockingManager
	if _wave_director != null and not _wave_director.gateway_ready.is_connected(_on_gateway_ready):
		_wave_director.gateway_ready.connect(_on_gateway_ready)
	if not GameFlow.stage_changed.is_connected(_on_stage_changed):
		GameFlow.stage_changed.connect(_on_stage_changed)

func _process(_delta: float) -> void:
	if _transfer_in_progress or _gateways.is_empty():
		return
	if not _is_ship_available() or GameFlow.get_active_run_definition() != _gateway_run or GameFlow.get_current_stage() != _gateway_stage:
		_clear_gateway()
		return
	if _briefing_gateway != null:
		if is_instance_valid(_briefing_gateway) and not _briefing_gateway.is_queued_for_deletion():
			return
		_close_briefing(true)
	if get_tree().paused or PauseManager.is_paused:
		return
	var closest: BossGateway = null
	var closest_distance_sq: float = INF
	for gateway: BossGateway in get_active_gateways():
		var distance_sq: float = _ship.global_position.distance_squared_to(gateway.global_position)
		var instance_id: int = gateway.get_instance_id()
		if _dismissed_gateways.has(instance_id):
			var rearm_radius: float = gateway.get_docking_radius() + maxf(gateway_rearm_margin, 0.0)
			if distance_sq > rearm_radius * rearm_radius:
				_dismissed_gateways.erase(instance_id)
			else:
				continue
		var radius: float = gateway.get_docking_radius()
		if distance_sq <= radius * radius and distance_sq < closest_distance_sq:
			closest = gateway
			closest_distance_sq = distance_sq
	if closest != null:
		_open_briefing(closest)

func get_active_gateway() -> BossGateway:
	if is_instance_valid(_briefing_gateway):
		return _briefing_gateway
	return _active_gateway if is_instance_valid(_active_gateway) else null

func get_active_gateways() -> Array[BossGateway]:
	var valid: Array[BossGateway] = []
	for gateway: BossGateway in _gateways:
		if is_instance_valid(gateway) and not gateway.is_queued_for_deletion():
			valid.append(gateway)
	return valid

func get_briefing_gateway() -> BossGateway:
	return _briefing_gateway if is_instance_valid(_briefing_gateway) else null

func is_briefing_open() -> bool:
	return get_briefing_gateway() != null

## Retained for HUD integrations; gateways now wait for explicit confirmation.
func get_docking_timer() -> float:
	return 0.0

func _is_ship_available() -> bool:
	return is_instance_valid(_ship) and not _ship.is_queued_for_deletion() and _ship.visible and _ship.is_alive()

func _on_gateway_ready(stage: StageDef, spawn_position: Vector3) -> void:
	_clear_gateway()
	if stage == null or stage.gateway_scene == null:
		push_warning("BossGatewayManager: gateway stage has no gateway scene.")
		return
	var tree: SceneTree = get_tree()
	if tree.current_scene == null:
		return
	_gateway_stage = stage
	_gateway_run = GameFlow.get_active_run_definition()
	var routes: Array[SectorRouteDef] = stage.get_gateway_routes()
	if routes.is_empty():
		var next_stage: StageDef = _resolve_linear_destination(stage)
		if next_stage == null:
			return
		var linear: SectorRouteDef = SectorRouteDef.new()
		linear.route_id = &"next_sector"
		linear.display_name = next_stage.get_display_name_or_default()
		linear.description = next_stage.description
		linear.destination_stage = next_stage
		routes.append(linear)
	var direction: Vector3 = spawn_position - _ship.global_position if _is_ship_available() else Vector3.FORWARD
	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	var side: Vector3 = direction.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	for index: int in routes.size():
		var gateway: BossGateway = stage.gateway_scene.instantiate() as BossGateway
		if gateway == null:
			push_warning("BossGatewayManager: gateway scene must instantiate BossGateway.")
			continue
		gateway.configure_route(routes[index])
		tree.current_scene.add_child(gateway)
		var center: Vector3 = _resolve_gateway_spawn_position(spawn_position, gateway)
		var spacing: float = gateway.get_docking_radius() * 2.0 + maxf(gateway_rearm_margin, 80.0)
		gateway.global_position = center + side * (float(index) - float(routes.size() - 1) * 0.5) * spacing
		_gateways.append(gateway)
		if _active_gateway == null:
			_active_gateway = gateway
		gateway_spawned.emit(gateway)
	if not _gateways.is_empty() and _poi_spawner != null:
		_poi_spawner.pause_spawning()

func _resolve_linear_destination(stage: StageDef) -> StageDef:
	if _gateway_run == null:
		return null
	if stage.next_stage_id != &"":
		var index: int = _gateway_run.find_stage_index_by_id(stage.next_stage_id)
		return _gateway_run.get_stage(index)
	return _gateway_run.get_stage(GameFlow.get_active_stage_index() + 1)

func _resolve_gateway_spawn_position(spawn_position: Vector3, gateway: BossGateway) -> Vector3:
	if not _is_ship_available():
		return spawn_position
	var minimum_distance: float = maxf(gateway_min_distance_from_ship, gateway.get_docking_radius() * 1.5)
	var direction: Vector3 = spawn_position - _ship.global_position
	if direction.length_squared() <= 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	if _ship.global_position.distance_squared_to(spawn_position) < minimum_distance * minimum_distance:
		return _ship.global_position + direction * minimum_distance
	return spawn_position

func _open_briefing(gateway: BossGateway) -> void:
	if _transfer_in_progress or is_briefing_open() or not _is_ship_available():
		return
	_briefing_gateway = gateway
	_was_paused = get_tree().paused
	_was_mouse_mode = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	docking_started.emit(gateway)
	briefing_opened.emit(gateway)

func cancel_gateway() -> void:
	var gateway: BossGateway = get_briefing_gateway()
	if gateway == null or _transfer_in_progress:
		return
	_dismissed_gateways[gateway.get_instance_id()] = true
	_close_briefing(true)
	docking_cancelled.emit(gateway)

func confirm_gateway() -> bool:
	var gateway: BossGateway = get_briefing_gateway()
	if gateway == null or _transfer_in_progress or not _is_ship_available():
		return false
	if GameFlow.get_current_stage() != _gateway_stage or GameFlow.get_active_run_definition() != _gateway_run:
		return false
	if not get_active_gateways().has(gateway):
		return false
	var radius: float = gateway.get_docking_radius()
	if _ship.global_position.distance_squared_to(gateway.global_position) > radius * radius:
		cancel_gateway()
		return false
	var route: SectorRouteDef = gateway.get_route()
	if route == null or route.get_destination_id() == &"":
		return false
	var offered: Array[SectorRouteDef] = _gateway_stage.get_gateway_routes()
	if not offered.is_empty() and not offered.has(route):
		return false
	_transfer_in_progress = true
	var old_nodes: Array[Node] = []
	_collect_runtime_stage_nodes(get_tree().current_scene, old_nodes)
	# Advance before freeing old actors: a rejected destination leaves this sector intact.
	var advanced: bool = GameFlow.advance_to_next_stage(route.get_destination_id())
	if not advanced:
		_transfer_in_progress = false
		return false
	docking_complete.emit(gateway)
	_close_briefing(true)
	for node: Node in old_nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
	if _poi_spawner != null:
		_poi_spawner.clear_runtime_tracking()
	if _docking_manager != null:
		_docking_manager.reset_for_stage()
	_ship.reset_for_stage_transition()
	if _wave_director != null:
		_wave_director.begin_stage_after_gateway_transfer()
	if _poi_spawner != null:
		_poi_spawner.resume_stage_spawning(true)
	_transfer_in_progress = false
	_clear_gateway()
	return true

func _complete_docking() -> void:
	confirm_gateway()

func _cancel_docking() -> void:
	cancel_gateway()

func _close_briefing(restore_state: bool) -> void:
	if _briefing_gateway == null:
		return
	_briefing_gateway = null
	if restore_state and is_inside_tree():
		if is_instance_valid(_ship):
			_ship.suppress_hull_repair_until_release()
		get_tree().paused = _was_paused
		Input.mouse_mode = _was_mouse_mode
	briefing_closed.emit()

func _collect_runtime_stage_nodes(node: Node, collected: Array[Node]) -> void:
	if not is_instance_valid(node) or node == _ship:
		return
	for child: Node in node.get_children():
		_collect_runtime_stage_nodes(child, collected)
	if node is Enemy or node is TargetObject or node is PoiInstance or node is BossGateway or node is NanobotSwarm or node is PackWarpExit or node is Projectile:
		collected.append(node)

func _on_stage_changed(_stage: StageDef, _stage_index: int) -> void:
	if not _transfer_in_progress:
		_clear_gateway()

func _clear_gateway() -> void:
	_close_briefing(true)
	for gateway: BossGateway in _gateways:
		if is_instance_valid(gateway) and not gateway.is_queued_for_deletion():
			gateway.queue_free()
	_gateways.clear()
	_active_gateway = null
	_gateway_stage = null
	_gateway_run = null
	_dismissed_gateways.clear()
	_docking_timer = 0.0
	gateway_cleared.emit()

func _exit_tree() -> void:
	_close_briefing(false)
	for gateway: BossGateway in _gateways:
		if is_instance_valid(gateway) and not gateway.is_queued_for_deletion():
			gateway.queue_free()
	_gateways.clear()
