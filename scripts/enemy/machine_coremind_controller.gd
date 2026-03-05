# script/enemy/machine_coremind_controller.gd (godot 4.5)
@tool
extends Node3D

@export_group("Node Paths")
@export var inner_sphere_path: NodePath = ^"MachineCoremindInnerSphereMesh"
@export var secondary_sphere_path: NodePath = ^"MachineCoremindSecondarySphereMesh"
@export var outer_sphere_path: NodePath = ^"MachineCoremindOuterSphereMesh"

@export_group("Sphere Rotation")
@export var sphere_speed_min_deg: float = 14.0
@export var sphere_speed_max_deg: float = 34.0
@export var sphere_retarget_min_sec: float = 0.9
@export var sphere_retarget_max_sec: float = 2.2

@export_group("Motion")
@export var angular_lerp_rate: float = 2.5
@export var preview_in_editor: bool = true

@onready var _inner_sphere: Node3D = get_node_or_null(inner_sphere_path) as Node3D
@onready var _secondary_sphere: Node3D = get_node_or_null(secondary_sphere_path) as Node3D
@onready var _outer_sphere: Node3D = get_node_or_null(outer_sphere_path) as Node3D

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _inner_current_rate: Vector3 = Vector3.ZERO
var _inner_target_rate: Vector3 = Vector3.ZERO
var _inner_retarget_timer: float = 0.0

var _secondary_current_rate: Vector3 = Vector3.ZERO
var _secondary_target_rate: Vector3 = Vector3.ZERO
var _secondary_retarget_timer: float = 0.0

var _outer_current_rate: Vector3 = Vector3.ZERO
var _outer_target_rate: Vector3 = Vector3.ZERO
var _outer_retarget_timer: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		set_process(false)
		return

	_rng.randomize()

	_inner_target_rate = _random_angular_velocity(sphere_speed_min_deg, sphere_speed_max_deg)
	_inner_current_rate = _inner_target_rate
	_inner_retarget_timer = _random_interval(sphere_retarget_min_sec, sphere_retarget_max_sec)

	_secondary_target_rate = _random_angular_velocity(sphere_speed_min_deg, sphere_speed_max_deg)
	_secondary_current_rate = _secondary_target_rate
	_secondary_retarget_timer = _random_interval(sphere_retarget_min_sec, sphere_retarget_max_sec)

	_outer_target_rate = _random_angular_velocity(sphere_speed_min_deg, sphere_speed_max_deg)
	_outer_current_rate = _outer_target_rate
	_outer_retarget_timer = _random_interval(sphere_retarget_min_sec, sphere_retarget_max_sec)

	if _inner_sphere == null and _secondary_sphere == null and _outer_sphere == null:
		set_process(false)
	else:
		set_process(true)

func _process(delta: float) -> void:
	_update_inner_rotation(delta)
	_update_secondary_rotation(delta)
	_update_outer_rotation(delta)

func _update_inner_rotation(delta: float) -> void:
	if _inner_sphere == null:
		return
	_inner_retarget_timer -= delta
	if _inner_retarget_timer <= 0.0:
		_inner_target_rate = _random_angular_velocity(sphere_speed_min_deg, sphere_speed_max_deg)
		_inner_retarget_timer = _random_interval(sphere_retarget_min_sec, sphere_retarget_max_sec)
	_inner_current_rate = _lerp_rate(_inner_current_rate, _inner_target_rate, delta)
	_rotate_node_local(_inner_sphere, _inner_current_rate, delta)

func _update_secondary_rotation(delta: float) -> void:
	if _secondary_sphere == null:
		return
	_secondary_retarget_timer -= delta
	if _secondary_retarget_timer <= 0.0:
		_secondary_target_rate = _random_angular_velocity(sphere_speed_min_deg, sphere_speed_max_deg)
		_secondary_retarget_timer = _random_interval(sphere_retarget_min_sec, sphere_retarget_max_sec)
	_secondary_current_rate = _lerp_rate(_secondary_current_rate, _secondary_target_rate, delta)
	_rotate_node_local(_secondary_sphere, _secondary_current_rate, delta)

func _update_outer_rotation(delta: float) -> void:
	if _outer_sphere == null:
		return
	_outer_retarget_timer -= delta
	if _outer_retarget_timer <= 0.0:
		_outer_target_rate = _random_angular_velocity(sphere_speed_min_deg, sphere_speed_max_deg)
		_outer_retarget_timer = _random_interval(sphere_retarget_min_sec, sphere_retarget_max_sec)
	_outer_current_rate = _lerp_rate(_outer_current_rate, _outer_target_rate, delta)
	_rotate_node_local(_outer_sphere, _outer_current_rate, delta)

func _lerp_rate(current_rate: Vector3, target_rate: Vector3, delta: float) -> Vector3:
	var weight: float = clamp(angular_lerp_rate * delta, 0.0, 1.0)
	return current_rate.lerp(target_rate, weight)

func _rotate_node_local(target_node: Node3D, angular_rate: Vector3, delta: float) -> void:
	target_node.rotate_object_local(Vector3.RIGHT, angular_rate.x * delta)
	target_node.rotate_object_local(Vector3.UP, angular_rate.y * delta)
	target_node.rotate_object_local(Vector3.BACK, angular_rate.z * delta)

func _random_interval(min_sec: float, max_sec: float) -> float:
	var lo: float = min(min_sec, max_sec)
	var hi: float = max(min_sec, max_sec)
	return _rng.randf_range(lo, hi)

func _random_angular_velocity(min_deg_per_sec: float, max_deg_per_sec: float) -> Vector3:
	var min_deg: float = min(min_deg_per_sec, max_deg_per_sec)
	var max_deg: float = max(min_deg_per_sec, max_deg_per_sec)
	var min_rate: float = deg_to_rad(min_deg)
	var max_rate: float = deg_to_rad(max_deg)

	var rate: Vector3 = Vector3(
		_rng.randf_range(-max_rate, max_rate),
		_rng.randf_range(-max_rate, max_rate),
		_rng.randf_range(-max_rate, max_rate)
	)
	var min_rate_sq: float = min_rate * min_rate
	if rate.length_squared() < min_rate_sq:
		var axis: Vector3 = Vector3(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0)
		)
		if axis.length_squared() < 0.0001:
			axis = Vector3.UP
		axis = axis.normalized()
		var mag: float = _rng.randf_range(min_rate, max_rate)
		rate = axis * mag

	return rate
