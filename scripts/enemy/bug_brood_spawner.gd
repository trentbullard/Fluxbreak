extends Node
class_name BugBroodSpawner

var _source: Enemy = null
var _child_def: EnemyDef = null
var _alive_cap: int = 0
var _total_cap: int = 0
var _global_cap: int = 12
var _enemy_cap: int = 50
var _radius: float = 70.0
var _total_spawned: int = 0
var _children: Array[WeakRef] = []
var _spawner: Spawner = null

func setup(source: Enemy, child_def: EnemyDef, alive_cap: int, total_cap: int, global_cap: int = 12, enemy_cap: int = 50, radius: float = 70.0) -> void:
	if is_instance_valid(_source):
		if _source.about_to_die.is_connected(_on_source_died):
			_source.about_to_die.disconnect(_on_source_died)
	clear_brood()
	_source = source
	_child_def = child_def
	_alive_cap = maxi(alive_cap, 0)
	_total_cap = maxi(total_cap, 0)
	_global_cap = maxi(global_cap, 0)
	_enemy_cap = maxi(enemy_cap, 0)
	_radius = maxf(radius, 1.0)
	_total_spawned = 0
	if is_instance_valid(_source):
		_source.about_to_die.connect(_on_source_died)

func get_living_count() -> int:
	var count: int = 0
	for reference: WeakRef in _children:
		var child: Enemy = reference.get_ref() as Enemy
		if is_instance_valid(child) and not child._dead and not child.is_queued_for_deletion():
			count += 1
	return count

func get_total_spawned() -> int:
	return _total_spawned

func spawn_brood(count: int) -> int:
	if not is_instance_valid(_source) or _source._dead or _source.is_queued_for_deletion() or not _source.is_inside_tree():
		return 0
	if _source._spawn_context != null and _source._spawn_context.is_summoned:
		return 0
	if _child_def == null or _child_def is EnemyBossDef or _child_def.get_faction_id() != _source.get_faction_id():
		return 0
	if not is_instance_valid(_spawner):
		_spawner = _find_spawner()
	if _spawner == null:
		return 0
	var available: int = mini(maxi(count, 0), mini(_alive_cap - get_living_count(), _total_cap - _total_spawned))
	var spawned: int = 0
	# There is no await between capacity checks and registration, so multiple
	# mothers cannot reserve the same global slot during one physics tick.
	for member in range(maxi(available, 0)):
		if _global_brood_count() >= _global_cap or int(_spawner.get_alive_counts().get("enemies", 0)) >= _enemy_cap:
			break
		var request: SpawnRequest = _build_child_request()
		var direction: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-0.65, 0.65), randf_range(-1.0, 1.0))
		if direction.length_squared() < 0.001:
			direction = Vector3.RIGHT
		var position: Vector3 = _source.global_position + direction.normalized() * _radius * randf_range(0.7, 1.0)
		var child: Enemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, _child_def, position, request) as Enemy
		if child == null:
			break
		child.add_to_group("bug_brood")
		child.set_meta("brood_parent_id", _source.get_instance_id())
		_children.append(weakref(child))
		_total_spawned += 1
		spawned += 1
	return spawned

func clear_brood() -> void:
	for reference: WeakRef in _children:
		var child: Enemy = reference.get_ref() as Enemy
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			# Despawning does not call death/reward handling.
			child.queue_free()
	_children.clear()

func _build_child_request() -> SpawnRequest:
	var request: SpawnRequest = SpawnRequest.new()
	request.enemy_def = _child_def
	request.is_summoned = true
	request.grants_kill_rewards = false
	request.contributes_to_pressure = false
	if _source._spawn_context != null:
		request.wave_index = _source._spawn_context.wave_index
		request.stage_index = _source._spawn_context.stage_index
		request.elapsed_sec = _source._spawn_context.elapsed_sec
		request.wave_card = _source._spawn_context.wave_card
		request.enemy_combat_scaling = _source._spawn_context.enemy_combat_scaling
	return request

func _find_spawner() -> Spawner:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var found: Array[Node] = scene.find_children("*", "Spawner", true, false)
	return found[0] as Spawner if not found.is_empty() else null

func _global_brood_count() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("bug_brood"):
		var child: Enemy = node as Enemy
		if is_instance_valid(child) and not child._dead and not child.is_queued_for_deletion():
			count += 1
	return count

func _on_source_died(_enemy: Enemy) -> void:
	clear_brood()

func _exit_tree() -> void:
	clear_brood()
