# enemy_turret.gd  (Godot 4.5)
extends Node3D
class_name EnemyTurret

@export var target_groups: Array[String] = []      # targets or player
@export var systems_bonus: float = 0.10            # upgrades add here
@export var team_id: int = 0

@onready var shot_sound: AudioStreamPlayer3D = $ShotSound
@onready var muzzle: Marker3D   = $Muzzle

var _detector: Area3D = null
var _weapon: WeaponDef = null
var _weapon_stats: WeaponStatSnapshot = null
var _cooldown: float = 0.0
var _targets: Array[Node3D] = []

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

func apply_weapon(w: WeaponDef, team_id_val: int, d: Area3D, snapshot: WeaponStatSnapshot = null) -> void:
	_weapon = w
	_weapon_stats = snapshot if snapshot != null else WeaponStatResolver.resolve_snapshot(w)
	WeaponStatResolver.apply_snapshot_to_turret(self, _weapon_stats)
	_detector = d
	team_id = team_id_val
	if _detector != null:
		var cs: CollisionShape3D = _detector.get_node("CollisionShape3D") as CollisionShape3D
		var sphere: SphereShape3D = cs.shape as SphereShape3D
		if sphere != null and w != null:
			sphere.radius = max(eff_base_range + eff_range_bonus_add, 0.0)

func get_shot_origin() -> Vector3:
	if muzzle != null:
		return muzzle.global_position
	return global_position

func build_combat_stat_context(_target: Object = null) -> CombatStatContext:
	var owner_enemy: Enemy = _resolve_owner_enemy()
	if owner_enemy == null:
		return null
	return owner_enemy.build_combat_stat_context()

func _ready() -> void:
	if _detector != null:
		_detector.body_entered.connect(_on_body_entered)
		_detector.body_exited.connect(_on_body_exited)

func decorator_body_signal(area: Area3D, is_enter: bool) -> void:
	if is_enter:
		area.body_entered.connect(_on_body_entered)
	else:
		area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if not (body is Node3D) or _targets.has(body):
		return
	
	for group_name: String in target_groups:
		if body.is_in_group(group_name):
			_targets.append(body)
			break

func _on_body_exited(body: Node) -> void:
	_targets.erase(body)

func _physics_process(delta: float) -> void:
	if _weapon == null:
		return
	
	# Trim freed/null targets
	for i in range(_targets.size() - 1, -1, -1):
		if _targets[i] == null or not is_instance_valid(_targets[i]):
			_targets.remove_at(i)

	_cooldown -= delta
	if _cooldown > 0.0:
		return

	var target: Node3D = _pick_nearest()
	if target == null:
		return
	
	_fire_at_with_roll(target)
	_cooldown = max(0.01, eff_fire_rate)

func _pick_nearest() -> Node3D:
	var best: Node3D = null
	var best_d2: float = INF
	for t in _targets:
		var d2: float = global_position.distance_squared_to(t.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = t
	return best

func _fire_at_with_roll(target: Node3D) -> void:
	if _weapon == null or _weapon.projectile_scene == null or not target.visible:
		return
	if muzzle == null:
		return

	var dir: Vector3 = (target.global_position - muzzle.global_position).normalized()
	var aim_basis: Basis = Basis.looking_at(dir, Vector3.UP)
	
	var hit_chance: float = WeaponCombatResolver.compute_effective_accuracy_vs_target(self, target)
	var outcome: int = WeaponCombatResolver.resolve_shot_for_turret(self, hit_chance)
	
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
	var combat_stat_context: CombatStatContext = build_combat_stat_context(target)
	p.configure_shot(self, target, outcome, dmg, eff_graze_mult, eff_crit_mult, _weapon.status_effects, false, combat_stat_context)
	get_tree().current_scene.add_child(p)

	if shot_sound != null:
		shot_sound.pitch_scale = randf_range(0.90, 1.10)
		shot_sound.play()

func _resolve_owner_enemy() -> Enemy:
	var node: Node = self
	while node != null:
		if node is Enemy:
			return node as Enemy
		node = node.get_parent()
	return null
