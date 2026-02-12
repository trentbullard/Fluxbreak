extends Node

@export var mouse_controller_path: NodePath = NodePath("../MouseFlightController")
@export_range(0.0, 0.95, 0.01) var stick_deadzone: float = 0.2
@export_range(0.1, 20.0, 0.1) var stick_ramp_speed: float = 1.0
@export_range(0.1, 20.0, 0.1) var stick_release_ramp_speed: float = 0.6

var _mouse_controller: Node = null
var _smoothed_stick: Vector2 = Vector2.ZERO

func _ready() -> void:
	_mouse_controller = get_node_or_null(mouse_controller_path)

func _process(_delta: float) -> void:
	if _mouse_controller == null or not _mouse_controller.has_method("set_controller_aim"):
		return

	var yaw_input: float = Input.get_action_strength("yaw_right") - Input.get_action_strength("yaw_left")
	var pitch_input: float = Input.get_action_strength("pitch_down") - Input.get_action_strength("pitch_up")
	var stick: Vector2 = Vector2(yaw_input, pitch_input)

	var active: bool = false
	var shaped: Vector2 = Vector2.ZERO

	var magnitude: float = stick.length()
	if magnitude > stick_deadzone:
		active = true
		var scaled: float = (magnitude - stick_deadzone) / max(1.0 - stick_deadzone, 0.001)
		shaped = stick.normalized() * clamp(scaled, 0.0, 1.0)

	var target_stick: Vector2 = shaped if active else Vector2.ZERO
	var ramp_speed: float = stick_ramp_speed if active else stick_release_ramp_speed
	_smoothed_stick = _smoothed_stick.move_toward(target_stick, ramp_speed * _delta)

	var controller_active: bool = active or _smoothed_stick.length_squared() > 0.000001
	_mouse_controller.call("set_controller_aim", _smoothed_stick, controller_active)
