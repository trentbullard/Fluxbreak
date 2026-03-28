extends Enemy
class_name EnemyBoss

signal weapon_socket_fired(socket: BossWeaponSocket, weapon: WeaponDef)

var _boss_def: EnemyBossDef = null
var _movement_def: BossMovementDef = null
var _locomotion_profile: BossLocomotionProfile = null
var _tracking_profile: BossTargetTrackingProfile = null
var _weapon_sockets: Array[BossWeaponSocket] = []
var _strafe_sign: float = 1.0
var _vertical_sign: float = 1.0
var _strafe_timer_sec: float = 0.0
var _vertical_timer_sec: float = 0.0

func configure_enemy(d: EnemyDef, spawn_context: EnemySpawnContext = null) -> void:
	super.configure_enemy(d, spawn_context)
	_boss_def = d as EnemyBossDef
	_movement_def = _boss_def.movement_def if _boss_def != null else null
	_locomotion_profile = _resolve_locomotion_profile()
	_tracking_profile = _resolve_tracking_profile()
	set_meta("kind", "boss")
	if not is_in_group("bosses"):
		add_to_group("bosses")
	_configure_weapon_sockets()
	_reset_movement_variation()

func get_boss_def() -> EnemyBossDef:
	return _boss_def

func is_boss_enemy() -> bool:
	return true

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if player_ship == null or not is_instance_valid(player_ship):
		return

	var target_position: Vector3 = player_ship.global_position
	target_position.y += _tracking_profile.aim_vertical_offset
	_update_tracking(target_position, delta)
	_update_movement(target_position, delta)
	_update_weapons(player_ship, delta)

func _exit_tree() -> void:
	for socket in _weapon_sockets:
		if socket == null:
			continue
		socket.clear_runtime_state()

func _configure_weapon_sockets() -> void:
	for socket in _weapon_sockets:
		if socket == null:
			continue
		socket.clear_runtime_state()
	_weapon_sockets.clear()

	var model_root: Node3D = get_visual_model_root()
	if model_root == null:
		return

	var found_nodes: Array[Node] = model_root.find_children("*", "BossWeaponSocket", true, false)
	for found_node in found_nodes:
		var socket: BossWeaponSocket = found_node as BossWeaponSocket
		if socket == null or socket.weapon == null:
			continue
		socket.configure_socket(self)
		_weapon_sockets.append(socket)

func _reset_movement_variation() -> void:
	_strafe_sign = -1.0 if randf() < 0.5 else 1.0
	_vertical_sign = -1.0 if randf() < 0.5 else 1.0
	_strafe_timer_sec = max(_locomotion_profile.strafe_retarget_sec, 0.1)
	_vertical_timer_sec = max(_locomotion_profile.vertical_retarget_sec, 0.1)

func _update_tracking(target_position: Vector3, delta: float) -> void:
	var to_target: Vector3 = target_position - global_position
	if to_target.length_squared() <= 0.0001:
		return
	var desired_transform: Transform3D = global_transform.looking_at(target_position, Vector3.UP)
	var weight: float = clampf(_tracking_profile.turn_lerp_rate * delta, 0.0, 1.0)
	var blended_basis: Basis = global_transform.basis.slerp(desired_transform.basis, weight)
	global_transform = Transform3D(blended_basis.orthonormalized(), global_position)

