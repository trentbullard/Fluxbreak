# target_object.gd  (Godot 4.5)
extends RigidBody3D
class_name TargetObject

@export var player_ship: Ship
@export var explosion_scene: PackedScene

@export var max_hull: float = 20.0
@export var max_shield: float = 0.0
@export var shield_regen: float = 0.0
@export var score_on_kill: int = 5
@export var lifetime: float = 20.0

var _dead: bool = false
var _last_xform: Transform3D = Transform3D()
var hull: float = 20.0
var shield: float = 0.0

enum Size {SM, MD, LG}
@export var size: Size = Size.MD
@export var randomize_on_spawn: bool = true

const SIZE_DATA: Dictionary = {
	Size.SM: { "hull_mult": 0.5, "scale": 0.25, "thrust_mult": 1.15, "evasion_add": 0.05 },
	Size.MD: { "hull_mult": 1.0, "scale": 1.0,  "thrust_mult": 1.0,  "evasion_add": 0.0  },
	Size.LG: { "hull_mult": 1.5, "scale": 2.0,  "thrust_mult": 0.85, "evasion_add": -0.05 }
}

func _ready() -> void:
	add_to_group("targets")
	_last_xform = global_transform

func _process(delta: float) -> void:
	if is_inside_tree():
		_last_xform = global_transform
		lifetime -= delta
		
		if lifetime < 0.0:
			hide()
			queue_free()

func apply_damage(amount: float) -> void:
	if _dead:
		return
	hull -= amount
	if hull <= 0.0:
		_die()

func _die() -> void:
	if _dead:
		return
	_dead = true
	RunState.add_score(score_on_kill, "target")
	
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

func set_ship(ship: Ship):
	player_ship = ship

func _apply_size(s: Size) -> void:
	var data: Dictionary = SIZE_DATA[s]
	hull = max_hull * float(data["hull_mult"])
	
	var model_root: Node3D = $MeshInstance3D
	if model_root != null:
		var k: float = float(data["scale"])
		model_root.scale = Vector3(k, k, k)
		var col: CollisionShape3D = $CollisionShape3D
		col.scale = Vector3(k, k, k)
