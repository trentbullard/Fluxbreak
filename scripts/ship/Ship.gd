extends CharacterBody3D
@export var max_thrust: float = 16.0
@export var boost_mult: float = 1.75
@export var turn_rate_deg: float = 90.0 # yaw/pitch per second
@export var roll_rate_deg: float = 120.0
@export var mass: float = 1.5          # higher = slower accel
@export var drag: float = 0.6           # mild space-damp for readability

# Optional: link to thruster for auto-intensity
@onready var thruster: GPUParticles3D = $ThrusterParticles
@onready var camera_pivot: Marker3D = $CameraPivot

var _vel: Vector3 = Vector3.ZERO

func _physics_process(delta: float) -> void:
	_handle_rotation(delta)
	_handle_thrust(delta)
	_apply_drag(delta)
	velocity = _vel
	move_and_slide()

	# Thruster intensity (purely visual)
	if thruster:
		thruster.emitting = Input.is_action_pressed("thrust") or Input.is_action_pressed("boost")
		thruster.amount_ratio = clamp(abs(_local_forward_speed()) / (max_thrust * boost_mult), 0.2, 1.0)

func _handle_rotation(delta: float) -> void:
	var yaw_input = 0.0
	if Input.is_action_pressed("turn_left"):  yaw_input += 1.0
	if Input.is_action_pressed("turn_right"): yaw_input -= 1.0

	var roll_input = 0.0
	if Input.is_action_pressed("roll_left"):  roll_input += 1.0
	if Input.is_action_pressed("roll_right"): roll_input -= 1.0

	# Yaw (turn around up), slight nose-down autopitch for motion readability can be added later
	var yaw = deg_to_rad(turn_rate_deg) * yaw_input * delta
	var roll = deg_to_rad(roll_rate_deg) * roll_input * delta
	rotate_object_local(Vector3.UP, yaw)
	rotate_object_local(Vector3.FORWARD, roll)

func _handle_thrust(delta: float) -> void:
	var local_forward = -transform.basis.z # Godot forward is -Z
	var throttle = 0.0
	if Input.is_action_pressed("thrust"):
		throttle -= 1.0
	if Input.is_action_pressed("reverse"):
		throttle += 0.6

	var boost = boost_mult if (Input.is_action_pressed("boost")) else 1.0
	var accel = (max_thrust * boost / mass) * throttle
	_vel += local_forward * accel * delta

func _apply_drag(delta: float) -> void:
	_vel = _vel.lerp(Vector3.ZERO, clamp(drag * delta, 0.0, 1.0))

func _local_forward_speed() -> float:
	var local_v = global_transform.basis.inverse() * _vel
	return -local_v.z
