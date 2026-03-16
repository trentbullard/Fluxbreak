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
var eff_channel_acquire_time: float = 0.0
var eff_channel_tick_interval: float = 0.0
var eff_ramp_max_stacks: float = 0.0
var eff_ramp_damage_per_stack: float = 0.0
var eff_ramp_stacks_on_hit: float = 0.0
var eff_ramp_stacks_on_crit: float = 0.0
var eff_ramp_stacks_lost_on_graze: float = 0.0
var eff_ramp_stacks_lost_on_miss: float = 0.0

signal weapon_changed(new_weapon: WeaponDef)

func _ready() -> void:
	_bind_controller()

func _enter_tree() -> void:
	_bind_controller()

func _exit_tree() -> void:
	if _controller != null:
		_controller.unregister_turret(self, team_id)
	if _stats != null and _stats.stats_changed.is_connected(_on_stats_changed):
		_stats.stats_changed.disconnect(_on_stats_changed)
	_controller = null
	_detector = null
	_stats = null
	if is_queued_for_deletion():
		_teardown_runtime()

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

func get_runtime() -> WeaponRuntime:
	return _runtime

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

func get_shot_origin() -> Vector3:
	if muzzle != null:
		return muzzle.global_position
	return global_position

func get_effective_ramp_max_stacks() -> int:
	return maxi(int(round(eff_ramp_max_stacks)), 0)

func get_effective_ramp_stacks_on_hit() -> int:
	return maxi(int(round(eff_ramp_stacks_on_hit)), 0)

func get_effective_ramp_stacks_on_crit() -> int:
	return maxi(int(round(eff_ramp_stacks_on_crit)), 0)

func get_effective_ramp_stacks_lost_on_graze() -> int:
	return maxi(int(round(eff_ramp_stacks_lost_on_graze)), 0)

func get_effective_ramp_stacks_lost_on_miss() -> int:
	return maxi(int(round(eff_ramp_stacks_lost_on_miss)), 0)

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
	
	if _controller != null and _controller != ctrl:
		_controller.unregister_turret(self, team_id)
	_controller = ctrl
	if _controller != null:
		_controller.register_turret(self, team_id)
		_detector = _controller.detector
		var next_stats: StatAggregator = _controller.get_stat_aggregator() if _controller.has_method("get_stat_aggregator") else null
		if _stats != null and _stats != next_stats and _stats.stats_changed.is_connected(_on_stats_changed):
			_stats.stats_changed.disconnect(_on_stats_changed)
		_stats = next_stats
		if _stats != null and not _stats.stats_changed.is_connected(_on_stats_changed):
			_stats.stats_changed.connect(_on_stats_changed)
		_refresh_effective_weapon_stats()

func _teardown_runtime() -> void:
	if _runtime == null:
		return
	_runtime.on_unequip()
	_runtime = null

