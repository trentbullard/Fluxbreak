# scripts/enemy/machine_warden_controller.gd (godot 4.5)
@tool
extends Node3D

@export_group("Node Paths")
@export var shield_mesh_path: NodePath = ^"MachineWardenShieldsMesh"
@export var sensor_ring_1_path: NodePath = ^"MachineWardenSensorRing1Mesh"
@export var sensor_ring_2_path: NodePath = ^"MachineWardenSensorRing2Mesh"

@export_group("Shield Rotation")
@export var shield_speed_min_deg: float = 7.0
@export var shield_speed_max_deg: float = 20.0
@export var shield_retarget_min_sec: float = 1.6
@export var shield_retarget_max_sec: float = 3.8

@export_group("Sensor Ring Rotation")
@export var sensor_speed_min_deg: float = 16.0
@export var sensor_speed_max_deg: float = 38.0
@export var sensor_retarget_min_sec: float = 0.9
@export var sensor_retarget_max_sec: float = 2.4

@export_group("Motion")
@export var angular_lerp_rate: float = 2.5
@export var preview_in_editor: bool = true

@onready var _shield_mesh: Node3D = get_node_or_null(shield_mesh_path) as Node3D
@onready var _sensor_ring_1_mesh: Node3D = get_node_or_null(sensor_ring_1_path) as Node3D
@onready var _sensor_ring_2_mesh: Node3D = get_node_or_null(sensor_ring_2_path) as Node3D

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _shield_current_rate: Vector3 = Vector3.ZERO
var _shield_target_rate: Vector3 = Vector3.ZERO
var _shield_retarget_timer: float = 0.0

var _sensor_1_current_rate: Vector3 = Vector3.ZERO
var _sensor_1_target_rate: Vector3 = Vector3.ZERO
var _sensor_1_retarget_timer: float = 0.0

var _sensor_2_current_rate: Vector3 = Vector3.ZERO
var _sensor_2_target_rate: Vector3 = Vector3.ZERO
var _sensor_2_retarget_timer: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		set_process(false)
		return

	_rng.randomize()

	_shield_target_rate = _random_angular_velocity(shield_speed_min_deg, shield_speed_max_deg)
	_shield_current_rate = _shield_target_rate
	_shield_retarget_timer = _random_interval(shield_retarget_min_sec, shield_retarget_max_sec)

	_sensor_1_target_rate = _random_angular_velocity(sensor_speed_min_deg, sensor_speed_max_deg)
	_sensor_1_current_rate = _sensor_1_target_rate
	_sensor_1_retarget_timer = _random_interval(sensor_retarget_min_sec, sensor_retarget_max_sec)

	_sensor_2_target_rate = _random_angular_velocity(sensor_speed_min_deg, sensor_speed_max_deg)
	_sensor_2_current_rate = _sensor_2_target_rate
	_sensor_2_retarget_timer = _random_interval(sensor_retarget_min_sec, sensor_retarget_max_sec)

	if _shield_mesh == null and _sensor_ring_1_mesh == null and _sensor_ring_2_mesh == null:
		set_process(false)
	else:
		set_process(true)

func _process(delta: float) -> void:
	_update_shield_rotation(delta)
	_update_sensor_1_rotation(delta)
	_update_sensor_2_rotation(delta)

func _update_shield_rotation(delta: float) -> void:
	if _shield_mesh == null:
		return
	_shield_retarget_timer -= delta
	if _shield_retarget_timer <= 0.0:
		_shield_target_rate = _random_angular_velocity(shield_speed_min_deg, shield_speed_max_deg)
		_shield_retarget_timer = _random_interval(shield_retarget_min_sec, shield_retarget_max_sec)
	_shield_current_rate = _lerp_rate(_shield_current_rate, _shield_target_rate, delta)
	_rotate_node_local(_shield_mesh, _shield_current_rate, delta)

func _update_sensor_1_rotation(delta: float) -> void:
	if _sensor_ring_1_mesh == null:
		return
	_sensor_1_retarget_timer -= delta
	if _sensor_1_retarget_timer <= 0.0:
		_sensor_1_target_rate = _random_angular_velocity(sensor_speed_min_deg, sensor_speed_max_deg)
		_sensor_1_retarget_timer = _random_interval(sensor_retarget_min_sec, sensor_retarget_max_sec)
	_sensor_1_current_rate = _lerp_rate(_sensor_1_current_rate, _sensor_1_target_rate, delta)
	_rotate_node_local(_sensor_ring_1_mesh, _sensor_1_current_rate, delta)

func _update_sensor_2_rotation(delta: float) -> void:
	if _sensor_ring_2_mesh == null:
		return
	_sensor_2_retarget_timer -= delta
	if _sensor_2_retarget_timer <= 0.0:
		_sensor_2_target_rate = _random_angular_velocity(sensor_speed_min_deg, sensor_speed_max_deg)
		_sensor_2_retarget_timer = _random_interval(sensor_retarget_min_sec, sensor_retarget_max_sec)
	_sensor_2_current_rate = _lerp_rate(_sensor_2_current_rate, _sensor_2_target_rate, delta)
	_rotate_node_local(_sensor_ring_2_mesh, _sensor_2_current_rate, delta)

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
