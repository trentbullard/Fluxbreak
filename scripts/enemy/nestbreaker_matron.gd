extends EnemyBoss
class_name NestbreakerMatron

var _bug_def: BugBossDef = null
var _attack: EnemyAttackTelegraph = null
var _active_socket: BossWeaponSocket = null
var _brood_spawner: BugBroodSpawner = null
var _attack_state: StringName = &"cadence"
var _state_remaining_sec: float = 0.0
var _next_charge: bool = true
var _active_charge: bool = false
var _socket_index: int = 0
var _phase_two: bool = false
var _charge_direction: Vector3 = Vector3.FORWARD
var _charge_destination: Vector3 = Vector3.ZERO
var _charge_velocity: Vector3 = Vector3.ZERO
var _swelling_model: Node3D = null
var _resting_model_scale: Vector3 = Vector3.ONE
var _brood_warning: Label3D = null

func configure_enemy(d: EnemyDef, spawn_context: EnemySpawnContext = null) -> void:
	_clear_encounter_runtime()
	super.configure_enemy(d, spawn_context)
	_bug_def = d as BugBossDef
	if _bug_def == null:
		_bug_def = BugBossDef.new()
	_attack_state = &"cadence"
	_next_charge = true
	_active_charge = false
	_socket_index = 0
	_phase_two = false
	_state_remaining_sec = _bug_def.initial_delay_sec
	set_meta("bug_phase", 1)
	if is_instance_valid(_brood_spawner):
		_brood_spawner.clear_brood()
		_brood_spawner.queue_free()
	_brood_spawner = BugBroodSpawner.new()
	_brood_spawner.name = "MatronBroodSpawner"
	add_child(_brood_spawner)
	_brood_spawner.setup(self, _bug_def.brood_child_def, _bug_def.brood_alive_cap, _bug_def.brood_total_cap, 12, 50, _bug_def.brood_spawn_radius)

func _ready() -> void:
	super._ready()
	about_to_die.connect(_on_matron_died, CONNECT_ONE_SHOT)

func get_attack_state() -> StringName:
	return _attack_state

func is_in_second_phase() -> bool:
	return _phase_two

func get_brood_spawner() -> BugBroodSpawner:
	return _brood_spawner

func _update_tracking(target_position: Vector3, delta: float) -> void:
	if (_attack_state == &"windup" and _active_charge) or _attack_state == &"charge":
		super._update_tracking(global_position + _charge_direction * 100.0, delta)
		return
	super._update_tracking(target_position, delta)

func _update_movement(target_position: Vector3, delta: float) -> void:
	if _attack_state == &"charge":
		# The charge trajectory is committed when its warning starts. Movement
		# cannot steer toward the player's new position or apply another hit.
		linear_velocity = _charge_velocity
		return
	if _attack_state == &"windup" or _attack_state == &"brood" or _attack_state == &"recovery":
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return
	super._update_movement(target_position, delta)

func _update_weapons(target: Node3D, delta: float) -> void:
	# Replaces boss socket autofire: only locked telegraphs deal Matron damage.
	if _dead or not is_instance_valid(target) or not target.visible or _bug_def == null:
		return
	if not _phase_two and hull <= eff_max_hull * _bug_def.phase_hull_threshold:
		_enter_second_phase()
	if _attack_state == &"windup":
		if not is_instance_valid(_attack) or _attack.is_queued_for_deletion():
			_attack = null
			_begin_recovery()
		return
	_state_remaining_sec = maxf(_state_remaining_sec - delta, 0.0)
	if _attack_state == &"brood":
		_update_brood_swelling()
		if _state_remaining_sec <= 0.0:
			_release_brood()
		return
	if _state_remaining_sec > 0.0:
		return
	if _attack_state == &"charge":
		_begin_recovery()
		return
	if _attack_state == &"recovery":
		_attack_state = &"cadence"
		_state_remaining_sec = _bug_def.cadence_sec * (_bug_def.phase_cadence_multiplier if _phase_two else 1.0)
		return
	_begin_attack(target)

