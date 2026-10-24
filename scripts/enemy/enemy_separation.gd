extends Node
class_name EnemySeparation

## One shared nearest-neighbor pass; actors consume an occasional lateral kick.
## Physical collision and the actor's normal locomotion remain independent.

## Seconds between shared proximity scans. No scene queries run between scans.
@export var proximity_check_interval_sec: float = 0.55
## Extra space beyond the two visual clearance spheres, in world meters.
@export var clearance_margin: float = 14.0
## Close centers use a stable pair direction instead of a noisy tiny offset.
@export var tight_radius: float = 12.0
## Requested lateral speed when another object first enters clearance range.
@export var min_pulse_speed: float = 8.0
## Requested lateral speed for objects whose centers almost coincide.
@export var max_pulse_speed: float = 35.0
## Bosses yield more slowly without changing their normal locomotion profile.
@export var boss_pulse_multiplier: float = 0.6

var _scan_remaining_sec: float = 0.0
var _scan_count: int = 0
var _radius_cache: Dictionary[int, float] = {}
var _pending_pulses: Dictionary[int, Dictionary] = {}

func _ready() -> void:
	add_to_group(&"enemy_separation")

func _physics_process(delta: float) -> void:
	_scan_remaining_sec -= maxf(delta, 0.0)
	if _scan_remaining_sec > 0.0:
		return
	_scan_remaining_sec = maxf(proximity_check_interval_sec, 0.05)
	_scan_proximity()

func get_scan_count() -> int:
	return _scan_count

func take_pulse(enemy: Enemy) -> Vector3:
	if not _is_candidate(enemy):
		return Vector3.ZERO
	var enemy_id: int = enemy.get_instance_id()
	if not _pending_pulses.has(enemy_id):
		return Vector3.ZERO
	var pending: Dictionary = _pending_pulses[enemy_id]
	_pending_pulses.erase(enemy_id)
	var neighbor_ref: WeakRef = pending.get(&"neighbor") as WeakRef
	if neighbor_ref == null:
		return Vector3.ZERO
	var neighbor: Node3D = neighbor_ref.get_ref() as Node3D
	if not _is_candidate(neighbor) or neighbor == enemy:
		return Vector3.ZERO
	var clearance: float = get_clearance_radius(enemy) + get_clearance_radius(neighbor) + maxf(clearance_margin, 0.0)
	if enemy.global_position.distance_squared_to(neighbor.global_position) >= clearance * clearance:
		return Vector3.ZERO
	var pulse: Vector3 = pending.get(&"pulse", Vector3.ZERO)
	return pulse

func get_clearance_radius(node: Node3D) -> float:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return 0.0
	var override_radius: float = 0.0
	var enemy: Enemy = node as Enemy
	var target: TargetObject = node as TargetObject
	if enemy != null and enemy.def != null:
		override_radius = enemy.def.separation_radius
	elif target != null and target.def != null:
		override_radius = target.def.separation_radius
	if override_radius > 0.0:
		return override_radius
	var instance_id: int = node.get_instance_id()
	if _radius_cache.has(instance_id):
		return _radius_cache[instance_id]
	var radius_squared: float = 0.0
	if enemy != null:
		var model_root: Node3D = enemy.get_visual_model_root(false)
		if model_root != null:
			radius_squared = _visual_radius_squared(model_root, node.global_position)
	elif target != null:
		# configure_target queues the old VisualRoot before adding its replacement.
		# Godot may rename the replacement until the old node is freed, so inspect
		# active mesh children without depending on their temporary node names.
		for child: Node in target.get_children():
			var visual: Node3D = child as Node3D
			if visual == null or visual.is_queued_for_deletion() or visual is CollisionObject3D or visual is CollisionShape3D or visual is CollisionPolygon3D:
				continue
			radius_squared = maxf(radius_squared, _visual_radius_squared(visual, node.global_position))
	var radius: float = sqrt(radius_squared) if radius_squared > 0.0 else 8.0
	_radius_cache[instance_id] = maxf(radius, 1.0)
	return _radius_cache[instance_id]

