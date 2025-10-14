# camera_rig.gd  (Godot 4.5)
extends Node3D

@export var ship: Ship
@export var camera: Camera3D
@export var height_offset: float = 1.5
@export var distance_offset: float = 10.0
@export var angle_offset_deg: float = 0.0
@export var fov: float = 90.0
@export var max_accel_for_offset: float = 100.0

@export var la_gain: float = 1.5
@export var la_clamp: float = 1.0

var _neutral_pos: Vector3
var _neutral_rot: Vector3

var _prev_velocity: Vector3 = Vector3.ZERO

var current_look_rot: Vector2 = Vector2.ZERO

func _ready() -> void:
	_neutral_pos = Vector3(0.0, height_offset, -distance_offset)
	_neutral_rot = Vector3(angle_offset_deg, 0.0, 0.0)
	position = _neutral_pos
	camera.fov = fov

func _physics_process(delta: float) -> void:
	# Convert global ω to ship-local ω
	var w_local: Vector3 = ship.transform.basis.inverse() * ship.angular_velocity

	var target_look: Vector2 = get_look_ahead_offset(w_local, Vector2(la_gain, la_gain))
	current_look_rot = current_look_rot.lerp(target_look, 6.0 * delta)

	# Build local rotation basis (start from your neutral camera pitch)
	var rot: Basis = Basis()
	rot = rot.rotated(Vector3.RIGHT, deg_to_rad(angle_offset_deg))  # base pitch tilt if you want it
	rot = rot.rotated(Vector3.RIGHT, current_look_rot.x)            # pitch
	rot = rot.rotated(Vector3.UP,    current_look_rot.y)            # yaw
	transform.basis = rot

	# Distance “push back” from accel magnitude (position is LOCAL)
	var current_velocity: Vector3 = ship.linear_velocity
	var acceleration: Vector3 = (current_velocity - _prev_velocity) / max(delta, 1e-4)
	_prev_velocity = current_velocity

	var target_distance: float = get_distance_offset(acceleration.length())
	position = Vector3(position.x, position.y, lerp(position.z, target_distance, 5.0 * delta))

func get_look_ahead_offset(w_local: Vector3, gain: Vector2) -> Vector2:
	# Godot convention: +X = pitch, +Y = yaw. Empirically, this feels right:
	# - pitch: tip camera DOWN when nose is pitching UP  → negative sign
	# - yaw:   look AHEAD into the turn (usually same sign as yaw)
	var pitch_off: float = clamp(-w_local.x * gain.x, -la_clamp, la_clamp)
	var yaw_off:   float = clamp( w_local.y * gain.y, -la_clamp, la_clamp)
	return Vector2(pitch_off, -yaw_off)

func get_distance_offset(accel_magnitude: float) -> float:
	var t: float = clamp(accel_magnitude / max_accel_for_offset, 0.0, 1.0)
	# Push camera back up to ~20% further when accelerating
	return distance_offset * lerp(1.0, 1.2, t)
