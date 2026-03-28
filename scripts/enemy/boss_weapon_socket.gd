extends Marker3D
class_name BossWeaponSocket

@export var weapon: WeaponDef

var systems_bonus: float = 0.0
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
var cooldown_remaining: float = 0.0

var _owner_enemy: EnemyBoss = null
var _visual_instance: Node3D = null
var _shot_sound: AudioStreamPlayer3D = null
var _weapon_stats: WeaponStatSnapshot = null

func configure_socket(owner_enemy: EnemyBoss) -> void:
	_owner_enemy = owner_enemy
	_weapon_stats = WeaponStatResolver.resolve_snapshot(weapon)
	WeaponStatResolver.apply_snapshot_to_turret(self, _weapon_stats)
	cooldown_remaining = 0.0
	_rebuild_visual()

func clear_runtime_state() -> void:
	_owner_enemy = null
	_weapon_stats = null
	cooldown_remaining = 0.0
	if _visual_instance != null and is_instance_valid(_visual_instance):
		_visual_instance.queue_free()
	_visual_instance = null
	if _shot_sound != null and is_instance_valid(_shot_sound):
		_shot_sound.queue_free()
	_shot_sound = null

func has_runtime_weapon() -> bool:
	return weapon != null

func get_weapon() -> WeaponDef:
	return weapon

func get_weapon_stats() -> WeaponStatSnapshot:
	return _weapon_stats

func get_shot_origin() -> Vector3:
	return global_position

func build_combat_stat_context(_target: Object = null) -> CombatStatContext:
	if _owner_enemy == null:
		return null
	return _owner_enemy.build_combat_stat_context()

func play_shot_sound() -> void:
	if _shot_sound == null:
		return
	_shot_sound.pitch_scale = randf_range(0.92, 1.08)
	_shot_sound.play()

func _rebuild_visual() -> void:
	if _visual_instance != null and is_instance_valid(_visual_instance):
		_visual_instance.queue_free()
	_visual_instance = null
	if _shot_sound != null and is_instance_valid(_shot_sound):
		_shot_sound.queue_free()
	_shot_sound = null

	if weapon != null and weapon.visual_scene != null:
		var visual_node: Node3D = weapon.visual_scene.instantiate() as Node3D
		if visual_node != null:
			add_child(visual_node)
			visual_node.transform = Transform3D.IDENTITY
			_visual_instance = visual_node

	if weapon != null and weapon.shot_sound != null:
		var shot_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		shot_player.stream = weapon.shot_sound
		shot_player.volume_db = -5.0
		add_child(shot_player)
		_shot_sound = shot_player
