# ship.gd  (Godot 4.5)
extends CharacterBody3D

# ---------- Translation ----------
@export var max_speed_forward := 200.0
@export var max_speed_reverse := 60.0
@export var accel_forward := 120.0
@export var accel_reverse := 60.0
@export var boost_mult := 2.0

# “Inertia stabilizers” (flight assist)
@export var fa_enabled := true
@export var fa_lateral_strength := 6.0    # how strongly we cancel X/Y drift (m/s^2)
@export var fa_vertical_strength := 6.0   # Z-up axis in local space
@export var fa_forward_brake := 2.5       # forward/back toward commanded speed

# Small drags for high-speed taming
@export var linear_drag := 0.2            # linear (per second)
@export var quad_drag := 0.003            # scales with v^2

# ---------- Rotation (radians) ----------
@export var max_ang_rate := Vector3( # caps the rate the *ship* can actually reach
	deg_to_rad(120.0),  # pitch
	deg_to_rad(120.0),  # yaw
	deg_to_rad(120.0))  # roll

@export var angular_accel := Vector3(
	deg_to_rad(500.0),  # how fast you ramp toward target rate
	deg_to_rad(500.0),
	deg_to_rad(500.0))

@export var angular_damp := 6.0          # air-brake for spin when inputs stop

# ---------- FX ----------
@onready var thruster: GPUParticles3D = $ThrusterParticles
@onready var camera_pivot: Marker3D = $CameraPivot

# runtime state
var _target_ang_rate := Vector3.ZERO   # desired ω from input (rad/s)
var _ang_vel := Vector3.ZERO           # actual ω (rad/s)
var _vel: Vector3 = Vector3.ZERO       # world m/s

func set_target_angular_rates(rad_per_sec: Vector3) -> void:
	# Clamp to ship capability (weighty ceiling)
	_target_ang_rate = Vector3(
		clamp(rad_per_sec.x, -max_ang_rate.x, max_ang_rate.x),
		clamp(rad_per_sec.y, -max_ang_rate.y, max_ang_rate.y),
		clamp(rad_per_sec.z, -max_ang_rate.z, max_ang_rate.z)
	)

func _physics_process(delta: float) -> void:
	_update_rotation(delta)
	_update_translation(delta)

	velocity = _vel
	move_and_slide()

	# Simple FX proxy
	if thruster:
		var fwd_speed := _forward_speed_local()   # + forward, - backward
		var forward_key := Input.is_action_pressed("thrust")
		var reverse_key := Input.is_action_pressed("reverse")

		# Only show the main rear thruster when we're holding the forward key (using thrust)
		# regardless of forward or reverse speed
		var main_emit := forward_key and not reverse_key

		thruster.emitting = main_emit
		thruster.amount_ratio = clamp(max(fwd_speed, 0.0) / (max_speed_forward * boost_mult), 0.15, 1.0)

# ---------- Rotation ----------
func _update_rotation(delta: float) -> void:
	# PD-lite: accelerate angular velocity toward target, then damp leftover spin
	var step := Vector3(
		move_toward(_ang_vel.x, _target_ang_rate.x, angular_accel.x * delta) - _ang_vel.x,
		move_toward(_ang_vel.y, _target_ang_rate.y, angular_accel.y * delta) - _ang_vel.y,
		move_toward(_ang_vel.z, _target_ang_rate.z, angular_accel.z * delta) - _ang_vel.z
	)
	_ang_vel += step

	# Damping when no command is present (feels heavier, less skatey)
	_ang_vel = _ang_vel.move_toward(Vector3.ZERO, angular_damp * delta * 0.5)

	# Apply rotation in local axes
	rotate_object_local(Vector3.RIGHT,   _ang_vel.x * delta) # pitch
	rotate_object_local(Vector3.UP,      _ang_vel.y * delta) # yaw
	rotate_object_local(Vector3.FORWARD, _ang_vel.z * delta) # roll

# ---------- Translation ----------
func _update_translation(delta: float) -> void:
	var boost := boost_mult if Input.is_action_pressed("boost") else 1.0

	# Desired forward speed from inputs
	var desired_fwd := 0.0
	if Input.is_action_pressed("thrust"):
		desired_fwd -= max_speed_forward * boost
	if Input.is_action_pressed("reverse"):
		desired_fwd += max_speed_reverse

	# Current velocity in *local* frame
	var v_basis := global_transform.basis
	var v_local := v_basis.inverse() * _vel

	# Ease toward desired forward speed with accel limits
	var acc := (accel_forward if desired_fwd >= v_local.z else accel_reverse) * boost
	v_local.z = move_toward(v_local.z, desired_fwd, acc * delta)

	# Flight assist trims side and vertical drift gradually (not instantly)
	if fa_enabled:
		var side_trim := sign(-v_local.x) * min(abs(v_local.x), fa_lateral_strength * delta) as float
		var up_trim   := sign(-v_local.y) * min(abs(v_local.y), fa_vertical_strength * delta) as float
		v_local.x += side_trim
		v_local.y += up_trim
	else:
		# optional: very light natural bleed even w/ FA off
		v_local.x = move_toward(v_local.x, 0.0, 0.5 * delta)
		v_local.y = move_toward(v_local.y, 0.0, 0.5 * delta)

	# Back to world space
	_vel = v_basis * v_local

	# Drags: linear + small quadratic so high speeds feel “thick”
	var speed := _vel.length()
	if speed > 0.0001:
		var lin := linear_drag * delta
		var quad := quad_drag * speed * speed * delta
		var total_drag := clamp(lin + quad, 0.0, 0.98) as float
		_vel *= (1.0 - total_drag)

func _forward_speed_local() -> float:
	var v_local := global_transform.basis.inverse() * _vel
	# forward in Godot is -Z, but we store forward speed as positive → use -Z
	return -v_local.z