func _update_movement(target_position: Vector3, delta: float) -> void:
	var to_target: Vector3 = target_position - global_position
	if to_target.length_squared() <= 0.0001:
		return

	_strafe_timer_sec -= delta
	if _strafe_timer_sec <= 0.0:
		_strafe_sign = -1.0 if randf() < 0.5 else 1.0
		_strafe_timer_sec = max(_locomotion_profile.strafe_retarget_sec, 0.1)

	_vertical_timer_sec -= delta
	if _vertical_timer_sec <= 0.0:
		_vertical_sign = -1.0 if randf() < 0.5 else 1.0
		_vertical_timer_sec = max(_locomotion_profile.vertical_retarget_sec, 0.1)

	var preferred_distance: float = max(_locomotion_profile.preferred_distance, 0.0)
	var tolerance: float = max(_locomotion_profile.distance_tolerance, 0.0)
	var min_distance: float = max(preferred_distance - tolerance, 0.0)
	var max_distance: float = preferred_distance + tolerance
	var distance_sq: float = global_position.distance_squared_to(target_position)
	var radial_direction: Vector3 = to_target.normalized()
	var radial_force: float = eff_thrust * max(_locomotion_profile.radial_force_scale, 0.0)

	if distance_sq > max_distance * max_distance:
		apply_central_force(radial_direction * radial_force)
	elif distance_sq < min_distance * min_distance:
		apply_central_force(-radial_direction * radial_force)

	var right: Vector3 = global_transform.basis.x.normalized()
	var up: Vector3 = global_transform.basis.y.normalized()
	var strafe_force: float = eff_thrust * max(_locomotion_profile.strafe_force_scale, 0.0)
	var vertical_force: float = eff_thrust * max(_locomotion_profile.vertical_force_scale, 0.0)
	apply_central_force(right * strafe_force * _strafe_sign)
	apply_central_force(up * vertical_force * _vertical_sign)

func _update_weapons(target: Node3D, delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.visible:
		return

	for socket in _weapon_sockets:
		if socket == null or socket.weapon == null:
			continue
		socket.cooldown_remaining = max(socket.cooldown_remaining - delta, 0.0)
		if socket.cooldown_remaining > 0.0:
			continue
		if not _is_target_in_range(socket, target):
			continue
		_fire_socket_at_target(socket, target)

func _is_target_in_range(socket: BossWeaponSocket, target: Node3D) -> bool:
	var max_range: float = max(socket.eff_base_range + socket.eff_range_bonus_add, 0.0)
	if max_range <= 0.0:
		return true
	return socket.global_position.distance_squared_to(target.global_position) <= max_range * max_range

func _fire_socket_at_target(socket: BossWeaponSocket, target: Node3D) -> void:
	var weapon: WeaponDef = socket.weapon
	if weapon == null:
		return

	var hit_chance: float = WeaponCombatResolver.compute_effective_accuracy_vs_target(socket, target)
	var outcome: int = WeaponCombatResolver.resolve_shot_for_turret(socket, hit_chance)
	var damage_min: float = minf(socket.eff_damage_min, socket.eff_damage_max)
	var damage_max: float = maxf(socket.eff_damage_min, socket.eff_damage_max)
	var rolled_damage: float = randf_range(damage_min, damage_max)
	var combat_stat_context: CombatStatContext = socket.build_combat_stat_context(target)

	if weapon.projectile_scene != null:
		var projectile: Projectile = weapon.projectile_scene.instantiate() as Projectile
		if projectile != null:
			var direction: Vector3 = (target.global_position - socket.global_position).normalized()
			var aim_basis: Basis = Basis.looking_at(direction, Vector3.UP)
			projectile.global_transform = Transform3D(aim_basis, socket.global_position)
			if socket.eff_projectile_speed > 0.0:
				projectile.speed = socket.eff_projectile_speed
			if socket.eff_projectile_life > 0.0:
				projectile.max_lifetime = socket.eff_projectile_life
			projectile.configure_shot(
				socket,
				target,
				outcome,
				rolled_damage,
				socket.eff_graze_mult,
				socket.eff_crit_mult,
				weapon.status_effects,
				false,
				combat_stat_context
			)
			get_tree().current_scene.add_child(projectile)
	else:
		WeaponCombatResolver.apply_shot_to_target(
			socket,
			target,
			outcome,
			rolled_damage,
			socket.eff_graze_mult,
			socket.eff_crit_mult,
			weapon.status_effects,
			false,
			combat_stat_context
		)

	socket.play_shot_sound()
	socket.cooldown_remaining = max(0.01, socket.eff_fire_rate)
	weapon_socket_fired.emit(socket, weapon)

func _resolve_locomotion_profile() -> BossLocomotionProfile:
	if _movement_def != null and _movement_def.locomotion_profile != null:
		return _movement_def.locomotion_profile
	return BossLocomotionProfile.new()

func _resolve_tracking_profile() -> BossTargetTrackingProfile:
	if _movement_def != null and _movement_def.target_tracking_profile != null:
		return _movement_def.target_tracking_profile
	return BossTargetTrackingProfile.new()
