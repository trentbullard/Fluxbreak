extends Node
class_name BossGatewayManager

signal gateway_spawned(gateway: BossGateway)
signal gateway_cleared()
signal docking_started(gateway: BossGateway)
signal docking_progress(gateway: BossGateway, time_remaining: float)
signal docking_cancelled(gateway: BossGateway)
signal docking_complete(gateway: BossGateway)

@export var ship_path: NodePath
@export var wave_director_path: NodePath
@export var poi_spawner_path: NodePath
@export var docking_manager_path: NodePath
@export var gateway_min_distance_from_ship: float = 550.0

var _ship: Ship
var _wave_director: WaveDirector
var _poi_spawner: PoiSpawner
var _docking_manager: DockingManager
var _active_gateway: BossGateway = null
var _docking_timer: float = 0.0
var _transfer_in_progress: bool = false

func _ready() -> void:
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

func _process(delta: float) -> void:
	if _active_gateway == null or _transfer_in_progress:
		return
	if _ship == null or not is_instance_valid(_ship):
		return
	if get_tree().paused:
		return
	var distance_sq: float = _ship.global_position.distance_squared_to(_active_gateway.global_position)
	var docking_radius: float = _active_gateway.get_docking_radius()
	if distance_sq <= docking_radius * docking_radius:
		if _docking_timer <= 0.0:
			_docking_timer = _active_gateway.get_docking_time()
			docking_started.emit(_active_gateway)
		_docking_timer = max(_docking_timer - max(delta, 0.0), 0.0)
		docking_progress.emit(_active_gateway, _docking_timer)
		if _docking_timer <= 0.0:
			_complete_docking()
		return
	if _docking_timer > 0.0:
		_cancel_docking()

func get_active_gateway() -> BossGateway:
	return _active_gateway

func get_docking_timer() -> float:
	return _docking_timer

func _on_gateway_ready(stage: StageDef, spawn_position: Vector3) -> void:
	_clear_gateway()
	if stage == null or stage.gateway_scene == null:
		push_warning("BossGatewayManager: active gateway stage has no gateway_scene configured.")
		return
	var gateway_node: Node = stage.gateway_scene.instantiate()
	var gateway: BossGateway = gateway_node as BossGateway
	if gateway == null:
		if gateway_node != null:
			gateway_node.queue_free()
		push_warning("BossGatewayManager: gateway_scene must instantiate a BossGateway root.")
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		gateway.queue_free()
		return
	tree.current_scene.add_child(gateway)
	gateway.global_position = _resolve_gateway_spawn_position(spawn_position, gateway)
	_active_gateway = gateway
	if _poi_spawner != null:
		_poi_spawner.pause_spawning()
	gateway_spawned.emit(gateway)

func _resolve_gateway_spawn_position(spawn_position: Vector3, gateway: BossGateway) -> Vector3:
	if _ship == null or not is_instance_valid(_ship):
		return spawn_position
	var minimum_distance: float = max(gateway_min_distance_from_ship, gateway.get_docking_radius() * 1.5)
	var ship_position: Vector3 = _ship.global_position
	var direction: Vector3 = spawn_position - ship_position
	if direction.length_squared() <= 0.0001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var target_position: Vector3 = spawn_position
	if ship_position.distance_squared_to(target_position) < minimum_distance * minimum_distance:
		target_position = ship_position + direction * minimum_distance
	return target_position

func _complete_docking() -> void:
	if _active_gateway == null:
		return
	docking_complete.emit(_active_gateway)
	_transfer_in_progress = true
	_docking_timer = 0.0
	_transfer_to_next_stage()

func _cancel_docking() -> void:
	if _active_gateway == null:
		return
	_docking_timer = 0.0
	docking_cancelled.emit(_active_gateway)

func _transfer_to_next_stage() -> void:
	_clear_runtime_stage_nodes()
	if _poi_spawner != null:
		_poi_spawner.clear_runtime_tracking()
	if _docking_manager != null:
		_docking_manager.reset_for_stage()
	var advanced: bool = GameFlow.advance_to_next_stage()
	if not advanced:
		_transfer_in_progress = false
		_clear_gateway()
		GameFlow.player_won()
		return
	if _ship != null and is_instance_valid(_ship):
		_ship.reset_for_stage_transition()
	if _wave_director != null:
		_wave_director.begin_stage_after_gateway_transfer()
	if _poi_spawner != null:
		_poi_spawner.resume_stage_spawning(true)
	_transfer_in_progress = false
	_clear_gateway()

func _clear_runtime_stage_nodes() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return
	_queue_free_runtime_nodes(tree.current_scene)

func _queue_free_runtime_nodes(node: Node) -> void:
	for child in node.get_children():
		_queue_free_runtime_nodes(child)
	if node == null or not is_instance_valid(node):
		return
	if node == _ship:
		return
	if (
		node is Enemy
		or node is TargetObject
		or node is PoiInstance
		or node is BossGateway
		or node is NanobotSwarm
		or node is PackWarpExit
		or node is Projectile
	):
		node.queue_free()

func _on_stage_changed(_stage: StageDef, _stage_index: int) -> void:
	_docking_timer = 0.0
	if _transfer_in_progress:
		return
	_clear_gateway()

func _clear_gateway() -> void:
	if _active_gateway != null and is_instance_valid(_active_gateway):
		_active_gateway.queue_free()
	_active_gateway = null
	_docking_timer = 0.0
	gateway_cleared.emit()
