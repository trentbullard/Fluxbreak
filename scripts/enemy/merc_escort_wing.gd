extends Node
class_name MercEscortWing

const ESCORT_GROUP: StringName = &"merc_escorts"
const OWNER_META: StringName = &"merc_escort_parent_id"

var _source: Enemy = null
var _child_def: EnemyDef = null
var _alive_cap: int = 0
var _total_cap: int = 0
var _global_cap: int = 10
var _enemy_cap: int = 50
var _radius: float = 75.0
var _total_spawned: int = 0
var _children: Array[WeakRef] = []
var _spawner: Spawner = null

## Configure once per owner. Repeated launches share the same lifetime budget.
func setup(source: Enemy, child_def: EnemyDef, alive_cap: int, total_cap: int, global_cap: int = 10, enemy_cap: int = 50, radius: float = 75.0) -> void:
	_disconnect_source()
	clear_escorts()
	_source = source
	_child_def = child_def
	_alive_cap = maxi(alive_cap, 0)
	_total_cap = maxi(total_cap, 0)
	_global_cap = maxi(global_cap, 0)
	_enemy_cap = maxi(enemy_cap, 0)
	_radius = maxf(radius, 1.0)
	_total_spawned = 0
	_spawner = null
	if is_instance_valid(_source):
		_source.about_to_die.connect(_on_source_died)
		_source.tree_exiting.connect(clear_escorts)

func get_living_escorts() -> Array[Enemy]:
	var living: Array[Enemy] = []
	for index: int in range(_children.size() - 1, -1, -1):
		var child: Enemy = _children[index].get_ref() as Enemy
		if not is_instance_valid(child) or child._dead or child.is_queued_for_deletion():
			_children.remove_at(index)
		else:
			living.append(child)
	return living

func get_living_count() -> int:
	return get_living_escorts().size()

func get_total_spawned() -> int:
	return _total_spawned

func spawn_escorts(count: int) -> int:
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
	# Synchronous checks and registration prevent multiple launchers reserving
	# the same global slot in one physics tick.
	for member: int in range(maxi(available, 0)):
		if _global_escort_count() >= _global_cap or int(_spawner.get_alive_counts().get("enemies", 0)) >= _enemy_cap:
			break
		var direction: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0))
		if direction.length_squared() < 0.001:
			direction = Vector3.RIGHT
		var position: Vector3 = _source.global_position + direction.normalized() * _radius * randf_range(0.7, 1.0)
		var child: Enemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, _child_def, position, _build_child_request()) as Enemy
		if child == null:
			break
		# Retain target detection on layer 8 while avoiding physical body contact.
		child.collision_layer = 8
		child.collision_mask = 0
		child.add_to_group(ESCORT_GROUP)
		child.set_meta(OWNER_META, _source.get_instance_id())
		_children.append(weakref(child))
		_total_spawned += 1
		spawned += 1
	return spawned

func clear_escorts() -> void:
	for reference: WeakRef in _children:
		var child: Enemy = reference.get_ref() as Enemy
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			# Cleanup deliberately skips kill, reward and pressure handling.
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

func _global_escort_count() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(ESCORT_GROUP):
		var child: Enemy = node as Enemy
		if is_instance_valid(child) and not child._dead and not child.is_queued_for_deletion():
			count += 1
	return count

func _disconnect_source() -> void:
	if not is_instance_valid(_source):
		return
	if _source.about_to_die.is_connected(_on_source_died):
		_source.about_to_die.disconnect(_on_source_died)
	if _source.tree_exiting.is_connected(clear_escorts):
		_source.tree_exiting.disconnect(clear_escorts)

func _on_source_died(_enemy: Enemy) -> void:
	clear_escorts()

func _exit_tree() -> void:
	clear_escorts()
	_disconnect_source()
