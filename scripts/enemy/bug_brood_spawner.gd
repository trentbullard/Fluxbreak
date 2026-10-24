extends Node
class_name BugBroodSpawner

var _source: Enemy = null
var _child_def: EnemyDef = null
var _radius: float = 70.0
var _total_spawned: int = 0
var _children: Array[WeakRef] = []
var _spawner: Spawner = null

## Configure the launcher. Existing children remain independent if it is replaced.
func setup(source: Enemy, child_def: EnemyDef, radius: float = 70.0) -> void:
	_source = source
	_child_def = child_def
	_radius = maxf(radius, 1.0)
	_total_spawned = 0
	_children.clear()
	_spawner = null

func get_living_count() -> int:
	for index: int in range(_children.size() - 1, -1, -1):
		var child: Enemy = _children[index].get_ref() as Enemy
		if not is_instance_valid(child) or child._dead or child.is_queued_for_deletion():
			_children.remove_at(index)
	return _children.size()

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
	# Retire dead weak references once per release, not once per frame.
	get_living_count()
	var spawned: int = 0
	# Each launch preserves its authored batch size without lifetime or living caps.
	for member: int in range(maxi(count, 0)):
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
