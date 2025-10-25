# projectile.gd (Godot 4.5)
extends Node3D
class_name Projectile

@export var speed: float = 1000.0
@export var max_lifetime: float = 2.0
@export var collision_mask: int = 1 << 2   # e.g., layer 3 = targets
@export var exclude_owner: Node = null     # set by turret to avoid hitting self

enum ShotResult { MISS, GRAZE, HIT, CRIT }

# --- outcome & config ---
var _outcome: int = ShotResult.MISS
var _crit_mult: float = 0.0
var _graze_mult: float = 0.3
var _from_player: bool = false
var _base_damage: float = 0.0
var _effects: Array[StatusEffectDef] = []

# --- targeting & flight ---
var _tref: WeakRef = null
var _target_died: bool = false
var _dir: Vector3
var _init_pos: Vector3
var _prev_pos: Vector3
var _life: float = 0.0
var _dmg_applied: bool = false

func configure_shot(source: Node, target: Node3D, outcome: int, rolled_dmg: float,
					graze_mult: float, crit_mult: float, effects: Array[StatusEffectDef], from_player: bool) -> void:
	exclude_owner = source
	_tref = weakref(target)
	_outcome = outcome
	_crit_mult = crit_mult
	_graze_mult = graze_mult
	_from_player = from_player
	_base_damage = max(0.0, rolled_dmg)
	_effects = effects if effects != null else []
	
	if target != null:
		if target.has_signal("about_to_die"):
			target.about_to_die.connect(_on_target_died, CONNECT_ONE_SHOT)
		target.tree_exiting.connect(_on_target_died, CONNECT_ONE_SHOT)

func _ready() -> void:
	_init_pos = global_position
	_prev_pos = global_position
	var t: Node3D = _get_target()
	_dir = (t.global_position - global_position).normalized() if t != null else -global_transform.basis.z

func _physics_process(delta: float) -> void:
	var t: Node3D = _get_target()
	if not _dmg_applied:
		if t != null and not _target_died:
			_apply_to_target(t)
		else:
			_outcome = ShotResult.MISS
			_dmg_applied = true

	var next_pos: Vector3 = global_position + _dir * speed * delta
	global_position = next_pos
	_prev_pos = next_pos
	
	if t != null and not _target_died and _dmg_applied:
		var d_travelled: float = _init_pos.distance_squared_to(global_position)
		var d_to_t: float = _init_pos.distance_squared_to(t.global_position)
		if d_travelled >= d_to_t:
			queue_free()
	
	_life += delta
	if _life >= max_lifetime:
		queue_free()

func _apply_to_target(target: Object) -> void:
	var dmg: float = 0.0
	var fx_pos: Vector3 = (target as Node3D).global_position if target is Node3D else global_position

	match _outcome:
		ShotResult.CRIT:
			EffectsBus.show_float(fx_pos, "CRIT", Color.GREEN)
			dmg = _base_damage * _crit_mult
		ShotResult.HIT:
			dmg = _base_damage
		ShotResult.GRAZE:
			EffectsBus.show_float(fx_pos, "GRAZE", Color(0.8, 0.8, 0.8))
			dmg = _base_damage * _graze_mult
		ShotResult.MISS:
			EffectsBus.show_float(fx_pos, "MISS", Color(1.0, 0.569, 0.271, 1.0))
			dmg = 0.0

	if dmg > 0.0 and target.has_method("apply_damage"):
		target.call("apply_damage", dmg)
		if _from_player:
			CombatStats.report_damage(dmg)
	
	if not _effects.is_empty() and target.has_method("apply_status_effect"):
		for eff in _effects:
			if eff == null:
				continue
			var roll: float = randf()
			var chance: float = 0.0
			match _outcome:
				ShotResult.CRIT:  chance = eff.chance_on_crit
				ShotResult.HIT:   chance = eff.chance_on_hit
				ShotResult.GRAZE: chance = eff.chance_on_graze
				_: chance = 0.0
			if roll <= chance:
				target.call("apply_status_effect", eff, exclude_owner)
	
	_dmg_applied = true

func _get_target() -> Node3D:
	return (_tref.get_ref() as Node3D) if _tref != null else null

func _on_target_died(_node: Node = null) -> void:
	_target_died = true
	_tref = weakref(null)