func _scan_proximity() -> void:
	_scan_count += 1
	_pending_pulses.clear()
	var candidates: Array[Node3D] = []
	var positions: Array[Vector3] = []
	var radii: Array[float] = []
	var instance_ids: Array[int] = []
	var active_ids: Dictionary[int, bool] = {}
	var margin: float = maxf(clearance_margin, 0.0)
	for target_node: Node in get_tree().get_nodes_in_group(&"targets"):
		var candidate: Node3D = target_node as Node3D
		if not _is_candidate(candidate):
			continue
		var instance_id: int = candidate.get_instance_id()
		candidates.append(candidate)
		positions.append(candidate.global_position)
		radii.append(get_clearance_radius(candidate))
		instance_ids.append(instance_id)
		active_ids[instance_id] = true
	for cached_id: int in _radius_cache.keys():
		if not active_ids.has(cached_id):
			_radius_cache.erase(cached_id)
	var candidate_count: int = candidates.size()
	for own_index: int in range(candidate_count):
		var enemy: Enemy = candidates[own_index] as Enemy
		if enemy == null:
			continue
		var nearest_index: int = -1
		var nearest_distance_squared: float = INF
		var own_position: Vector3 = positions[own_index]
		var own_radius: float = radii[own_index]
		for neighbor_index: int in range(candidate_count):
			if neighbor_index == own_index:
				continue
			var distance_squared: float = own_position.distance_squared_to(positions[neighbor_index])
			var clearance: float = own_radius + radii[neighbor_index] + margin
			if distance_squared >= clearance * clearance:
				continue
			if distance_squared < nearest_distance_squared or (distance_squared == nearest_distance_squared and (nearest_index < 0 or instance_ids[neighbor_index] < instance_ids[nearest_index])):
				nearest_index = neighbor_index
				nearest_distance_squared = distance_squared
		if nearest_index < 0:
			continue
		var nearest: Node3D = candidates[nearest_index]
		var clearance: float = own_radius + radii[nearest_index] + margin
		var closeness: float = clampf(1.0 - sqrt(nearest_distance_squared) / maxf(clearance, 0.001), 0.0, 1.0)
		var speed: float = lerpf(maxf(min_pulse_speed, 0.0), maxf(max_pulse_speed, min_pulse_speed), closeness)
		if enemy is EnemyBoss:
			speed *= maxf(boss_pulse_multiplier, 0.0)
		var direction: Vector3 = _get_pulse_direction(enemy, nearest, nearest_distance_squared)
		_pending_pulses[instance_ids[own_index]] = {&"neighbor": weakref(nearest), &"pulse": direction * speed}

func _is_candidate(node: Node3D) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion() or not node.is_visible_in_tree():
		return false
	var enemy: Enemy = node as Enemy
	if enemy != null:
		return not enemy._dead and enemy.hull > 0.0
	var target: TargetObject = node as TargetObject
	return target != null and not target._dead and target.hull > 0.0

func _get_pulse_direction(enemy: Enemy, neighbor: Node3D, distance_squared: float) -> Vector3:
	# Both members of a ship pair share this plane, even if their headings differ.
	var midpoint: Vector3 = (enemy.global_position + neighbor.global_position) * 0.5
	var axis: Vector3 = Vector3.FORWARD
	if is_instance_valid(enemy.player_ship) and enemy.player_ship.is_inside_tree():
		var to_player: Vector3 = enemy.player_ship.global_position - midpoint
		if to_player.length_squared() > 0.0001:
			axis = to_player.normalized()
	var away: Vector3 = enemy.global_position - neighbor.global_position
	var lateral_away: Vector3 = away - axis * away.dot(axis)
	var direction: Vector3 = Vector3.ZERO
	if distance_squared > maxf(tight_radius, 0.0) * maxf(tight_radius, 0.0):
		direction = lateral_away
	if direction.length_squared() <= 0.0001:
		direction = _get_pair_direction(enemy.get_instance_id(), neighbor.get_instance_id(), axis)
		if direction.dot(lateral_away) < 0.0:
			direction = -direction
	return direction.normalized()

func _get_pair_direction(own_id: int, neighbor_id: int, axis: Vector3) -> Vector3:
	var lower_id: int = mini(own_id, neighbor_id)
	var higher_id: int = maxi(own_id, neighbor_id)
	# Many stable lanes spread coincident crowds without consuming combat RNG.
	# Bound operands before mixing so long-lived instance IDs cannot overflow.
	var pair_hash: int = ((lower_id % 104729) * 73856093) ^ ((higher_id % 130363) * 19349663)
	var angle: float = (float(pair_hash % 64) + 0.5) * TAU / 64.0
	var reference: Vector3 = Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var tangent: Vector3 = axis.cross(reference).normalized()
	var bitangent: Vector3 = axis.cross(tangent).normalized()
	var direction: Vector3 = tangent * cos(angle) + bitangent * sin(angle)
	return direction * (1.0 if own_id == lower_id else -1.0)

func _visual_radius_squared(root: Node3D, origin: Vector3) -> float:
	if root.is_queued_for_deletion():
		return 0.0
	var radius_squared: float = 0.0
	var mesh_instance: MeshInstance3D = root as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		var bounds: AABB = mesh_instance.mesh.get_aabb()
		for corner: int in range(8):
			var point: Vector3 = mesh_instance.global_transform * bounds.get_endpoint(corner)
			radius_squared = maxf(radius_squared, origin.distance_squared_to(point))
	for child: Node in root.get_children():
		var child_3d: Node3D = child as Node3D
		if child_3d != null:
			radius_squared = maxf(radius_squared, _visual_radius_squared(child_3d, origin))
	return radius_squared
