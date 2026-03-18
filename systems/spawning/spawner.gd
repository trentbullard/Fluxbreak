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
@export var pack_warp_scene: PackedScene = preload("res://scenes/vfx/pack_warp_exit.tscn")
@export var ship_path: NodePath

@export var spawn_radius: float = 400
@export var spawn_interval: float = 1.5
@export var min_distance_from_ship: float = 150.0
@export_group("Enemy Pack Spawn")
@export var close_spawn_radius: float = 600.0
@export var far_spawn_radius: float = 2400.0
@export var pack_member_radius_min: float = 80.0
@export var pack_member_radius_max: float = 220.0
@export var pack_anchor_min_separation: float = 450.0
@export var pack_anchor_attempts: int = 10
@export var enemy_warp_stagger_sec: float = 0.04
@export var enemy_warp_stagger_max_sec: float = 0.12
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
	return _spawn_one_with_def_at_position(kind, def, request, false, Vector3.ZERO)

func spawn_one_with_def_at_position(kind: int, def: Resource, position: Vector3, request: SpawnRequest = null) -> Node3D:
	return _spawn_one_with_def_at_position(kind, def, request, true, position)

func _spawn_one_with_def_at_position(kind: int, def: Resource, request: SpawnRequest, use_position_override: bool, position_override: Vector3) -> Node3D:
	if enemy_scene == null or target_scene == null:
		return null
	if not _can_spawn_now():
		return null
	
	var inst: Node3D = (enemy_scene if kind == SpawnKind.ENEMY else target_scene).instantiate() as Node3D
	_last_kind_was_enemy = (kind == SpawnKind.ENEMY)
	_have_last = true
	
	var pos: Vector3 = position_override if use_position_override else _pick_spawn_position()
	pos = _ensure_min_distance_from_ship(pos)
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

func spawn_enemy_pack_burst(
	def: EnemyDef,
	count: int,
	anchor: Vector3,
	member_radius: float,
	request: SpawnRequest = null
) -> int:
	var spawned: int = 0
	for i in count:
		var spawn_position: Vector3 = _pick_pack_member_position(anchor, member_radius)
		var inst: Node3D = spawn_one_with_def_at_position(SpawnKind.ENEMY, def, spawn_position, request)
		if inst == null:
			break
		if inst.has_method("play_warp_in"):
			var warp_delay_sec: float = min(float(spawned) * enemy_warp_stagger_sec, enemy_warp_stagger_max_sec)
			inst.call("play_warp_in", warp_delay_sec)
		spawned += 1
	return spawned

func spawn_enemy_pack_warp(anchor: Vector3, member_radius: float, spawn_pressure_scale: float = 0.0) -> Node3D:
	if pack_warp_scene == null:
		return null
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return null
	var warp_node: Node3D = pack_warp_scene.instantiate() as Node3D
	if warp_node == null:
		return null
	if warp_node.has_method("configure_for_pack"):
		warp_node.call("configure_for_pack", member_radius, spawn_pressure_scale)
	tree.current_scene.add_child(warp_node)
	warp_node.global_position = anchor
	return warp_node

func build_enemy_pack_layout(spawn_pressure_scale: float, prior_anchors: Array[Vector3]) -> Dictionary:
	var scale: float = clampf(spawn_pressure_scale, 0.0, 1.0)
	var base_anchor_radius: float = lerpf(close_spawn_radius, far_spawn_radius, scale)
	var anchor_radius: float = max(base_anchor_radius * _rng.randf_range(0.85, 1.15), min_distance_from_ship)
	var member_radius: float = lerpf(pack_member_radius_min, pack_member_radius_max, scale)
	var anchor: Vector3 = _pick_pack_anchor(anchor_radius, prior_anchors)
	var center: Vector3 = _player_ship.global_position if _player_ship != null else Vector3.ZERO
	var actual_anchor_radius: float = sqrt(anchor.distance_squared_to(center))
	return {
		"anchor": anchor,
		"anchor_radius": actual_anchor_radius,
		"member_radius": member_radius,
		"spawn_pressure_scale": scale,
	}

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
	var dir: Vector3 = _random_direction()
	var pos: Vector3 = center + dir * spawn_radius
	return _ensure_min_distance_from_ship(pos)

func _pick_pack_anchor(anchor_radius: float, prior_anchors: Array[Vector3]) -> Vector3:
	var center: Vector3 = _player_ship.global_position if _player_ship != null else Vector3.ZERO
	var current_separation: float = max(pack_anchor_min_separation, 0.0)
	var attempts: int = max(pack_anchor_attempts, 1)
	for attempt in attempts:
		var candidate: Vector3 = center + _random_direction() * anchor_radius
		if _is_valid_pack_anchor(candidate, prior_anchors, current_separation):
			return candidate
		if attempt > 0 and (attempt + 1) % 3 == 0:
			current_separation *= 0.75
	var fallback: Vector3 = center + _random_direction() * anchor_radius
	return _ensure_min_distance_from_ship(fallback)

func _pick_pack_member_position(anchor: Vector3, member_radius: float) -> Vector3:
	var offset: Vector3 = Vector3.ZERO
	if member_radius > 0.0:
		offset = _random_point_in_sphere(member_radius)
	return _ensure_min_distance_from_ship(anchor + offset)

func _is_valid_pack_anchor(candidate: Vector3, prior_anchors: Array[Vector3], separation: float) -> bool:
	if _player_ship != null:
		var center: Vector3 = _player_ship.global_position
		var min_distance_sq: float = min_distance_from_ship * min_distance_from_ship
		if candidate.distance_squared_to(center) < min_distance_sq:
			return false
	var separation_sq: float = separation * separation
	for anchor in prior_anchors:
		if candidate.distance_squared_to(anchor) < separation_sq:
			return false
	return true

func _ensure_min_distance_from_ship(position: Vector3) -> Vector3:
	if _player_ship == null or not is_instance_valid(_player_ship):
		return position
	var center: Vector3 = _player_ship.global_position
	var min_distance_sq: float = min_distance_from_ship * min_distance_from_ship
	if position.distance_squared_to(center) >= min_distance_sq:
		return position
	var outward: Vector3 = position - center
	if outward.length_squared() < 0.0001:
		outward = _random_direction()
	else:
		outward = outward.normalized()
	return center + outward * min_distance_from_ship

func _random_direction() -> Vector3:
	var direction: Vector3 = Vector3.ZERO
	while direction.length_squared() < 0.0001:
		direction = Vector3(
			_rng.randf() * 2.0 - 1.0,
			_rng.randf() * 2.0 - 1.0,
			_rng.randf() * 2.0 - 1.0
		)
	return direction.normalized()

func _random_point_in_sphere(radius: float) -> Vector3:
	if radius <= 0.0:
		return Vector3.ZERO
	var direction: Vector3 = _random_direction()
	var distance: float = radius * pow(_rng.randf(), 1.0 / 3.0)
	return direction * distance

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
