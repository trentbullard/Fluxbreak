# projectile.gd (Godot 4.5)
extends Node3D
class_name Projectile

@export var speed: float = 1000.0
@export var damage: float = 10.0
@export var max_lifetime: float = 2.0
@export var collision_mask: int = 1 << 2   # e.g., layer 3 = targets
@export var exclude_owner: Node = null     # set by turret to avoid hitting self

var _target: Node3D = null
var _outcome: int = ShotResult.MISS
var _crit_mult: float = 0.0
var _graze_mult: float = 0.3

var _init_pos: Vector3
var _prev_pos: Vector3
var _life: float = 0.0
var _dir: Vector3
var _dmg_applied: bool = false

enum ShotResult { MISS, GRAZE, HIT, CRIT }

func configure_with_outcome(source: Node, target: Node3D, outcome: int, graze_mult: float, crit_mult: float) -> void:
	exclude_owner = source
	_target = target
	_outcome = outcome
	_crit_mult = crit_mult
	_graze_mult = graze_mult

func _ready() -> void:
	_init_pos = global_position
	_prev_pos = global_position
	_dir = (_target.global_position - _init_pos).normalized()

func _physics_process(delta: float) -> void:
	var travel: Vector3 = _dir * speed * delta
	var next_pos: Vector3 = global_position + travel
	
	if not _dmg_applied:
		_apply_to_target(_target)
	
	if is_instance_valid(_target):
		var d_to_t: float = _init_pos.distance_squared_to(_target.global_position)
		if d_to_t <= 0.0:
			queue_free()
	
	# No hit: move forward and continue
	global_position = next_pos
	_prev_pos = next_pos

	_life += delta
	if _life >= max_lifetime:
		queue_free()

func _apply_to_target(collider: Object) -> void:
	var dmg: float = 0.0
	var fx_pos: Vector3 = collider.global_position
	match _outcome:
		ShotResult.CRIT:
			EffectsBus.show_float(fx_pos, "CRIT", Color.GREEN)
			dmg = damage * _crit_mult
		ShotResult.HIT: dmg = damage
		ShotResult.GRAZE:
			EffectsBus.show_float(fx_pos, "GRAZE", Color(0.8, 0.8, 0.8))
			dmg = damage * _graze_mult
		ShotResult.MISS:
			EffectsBus.show_float(fx_pos, "MISS", Color(1.0, 0.5, 0.3))
			dmg = 0.0
	if dmg > 0.0 and collider != null and collider.has_method("apply_damage"):
		(collider as Object).call("apply_damage", dmg)
	_dmg_applied = true
