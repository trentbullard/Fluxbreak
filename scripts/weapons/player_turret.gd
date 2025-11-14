# scripts/weapons/player_turret.gd (godot 4.5)
extends Node3D
class_name PlayerTurret

@export var controller_path: NodePath
@export var target_groups: Array[String] = []      # targets or player
@export var systems_bonus: float = 0.10            # upgrades add here
@export var team_id: int = 0

@export var visual_controller: LaserTurretVisualController
@export var muzzle: Marker3D
@export var shot_sound: AudioStreamPlayer3D
@export var max_shot_sounds: int = 4

## Extra range added to the weapon's base_range for assignment purposes.
## This models ammo/accuracy modifiers that let a turret engage past its base range at a penalty.
@export var range_bonus: float = 0.0

## Optional hard cap for how far this turret may ever be assigned (0 = auto: base + range_bonus).
@export var max_range_override: float = 0.0

var _weapon: WeaponDef = null
var _cooldown := 0.0
var _controller: TurretController = null
var _detector: Area3D = null

const Stat = StatTypes.Stat
var _stats: StatAggregator = null

# Cached effective stats
var eff_fire_rate: float = 0.0
var eff_base_accuracy: float = 0.0
var eff_range_falloff: float = 0.0
var eff_crit_chance: float = 0.0
var eff_graze_on_hit: float = 0.0
var eff_graze_on_miss: float = 0.0
var eff_crit_mult: float = 1.0
var eff_graze_mult: float = 0.3
var eff_damage_min: float = 0.0
var eff_damage_max: float = 0.0
var eff_base_range: float = 0.0
var eff_range_bonus_add: float = 0.0
var eff_systems_bonus_add: float = 0.0
var eff_projectile_speed: float = 0.0
var eff_projectile_life: float = 0.0
var eff_projectile_spread_deg: float = 0.0

enum ShotResult { MISS, GRAZE, HIT, CRIT }

signal weapon_changed(new_weapon: WeaponDef)

func _ready() -> void:
	_bind_controller()

func _enter_tree() -> void:
	_bind_controller()

func _exit_tree() -> void:
	if _controller != null:
		_controller.unregister_turret(self, team_id)

# --- public api ---

func apply_weapon(w: WeaponDef, team_id_val: int) -> void:
	_weapon = w
	team_id = team_id_val
	weapon_changed.emit(_weapon)
	if shot_sound != null and w != null:
		shot_sound.stream = w.shot_sound
		shot_sound.max_polyphony = max_shot_sounds
	_refresh_effective_weapon_stats()

func get_weapon() -> WeaponDef:
	return _weapon

func swap_weapon(new_weapon: WeaponDef, keep_cooldown: bool = true) -> void:
	var prev_cd: float = _cooldown
	apply_weapon(new_weapon, team_id)
	_cooldown = prev_cd if keep_cooldown else 0.0

func set_visual_controller(vc: LaserTurretVisualController) -> void:
	visual_controller = vc
	if visual_controller != null:
		visual_controller.set_charge(0.0)

## Return the weapon's base range (from the currently equipped weapon) or 0 if none.
func get_base_range() -> float:
	if _weapon != null:
		return eff_base_range
	return 0.0

## Return the maximum range the controller may assign to this turret.
## If `max_range_override` > 0 it is used, otherwise base_range + range_bonus.
func get_max_assign_range() -> float:
	var base: float = get_base_range()
	if max_range_override > 0.0:
		return max_range_override
	return base + range_bonus + eff_range_bonus_add

# --- firing loop ---

func _physics_process(delta: float) -> void:
	if _weapon == null or _controller == null:
		return

	_cooldown -= delta
	if visual_controller != null and eff_fire_rate > 0.0:
		var t_charge: float = 1.0 - clamp(_cooldown / eff_fire_rate, 0.0, 1.0)
		visual_controller.set_charge(t_charge)
	
	if _cooldown > 0.0:
		return

	var tgt: Node3D = _controller.get_assigned_target(self, team_id)
	if tgt == null:
		return
	
	_fire_at_with_roll(tgt)
	_cooldown = max(0.01, eff_fire_rate)