func _on_stats_changed(_affected: Array[Stat]) -> void:
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
		eff_channel_acquire_time = 0.0
		eff_channel_tick_interval = 0.0
		eff_ramp_max_stacks = 0.0
		eff_ramp_damage_per_stack = 0.0
		eff_ramp_stacks_on_hit = 0.0
		eff_ramp_stacks_on_crit = 0.0
		eff_ramp_stacks_lost_on_graze = 0.0
		eff_ramp_stacks_lost_on_miss = 0.0
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
	var uses_channel: bool = _weapon.uses_channel_stats()
	var uses_ramp: bool = _weapon.uses_ramp_stats()
	var base_channel_acquire: float = _weapon.get_channel_acquire_time() if uses_channel else 0.0
	var base_channel_tick: float = _weapon.get_channel_tick_interval() if uses_channel else 0.0
	var base_ramp_max_stacks: float = float(_weapon.get_ramp_max_stacks()) if uses_ramp else 0.0
	var base_ramp_damage_per_stack: float = _weapon.get_ramp_damage_per_stack() if uses_ramp else 0.0
	var base_ramp_stacks_on_hit: float = float(_weapon.get_ramp_stacks_on_hit()) if uses_ramp else 0.0
	var base_ramp_stacks_on_crit: float = float(_weapon.get_ramp_stacks_on_crit()) if uses_ramp else 0.0
	var base_ramp_stacks_lost_on_graze: float = float(_weapon.get_ramp_stacks_lost_on_graze()) if uses_ramp else 0.0
	var base_ramp_stacks_lost_on_miss: float = float(_weapon.get_ramp_stacks_lost_on_miss()) if uses_ramp else 0.0

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
		eff_channel_acquire_time = max(base_channel_acquire, 0.0) if uses_channel else 0.0
		eff_channel_tick_interval = max(base_channel_tick, 0.01) if uses_channel else 0.0
		eff_ramp_max_stacks = max(base_ramp_max_stacks, 0.0) if uses_ramp else 0.0
		eff_ramp_damage_per_stack = max(base_ramp_damage_per_stack, 0.0) if uses_ramp else 0.0
		eff_ramp_stacks_on_hit = max(base_ramp_stacks_on_hit, 0.0) if uses_ramp else 0.0
		eff_ramp_stacks_on_crit = max(base_ramp_stacks_on_crit, 0.0) if uses_ramp else 0.0
		eff_ramp_stacks_lost_on_graze = max(base_ramp_stacks_lost_on_graze, 0.0) if uses_ramp else 0.0
		eff_ramp_stacks_lost_on_miss = max(base_ramp_stacks_lost_on_miss, 0.0) if uses_ramp else 0.0
		return

	# With aggregator
	eff_fire_rate = max(0.01, aggr.compute_for_context(Stat.WEAPON_FIRE_RATE, base_fire_rate, StatAggregator.Context.PLAYER))
	eff_base_accuracy = clamp(aggr.compute_for_context(Stat.WEAPON_BASE_ACCURACY, base_acc, StatAggregator.Context.PLAYER), 0.0, 1.0)
	eff_range_falloff = clamp(aggr.compute_for_context(Stat.WEAPON_RANGE_FALLOFF, base_falloff, StatAggregator.Context.PLAYER), 0.0, 1.0)
	eff_crit_chance = clamp(aggr.compute_for_context(Stat.WEAPON_CRIT_CHANCE, base_cc, StatAggregator.Context.PLAYER), 0.0, 1.0)
	eff_graze_on_hit = clamp(aggr.compute_for_context(Stat.WEAPON_GRAZE_ON_HIT, base_goh, StatAggregator.Context.PLAYER), 0.0, 1.0)
	eff_graze_on_miss = clamp(aggr.compute_for_context(Stat.WEAPON_GRAZE_ON_MISS, base_gom, StatAggregator.Context.PLAYER), 0.0, 1.0)
	eff_crit_mult = max(0.0, aggr.compute_for_context(Stat.WEAPON_CRIT_MULT, base_cm, StatAggregator.Context.PLAYER))
	eff_graze_mult = max(0.0, aggr.compute_for_context(Stat.WEAPON_GRAZE_MULT, base_gm, StatAggregator.Context.PLAYER))
	eff_damage_min = aggr.compute_for_context(Stat.WEAPON_DAMAGE_MIN, base_dmin, StatAggregator.Context.PLAYER)
	eff_damage_max = aggr.compute_for_context(Stat.WEAPON_DAMAGE_MAX, base_dmax, StatAggregator.Context.PLAYER)
	eff_base_range = aggr.compute_for_context(Stat.WEAPON_BASE_RANGE, base_range, StatAggregator.Context.PLAYER)
	eff_range_bonus_add = aggr.compute_for_context(Stat.WEAPON_RANGE_BONUS, 0.0, StatAggregator.Context.PLAYER)
	eff_systems_bonus_add = aggr.compute_for_context(Stat.WEAPON_SYSTEMS_BONUS, 0.0, StatAggregator.Context.PLAYER)
	eff_projectile_speed = aggr.compute_for_context(Stat.PROJECTILE_SPEED, 0.0, StatAggregator.Context.PLAYER)
	eff_projectile_life = aggr.compute_for_context(Stat.PROJECTILE_LIFE, 0.0, StatAggregator.Context.PLAYER)
	eff_projectile_spread_deg = aggr.compute_for_context(Stat.PROJECTILE_SPREAD, 0.0, StatAggregator.Context.PLAYER)
	if uses_channel:
		var tick_after_fire_rate: float = max(0.01, aggr.compute_for_context(Stat.WEAPON_FIRE_RATE, max(base_channel_tick, 0.01), StatAggregator.Context.PLAYER))
		eff_channel_acquire_time = max(0.0, aggr.compute_for_context(Stat.WEAPON_CHANNEL_ACQUIRE_TIME, base_channel_acquire, StatAggregator.Context.PLAYER))
		eff_channel_tick_interval = max(0.01, aggr.compute_for_context(Stat.WEAPON_CHANNEL_TICK_INTERVAL, tick_after_fire_rate, StatAggregator.Context.PLAYER))
	else:
		eff_channel_acquire_time = 0.0
		eff_channel_tick_interval = 0.0
	if uses_ramp:
		eff_ramp_max_stacks = max(0.0, aggr.compute_for_context(Stat.WEAPON_RAMP_MAX_STACKS, base_ramp_max_stacks, StatAggregator.Context.PLAYER))
		eff_ramp_damage_per_stack = max(0.0, aggr.compute_for_context(Stat.WEAPON_RAMP_DAMAGE_PER_STACK, base_ramp_damage_per_stack, StatAggregator.Context.PLAYER))
		eff_ramp_stacks_on_hit = max(0.0, aggr.compute_for_context(Stat.WEAPON_RAMP_STACKS_ON_HIT, base_ramp_stacks_on_hit, StatAggregator.Context.PLAYER))
		eff_ramp_stacks_on_crit = max(0.0, aggr.compute_for_context(Stat.WEAPON_RAMP_STACKS_ON_CRIT, base_ramp_stacks_on_crit, StatAggregator.Context.PLAYER))
		eff_ramp_stacks_lost_on_graze = max(0.0, aggr.compute_for_context(Stat.WEAPON_RAMP_STACKS_LOST_ON_GRAZE, base_ramp_stacks_lost_on_graze, StatAggregator.Context.PLAYER))
		eff_ramp_stacks_lost_on_miss = max(0.0, aggr.compute_for_context(Stat.WEAPON_RAMP_STACKS_LOST_ON_MISS, base_ramp_stacks_lost_on_miss, StatAggregator.Context.PLAYER))
	else:
		eff_ramp_max_stacks = 0.0
		eff_ramp_damage_per_stack = 0.0
		eff_ramp_stacks_on_hit = 0.0
		eff_ramp_stacks_on_crit = 0.0
		eff_ramp_stacks_lost_on_graze = 0.0
		eff_ramp_stacks_lost_on_miss = 0.0
