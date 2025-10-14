# Reticle.gd  (Godot 4.5)
extends Control
class_name Reticle

@export var ship_path: NodePath

# ---------- Mouse spring (inner circle) ----------
@export var max_radius_px: float = 160.0
@export var mouse_gain: float = 1.0
@export var k_spring: float = 40.0
@export var c_damp: float = 12.0

# ---------- Ship angular-velocity driven offset (outer parentheses) ----------
@export var av_to_px_gain: Vector2 = Vector2(60.0, 60.0)  # px per rad/s (x=yaw, y=pitch)
@export var av_max_offset_px: float = 120.0
@export var av_smooth: float = 14.0                        # higher = snappier smoothing

# ---------- Visuals ----------
@export var line_width: float = 2.0
@export var center_radius_px: float = 10.0
@export var paren_radius_px: float = 26.0
@export var paren_size_px: float = 18.0
@export var paren_arc_r_px: float = 12.0
@export var color: Color = Color(1,1,1,1)

signal aim_offset_changed(nrm: Vector2)  # inner cursor normalized to max_radius_px

var _aim_pos: Vector2 = Vector2.ZERO
var _aim_vel: Vector2 = Vector2.ZERO

var _outer_pos: Vector2 = Vector2.ZERO   # from angular velocity

var _ship: Node3D

func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if ship_path != NodePath(""):
		_ship = get_node_or_null(ship_path) as Node3D

func _unhandled_input(event: InputEvent) -> void:
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null:
		_aim_pos += mm.relative * mouse_gain
		var aim_len: float = _aim_pos.length()
		if aim_len > max_radius_px:
			_aim_pos = _aim_pos / aim_len * max_radius_px

func _process(delta: float) -> void:
	# --- inner spring (mouse cursor) ---
	#var accel_in: Vector2 = (-k_spring * _aim_pos) + (-c_damp * _aim_vel)
	#_aim_vel += accel_in * delta
	#_aim_pos += _aim_vel * delta
	#if _aim_pos.length() < 0.01 and _aim_vel.length() < 0.01:
		#_aim_pos = Vector2.ZERO
		#_aim_vel = Vector2.ZERO

	# --- outer offset (ship angular velocity) ---
	if _ship != null and _ship is RigidBody3D:
		var rb: RigidBody3D = _ship as RigidBody3D
		# Map ship angular velocity (rad/s) to screen offset.
		# Yaw (around +Y) → right (+X). Pitch (around +X) → up (-Y).
		var av: Vector3 = rb.angular_velocity
		var target: Vector2 = Vector2(av.y * av_to_px_gain.x, -av.x * av_to_px_gain.y)

		# clamp target to disc
		var tlen: float = target.length()
		if tlen > av_max_offset_px:
			target = target / tlen * av_max_offset_px

		# critically damped-ish smoothing toward target (simple exponential)
		var lerp_t: float = 1.0 - exp(-av_smooth * delta)
		_outer_pos = _outer_pos.lerp(target, lerp_t)
	else:
		_outer_pos = _outer_pos.lerp(Vector2.ZERO, 1.0 - exp(-av_smooth * delta))

	queue_redraw()
	emit_signal("aim_offset_changed", _aim_pos / max_radius_px)

func _draw() -> void:
	var rect: Rect2 = get_viewport_rect()
	var screen_center: Vector2 = rect.size * 0.5

	# Outer parentheses sit at the AV-driven position
	var outer_center: Vector2 = screen_center + _outer_pos
	_draw_parentheses(outer_center)

	# Inner circle follows mouse spring
	var inner_center: Vector2 = screen_center + _aim_pos
	draw_circle(inner_center, center_radius_px, color, false, line_width)

func _draw_parentheses(center: Vector2) -> void:
	var left_center: Vector2 = center + Vector2(-paren_radius_px, 0.0)
	var right_center: Vector2 = center + Vector2(paren_radius_px, 0.0)
	_draw_paren(left_center, true)
	_draw_paren(right_center, false)

func _draw_paren(pivot: Vector2, is_left: bool) -> void:
	var half_h: float = paren_size_px * 0.5
	var top: Vector2 = pivot + Vector2(0.0, -half_h)
	var bot: Vector2 = pivot + Vector2(0.0,  half_h)
	var dir: float = -1.0 if is_left else 1.0
	var arc_center_top: Vector2 = top + Vector2(dir * paren_arc_r_px, 0.0)
	var arc_center_bot: Vector2 = bot + Vector2(dir * paren_arc_r_px, 0.0)

	draw_line(top, top + Vector2(dir * (paren_arc_r_px * 0.6), 0.0), color, line_width, true)
	draw_line(bot, bot + Vector2(dir * (paren_arc_r_px * 0.6), 0.0), color, line_width, true)

	var start_top: float = (-PI * 0.25) if is_left else (PI * 1.25)
	var end_top: float   = ( PI * 0.25) if is_left else (PI * 0.75)
	var start_bot: float = (-PI * 0.75) if is_left else (PI * 0.75)
	var end_bot: float   = (-PI * 1.25) if is_left else (PI * 1.25)

	_draw_arc(arc_center_top, paren_arc_r_px, start_top, end_top)
	_draw_arc(arc_center_bot, paren_arc_r_px, start_bot, end_bot)

func _draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = 16
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var a: float = lerp(start_angle, end_angle, t)
		var p: Vector2 = center + Vector2(cos(a), sin(a)) * radius
		points.append(p)
	draw_polyline(points, color, line_width, true)

# Helpers if you want to consume the offsets:
func get_mouse_screen_offset_px() -> Vector2:
	return _aim_pos

func get_outer_screen_offset_px() -> Vector2:
	return _outer_pos

func get_mouse_offset_normalized() -> Vector2:
	if max_radius_px <= 0.0:
		return Vector2.ZERO
	return _aim_pos / max_radius_px