func _effective_accuracy_vs(target: Node3D) -> float:
	if _weapon == null:
		return 0.0

	var ev: float = 0.0
	if target.has_method("get_evasion"):
		ev = float(target.call("get_evasion"))

	var dist: float = global_position.distance_to(target.global_position)
	var base_r: float = max(1.0, eff_base_range)
	var range_factor: float = clamp(dist / base_r, 0.0, 1.0)
	var acc_base: float = max(eff_base_accuracy + systems_bonus + eff_systems_bonus_add, 0.0)
	var acc_range_scaled: float = acc_base * lerp(1.0, 1.0 - eff_range_falloff, range_factor)
	return clamp(acc_range_scaled - ev, 0.0, 1.0)

func _fire_at_with_roll(target: Node3D) -> void:
	if _weapon == null or _weapon.projectile_scene == null or not target.visible:
		return

	# Aim with optional spread
	var dir: Vector3 = (target.global_position - muzzle.global_position).normalized()
	if eff_projectile_spread_deg > 0.0:
		dir = _apply_spread(dir, eff_projectile_spread_deg)
	var aim_basis: Basis = Basis.looking_at(dir, Vector3.UP)
	
	var hit_chance: float = _effective_accuracy_vs(target)
	var outcome: int = _resolve_shot(hit_chance)
	var dmg_min: float = minf(eff_damage_min, eff_damage_max)
	var dmg_max: float = maxf(eff_damage_min, eff_damage_max)
	var dmg: float = randf_range(dmg_min, dmg_max)

	var p: Projectile = _weapon.projectile_scene.instantiate() as Projectile
	if p == null:
		return

	p.global_transform = Transform3D(aim_basis, muzzle.global_position)
	if eff_projectile_speed > 0.0:
		p.speed = eff_projectile_speed
	if eff_projectile_life > 0.0:
		p.max_lifetime = eff_projectile_life
	p.configure_shot(self, target, outcome, dmg, eff_graze_mult, eff_crit_mult, _weapon.status_effects, true)
	get_tree().current_scene.add_child(p)

	if shot_sound != null:
		shot_sound.pitch_scale = randf_range(0.80, 1.20)
		shot_sound.play()
	
	if visual_controller != null:
		visual_controller.reset_after_shot()

func _resolve_shot(hit_chance: float) -> int:
	var hc: float = clamp(hit_chance, 0.0, 1.0)
	var cc: float = clamp(eff_crit_chance, 0.0, 1.0)
	var gh: float = clamp(eff_graze_on_hit, 0.0, 1.0)
	var gm: float = clamp(eff_graze_on_miss, 0.0, 1.0)

	# If it hits at all…
	var r1: float = randf()
	if r1 <= hc:
		# crit → graze-on-hit → normal
		var r2: float = randf()
		if r2 <= cc:
			return ShotResult.CRIT
		elif r2 <= cc + max(0.0, 1.0 - cc) * gh:
			return ShotResult.GRAZE
		else:
			return ShotResult.HIT
	else:
		# miss → maybe graze-on-miss
		var r3: float = randf()
		if r3 <= gm:
			return ShotResult.GRAZE
		return ShotResult.MISS

# --- private ---

func _bind_controller() -> void:
	var ctrl: TurretController = null
	
	if controller_path != NodePath():
		ctrl = get_node_or_null(controller_path) as TurretController
	
	if ctrl == null:
		var p: Node = get_parent()
		while p != null and ctrl == null:
			ctrl = p as TurretController
			p = p.get_parent()
	
	_controller = ctrl
	if _controller != null:
		_controller.register_turret(self, team_id)
		_detector = _controller.detector
		_stats = _controller.get_stat_aggregator() if _controller.has_method("get_stat_aggregator") else null
		if _stats != null and not _stats.stats_changed.is_connected(_on_stats_changed):
			_stats.stats_changed.connect(_on_stats_changed)
		_refresh_effective_weapon_stats()

func _on_stats_changed(_affected: Array[int]) -> void:
	_refresh_effective_weapon_stats()

