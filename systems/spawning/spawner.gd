# scripts/systems/spawning/spawner.gd  (Godot 4.5)
extends Node3D
class_name Spawner

signal alive_counts_changed(enemies: int, targets: int, total: int)

enum SpawnKind {ENEMY, TARGET}
@export_enum("Any", "EnemiesOnly", "TargetsOnly")
var spawn_mode: int = 0

@export var enemy_weight: float = 0.6
@export var anti_streak_bias: float = 0.5

@export var target_scene: PackedScene
@export var enemy_scene: PackedScene
@export var ship_path: NodePath

@export var spawn_radius: float = 400
@export var spawn_interval: float = 1.5
@export var min_distance_from_ship: float = 150.0
@export_group("Legacy Caps")
@export var max_alive_total: int = 30
@export var max_enemies_alive: int = 10
@export var max_targets_alive: int = 3
@export var maintain_target_floor: bool = false
@export var target_floor_alive: int = 2
@export var target_topup_interval: float = 10.0

@export var directed_mode: bool = true

var _alive: int = 0
var _alive_enemies: int = 0
var _alive_targets: int = 0
var _target_topup: Timer
var _timer: Timer
var _player_ship: Node3D
var _last_kind_was_enemy: bool = false
var _have_last: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_player_ship = get_node_or_null(ship_path) as Node3D
	_timer = Timer.new()
	_timer.wait_time = spawn_interval
	_timer.autostart = (not directed_mode)
	_timer.timeout.connect(_try_spawn)
	add_child(_timer)
	
	_target_topup = Timer.new()
	_target_topup.wait_time = target_topup_interval
	_target_topup.autostart = (not directed_mode)
	_target_topup.timeout.connect(_maintain_targets)
	add_child(_target_topup)

func spawn_one_with_def(kind: int, def: Resource, request: SpawnRequest = null) -> Node3D:
	if enemy_scene == null or target_scene == null:
		return null
	if not _can_spawn_now():
		return null
	
	var inst: Node3D = (enemy_scene if kind == SpawnKind.ENEMY else target_scene).instantiate() as Node3D
	_last_kind_was_enemy = (kind == SpawnKind.ENEMY)
	_have_last = true
	
	var pos: Vector3 = _pick_spawn_position()
	if inst.has_method("set_ship"):
		inst.call("set_ship", _player_ship)
	
	if kind == SpawnKind.ENEMY and def is EnemyDef and inst.has_method("configure_enemy"):
		var enemy_context: EnemySpawnContext = null
		if request != null:
			enemy_context = request.build_enemy_spawn_context(def as EnemyDef)
		inst.call("configure_enemy", def as EnemyDef, enemy_context)
	elif kind == SpawnKind.TARGET and def is TargetDef and inst.has_method("configure_target"):
		inst.call("configure_target", def as TargetDef)
	
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		inst.queue_free()
		return null
	tree.current_scene.add_child(inst)
	inst.global_position = pos
	
	_alive += 1
	if kind == SpawnKind.ENEMY: _alive_enemies += 1
	else: _alive_targets += 1
	alive_counts_changed.emit(_alive_enemies, _alive_targets, _alive)
	
	var kind_captured: int = kind
	inst.tree_exited.connect(func() -> void:
		_alive = max(_alive - 1, 0)
		if kind_captured == SpawnKind.ENEMY:
			_alive_enemies = max(_alive_enemies - 1, 0)
		else:
			_alive_targets = max(_alive_targets - 1, 0)
		alive_counts_changed.emit(_alive_enemies, _alive_targets, _alive)
	)
	
	return inst

