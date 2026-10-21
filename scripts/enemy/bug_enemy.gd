extends Enemy
class_name BugEnemy

const ATTACK_COLOR: Color = Color(0.75, 0.95, 0.20, 0.9)
const BROOD_COLOR: Color = Color(0.45, 1.0, 0.35)

var _behavior: BugBehaviorDef = BugBehaviorDef.new()
var _controlled_turrets: Array[EnemyTurret] = []
var _active_attack: EnemyAttackTelegraph = null
var _attack_cooldown_left: float = 1.0
var _recovery_left: float = 0.0
var _brood: BugBroodSpawner = null
var _brood_interval_left: float = 8.0
var _brood_windup_left: float = 0.0
var _brood_label: Label3D = null
var _animated_model: Node3D = null
var _rest_model_scale: Vector3 = Vector3.ONE
var _orbit_direction: float = 1.0
var _active_zone: BugSporeZone = null
var _zones_created: int = 0
var _zone_interval_left: float = 0.0
var _hive_next_is_zone: bool = false
var _charge_direction: Vector3 = Vector3.FORWARD
var _charge_origin: Vector3 = Vector3.ZERO
var _charge_endpoint: Vector3 = Vector3.ZERO
var _charge_time_left: float = 0.0

func configure_enemy(d: EnemyDef, spawn_context: EnemySpawnContext = null) -> void:
	_cancel_attack()
	_cancel_zone()
	_clear_brood()
	super.configure_enemy(d, spawn_context)
	var bug_def: BugEnemyDef = d as BugEnemyDef
	_behavior = bug_def.behavior if bug_def != null and bug_def.behavior != null else BugBehaviorDef.new()
	set_meta(&"bug_mode", _behavior.mode)
	_collect_controlled_turrets()
	_animated_model = get_visual_model_root(false)
	if _animated_model != null:
		_rest_model_scale = _animated_model.scale
	_attack_cooldown_left = 1.0
	_recovery_left = 0.0
	_brood_interval_left = maxf(_behavior.brood_interval_sec, 1.0)
	_brood_windup_left = 0.0
	_charge_time_left = 0.0
	_zones_created = 0
	_zone_interval_left = 1.0
	_hive_next_is_zone = false
	if bug_def != null and bug_def.brood_child_def != null and _behavior.mode in [BugBehaviorDef.Mode.BROODMOTHER, BugBehaviorDef.Mode.HIVE_QUEEN] and not _spawn_context.is_summoned:
		_brood = BugBroodSpawner.new()
		_brood.name = "BroodSpawner"
		add_child(_brood)
		_brood.setup(self, bug_def.brood_child_def, _behavior.brood_alive_cap, _behavior.brood_total_cap, _behavior.brood_global_cap, _behavior.brood_enemy_cap, _behavior.brood_release_radius)
	if is_instance_valid(_brood_label):
		_brood_label.visible = false

func _ready() -> void:
	super._ready()
	_collect_controlled_turrets()
	_attack_cooldown_left = randf_range(0.7, 1.4)
	_orbit_direction = -1.0 if get_instance_id() % 2 == 0 else 1.0
	if _animated_model == null:
		_animated_model = get_visual_model_root(false)
		if _animated_model != null:
			_rest_model_scale = _animated_model.scale
	_brood_label = Label3D.new()
	_brood_label.name = "BroodCountdown"
	_brood_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_brood_label.no_depth_test = true
	_brood_label.font_size = 28
	_brood_label.outline_size = 6
	_brood_label.pixel_size = 0.3
	_brood_label.position = Vector3.UP * (label_height + 22.0)
	_brood_label.modulate = BROOD_COLOR
	_brood_label.visible = false
	add_child(_brood_label)
	about_to_die.connect(_on_bug_about_to_die)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(player_ship) or not player_ship.visible or not player_ship.is_alive():
		_cancel_attack()
		_cancel_zone()
		_charge_time_left = 0.0
		linear_velocity = Vector3.ZERO
		_brood_windup_left = 0.0
		if is_instance_valid(_brood_label):
			_brood_label.visible = false
		_animate_contraction(0.0)
		return
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_recovery_left = maxf(_recovery_left - delta, 0.0)
	_brood_interval_left = maxf(_brood_interval_left - delta, 0.0)
	_zone_interval_left = maxf(_zone_interval_left - delta, 0.0)
	var to_player: Vector3 = player_ship.global_position - global_position
	var committed_charge: bool = _behavior.mode == BugBehaviorDef.Mode.DEVOURER and (_charge_time_left > 0.0 or is_instance_valid(_active_attack))
	if to_player.length_squared() > 0.0001 and not committed_charge:
		_face_target(player_ship.global_position)
	match _behavior.mode:
		BugBehaviorDef.Mode.SPORELING:
			_tick_sporeling()
		BugBehaviorDef.Mode.CARAPACE:
			_tick_carapace()
		BugBehaviorDef.Mode.BROODMOTHER:
			_tick_broodmother(delta)
		BugBehaviorDef.Mode.DEVOURER:
			_tick_devourer(delta)
		BugBehaviorDef.Mode.HIVE_QUEEN:
			_tick_hive_queen(delta)

