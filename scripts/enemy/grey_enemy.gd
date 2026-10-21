extends Enemy
class_name GreyEnemy

const PULSE_COLOR: Color = Color(0.66, 0.5, 1.0, 0.9)
const THREAT_RETRY_SEC: float = 0.25

var _behavior: GreyBehaviorDef = GreyBehaviorDef.new()
var _controlled_turrets: Array[EnemyTurret] = []
var _active_attack: EnemyAttackTelegraph = null
var _displacement: GreyDisplacement = null
var _tether: GreyTether = null
var _attack_cooldown_left: float = 1.0
var _displacement_cooldown_left: float = 1.5
var _recovery_left: float = 0.0
var _post_displacement_pulse: bool = false
var _vessel_next_pulse: bool = false
var _orbit_direction: float = 1.0
var _target_scan_left: float = 0.0
var _rupture_pulses_remaining: int = 0
var _rupture_gap_left: float = 0.0
var _mothership_next_action: int = 0
var _cancelling_specials: bool = false

func configure_enemy(d: EnemyDef, spawn_context: EnemySpawnContext = null) -> void:
	_cancel_specials()
	super.configure_enemy(d, spawn_context)
	var grey_def: GreyEnemyDef = d as GreyEnemyDef
	_behavior = grey_def.behavior if grey_def != null and grey_def.behavior != null else GreyBehaviorDef.new()
	set_meta(&"grey_mode", _behavior.mode)
	_collect_controlled_turrets()
	_attack_cooldown_left = 1.0
	_displacement_cooldown_left = 1.5
	_recovery_left = 0.0
	_post_displacement_pulse = false
	_vessel_next_pulse = false
	_target_scan_left = 0.0
	_mothership_next_action = 0

func _ready() -> void:
	super._ready()
	_collect_controlled_turrets()
	_attack_cooldown_left = randf_range(0.9, 1.5)
	_orbit_direction = -1.0 if get_instance_id() % 2 == 0 else 1.0
	about_to_die.connect(_on_grey_about_to_die)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not _has_living_target():
		_cancel_specials()
		_post_displacement_pulse = false
		_target_scan_left = maxf(_target_scan_left - delta, 0.0)
		if _target_scan_left <= 0.0:
			_target_scan_left = 0.5
			_reacquire_target()
		return
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_displacement_cooldown_left = maxf(_displacement_cooldown_left - delta, 0.0)
	_recovery_left = maxf(_recovery_left - delta, 0.0)
	_rupture_gap_left = maxf(_rupture_gap_left - delta, 0.0)
	if global_position.distance_squared_to(player_ship.global_position) > 0.0001:
		_face_target(player_ship.global_position)
	match _behavior.mode:
		GreyBehaviorDef.Mode.PROBE:
			_tick_probe()
		GreyBehaviorDef.Mode.SEEKER:
			_tick_seeker()
		GreyBehaviorDef.Mode.VESSEL:
			_tick_vessel()
		GreyBehaviorDef.Mode.HARBINGER:
			_tick_harbinger()
		GreyBehaviorDef.Mode.MOTHERSHIP:
			_tick_mothership()

func get_tactical_state() -> String:
	if is_instance_valid(_displacement):
		return "Displacement endpoints locked"
	if is_instance_valid(_tether):
		return "Psionic tether"
	if is_instance_valid(_active_attack):
		return "Psionic pulse winding up"
	if _recovery_left > 0.0:
		return "Exposed recovery"
	if _rupture_pulses_remaining > 0:
		return "Second rupture preparing"
	match _behavior.mode:
		GreyBehaviorDef.Mode.SEEKER:
			return "Seeking displacement"
		GreyBehaviorDef.Mode.VESSEL:
			return "Keeping tether distance"
		GreyBehaviorDef.Mode.HARBINGER:
			return "Preparing sequential ruptures"
		GreyBehaviorDef.Mode.MOTHERSHIP:
			return "Coordinating psionic actions"
		_:
			return "Psionic drift"

func _tick_probe() -> void:
	if _tick_committed_action():
		return
	_steer_in_band(player_ship.global_position)
	if _attack_cooldown_left <= 0.0:
		_start_pulse("PSIONIC PULSE")

func _tick_seeker() -> void:
	if _tick_committed_action():
		return
	if _post_displacement_pulse:
		# Relocation itself is harmless. This is a new, separately dodgeable tell.
		if _attack_cooldown_left <= 0.0 and _start_pulse("SEEKER PULSE"):
			_post_displacement_pulse = false
		return
	_steer_in_band(player_ship.global_position)
	if _displacement_cooldown_left <= 0.0 and _has_target_in_weapon_range():
		_start_displacement()
	elif _attack_cooldown_left <= 0.0:
		_start_pulse("SEEKER PULSE")

func _tick_vessel() -> void:
	if _tick_committed_action():
		return
	_steer_in_band(player_ship.global_position)
	if _attack_cooldown_left <= 0.0 and _has_target_in_weapon_range():
		if _vessel_next_pulse:
			if _start_pulse("VESSEL PULSE"):
				_vessel_next_pulse = false
		else:
			_start_tether()