func spawn_one(kind: int) -> Node3D:
	if enemy_scene == null or target_scene == null:
		return null
	if not _can_spawn_now():
		return null
	
	var inst: Node3D = null
	if kind == SpawnKind.ENEMY:
		inst = enemy_scene.instantiate() as Node3D
		_last_kind_was_enemy = true
	else:
		inst = target_scene.instantiate() as Node3D
		_last_kind_was_enemy = false
	_have_last = true
	
	var pos: Vector3 = _pick_spawn_position()
	if inst.has_method("set_ship"):
		inst.call("set_ship", _player_ship)
	
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		inst.queue_free()
		return null
	tree.current_scene.add_child(inst)
	inst.global_position = pos
	
	_alive += 1
	if kind == SpawnKind.ENEMY:
		_alive_enemies += 1
	else:
		_alive_targets += 1
	alive_counts_changed.emit(_alive_enemies, _alive_targets, _alive)
	
	var kind_caputured: int = kind
	inst.tree_exited.connect(func() -> void:
		_alive = max(_alive - 1, 0)
		if kind_caputured == SpawnKind.ENEMY:
			_alive_enemies = max(_alive_enemies - 1, 0)
		else:
			_alive_targets = max(_alive_targets - 1, 0)
		alive_counts_changed.emit(_alive_enemies, _alive_targets, _alive)
	)
	
	return inst

func get_alive_counts() -> Dictionary:
	return {
		"enemies": _alive_enemies,
		"targets": _alive_targets,
		"total": _alive
	}

func spawn_enemy_burst(def: EnemyDef, count: int, request: SpawnRequest = null) -> int:
	var spawned: int = 0
	for i in count:
		if spawn_one_with_def(SpawnKind.ENEMY, def, request) == null:
			break
		spawned += 1
	return spawned

func spawn_target_burst(def: TargetDef, count: int) -> int:
	var spawned: int = 0
	for i in count:
		if spawn_one_with_def(SpawnKind.TARGET, def) == null:
			break
		spawned += 1
	return spawned

func spawn_burst(kind: int, count: int) -> int:
	var spawned: int = 0
	for i in count:
		if spawn_one(kind) == null:
			break
		spawned += 1
	return spawned

func set_max_alive(new_max: int) -> void:
	max_enemies_alive = new_max

func set_max_alive_total(n: int) -> void:
	max_alive_total = max(n, 0)

func _maintain_targets() -> void:
	if not maintain_target_floor:
		return
	var want: int = max(target_floor_alive - _alive_targets, 0)
	if want > 0:
		spawn_burst(SpawnKind.TARGET, want)

func _try_spawn() -> void:
	var kind: int = _pick_spawn_kind()
	spawn_one(kind)

func _pick_spawn_position() -> Vector3:
	var center: Vector3 = _player_ship.global_position if _player_ship != null else Vector3.ZERO
	var dir: Vector3 = Vector3(_rng.randf()*2.0 - 1.0, _rng.randf()*2.0 - 1.0, _rng.randf()*2.0 - 1.0).normalized()
	var pos: Vector3 = center + dir * spawn_radius
	if _player_ship != null and pos.distance_to(center) < min_distance_from_ship:
		pos = center + dir * min_distance_from_ship
	return pos

func _pick_spawn_kind() -> int:
	var allowed_enemy: bool = (spawn_mode != 2)
	var allowed_target: bool = (spawn_mode != 1)
	if allowed_enemy and not allowed_target:
		return SpawnKind.ENEMY
	if allowed_target and not allowed_enemy:
		return SpawnKind.TARGET
	
	var e_weight: float = clampf(enemy_weight, 0.0, 1.0)
	var t_weight: float = 1.0 - e_weight
	if _have_last:
		var bias: float = clampf(anti_streak_bias, 0.0, 1.0)
		if _last_kind_was_enemy:
			e_weight *= (1.0 - bias)
		else:
			t_weight *= (1.0 - bias)
	
	var total: float = e_weight + t_weight
	if total <= 0.0:
		return SpawnKind.ENEMY
	var roll: float = _rng.randf() * total
	return SpawnKind.ENEMY if roll < e_weight else SpawnKind.TARGET

func _can_spawn_now() -> bool:
	if not is_instance_valid(_player_ship):
		return false
	if _player_ship.has_method("is_alive") and not bool(_player_ship.call("is_alive")):
		return false
	var tree: SceneTree = get_tree()
	return tree != null and tree.current_scene != null
