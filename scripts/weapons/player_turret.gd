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

func build_combat_stat_context(target: Object = null) -> CombatStatContext:
	var owner_ship: Ship = _resolve_owner_ship()
	if owner_ship == null:
		return null
	var weapon_id: StringName = _weapon.get_weapon_id() if _weapon != null else &""
	return owner_ship.build_combat_stat_context(weapon_id, target)

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
	var compute_value: Callable = Callable()
	if _stats != null:
		var aggr: StatAggregator = _stats
		compute_value = func(stat_id: int, base_value: float) -> float:
			return aggr.compute_for_context(stat_id, base_value, StatAggregator.Context.PLAYER)
	var snapshot: WeaponStatSnapshot = WeaponStatResolver.resolve_snapshot(_weapon, compute_value)
	WeaponStatResolver.apply_snapshot_to_turret(self, snapshot)

func _resolve_owner_ship() -> Ship:
	var node: Node = self
	while node != null:
		if node is Ship:
			return node as Ship
		node = node.get_parent()
	return null
