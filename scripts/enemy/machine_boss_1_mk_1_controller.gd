@tool
extends Node3D

@export_group("Node Paths")
@export var back_orbiters_path: NodePath = ^"MachineBoss1Mesh/machine_boss_1_root/machine_boss_1_back_orbiters"
@export var front_orbiters_path: NodePath = ^"MachineBoss1Mesh/machine_boss_1_root/machine_boss_1_front_orbiters"
@export var inner_orbiters_path: NodePath = ^"MachineBoss1Mesh/machine_boss_1_root/machine_boss_1_inner_orbiters"
@export var outer_orbiters_path: NodePath = ^"MachineBoss1Mesh/machine_boss_1_root/machine_boss_1_outer_orbiters"

@export_group("Orbiter Rotation")
@export var orbiter_speed_min_deg: float = 12.0
@export var orbiter_speed_max_deg: float = 30.0
@export var orbiter_retarget_min_sec: float = 1.0
@export var orbiter_retarget_max_sec: float = 2.8

@export_group("Motion")
@export var angular_lerp_rate: float = 2.5
@export var preview_in_editor: bool = true

@onready var _back_orbiters: Node3D = get_node_or_null(back_orbiters_path) as Node3D
@onready var _front_orbiters: Node3D = get_node_or_null(front_orbiters_path) as Node3D
@onready var _inner_orbiters: Node3D = get_node_or_null(inner_orbiters_path) as Node3D
@onready var _outer_orbiters: Node3D = get_node_or_null(outer_orbiters_path) as Node3D

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _back_current_rate_rad_per_sec: float = 0.0
var _back_target_rate_rad_per_sec: float = 0.0
var _back_retarget_timer_sec: float = 0.0

var _front_current_rate_rad_per_sec: float = 0.0
var _front_target_rate_rad_per_sec: float = 0.0
var _front_retarget_timer_sec: float = 0.0

var _inner_current_rate_rad_per_sec: float = 0.0
var _inner_target_rate_rad_per_sec: float = 0.0
var _inner_retarget_timer_sec: float = 0.0

var _outer_current_rate_rad_per_sec: float = 0.0
var _outer_target_rate_rad_per_sec: float = 0.0
var _outer_retarget_timer_sec: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		set_process(false)
		return

	_rng.randomize()

	_back_target_rate_rad_per_sec = _random_angular_velocity(orbiter_speed_min_deg, orbiter_speed_max_deg)
	_back_current_rate_rad_per_sec = _back_target_rate_rad_per_sec
	_back_retarget_timer_sec = _random_interval(orbiter_retarget_min_sec, orbiter_retarget_max_sec)

	_front_target_rate_rad_per_sec = _random_angular_velocity(orbiter_speed_min_deg, orbiter_speed_max_deg)
	_front_current_rate_rad_per_sec = _front_target_rate_rad_per_sec
	_front_retarget_timer_sec = _random_interval(orbiter_retarget_min_sec, orbiter_retarget_max_sec)

	_inner_target_rate_rad_per_sec = _random_angular_velocity(orbiter_speed_min_deg, orbiter_speed_max_deg)
	_inner_current_rate_rad_per_sec = _inner_target_rate_rad_per_sec
	_inner_retarget_timer_sec = _random_interval(orbiter_retarget_min_sec, orbiter_retarget_max_sec)

	_outer_target_rate_rad_per_sec = _random_angular_velocity(orbiter_speed_min_deg, orbiter_speed_max_deg)
	_outer_current_rate_rad_per_sec = _outer_target_rate_rad_per_sec
	_outer_retarget_timer_sec = _random_interval(orbiter_retarget_min_sec, orbiter_retarget_max_sec)

	if _back_orbiters == null and _front_orbiters == null and _inner_orbiters == null and _outer_orbiters == null:
		set_process(false)
	else:
		set_process(true)

func _process(delta: float) -> void:
	_update_back_orbiters_rotation(delta)
	_update_front_orbiters_rotation(delta)
	_update_inner_orbiters_rotation(delta)
	_update_outer_orbiters_rotation(delta)

