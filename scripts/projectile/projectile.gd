# projectile.gd (Godot 4.5)
extends Node3D
class_name Projectile

@export var speed: float = 1000.0
@export var max_lifetime: float = 2.0
@export var collision_mask: int = 1 << 2   # e.g., layer 3 = targets
@export var exclude_owner: Node = null     # set by turret to avoid hitting self

# --- outcome & config ---
var _outcome: int = WeaponCombatResolver.ShotResult.MISS
var _crit_mult: float = 0.0
var _graze_mult: float = 0.3
var _from_player: bool = false
var _base_damage: float = 0.0
var _effects: Array[StatusEffectDef] = []
var _combat_stat_context: CombatStatContext = null

# --- targeting & flight ---
var _tref: WeakRef = null
var _target_died: bool = false
var _dir: Vector3
var _init_pos: Vector3
var _cleanup_distance_sq: float = 0.0
var _life: float = 0.0
var _dmg_applied: bool = false

func configure_shot(source: Node, target: Node3D, outcome: int, rolled_dmg: float,
					graze_mult: float, crit_mult: float, effects: Array[StatusEffectDef], from_player: bool, combat_stat_context: CombatStatContext = null) -> void:
	exclude_owner = source
	_tref = weakref(target)
	_outcome = outcome
	_crit_mult = crit_mult
	_graze_mult = graze_mult
	_from_player = from_player
	_base_damage = max(0.0, rolled_dmg)
	_effects = effects if effects != null else []
	_combat_stat_context = combat_stat_context.duplicate_context() if combat_stat_context != null else null
	
	if target != null:
		_cleanup_distance_sq = 0.0
		if target.has_signal("about_to_die"):
			target.about_to_die.connect(_on_target_died, CONNECT_ONE_SHOT)
		target.tree_exiting.connect(_on_target_died, CONNECT_ONE_SHOT)
	else:
		_cleanup_distance_sq = 0.0

func _ready() -> void:
	_init_pos = global_position
	var t: Node3D = _get_target()
	_dir = (t.global_position - global_position).normalized() if t != null else -global_transform.basis.z
	if _cleanup_distance_sq <= 0.0 and t != null:
		_cleanup_distance_sq = _init_pos.distance_squared_to(t.global_position)

func _physics_process(delta: float) -> void:
	var t: Node3D = _get_target()
	if not _dmg_applied:
		if t != null and not _target_died:
			_apply_to_target(t)
		else:
			_outcome = WeaponCombatResolver.ShotResult.MISS
			_dmg_applied = true

	var next_pos: Vector3 = global_position + _dir * speed * delta
	global_position = next_pos
	
	if _outcome != WeaponCombatResolver.ShotResult.MISS and _cleanup_distance_sq > 0.0 and _dmg_applied:
		var d_travelled: float = _init_pos.distance_squared_to(global_position)
		if d_travelled >= _cleanup_distance_sq:
			queue_free()
	
	_life += delta
	if _life >= max_lifetime:
		queue_free()

func _apply_to_target(target: Object) -> void:
	var valid_source: Object = null
	if exclude_owner != null and is_instance_valid(exclude_owner):
		valid_source = exclude_owner
	WeaponCombatResolver.apply_shot_to_target(
		valid_source,
		target,
		_outcome,
		_base_damage,
		_graze_mult,
		_crit_mult,
		_effects,
		_from_player,
		_combat_stat_context
	)
	_dmg_applied = true

func _get_target() -> Node3D:
	return (_tref.get_ref() as Node3D) if _tref != null else null

func _on_target_died(_node: Node = null) -> void:
	_target_died = true
	_tref = weakref(null)