func _begin_attack(target: Node3D) -> void:
	if _dead or _weapon_sockets.is_empty() or is_instance_valid(_attack):
		return
	var socket: BossWeaponSocket = _weapon_sockets[_socket_index % _weapon_sockets.size()]
	if not is_instance_valid(socket) or socket.weapon == null or not _is_target_in_range(socket, target):
		return
	_socket_index += 1
	_active_charge = _next_charge
	_next_charge = not _next_charge
	_active_socket = socket
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if _active_charge:
		_attack_state = &"windup"
		_charge_direction = (target.global_position - global_position).normalized()
		if _charge_direction.length_squared() <= 0.0001:
			_charge_direction = -global_basis.z.normalized()
		_charge_destination = target.global_position + _charge_direction * _bug_def.charge_overshoot
	else:
		_attack_state = &"brood"
		_state_remaining_sec = maxf(_bug_def.brood_windup_sec, 0.05)
		_swelling_model = get_visual_model_root()
		if is_instance_valid(_swelling_model):
			_resting_model_scale = _swelling_model.scale
		_build_brood_warning()
		return
	_attack = EnemyAttackTelegraph.new()
	_attack.set_warning_style("CHARGE", Color(0.66, 1.0, 0.22))
	get_tree().current_scene.add_child(_attack)
	_attack.resolved.connect(_on_attack_resolved, CONNECT_ONE_SHOT)
	_attack.start_attack(self, target, socket, _bug_def.charge_windup_sec, _bug_def.charge_radius, true)

func _on_attack_resolved(_hit: bool) -> void:
	if _dead:
		return
	if is_instance_valid(_active_socket):
		weapon_socket_fired.emit(_active_socket, _active_socket.weapon)
	_active_socket = null
	_attack = null
	_restore_swelling()
	_attack_state = &"charge"
	_state_remaining_sec = maxf(_bug_def.charge_move_sec, 0.1)
	_charge_velocity = (_charge_destination - global_position) / _state_remaining_sec
	linear_velocity = _charge_velocity

func _release_brood() -> void:
	if is_instance_valid(_brood_spawner):
		var release_count: int = _bug_def.phase_brood_release_count if _phase_two else _bug_def.brood_release_count
		_brood_spawner.spawn_brood(release_count)
	_begin_recovery()

func _build_brood_warning() -> void:
	_brood_warning = Label3D.new()
	_brood_warning.name = "BroodReleaseCountdown"
	_brood_warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_brood_warning.no_depth_test = true
	_brood_warning.font_size = 30
	_brood_warning.outline_size = 6
	_brood_warning.pixel_size = 0.28
	_brood_warning.position = Vector3.UP * (label_height + 22.0)
	_brood_warning.modulate = Color(0.95, 0.37, 0.72)
	add_child(_brood_warning)
	_update_brood_swelling()

func _update_brood_swelling() -> void:
	var progress: float = 1.0 - clampf(_state_remaining_sec / maxf(_bug_def.brood_windup_sec, 0.05), 0.0, 1.0)
	if is_instance_valid(_swelling_model):
		_swelling_model.scale = _resting_model_scale * (1.0 + progress * 0.22)
	if is_instance_valid(_brood_warning):
		_brood_warning.text = "BROOD RELEASE  %.1f" % _state_remaining_sec

func _restore_swelling() -> void:
	if is_instance_valid(_swelling_model):
		_swelling_model.scale = _resting_model_scale
	_swelling_model = null
	if is_instance_valid(_brood_warning):
		_brood_warning.queue_free()
	_brood_warning = null

func _begin_recovery() -> void:
	_restore_swelling()
	_active_socket = null
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_attack_state = &"recovery"
	_state_remaining_sec = _bug_def.recovery_sec

func _enter_second_phase() -> void:
	_phase_two = true
	set_meta("bug_phase", 2)
	EffectsBus.show_float(global_position, "BROOD FRENZY", Color(0.95, 0.37, 0.72))

func _on_matron_died(_enemy: Enemy) -> void:
	_clear_encounter_runtime()

func _clear_encounter_runtime() -> void:
	if is_instance_valid(_attack):
		_attack.cancel()
	_attack = null
	_active_socket = null
	linear_velocity = Vector3.ZERO
	_restore_swelling()
	if is_instance_valid(_brood_spawner):
		_brood_spawner.clear_brood()

func _exit_tree() -> void:
	_clear_encounter_runtime()
	super._exit_tree()