func _update_back_orbiters_rotation(delta: float) -> void:
	if _back_orbiters == null:
		return
	_back_retarget_timer_sec -= delta
	if _back_retarget_timer_sec <= 0.0:
		_back_target_rate_rad_per_sec = _random_angular_velocity(orbiter_speed_min_deg, orbiter_speed_max_deg)
		_back_retarget_timer_sec = _random_interval(orbiter_retarget_min_sec, orbiter_retarget_max_sec)
	_back_current_rate_rad_per_sec = _lerp_rate(_back_current_rate_rad_per_sec, _back_target_rate_rad_per_sec, delta)
	_rotate_node_local_z(_back_orbiters, _back_current_rate_rad_per_sec, delta)

func _update_front_orbiters_rotation(delta: float) -> void:
	if _front_orbiters == null:
		return
	_front_retarget_timer_sec -= delta
	if _front_retarget_timer_sec <= 0.0:
		_front_target_rate_rad_per_sec = _random_angular_velocity(orbiter_speed_min_deg, orbiter_speed_max_deg)
		_front_retarget_timer_sec = _random_interval(orbiter_retarget_min_sec, orbiter_retarget_max_sec)
	_front_current_rate_rad_per_sec = _lerp_rate(_front_current_rate_rad_per_sec, _front_target_rate_rad_per_sec, delta)
	_rotate_node_local_z(_front_orbiters, _front_current_rate_rad_per_sec, delta)

func _update_inner_orbiters_rotation(delta: float) -> void:
	if _inner_orbiters == null:
		return
	_inner_retarget_timer_sec -= delta
	if _inner_retarget_timer_sec <= 0.0:
		_inner_target_rate_rad_per_sec = _random_angular_velocity(orbiter_speed_min_deg, orbiter_speed_max_deg)
		_inner_retarget_timer_sec = _random_interval(orbiter_retarget_min_sec, orbiter_retarget_max_sec)
	_inner_current_rate_rad_per_sec = _lerp_rate(_inner_current_rate_rad_per_sec, _inner_target_rate_rad_per_sec, delta)
	_rotate_node_local_z(_inner_orbiters, _inner_current_rate_rad_per_sec, delta)

func _update_outer_orbiters_rotation(delta: float) -> void:
	if _outer_orbiters == null:
		return
	_outer_retarget_timer_sec -= delta
	if _outer_retarget_timer_sec <= 0.0:
		_outer_target_rate_rad_per_sec = _random_angular_velocity(orbiter_speed_min_deg, orbiter_speed_max_deg)
		_outer_retarget_timer_sec = _random_interval(orbiter_retarget_min_sec, orbiter_retarget_max_sec)
	_outer_current_rate_rad_per_sec = _lerp_rate(_outer_current_rate_rad_per_sec, _outer_target_rate_rad_per_sec, delta)
	_rotate_node_local_z(_outer_orbiters, _outer_current_rate_rad_per_sec, delta)

func _lerp_rate(current_rate: float, target_rate: float, delta: float) -> float:
	var weight: float = clamp(angular_lerp_rate * delta, 0.0, 1.0)
	return lerpf(current_rate, target_rate, weight)

func _rotate_node_local_z(target_node: Node3D, angular_rate_rad_per_sec: float, delta: float) -> void:
	target_node.rotate_object_local(Vector3.BACK, angular_rate_rad_per_sec * delta)

func _random_interval(min_sec: float, max_sec: float) -> float:
	var lo: float = min(min_sec, max_sec)
	var hi: float = max(min_sec, max_sec)
	return _rng.randf_range(lo, hi)

func _random_angular_velocity(min_deg_per_sec: float, max_deg_per_sec: float) -> float:
	var min_deg: float = min(min_deg_per_sec, max_deg_per_sec)
	var max_deg: float = max(min_deg_per_sec, max_deg_per_sec)
	var min_rate: float = deg_to_rad(min_deg)
	var max_rate: float = deg_to_rad(max_deg)
	var rate: float = _rng.randf_range(min_rate, max_rate)
	if _rng.randf() < 0.5:
		rate *= -1.0
	return rate
