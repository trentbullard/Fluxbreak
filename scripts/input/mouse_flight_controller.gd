extends Node

@export var ship_path: NodePath               # assign your Ship node
@export var sensitivity := 0.13               # pixels → aim movement
@export var radius_px := 300.0                # max off-center distance
@export var deadzone_px := 6.0                # ignore tiny jitter
@export var smooth := 5.0                     # aim smoothing (higher = snappier)
@export var lock_mouse_on_start := true
@export var roll_keys := Vector2(0, 0)

var _ship: Node
var _aim := Vector2.ZERO
var _target_aim := Vector2.ZERO

func _ready() -> void:
	_ship = get_node_or_null(ship_path)
	if lock_mouse_on_start:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			var mode = Input.get_mouse_mode()
			Input.set_mouse_mode(
				Input.MOUSE_MODE_CAPTURED if mode == Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_VISIBLE
			)
	
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_target_aim += event.relative * sensitivity
		if _target_aim.length() > radius_px:
			_target_aim = _target_aim.normalized() * radius_px

func _process(delta: float) -> void:
	if _ship == null:
		return
	
	var t: float = clamp(smooth * delta, 0.0, 1.0)
	_aim = _aim.lerp(_target_aim, t)
	
	var aim_vec := _aim
	if aim_vec.length() < deadzone_px:
		aim_vec = Vector2.ZERO
	
	var norm := aim_vec / radius_px
	var steering := Vector2(-norm.x, -norm.y).clamp(Vector2(-1, -1), Vector2(1, 1))
	
	if "set_steering" in _ship:
		_ship.set_steering(steering)
	
	var roll := 0.0
	if Input.is_action_pressed("roll_left"): roll -= 1.0
	if Input.is_action_pressed("roll_right"): roll += 1.0
	if "set_roll" in _ship:
		_ship.set_roll(roll)
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
