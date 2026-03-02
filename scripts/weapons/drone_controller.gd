extends Node3D
class_name DroneController

const STATE_DOCKED: int = 0
const STATE_ACTIVE: int = 1
const STATE_ATTACKING: int = 2
const STATE_RETURNING: int = 3

signal state_reported(origin_bay_id: int, slot_index: int, next_state: int)

var origin_bay_id: int = -1
var slot_index: int = -1
var _target_ref: WeakRef = weakref(null)
var _anchor_ref: WeakRef = weakref(null)
var _flight_state: int = STATE_DOCKED
var _velocity: Vector3 = Vector3.ZERO
var _swarm_clock: float = 0.0
var _slot_phase: float = 0.0
var _trail_particles: GPUParticles3D = null
var _trail_process: ParticleProcessMaterial = null
var _trail_dir: Vector3 = Vector3.BACK

const ACTIVE_SPEED: float = 110.0
const ACTIVE_ACCEL: float = 450.0
const ATTACK_SPEED: float = 165.0
const ATTACK_ACCEL: float = 700.0
const RETURN_SPEED: float = 140.0
const RETURN_ACCEL: float = 650.0
const SWARM_RADIUS_BASE: float = 4.0
const SWARM_RADIUS_STEP: float = 1.15
const SWARM_HEIGHT: float = 0.85
const SWARM_ANGULAR_SPEED: float = 2.6
const ATTACK_ORBIT_RADIUS: float = 2.1
const ATTACK_ANGULAR_SPEED: float = 7.0
const TRAIL_LENGTH: float = 2.0
const TRAIL_WIDTH: float = 0.05
const TRAIL_MIN_LIFETIME: float = 0.03
const TRAIL_MAX_LIFETIME: float = 0.22

func configure_drone(origin_bay_id_value: int, slot_index_value: int, anchor: Node3D = null) -> void:
	origin_bay_id = origin_bay_id_value
	slot_index = slot_index_value
	_anchor_ref = weakref(anchor) if anchor != null else weakref(null)
	_slot_phase = float(slot_index) * 0.917

func command_launch(target: Node3D) -> void:
	_flight_state = STATE_ACTIVE
	command_set_target(target)
	_report_state(STATE_ACTIVE)

func command_attack(target: Node3D) -> void:
	command_set_target(target)
	if target == null:
		_flight_state = STATE_ACTIVE
		_report_state(STATE_ACTIVE)
		return
	_flight_state = STATE_ATTACKING
	_report_state(STATE_ATTACKING)

func command_idle() -> void:
	_flight_state = STATE_ACTIVE
	command_set_target(null)
	_report_state(STATE_ACTIVE)

func command_set_target(target: Node3D) -> void:
	_target_ref = weakref(target) if target != null else weakref(null)

func command_begin_return() -> void:
	_flight_state = STATE_RETURNING
	command_set_target(null)
	_report_state(STATE_RETURNING)

func command_dock() -> void:
	_flight_state = STATE_DOCKED
	_velocity = Vector3.ZERO
	command_set_target(null)
	_report_state(STATE_DOCKED)
	if is_inside_tree():
		call_deferred("queue_free")
	else:
		queue_free()

func get_target() -> Node3D:
	return _target_ref.get_ref() as Node3D if _target_ref != null else null

func _physics_process(delta: float) -> void:
	if _flight_state == STATE_DOCKED:
		return
	var anchor: Node3D = _get_anchor()
	if anchor == null:
		return

	_swarm_clock += delta

	match _flight_state:
		STATE_ACTIVE:
			var swarm_point: Vector3 = _compute_anchor_swarm_point(anchor)
			_move_toward_world_point(swarm_point, ACTIVE_SPEED, ACTIVE_ACCEL, delta)
		STATE_ATTACKING:
			var target: Node3D = get_target()
			if target == null or not is_instance_valid(target):
				_flight_state = STATE_ACTIVE
				_report_state(STATE_ACTIVE)
				return
			var attack_point: Vector3 = _compute_target_attack_point(target)
			_move_toward_world_point(attack_point, ATTACK_SPEED, ATTACK_ACCEL, delta)
		STATE_RETURNING:
			var return_point: Vector3 = anchor.global_position
			_move_toward_world_point(return_point, RETURN_SPEED, RETURN_ACCEL, delta)

func _get_anchor() -> Node3D:
	return _anchor_ref.get_ref() as Node3D if _anchor_ref != null else null

func _compute_anchor_swarm_point(anchor: Node3D) -> Vector3:
	var radius: float = SWARM_RADIUS_BASE + SWARM_RADIUS_STEP * float(max(0, slot_index))
	var angle: float = _swarm_clock * SWARM_ANGULAR_SPEED + _slot_phase
	var local_offset: Vector3 = Vector3(
		cos(angle) * radius,
		sin(angle * 1.6 + _slot_phase) * SWARM_HEIGHT,
		sin(angle) * radius
	)
	return anchor.global_position + anchor.global_transform.basis * local_offset

func _compute_target_attack_point(target: Node3D) -> Vector3:
	var angle: float = _swarm_clock * ATTACK_ANGULAR_SPEED + _slot_phase
	var local_offset: Vector3 = Vector3(
		cos(angle) * ATTACK_ORBIT_RADIUS,
		sin(angle * 2.0 + _slot_phase) * (SWARM_HEIGHT * 0.45),
		sin(angle) * ATTACK_ORBIT_RADIUS
	)
	return target.global_position + local_offset

func _move_toward_world_point(world_point: Vector3, max_speed: float, accel: float, delta: float) -> void:
	var to_goal: Vector3 = world_point - global_position
	var dist: float = to_goal.length()
	var desired_vel: Vector3 = Vector3.ZERO
	if dist > 0.001:
		var target_speed: float = min(max_speed, dist * 8.0)
		desired_vel = to_goal / dist * target_speed

	_velocity = _velocity.move_toward(desired_vel, accel * delta)
	global_position += _velocity * delta
	_update_trail()

func _report_state(next_state: int) -> void:
	state_reported.emit(origin_bay_id, slot_index, next_state)
