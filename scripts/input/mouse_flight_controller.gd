# mouse_flight_controller.gd  (Godot 4.5)
extends Node

@export var ship: Ship
@export var radius_px := 300.0
@export var deadzone_px := 6.0
@export var sensitivity := 0.13         # mouse → aim pixels
@export var lock_mouse_on_start := true

# Map aim (0..1) → deg/s target. Keep below your ship's angular caps.
@export var max_pitch_rate_deg := 110.0
@export var max_yaw_rate_deg   := 110.0
@export var expo := 0.2                # 0..1. Higher = softer near center

# Optional “bank into turns”
@export var auto_bank := true
@export var bank_factor := 0.6         # 0..1 portion of yaw rate → roll rate
@export var max_roll_rate_deg := 120.0

var _aim := Vector2.ZERO
var _target_aim := Vector2.ZERO

func get_aim_px() -> Vector2:
	return _aim

func get_radius_px() -> float:
	return radius_px

func _ready() -> void:
	if lock_mouse_on_start:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_target_aim += event.relative * sensitivity
		if _target_aim.length() > radius_px:
			_target_aim = _target_aim.normalized() * radius_px

func _process(_dt: float) -> void:
	# light smoothing without the springiness
	_aim = _aim.lerp(_target_aim, 0.35)

	var a := _aim
	if a.length() < deadzone_px:
		a = Vector2.ZERO

	# Normalize to -1..1, apply expo curve for fine control near center
	var norm := a / radius_px
	var curved := Vector2(
		signf(norm.x) * pow(abs(norm.x), 1.0 - expo),
		signf(norm.y) * pow(abs(norm.y), 1.0 - expo)
	).clamp(Vector2(-1, -1), Vector2(1, 1))

	var target_yaw_rate   := -curved.x * max_yaw_rate_deg    # left/right
	var target_pitch_rate := -curved.y * max_pitch_rate_deg  # up/down

	var target_roll_rate := 0.0
	if auto_bank:
		target_roll_rate += bank_factor * target_yaw_rate
	if Input.is_action_pressed("roll_left"):  target_roll_rate += max_roll_rate_deg
	if Input.is_action_pressed("roll_right"): target_roll_rate -= max_roll_rate_deg

	ship.set_target_angular_rates(
		Vector3( deg_to_rad(target_pitch_rate),  # X (pitch)
				 deg_to_rad(target_yaw_rate),    # Y (yaw)
				 deg_to_rad(target_roll_rate) )  # Z (roll)
	)