func get_tactical_state() -> String:
	if _charge_time_left > 0.0:
		return "Committed charge — move aside"
	if is_instance_valid(_active_zone):
		return "Fixed spore zone — move clear"
	if _brood_windup_left > 0.0:
		return "Brood release %.1f" % _brood_windup_left
	if is_instance_valid(_active_attack):
		match _behavior.mode:
			BugBehaviorDef.Mode.CARAPACE:
				return "Carapace ram winding up"
			BugBehaviorDef.Mode.BROODMOTHER:
				return "Spore volley winding up"
			BugBehaviorDef.Mode.DEVOURER:
				return "Devourer charge winding up"
			_:
				return "Spore strike winding up"
	if _recovery_left > 0.0:
		return "Exposed recovery"
	match _behavior.mode:
		BugBehaviorDef.Mode.CARAPACE:
			return "Closing with armored carapace"
		BugBehaviorDef.Mode.BROODMOTHER:
			if _brood != null and _brood.get_total_spawned() >= _behavior.brood_total_cap:
				return "Brood exhausted"
			return "Keeping distance"
		BugBehaviorDef.Mode.DEVOURER:
			return "Stalking a charge line"
		BugBehaviorDef.Mode.HIVE_QUEEN:
			if not _can_release_brood() and _zones_created >= maxi(_behavior.zone_total_cap, 1):
				return "Hive reserves exhausted"
			return "Hive command organism"
		_:
			return "Swarm pursuit"

func _tick_sporeling() -> void:
	if _tick_committed_attack():
		return
	_steer_in_band(player_ship.global_position, _behavior.approach_range * 0.45, _behavior.approach_range * 0.8)
	if _attack_cooldown_left <= 0.0 and _is_player_in_attack_range():
		_start_attack(false, "SPORE STRIKE")

func _tick_carapace() -> void:
	if _tick_committed_attack():
		return
	_steer_in_band(player_ship.global_position, _behavior.approach_range * 0.45, _behavior.approach_range * 0.85)
	if _attack_cooldown_left <= 0.0 and _is_player_in_attack_range():
		_start_attack(true, "CARAPACE RAM")

func _tick_broodmother(delta: float) -> void:
	if _brood_windup_left > 0.0:
		_steer_to_velocity(Vector3.ZERO)
		_brood_windup_left = maxf(_brood_windup_left - delta, 0.0)
		var progress: float = 1.0 - _brood_windup_left / maxf(_behavior.brood_windup_sec, 0.3)
		_animate_contraction(progress)
		_brood_label.text = "BROOD RELEASE  %.1f" % _brood_windup_left
		if _brood_windup_left <= 0.0:
			_release_brood()
		return
	if _tick_committed_attack():
		return
	_steer_in_band(player_ship.global_position, _behavior.approach_range, _behavior.retreat_range)
	if _brood_interval_left <= 0.0 and _can_release_brood():
		_brood_windup_left = maxf(_behavior.brood_windup_sec, 0.3)
		_brood_label.text = "BROOD RELEASE  %.1f" % _brood_windup_left
		_brood_label.visible = true
		return
	if _attack_cooldown_left <= 0.0 and _has_target_in_weapon_range():
		_start_attack(false, "SPORE VOLLEY")