func _tick_harbinger() -> void:
	if _tick_committed_action():
		return
	if _rupture_pulses_remaining == 1:
		_steer_to_velocity(Vector3.ZERO)
		if not _has_target_in_weapon_range():
			_rupture_pulses_remaining = 0
			_begin_recovery()
		elif _rupture_gap_left <= 0.0 and _attack_cooldown_left <= 0.0:
			_start_pulse("RUPTURE II")
		return
	_steer_in_band(player_ship.global_position)
	if _attack_cooldown_left <= 0.0 and _has_target_in_weapon_range():
		_rupture_pulses_remaining = 2
		if not _start_pulse("RUPTURE I"):
			_rupture_pulses_remaining = 0

func _tick_mothership() -> void:
	if _tick_committed_action():
		return
	_steer_in_band(player_ship.global_position)
	if _attack_cooldown_left > 0.0 or not _has_target_in_weapon_range():
		return
	match _mothership_next_action:
		0:
			_start_pulse("MOTHERSHIP RUPTURE")
		1:
			if not _start_displacement():
				# A cramped destination skips only the harmless move, never its recovery.
				_mothership_next_action = 2
				_begin_recovery()
		_:
			_start_tether()

func _tick_committed_action() -> bool:
	if is_instance_valid(_active_attack) or is_instance_valid(_displacement) or is_instance_valid(_tether) or _recovery_left > 0.0:
		_steer_to_velocity(Vector3.ZERO)
		return true
	return false

func _start_pulse(attack_name: String) -> bool:
	if _cancelling_specials or _dead or not _has_living_target() or is_instance_valid(_active_attack) or is_instance_valid(_displacement) or is_instance_valid(_tether) or not _has_target_in_weapon_range():
		return false
	if not GreyThreatLimiter.can_start_pulse(self):
		_attack_cooldown_left = THREAT_RETRY_SEC
		return false
	var turret: EnemyTurret = _first_valid_turret()
	var encounter_root: Node = get_tree().current_scene
	if turret == null or encounter_root == null:
		return false
	_active_attack = EnemyAttackTelegraph.new()
	_active_attack.set_warning_style(attack_name, PULSE_COLOR)
	encounter_root.add_child(_active_attack)
	_active_attack.resolved.connect(_on_pulse_resolved)
	_active_attack.start_attack(self, player_ship, turret, maxf(_behavior.attack_windup_sec, 0.3), maxf(_behavior.attack_radius, 1.0), false)
	return true

func _on_pulse_resolved(_hit: bool) -> void:
	_active_attack = null
	if _cancelling_specials or _dead or not _has_living_target():
		_rupture_pulses_remaining = 0
		return
	if _behavior.mode == GreyBehaviorDef.Mode.HARBINGER and _rupture_pulses_remaining > 1:
		_rupture_pulses_remaining = 1
		_rupture_gap_left = maxf(_behavior.rupture_second_gap_sec, 0.3)
		_attack_cooldown_left = 0.0
		return
	_rupture_pulses_remaining = 0
	if _behavior.mode == GreyBehaviorDef.Mode.MOTHERSHIP:
		_mothership_next_action = 1
	_begin_recovery()

func _start_displacement() -> bool:
	if _cancelling_specials or _dead or not _has_living_target() or is_instance_valid(_displacement) or is_instance_valid(_active_attack) or is_instance_valid(_tether):
		return false
	var encounter_root: Node = get_tree().current_scene
	if encounter_root == null:
		return false
	var destination: Vector3 = _pick_displacement_destination()
	if destination.distance_squared_to(global_position) <= 1.0:
		_displacement_cooldown_left = maxf(_behavior.displacement_interval_sec, 1.0)
		return false
	_displacement = GreyDisplacement.new()
	encounter_root.add_child(_displacement)
	_displacement.completed.connect(_on_displacement_completed)
	if not _displacement.start_displacement(self, destination, maxf(_behavior.displacement_windup_sec, 0.4)):
		var failed_displacement: GreyDisplacement = _displacement
		_displacement = null
		failed_displacement.completed.disconnect(_on_displacement_completed)
		failed_displacement.cancel()
		_displacement_cooldown_left = maxf(_behavior.displacement_interval_sec, 1.0)
		return false
	return true

func _pick_displacement_destination() -> Vector3:
	var away: Vector3 = global_position - player_ship.global_position
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3.BACK
	away = away.normalized()
	var radial: Vector3 = away.rotated(Vector3.UP, _orbit_direction * deg_to_rad(65.0))
	var clearance: float = maxf(_behavior.displacement_min_player_distance, 50.0)
	var band_distance: float = maxf((_behavior.approach_range + _behavior.retreat_range) * 0.5, clearance)
	var destination: Vector3 = player_ship.global_position + radial * band_distance
	var max_step: float = maxf(_behavior.displacement_distance, 30.0)
	destination = global_position + (destination - global_position).limit_length(max_step)
	if destination.distance_squared_to(player_ship.global_position) < clearance * clearance:
		destination = player_ship.global_position + away * clearance
		if destination.distance_squared_to(global_position) > max_step * max_step:
			return global_position
	return destination

