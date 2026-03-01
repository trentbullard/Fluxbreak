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
var _runtime: WeaponRuntime = null
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

signal weapon_changed(new_weapon: WeaponDef)

func _ready() -> void:
	_bind_controller()

func _enter_tree() -> void:
	_bind_controller()

func _exit_tree() -> void:
	if _runtime != null:
		_runtime.on_unequip()
		_runtime = null
	if _controller != null:
		_controller.unregister_turret(self, team_id)

# --- public api ---

func apply_weapon(w: WeaponDef, team_id_val: int) -> void:
	var previous_team: int = team_id
	if _controller != null and previous_team != team_id_val:
		_controller.unregister_turret(self, previous_team)

	var next_runtime: WeaponRuntime = WeaponRuntimeFactory.create_for(self, w)
	if _runtime != null:
		_runtime.on_unequip()

	_weapon = w
	team_id = team_id_val

	if _controller != null and previous_team != team_id:
		_controller.register_turret(self, team_id)

	weapon_changed.emit(_weapon)
	if shot_sound != null:
		shot_sound.stream = w.shot_sound if w != null else null
		shot_sound.max_polyphony = max_shot_sounds
	_refresh_effective_weapon_stats()
	_runtime = next_runtime
	if _runtime != null:
		_runtime.on_equip()

func get_weapon() -> WeaponDef:
	return _weapon

func swap_weapon(new_weapon: WeaponDef, keep_cooldown: bool = true, team_id_val: int = team_id) -> void:
	var prev_cd: float = _runtime.get_cooldown() if _runtime != null else 0.0
	apply_weapon(new_weapon, team_id_val)
	if _runtime != null:
		_runtime.set_cooldown(prev_cd if keep_cooldown else 0.0)

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

func get_controller() -> TurretController:
	return _controller

# --- firing loop ---

func _physics_process(delta: float) -> void:
	if _runtime == null:
		return
	_runtime.physics_process(delta)

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