func _tick_committed_attack() -> bool:
	if is_instance_valid(_active_attack):
		_steer_to_velocity(Vector3.ZERO)
		var progress: float = 1.0 - _active_attack.get_time_remaining() / maxf(_behavior.attack_windup_sec, 0.2)
		_animate_contraction(progress)
		return true
	_animate_contraction(0.0)
	if _recovery_left > 0.0:
		_steer_to_velocity(Vector3.ZERO)
		return true
	return false

func _tick_devourer(delta: float) -> void:
	if _charge_time_left > 0.0:
		_animate_contraction(0.0)
		# Only the warning resolves damage. This visible travel never tests bodies.
		var along_path: float = (global_position - _charge_origin).dot(_charge_direction)
		var path_length: float = (_charge_endpoint - _charge_origin).length()
		var distance_left: float = maxf(path_length - along_path, 0.0)
		_charge_time_left = maxf(_charge_time_left - delta, 0.0)
		if _charge_time_left <= 0.0 or distance_left <= 0.1:
			_finish_devourer_charge()
			return
		linear_velocity = _charge_direction * minf(maxf(_behavior.charge_speed, 1.0), distance_left / maxf(delta, 0.001))
		_face_target(global_position + _charge_direction * 100.0)
		return
	if is_instance_valid(_active_attack):
		# Hold the launch point so physical travel follows the marked corridor.
		linear_velocity = Vector3.ZERO
		_animate_contraction(1.0 - _active_attack.get_time_remaining() / maxf(_behavior.attack_windup_sec, 0.2))
		return
	if _tick_committed_attack():
		return
	_steer_in_band(player_ship.global_position, _behavior.approach_range * 0.55, _behavior.approach_range * 0.85)
	if _attack_cooldown_left <= 0.0 and _is_player_in_attack_range():
		_start_devourer_charge()

func _start_devourer_charge() -> void:
	if _dead or is_instance_valid(_active_attack) or _charge_time_left > 0.0 or not _has_target_in_weapon_range():
		return
	var turret: EnemyTurret = _first_valid_turret()
	var encounter_root: Node = get_tree().current_scene
	if turret == null or encounter_root == null:
		return
	_charge_origin = global_position
	var to_target: Vector3 = player_ship.global_position - _charge_origin
	_charge_direction = to_target.normalized() if to_target.length_squared() > 0.001 else -global_basis.z.normalized()
	var travel_distance: float = minf(to_target.length() + maxf(_behavior.charge_overshoot_distance, 0.0), maxf(_behavior.charge_speed, 1.0) * maxf(_behavior.charge_travel_sec, 0.3))
	_charge_endpoint = _charge_origin + _charge_direction * travel_distance
	linear_velocity = Vector3.ZERO
	_active_attack = EnemyAttackTelegraph.new()
	_active_attack.set_warning_style("DEVOURER CHARGE", ATTACK_COLOR)
	encounter_root.add_child(_active_attack)
	_active_attack.resolved.connect(_on_devourer_charge_resolved)
	_active_attack.start_attack(self, player_ship, turret, maxf(_behavior.attack_windup_sec, 0.2), maxf(_behavior.attack_radius, 1.0), true, _charge_endpoint)

func _on_devourer_charge_resolved(_hit: bool) -> void:
	_active_attack = null
	_charge_time_left = maxf(_behavior.charge_travel_sec, 0.3)
	linear_velocity = _charge_direction * maxf(_behavior.charge_speed, 1.0)
	_animate_contraction(0.0)

func _finish_devourer_charge() -> void:
	_charge_time_left = 0.0
	linear_velocity = Vector3.ZERO
	_attack_cooldown_left = maxf(_behavior.attack_cooldown_sec, 0.1)
	_recovery_left = maxf(_behavior.attack_recovery_sec, 0.1)

