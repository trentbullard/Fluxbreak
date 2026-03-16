extends Node3D
class_name ParticleBeamMk1TurretVisualController

const EPSILON: float = 0.0001
const MAX_PITCH_RAD: float = PI * 0.5

var _turret: PlayerTurret = null
var _yaw_pivot: Node3D = null
var _pitch_pivot: Node3D = null

func _ready() -> void:
	_refresh_cache()
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if not _refresh_cache():
		return

	var target: Node3D = _get_assigned_target()
	if target == null or not is_instance_valid(target):
		_restore_rest_pose()
		return

	var clamped_local_target: Vector3 = to_local(target.global_position)
	clamped_local_target.y = maxf(clamped_local_target.y, 0.0)
	if clamped_local_target.length_squared() <= EPSILON:
		_restore_rest_pose()
		return

	_apply_aim(to_global(clamped_local_target))

func _refresh_cache() -> bool:
	if _turret == null or not is_instance_valid(_turret):
		_turret = _find_owner_turret()
	if _yaw_pivot == null or not is_instance_valid(_yaw_pivot):
		_yaw_pivot = _find_named_node3d(self, "BWA_yaw_pivot")
	if _pitch_pivot == null or not is_instance_valid(_pitch_pivot):
		_pitch_pivot = _find_named_node3d(self, "BWA_pitch_pivot")
	return _yaw_pivot != null and _pitch_pivot != null

func _apply_aim(target_world: Vector3) -> void:
	var yaw_parent: Node3D = _yaw_pivot.get_parent() as Node3D
	if yaw_parent == null:
		_restore_rest_pose()
		return

	var yaw_local_target: Vector3 = yaw_parent.to_local(target_world) - _yaw_pivot.position
	var yaw_flat_sq: float = yaw_local_target.x * yaw_local_target.x + yaw_local_target.z * yaw_local_target.z
	if yaw_flat_sq > EPSILON:
		_yaw_pivot.rotation = Vector3(0.0, atan2(-yaw_local_target.x, -yaw_local_target.z), 0.0)

	var pitch_parent: Node3D = _pitch_pivot.get_parent() as Node3D
	if pitch_parent == null:
		_restore_rest_pose()
		return

	var pitch_local_target: Vector3 = pitch_parent.to_local(target_world) - _pitch_pivot.position
	var pitch_forward: float = -pitch_local_target.z
	var pitch_up: float = maxf(pitch_local_target.y, 0.0)
	if pitch_forward <= EPSILON and pitch_up <= EPSILON:
		_restore_rest_pose()
		return
	_pitch_pivot.rotation = Vector3(clampf(atan2(pitch_up, maxf(pitch_forward, EPSILON)), 0.0, MAX_PITCH_RAD), 0.0, 0.0)

func _restore_rest_pose() -> void:
	if _yaw_pivot != null:
		_yaw_pivot.rotation = Vector3.ZERO
	if _pitch_pivot != null:
		_pitch_pivot.rotation = Vector3.ZERO

func _get_assigned_target() -> Node3D:
	if _turret == null:
		return null
	var controller: TurretController = _turret.get_controller()
	if controller == null:
		return null
	return controller.get_assigned_target(_turret, _turret.team_id)

func _find_owner_turret() -> PlayerTurret:
	var cursor: Node = get_parent()
	while cursor != null:
		var assembly: TurretAssembly = cursor as TurretAssembly
		if assembly != null:
			return assembly.get_node_or_null("Turret") as PlayerTurret
		cursor = cursor.get_parent()
	return null

func _find_named_node3d(root: Node, target_name: String) -> Node3D:
	if root is Node3D and root.name == target_name:
		return root as Node3D
	for child: Node in root.get_children():
		var nested: Node3D = _find_named_node3d(child, target_name)
		if nested != null:
			return nested
	return null