func _refresh_effective_weapon_stats() -> void:
	if _weapon == null:
		# Zero-out to avoid using stale data
		eff_fire_rate = 0.0
		eff_base_accuracy = 0.0
		eff_range_falloff = 0.0
		eff_crit_chance = 0.0
		eff_graze_on_hit = 0.0
		eff_graze_on_miss = 0.0
		eff_crit_mult = 1.0
		eff_graze_mult = 0.3
		eff_damage_min = 0.0
		eff_damage_max = 0.0
		eff_base_range = 0.0
		eff_range_bonus_add = 0.0
		eff_systems_bonus_add = 0.0
		eff_projectile_speed = 0.0
		eff_projectile_life = 0.0
		eff_projectile_spread_deg = 0.0
		return

	var aggr: StatAggregator = _stats
	# Base from weapon
	var base_fire_rate: float = _weapon.fire_rate
	var base_acc: float = _weapon.base_accuracy
	var base_range: float = _weapon.base_range
	var base_falloff: float = _weapon.accuracy_range_falloff
	var base_cc: float = _weapon.crit_chance
	var base_goh: float = _weapon.graze_on_hit
	var base_gom: float = _weapon.graze_on_miss
	var base_cm: float = _weapon.crit_mult
	var base_gm: float = _weapon.graze_mult
	var base_dmin: float = _weapon.damage_min
	var base_dmax: float = _weapon.damage_max

	# If no aggregator, copy base
	if aggr == null:
		eff_fire_rate = base_fire_rate
		eff_base_accuracy = base_acc
		eff_range_falloff = base_falloff
		eff_crit_chance = base_cc
		eff_graze_on_hit = base_goh
		eff_graze_on_miss = base_gom
		eff_crit_mult = base_cm
		eff_graze_mult = base_gm
		eff_damage_min = base_dmin
		eff_damage_max = base_dmax
		eff_base_range = base_range
		eff_range_bonus_add = 0.0
		eff_systems_bonus_add = 0.0
		eff_projectile_speed = 0.0
		eff_projectile_life = 0.0
		eff_projectile_spread_deg = 0.0
		return

	# With aggregator
	eff_fire_rate = max(0.01, aggr.compute(Stat.WEAPON_FIRE_RATE, base_fire_rate))
	eff_base_accuracy = clamp(aggr.compute(Stat.WEAPON_BASE_ACCURACY, base_acc), 0.0, 1.0)
	eff_range_falloff = clamp(aggr.compute(Stat.WEAPON_RANGE_FALLOFF, base_falloff), 0.0, 1.0)
	eff_crit_chance = clamp(aggr.compute(Stat.WEAPON_CRIT_CHANCE, base_cc), 0.0, 1.0)
	eff_graze_on_hit = clamp(aggr.compute(Stat.WEAPON_GRAZE_ON_HIT, base_goh), 0.0, 1.0)
	eff_graze_on_miss = clamp(aggr.compute(Stat.WEAPON_GRAZE_ON_MISS, base_gom), 0.0, 1.0)
	eff_crit_mult = max(0.0, aggr.compute(Stat.WEAPON_CRIT_MULT, base_cm))
	eff_graze_mult = max(0.0, aggr.compute(Stat.WEAPON_GRAZE_MULT, base_gm))
	eff_damage_min = aggr.compute(Stat.WEAPON_DAMAGE_MIN, base_dmin)
	eff_damage_max = aggr.compute(Stat.WEAPON_DAMAGE_MAX, base_dmax)
	eff_base_range = aggr.compute(Stat.WEAPON_BASE_RANGE, base_range)
	eff_range_bonus_add = aggr.compute(Stat.WEAPON_RANGE_BONUS, 0.0)
	eff_systems_bonus_add = aggr.compute(Stat.WEAPON_SYSTEMS_BONUS, 0.0)
	eff_projectile_speed = aggr.compute(Stat.PROJECTILE_SPEED, 0.0)
	eff_projectile_life = aggr.compute(Stat.PROJECTILE_LIFE, 0.0)
	eff_projectile_spread_deg = aggr.compute(Stat.PROJECTILE_SPREAD, 0.0)

func _apply_spread(dir: Vector3, spread_deg: float) -> Vector3:
	var angle_rad: float = deg_to_rad(spread_deg)
	var up_vec: Vector3 = Vector3.UP
	if abs(dir.dot(Vector3.UP)) > 0.99:
		up_vec = Vector3.RIGHT
	var tangent: Vector3 = dir.cross(up_vec).normalized()
	var bitangent: Vector3 = dir.cross(tangent).normalized()
	var u: float = randf()
	var v: float = randf()
	var theta: float = 2.0 * PI * u
	var r: float = angle_rad * sqrt(v)
	var offset: Vector3 = (tangent * cos(theta) + bitangent * sin(theta)) * tan(r)
	var ndir: Vector3 = (dir + offset).normalized()
	return ndir