func _tick_hive_queen(delta: float) -> void:
	if _brood_windup_left > 0.0:
		_tick_broodmother(delta)
		if _brood_windup_left <= 0.0:
			_hive_next_is_zone = true
		return
	if is_instance_valid(_active_zone):
		_steer_to_velocity(Vector3.ZERO)
		_animate_contraction(1.0 - _active_zone.get_time_remaining() / maxf(_behavior.zone_windup_sec, 0.5))
		return
	if _tick_committed_attack():
		return
	_steer_in_band(player_ship.global_position, _behavior.approach_range, _behavior.retreat_range)
	var brood_available: bool = _can_release_brood()
	var zone_available: bool = _zones_created < maxi(_behavior.zone_total_cap, 1)
	if (_hive_next_is_zone or not brood_available) and zone_available:
		if _zone_interval_left <= 0.0 and _has_target_in_weapon_range():
			_start_spore_zone()
		return
	if brood_available and _brood_interval_left <= 0.0:
		_brood_windup_left = maxf(_behavior.brood_windup_sec, 0.3)
		if is_instance_valid(_brood_label):
			_brood_label.text = "HIVE BROOD  %.1f" % _brood_windup_left
			_brood_label.visible = true

func _start_spore_zone() -> void:
	if is_instance_valid(_active_zone) or _dead or _zones_created >= maxi(_behavior.zone_total_cap, 1) or not _has_target_in_weapon_range():
		return
	if not BugSporeZone.can_spawn(self, _behavior.zone_global_cap):
		return
	var turret: EnemyTurret = _first_valid_turret()
	var encounter_root: Node = get_tree().current_scene
	if turret == null or encounter_root == null:
		return
	var zone: BugSporeZone = BugSporeZone.new()
	encounter_root.add_child(zone)
	if not zone.start_zone(self, player_ship, turret, _behavior.zone_windup_sec, _behavior.zone_radius, _behavior.zone_pulse_count, "HIVE SPORE ZONE", _behavior.zone_global_cap):
		return
	_active_zone = zone
	_zones_created += 1
	zone.finished.connect(_on_spore_zone_finished, CONNECT_ONE_SHOT)

func _on_spore_zone_finished() -> void:
	_active_zone = null
	_zone_interval_left = maxf(_behavior.zone_interval_sec, 1.0)
	_recovery_left = maxf(_behavior.attack_recovery_sec, 0.1)
	_hive_next_is_zone = false
	_animate_contraction(0.0)

func _start_attack(corridor: bool, attack_name: String) -> void:
	if _dead or is_instance_valid(_active_attack) or not _has_target_in_weapon_range():
		return
	var turret: EnemyTurret = _first_valid_turret()
	var encounter_root: Node = get_tree().current_scene
	if turret == null or encounter_root == null:
		return
	_active_attack = EnemyAttackTelegraph.new()
	_active_attack.set_warning_style(attack_name, ATTACK_COLOR)
	encounter_root.add_child(_active_attack)
	_active_attack.resolved.connect(_on_attack_resolved)
	_active_attack.start_attack(self, player_ship, turret, maxf(_behavior.attack_windup_sec, 0.2), maxf(_behavior.attack_radius, 1.0), corridor)

func _on_attack_resolved(_hit: bool) -> void:
	_active_attack = null
	_attack_cooldown_left = maxf(_behavior.attack_cooldown_sec, 0.1)
	_recovery_left = maxf(_behavior.attack_recovery_sec, 0.1)
	_animate_contraction(0.0)

func _can_release_brood() -> bool:
	return is_instance_valid(_brood) and _brood.get_living_count() < _behavior.brood_alive_cap and _brood.get_total_spawned() < _behavior.brood_total_cap

func _release_brood() -> void:
	if is_instance_valid(_brood):
		var released: int = _brood.spawn_brood(maxi(_behavior.brood_burst_count, 1))
		if released > 0:
			EffectsBus.show_float(global_position, "BROOD +%d" % released, BROOD_COLOR)
	_brood_interval_left = maxf(_behavior.brood_interval_sec, 1.0)
	_brood_windup_left = 0.0
	_recovery_left = maxf(_behavior.attack_recovery_sec, 0.1)
	if is_instance_valid(_brood_label):
		_brood_label.visible = false
	_animate_contraction(0.0)

