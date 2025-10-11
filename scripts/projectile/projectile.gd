# projectile.gd (Godot 4.5)
extends Node3D
class_name Projectile

@export var speed: float = 1000.0
@export var damage: float = 10.0
@export var max_lifetime: float = 2.0
@export var collision_mask: int = 1 << 2   # e.g., layer 3 = targets
@export var exclude_owner: Node = null     # set by turret to avoid hitting self

var _prev_pos: Vector3
var _life: float = 0.0

func _ready() -> void:
	_prev_pos = global_position

func _physics_process(delta: float) -> void:
	var dir: Vector3 = -global_transform.basis.z
	var travel: Vector3 = dir * speed * delta
	var next_pos: Vector3 = global_position + travel

	# Sweep from _prev_pos to next_pos
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(_prev_pos, next_pos)
	params.collision_mask = collision_mask
	if exclude_owner != null:
		params.exclude = [exclude_owner]

	var hit: Dictionary = space.intersect_ray(params)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_method("apply_damage"):
			(collider as Object).call("apply_damage", damage)
		queue_free()
		return

	# No hit: move forward and continue
	global_position = next_pos
	_prev_pos = next_pos

	_life += delta
	if _life >= max_lifetime:
		queue_free()

func configure(source: Node) -> void:
	exclude_owner = source
