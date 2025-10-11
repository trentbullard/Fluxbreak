extends CharacterBody3D
@export var max_thrust: float = 100
@export var boost_mult: float = 1.75
@export var yaw_rate_deg: float = 120.0
@export var pitch_rate_deg: float = 120.0
@export var roll_rate_deg: float = 120.0
@export var turn_rate_deg: float = 90.0
@export var mass: float = 1.5
@export var drag: float = 0.6
@export var shield_max: float = 100
@export var shield: float = 75
@export var hull_max: float = 100
@export var hull: float = 50

@onready var thruster: GPUParticles3D = $ThrusterParticles
@onready var camera_pivot: Marker3D = $CameraPivot

var steering := Vector2.ZERO	# x = yaw (-1..1), y = pitch (-1..1)
var roll_input := 0.0			# keep Q/E roll or A/D

var _vel: Vector3 = Vector3.ZERO

func set_steering(vec: Vector2) -> void:
	steering = vec.clamp(Vector2(-1, -1), Vector2(1, 1))

func set_roll(val: float) -> void:
	roll_input = clamp(val, -1.0, 1.0)

func _physics_process(delta: float) -> void:
	_handle_rotation(delta)
	_handle_thrust(delta)
	_apply_drag(delta)
	
	velocity = _vel
	move_and_slide()

	if thruster:
		thruster.emitting = Input.is_action_pressed("thrust") or (!Input.is_action_pressed("reverse") and Input.is_action_pressed("boost"))
		thruster.amount_ratio = clamp(abs(_local_forward_speed()) / (max_thrust * boost_mult), 0.2, 1.0)

func _handle_rotation(delta: float) -> void:
	var yaw = deg_to_rad(yaw_rate_deg) * steering.x * delta
	var pitch = deg_to_rad(pitch_rate_deg) * steering.y * delta
	var roll = deg_to_rad(roll_rate_deg) * roll_input * delta

	rotate_object_local(Vector3.UP, yaw)
	rotate_object_local(Vector3.RIGHT, pitch)
	rotate_object_local(Vector3.FORWARD, roll)

func _handle_thrust(delta: float) -> void:
	var local_forward = -transform.basis.z
	var throttle := 0.0
	if Input.is_action_pressed("thrust"):
		throttle += 1.0
	if Input.is_action_pressed("reverse"):
		throttle -= 0.6

	var boost = boost_mult if (Input.is_action_pressed("boost")) else 1.0
	var accel = (max_thrust * boost / mass) * throttle
	_vel += local_forward * accel * delta

func _apply_drag(delta: float) -> void:
	_vel = _vel.lerp(Vector3.ZERO, clamp(drag * delta, 0.0, 1.0))

func _local_forward_speed() -> float:
	var local_v = global_transform.basis.inverse() * _vel
	return -local_v.z