func _on_displacement_completed(moved: bool) -> void:
	_displacement = null
	if _cancelling_specials or _dead or not _has_living_target():
		return
	_displacement_cooldown_left = maxf(_behavior.displacement_interval_sec, 1.0)
	if _behavior.mode == GreyBehaviorDef.Mode.MOTHERSHIP:
		if moved:
			_orbit_direction *= -1.0
		_mothership_next_action = 2
		_begin_recovery()
	elif moved:
		_orbit_direction *= -1.0
		_post_displacement_pulse = true
		_attack_cooldown_left = 0.0
	else:
		_begin_recovery()

func _start_tether() -> bool:
	if _cancelling_specials or _dead or not _has_living_target() or is_instance_valid(_tether) or is_instance_valid(_active_attack) or is_instance_valid(_displacement):
		return false
	if not GreyThreatLimiter.can_start_tether(self):
		_attack_cooldown_left = THREAT_RETRY_SEC
		return false
	var encounter_root: Node = get_tree().current_scene
	if encounter_root == null:
		return false
	_tether = GreyTether.new()
	encounter_root.add_child(_tether)
	_tether.completed.connect(_on_tether_completed)
	if not _tether.start_tether(self, player_ship, maxf(_behavior.tether_windup_sec, 0.4), _behavior.tether_duration_sec, _behavior.tether_slow_multiplier, _behavior.tether_break_distance, maxf(_behavior.tether_radius, 1.0)):
		var failed_tether: GreyTether = _tether
		_tether = null
		failed_tether.completed.disconnect(_on_tether_completed)
		failed_tether.cancel()
		_begin_recovery()
		return false
	return true

func _on_tether_completed(_attached: bool) -> void:
	_tether = null
	if _cancelling_specials or _dead or not _has_living_target():
		return
	if _behavior.mode == GreyBehaviorDef.Mode.MOTHERSHIP:
		_mothership_next_action = 0
	else:
		_vessel_next_pulse = true
	_begin_recovery()

func _begin_recovery() -> void:
	_attack_cooldown_left = maxf(_behavior.attack_cooldown_sec, 0.1)
	_recovery_left = maxf(_behavior.attack_recovery_sec, 0.1)
	if _behavior.mode == GreyBehaviorDef.Mode.MOTHERSHIP:
		_recovery_left = maxf(_recovery_left, _behavior.mothership_action_gap_sec)

func _steer_in_band(target_position: Vector3) -> void:
	var to_target: Vector3 = target_position - global_position
	var distance_squared: float = to_target.length_squared()
	var radial: Vector3 = to_target.normalized()
	var tangent: Vector3 = radial.cross(Vector3.UP).normalized() * _orbit_direction
	var desired_velocity: Vector3 = tangent * _behavior.max_speed * _behavior.orbit_strength
	var inner: float = maxf(_behavior.approach_range, 1.0)
	var outer: float = maxf(_behavior.retreat_range, inner)
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
	# Every Grey attack owns a visible commitment; autonomous fire stays disabled.
	for turret: EnemyTurret in _controlled_turrets:
		turret.set_physics_process(false)

func _first_valid_turret() -> EnemyTurret:
	for turret: EnemyTurret in _controlled_turrets:
		if is_instance_valid(turret):
			return turret
	return null

func _has_living_target() -> bool:
	return is_instance_valid(player_ship) and player_ship.visible and player_ship.is_alive()

func _has_target_in_weapon_range() -> bool:
	if not _has_living_target():
		return false
	for turret: EnemyTurret in _controlled_turrets:
		if not is_instance_valid(turret):
			continue
		var weapon_range: float = maxf(turret.eff_base_range + turret.eff_range_bonus_add, 0.0)
		if turret.get_shot_origin().distance_squared_to(player_ship.global_position) <= weapon_range * weapon_range:
			return true
	return false

func _reacquire_target() -> void:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var candidate: Ship = node as Ship
		if candidate != null and candidate.visible and candidate.is_alive():
			player_ship = candidate
			return

func _cancel_specials() -> void:
	_cancelling_specials = true
	_rupture_pulses_remaining = 0
	_rupture_gap_left = 0.0
	_mothership_next_action = 0
	_post_displacement_pulse = false
	var attack: EnemyAttackTelegraph = _active_attack
	_active_attack = null
	if is_instance_valid(attack):
		if attack.resolved.is_connected(_on_pulse_resolved):
			attack.resolved.disconnect(_on_pulse_resolved)
		attack.cancel()
	var displacement: GreyDisplacement = _displacement
	_displacement = null
	if is_instance_valid(displacement):
		if displacement.completed.is_connected(_on_displacement_completed):
			displacement.completed.disconnect(_on_displacement_completed)
		displacement.cancel()
	var tether: GreyTether = _tether
	_tether = null
	if is_instance_valid(tether):
		if tether.completed.is_connected(_on_tether_completed):
			tether.completed.disconnect(_on_tether_completed)
		tether.cancel()
	_cancelling_specials = false

func _on_grey_about_to_die(_enemy: Enemy) -> void:
	_cancel_specials()
	_post_displacement_pulse = false

func _exit_tree() -> void:
	_cancel_specials()