func _animate_contraction(progress: float) -> void:
	if not is_instance_valid(_animated_model):
		return
	if is_instance_valid(_warp_tween) and _warp_tween.is_running():
		return
	# The full silhouette compresses before release, making the body itself a tell.
	var amount: float = clampf(progress, 0.0, 1.0)
	_animated_model.scale = _rest_model_scale * Vector3(1.0 + amount * 0.13, 1.0 - amount * 0.18, 1.0 - amount * 0.22)

func _steer_in_band(target_position: Vector3, inner_range: float, outer_range: float) -> void:
	var to_target: Vector3 = target_position - global_position
	var distance_squared: float = to_target.length_squared()
	var radial: Vector3 = to_target.normalized()
	var tangent: Vector3 = radial.cross(Vector3.UP).normalized() * _orbit_direction
	var desired_velocity: Vector3 = tangent * _behavior.max_speed * _behavior.orbit_strength
	var inner: float = maxf(inner_range, 1.0)
	var outer: float = maxf(outer_range, inner)
	if distance_squared > outer * outer:
		desired_velocity += radial * _behavior.max_speed
	elif distance_squared < inner * inner:
		desired_velocity -= radial * _behavior.max_speed
	_steer_to_velocity(desired_velocity.limit_length(maxf(_behavior.max_speed, 1.0)))

func _steer_to_velocity(desired_velocity: Vector3) -> void:
	var correction: Vector3 = (desired_velocity - linear_velocity) * maxf(_behavior.steering_response, 0.1)
	apply_central_force(correction.limit_length(maxf(eff_thrust, 0.0)))

func _collect_controlled_turrets() -> void:
	_controlled_turrets.clear()
	for path: NodePath in turret_paths:
		var turret: EnemyTurret = get_node_or_null(path) as EnemyTurret
		if turret != null and not _controlled_turrets.has(turret):
			_controlled_turrets.append(turret)
	if _controlled_turrets.is_empty():
		for child: Node in get_children():
			if child is EnemyTurret:
				_controlled_turrets.append(child as EnemyTurret)
	# Every Bug shot is committed through a visible warning; no hidden firing.
	for turret: EnemyTurret in _controlled_turrets:
		turret.set_physics_process(false)

func _first_valid_turret() -> EnemyTurret:
	for turret: EnemyTurret in _controlled_turrets:
		if is_instance_valid(turret):
			return turret
	return null

func _has_target_in_weapon_range() -> bool:
	if not is_instance_valid(player_ship):
		return false
	for turret: EnemyTurret in _controlled_turrets:
		if not is_instance_valid(turret):
			continue
		var weapon_range: float = maxf(turret.eff_base_range + turret.eff_range_bonus_add, 0.0)
		if turret.get_shot_origin().distance_squared_to(player_ship.global_position) <= weapon_range * weapon_range:
			return true
	return false

func _is_player_in_attack_range() -> bool:
	var attack_range: float = maxf(_behavior.approach_range, 1.0)
	return global_position.distance_squared_to(player_ship.global_position) <= attack_range * attack_range and _has_target_in_weapon_range()

func _cancel_attack() -> void:
	if is_instance_valid(_active_attack):
		_active_attack.cancel()
	_active_attack = null
	_charge_time_left = 0.0

func _cancel_zone() -> void:
	if is_instance_valid(_active_zone):
		_active_zone.cancel()
	_active_zone = null

func _clear_brood() -> void:
	if is_instance_valid(_brood):
		_brood.clear_brood()
		_brood.queue_free()
	_brood = null

func _on_bug_about_to_die(_enemy: Enemy) -> void:
	_cancel_attack()
	_cancel_zone()
	_clear_brood()
	_brood_windup_left = 0.0
	if is_instance_valid(_brood_label):
		_brood_label.visible = false

func _exit_tree() -> void:
	_cancel_attack()
	_cancel_zone()
	_clear_brood()
