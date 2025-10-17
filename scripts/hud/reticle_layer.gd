# Reticle.gd
extends Control
class_name Reticle

@export var ship_path: NodePath
@export var center_radius_px: float = 10.0
@export var line_width: float = 2.0
@export var color: Color = Color(1, 1, 1, 0.6)

var _controller: Node
var _ship: Node3D
var _max_radius_px: float

func _ready() -> void:
	anchor_left = 0.0; anchor_top = 0.0; anchor_right = 1.0; anchor_bottom = 1.0
	offset_left = 0.0; offset_top = 0.0; offset_right = 0.0; offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if ship_path != NodePath(""):
		_ship = get_node_or_null(ship_path) as Node3D
		_controller = _ship.get_node_or_null("MouseFlightController")
		if _controller != null and _controller.has_method("get_aim_px"):
			var r: float = _controller.get("radius_px")
			if r > 0.0:
				_max_radius_px = r

func _process(_delta: float) -> void:
	var aim_px: Vector2 = Vector2.ZERO
	if _controller != null and _controller.has_method("get_aim_px"):
		aim_px = _controller.call("get_aim_px") as Vector2

	queue_redraw()

func _draw() -> void:
	var rect: Rect2 = get_viewport_rect()
	var screen_center: Vector2 = rect.size * 0.5

	# Read once to avoid double-call
	var aim_px: Vector2 = Vector2.ZERO
	if _controller != null and _controller.has_method("get_aim_px"):
		aim_px = _controller.call("get_aim_px") as Vector2

	# Inner Circle - Ship Direct
	var inner_center: Vector2 = screen_center + aim_px
	draw_circle(inner_center, center_radius_px, color, false, line_width)
