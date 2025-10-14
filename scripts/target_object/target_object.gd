# target_object.gd  (Godot 4.5)
extends RigidBody3D
@export var hp: float = 20.0
@export var drift_speed: float = 0.0
@export var spin_speed: float = 0.0
@export var start_frozen: bool = true
@export var explosion_scene: PackedScene

@export var ship_path: NodePath
@export var show_within_meters: float = 200.0
@export var label_height: float = 1.5
@export var label_update_hz: float = 10.0

var _accum := 0.0
var _dead: bool = false
var _last_xform: Transform3D = Transform3D()

func _ready() -> void:
	add_to_group("targets")
	if start_frozen:
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	randomize()
	apply_impulse(Vector3.ZERO, Vector3(
		randf_range(-1,1),
		randf_range(-1,1),
		randf_range(-1,1)
	).normalized() * drift_speed)
	angular_velocity = Vector3(randf(), randf(), randf()) * spin_speed
	_last_xform = global_transform

func _process(delta: float) -> void:
	if is_inside_tree():
		_last_xform = global_transform

	_accum += delta
	var interval: float = 1.0 / max(label_update_hz, 1.0)
	if _accum >= interval:
		_accum = 0.0

func apply_damage(amount: float) -> void:
	if _dead:
		return
	hp -= amount
	if hp <= 0.0:
		_die()

func _die() -> void:
	if _dead:
		return
	_dead = true
	
	if has_node("CollisionShape3D"):
		var col: CollisionShape3D = $CollisionShape3D
		col.disabled = true
	
	var xf: Transform3D = _last_xform
	if is_inside_tree():
		xf = global_transform

	if explosion_scene != null:
		var fx: CPUParticles3D = explosion_scene.instantiate() as CPUParticles3D
		fx.global_transform = xf
	
		var parent_for_fx: Node = get_tree().root
		if get_parent() != null:
			parent_for_fx = get_parent()
		parent_for_fx.add_child(fx)

	hide()
	queue_free()

func _is_offscreen(cam: Camera3D, world_pos: Vector3) -> bool:
	# Behind camera?
	if cam.is_position_behind(world_pos):
		return true

	# Outside viewport rect?
	var screen_pos: Vector2 = cam.unproject_position(world_pos)
	var rect: Rect2i = get_viewport().get_visible_rect()
	return not rect.has_point(screen_pos)
