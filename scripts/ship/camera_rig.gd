# Original follow camera with configurable view preferences.
extends Node3D

## Physical player ship followed by this local rig.
@export var ship: Ship
## Existing view camera beneath the rig.
@export var camera: Camera3D
## Authored ship-relative height before the preference multiplier.
@export var height_offset: float = 1.5
## Authored chase distance before the preference multiplier.
@export var distance_offset: float = 10.0
## Authored neutral camera pitch in degrees.
@export var angle_offset_deg: float = 0.0
## Field of view overridden by the player's view preference.
@export var fov: float = 90.0
## Acceleration magnitude at which pullback reaches its configured maximum.
@export var max_accel_for_offset: float = 100.0

## Original angular-velocity look gain.
@export var la_gain: float = 1.5
## Original independent pitch/yaw look limits in radians.
@export var la_clamp: float = 1.0

var _base_height: float = 1.5
var _base_distance: float = 10.0
var _rotation_response: float = 6.0
var _distance_response: float = 5.0
var _look_ahead: float = 1.0
var _acceleration_pullback: float = 0.2
var _prev_velocity: Vector3 = Vector3.ZERO
var _last_accel_magnitude: float = 0.0

var current_look_rot: Vector2 = Vector2.ZERO

func _ready() -> void:
	_base_height = height_offset
	_base_distance = distance_offset
	EventBus.camera_preferences_changed.connect(_on_camera_preferences_changed)
	_apply_preferences(CameraPreferences.get_settings())
	position = Vector3(0.0, height_offset, -distance_offset)

## Ship selection supplies authored offsets; user multipliers never accumulate.
func apply_ship_visuals(visuals: ShipVisualDef) -> void:
	if visuals == null:
		return
	_base_height = visuals.camera_height
	_base_distance = visuals.camera_distance
	angle_offset_deg = visuals.camera_angle_deg
	_apply_preferences(CameraPreferences.get_settings())
	position = Vector3(0.0, height_offset, -distance_offset)

func _apply_preferences(settings: Dictionary) -> void:
	height_offset = _base_height * float(settings[&"height_scale"])
	distance_offset = _base_distance * float(settings[&"distance_scale"])
	fov = float(settings[&"fov"])
	var tightness: float = float(settings[&"tightness"])
	_rotation_response = lerpf(4.0, 16.0, tightness)
	_distance_response = lerpf(3.0, 15.0, tightness)
	_look_ahead = float(settings[&"look_ahead"])
	_acceleration_pullback = float(settings[&"acceleration_pullback"])
	if is_instance_valid(camera):
		camera.fov = fov

func _on_camera_preferences_changed(settings: Dictionary) -> void:
	var previous_distance: float = get_distance_offset(_last_accel_magnitude)
	var previous_look_ahead: float = _look_ahead
	_apply_preferences(settings)
	# Scale the existing elastic pose for paused previews without stepping flight.
	position.y = height_offset
	position.z *= get_distance_offset(_last_accel_magnitude) / maxf(previous_distance, 0.0001)
	if not is_equal_approx(previous_look_ahead, _look_ahead):
		if previous_look_ahead > 0.0001:
			current_look_rot *= _look_ahead / previous_look_ahead
		elif is_instance_valid(ship):
			var w_local: Vector3 = ship.transform.basis.inverse() * ship.angular_velocity
			current_look_rot = get_look_ahead_offset(w_local, Vector2(la_gain, la_gain))
	_apply_look_rotation()

func _physics_process(delta: float) -> void:
	# Convert global ω to ship-local ω
	var w_local: Vector3 = ship.transform.basis.inverse() * ship.angular_velocity

	var target_look: Vector2 = get_look_ahead_offset(w_local, Vector2(la_gain, la_gain))
	current_look_rot = current_look_rot.lerp(target_look, _rotation_response * delta)

	_apply_look_rotation()

	# Distance “push back” from accel magnitude (position is LOCAL)
	var current_velocity: Vector3 = ship.linear_velocity
	var acceleration: Vector3 = (current_velocity - _prev_velocity) / max(delta, 1e-4)
	_prev_velocity = current_velocity
	_last_accel_magnitude = acceleration.length()

	var target_distance: float = get_distance_offset(_last_accel_magnitude)
	position = Vector3(position.x, position.y, lerp(position.z, target_distance, _distance_response * delta))

func _apply_look_rotation() -> void:
	# Build local rotation basis (start from your neutral camera pitch)
	var rot: Basis = Basis()
	rot = rot.rotated(Vector3.RIGHT, deg_to_rad(angle_offset_deg))  # base pitch tilt if you want it
	rot = rot.rotated(Vector3.RIGHT, current_look_rot.x)            # pitch
	rot = rot.rotated(Vector3.UP,    current_look_rot.y)            # yaw
	transform.basis = rot

func get_look_ahead_offset(w_local: Vector3, gain: Vector2) -> Vector2:
	# Godot convention: +X = pitch, +Y = yaw. Empirically, this feels right:
	# - pitch: tip camera DOWN when nose is pitching UP  → negative sign
	# - yaw:   look AHEAD into the turn (usually same sign as yaw)
	var pitch_off: float = clamp(-w_local.x * gain.x, -la_clamp, la_clamp)
	var yaw_off:   float = clamp( w_local.y * gain.y, -la_clamp, la_clamp)
	return Vector2(pitch_off, -yaw_off) * _look_ahead

func get_distance_offset(accel_magnitude: float) -> float:
	var t: float = clamp(accel_magnitude / max_accel_for_offset, 0.0, 1.0)
	return distance_offset * lerp(1.0, 1.0 + _acceleration_pullback, t)
