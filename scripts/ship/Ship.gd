# ship.gd  (Godot 4.5)
extends RigidBody3D
class_name Ship

@export var max_speed_forward := 400.0 # hard cap on forward speed
@export var max_speed_reverse := 60.0  # hard cap on reverse speed
@export var drag: float = 0.01         # higher is faster slowdown
@export var accel_forward := 100.0     # the amount of acceleration being applied by thrust (fighting drag)
@export var accel_reverse := 60.0      # see above
@export var boost_mult := 1.5          # multiplies accel

@export var max_ang_rate := Vector3( # caps the rate the *ship* can actually reach
	deg_to_rad(120.0),  # pitch
	deg_to_rad(120.0),  # yaw
	deg_to_rad(120.0))  # roll

@export var angular_accel := Vector3(
	deg_to_rad(500.0),  # how fast you ramp toward target rate
	deg_to_rad(500.0),
	deg_to_rad(500.0))

@onready var thruster: GPUParticles3D = $ThrusterParticles
@onready var camera_pivot: Marker3D = $CameraPivot

var _target_ang_rate := Vector3.ZERO   # desired ω from input (rad/s)

func _physics_process(_delta: float) -> void:
	_update_translation()

	if thruster:
		var forward_vel: float = linear_velocity.dot(-transform.basis.z)
		var forward_key := Input.is_action_pressed("thrust")
		var reverse_key := Input.is_action_pressed("reverse")
		var main_emit := forward_key and not reverse_key

		thruster.emitting = main_emit
		thruster.amount_ratio = clamp(max(forward_vel, 0.0) / (max_speed_forward * boost_mult), 0.15, 1.0)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt: float = state.step
	
	var basis_inv: Basis = transform.basis.inverse()
	var w_local: Vector3 = basis_inv * state.angular_velocity
	
	var next_local: Vector3 = Vector3(
		move_toward(w_local.x, _target_ang_rate.x, angular_accel.x * dt),
		move_toward(w_local.y, _target_ang_rate.y, angular_accel.y * dt),
		move_toward(w_local.z, _target_ang_rate.z, angular_accel.z * dt)
	)
	
	state.angular_velocity = transform.basis * next_local
	
	var lv: Vector3 = state.linear_velocity
	var drag_force: Vector3
	
	if Input.is_action_pressed("thrust") or Input.is_action_pressed("reverse"):
		drag_force = -lv * lv.length() * 0.001
	else:
		drag_force = -lv * lv.length() * drag
	
	state.apply_central_force(drag_force)

func _update_translation() -> void:
	var boost := boost_mult if Input.is_action_pressed("boost") else 1.0
	
	if Input.is_action_pressed("thrust"):
		var forward_vel: float = linear_velocity.dot(-transform.basis.z)
		if forward_vel < max_speed_forward:
			apply_central_force(-transform.basis.z * accel_forward * boost)
	if Input.is_action_pressed("reverse"):
		var reverse_vel: float = linear_velocity.dot(transform.basis.z)
		if reverse_vel < max_speed_reverse:
			apply_central_force(transform.basis.z * accel_reverse * boost)

func set_target_angular_rates(rad_per_sec: Vector3) -> void:
	_target_ang_rate = Vector3(
		clamp(rad_per_sec.x, -max_ang_rate.x, max_ang_rate.x),
		clamp(rad_per_sec.y, -max_ang_rate.y, max_ang_rate.y),
		clamp(rad_per_sec.z, -max_ang_rate.z, max_ang_rate.z)
	)

func get_speed_caps() -> Vector2:
	return Vector2(max_speed_reverse, max_speed_forward)
