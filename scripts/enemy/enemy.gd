# target_object.gd  (Godot 4.5)
extends RigidBody3D
class_name Enemy

@export var _hp: float = 20.0
@export var evasion: float = 0.10        # 0..1
@export var thrust: float = 35.0
@export var explosion_scene: PackedScene

@export var player_ship: Ship
@export var label_height: float = 1.5
@export var label_update_hz: float = 10.0

@export var min_distance: float = 250.0
@export var max_distance: float = 400.0

var _dead: bool = false
var _last_xform: Transform3D = Transform3D()

enum Size {SM, MD, LG}

func _ready() -> void:
	add_to_group("targets")
	_last_xform = global_transform

func _physics_process(_delta: float) -> void:
	if player_ship != null:
		face_target(player_ship.global_position)
		orbit_target(player_ship.global_position)

func _process(_delta: float) -> void:
	if is_inside_tree():
		_last_xform = global_transform

func apply_damage(amount: float) -> void:
	if _dead:
		return
	_hp -= amount
	if _hp <= 0.0:
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

func face_target(target: Vector3) -> void:
	var new_transform: Transform3D = global_transform.looking_at(target, Vector3.UP)
	new_transform.origin = global_position
	global_transform = new_transform

func orbit_target(target: Vector3) -> void:
	var diff: Vector3 = global_position - target
	var too_close: bool = diff.length_squared() <= min_distance * min_distance
	var too_far: bool = diff.length_squared() > max_distance * max_distance
	
	if too_close:
		apply_central_force(global_transform.basis.z * thrust)
	
	if too_far:
		apply_central_force(-global_transform.basis.z * thrust)

func set_ship(ship: Ship):
	player_ship = ship

func get_evasion() -> float:
	return clamp(evasion, 0.0, 1.0)

func set_size(size: Size) -> void:
	match size:
		Size.SM:
			_hp = _hp * 0.5
			scale *= 0.5
		Size.LG:
			_hp = _hp * 1.5
			scale *= 1.5
