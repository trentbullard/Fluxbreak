extends EnemyBoss
class_name BugFirstQueen

const FIRST_SEQUENCE: Array[StringName] = [&"brood", &"spores"]
const SECOND_SEQUENCE: Array[StringName] = [&"brood", &"spores", &"charge"]
const FINAL_SEQUENCE: Array[StringName] = [&"spores", &"brood", &"charge", &"spores"]

var _queen_def: BugQueenDef = null
var _attack: EnemyAttackTelegraph = null
var _spore_zone: BugSporeZone = null
var _active_socket: BossWeaponSocket = null
var _brood_spawner: BugBroodSpawner = null
var _attack_state: StringName = &"cadence"
var _state_remaining_sec: float = 0.0
var _phase: int = 1
var _sequence_index: int = 0
var _socket_index: int = 0
var _charge_direction: Vector3 = Vector3.FORWARD
var _charge_destination: Vector3 = Vector3.ZERO
var _charge_velocity: Vector3 = Vector3.ZERO
var _swelling_model: Node3D = null
var _resting_model_scale: Vector3 = Vector3.ONE
var _brood_warning: Label3D = null

func configure_enemy(d: EnemyDef, spawn_context: EnemySpawnContext = null) -> void:
	_clear_encounter_runtime()
	if is_instance_valid(_brood_spawner):
		_brood_spawner.queue_free()
	_brood_spawner = null
	super.configure_enemy(d, spawn_context)
	_queen_def = d as BugQueenDef
	if _queen_def == null:
		_queen_def = BugQueenDef.new()
	_attack_state = &"cadence"
	_state_remaining_sec = maxf(_queen_def.initial_delay_sec, 0.1)
	_phase = 1
	_sequence_index = 0
	_socket_index = 0
	set_meta(&"bug_phase", _phase)
	_brood_spawner = BugBroodSpawner.new()
	_brood_spawner.name = "QueenBroodSpawner"
	add_child(_brood_spawner)
	_brood_spawner.setup(self, _queen_def.brood_child_def, mini(_queen_def.brood_alive_cap, 8), mini(_queen_def.brood_total_cap, 16), 12, 50, _queen_def.brood_spawn_radius)

func _ready() -> void:
	super._ready()
	about_to_die.connect(_on_queen_died, CONNECT_ONE_SHOT)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(player_ship) or not player_ship.visible or not player_ship.is_alive():
		_clear_encounter_runtime()
		_attack_state = &"cadence"
		if _queen_def != null:
			_state_remaining_sec = maxf(_queen_def.initial_delay_sec, 0.1)
		return
	super._physics_process(delta)

func get_phase() -> int:
	return _phase

func get_attack_state() -> StringName:
	return _attack_state

func get_brood_spawner() -> BugBroodSpawner:
	return _brood_spawner

func _update_tracking(target_position: Vector3, delta: float) -> void:
	if _attack_state == &"charge_windup" or _attack_state == &"charge":
		super._update_tracking(global_position + _charge_direction * 100.0, delta)
		return
	super._update_tracking(target_position, delta)

func _update_movement(target_position: Vector3, delta: float) -> void:
	if _attack_state == &"charge":
		# Motion follows the locked corridor. The warning already resolved the
		# only charge hit; a passing Queen never deals physical contact damage.
		linear_velocity = _charge_velocity
		return
	if _attack_state != &"cadence":
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return
	super._update_movement(target_position, delta)

func _update_weapons(target: Node3D, delta: float) -> void:
	# Socket autofire is replaced entirely by explicit warned attacks.
	if _dead or _queen_def == null or not is_instance_valid(target) or not target.visible:
		return
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		_clear_encounter_runtime()
		return
	_update_phase()
	if _attack_state == &"charge_windup":
		if not is_instance_valid(_attack) or _attack.is_queued_for_deletion():
			_attack = null
			_begin_recovery()
		return
	if _attack_state == &"spores":
		if not is_instance_valid(_spore_zone) or _spore_zone.is_queued_for_deletion():
			_spore_zone = null
			_begin_recovery()
		return
	_state_remaining_sec = maxf(_state_remaining_sec - maxf(delta, 0.0), 0.0)
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
		_state_remaining_sec = maxf(_queen_def.cadence_sec, 0.1) * (_queen_def.final_phase_cadence_multiplier if _phase == 3 else 1.0)
		return
	_begin_attack(target)

func _update_phase() -> void:
	var next_phase: int = _phase
	if hull <= eff_max_hull * minf(_queen_def.final_phase_hull_threshold, _queen_def.second_phase_hull_threshold):
		next_phase = 3
	elif hull <= eff_max_hull * _queen_def.second_phase_hull_threshold:
		next_phase = maxi(next_phase, 2)
	if next_phase <= _phase:
		return
	_phase = next_phase
	_sequence_index = 0
	set_meta(&"bug_phase", _phase)
	EffectsBus.show_float(global_position, "QUEEN'S HUNGER" if _phase == 2 else "LAST BROOD", Color(0.92, 0.36, 0.70))

func _begin_attack(target: Node3D) -> void:
	if _dead or not is_instance_valid(target) or _weapon_sockets.is_empty() or is_instance_valid(_attack) or is_instance_valid(_spore_zone):
		return
	var socket: BossWeaponSocket = _weapon_sockets[_socket_index % _weapon_sockets.size()]
	if not is_instance_valid(socket) or socket.weapon == null or not _is_target_in_range(socket, target):
		return
	var sequence: Array[StringName] = FIRST_SEQUENCE if _phase == 1 else (SECOND_SEQUENCE if _phase == 2 else FINAL_SEQUENCE)
	var attack_kind: StringName = sequence[_sequence_index % sequence.size()]
	_sequence_index += 1
	_socket_index += 1
	_active_socket = socket
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	match attack_kind:
		&"brood":
			_begin_brood()
		&"spores":
			_begin_spores(target, socket)
		&"charge":
			_begin_charge(target, socket)

func _begin_brood() -> void:
	if not is_instance_valid(_brood_spawner) or _brood_spawner.get_total_spawned() >= mini(_queen_def.brood_total_cap, 16) or _brood_spawner.get_living_count() >= mini(_queen_def.brood_alive_cap, 8):
		_begin_recovery()
		return
	_attack_state = &"brood"
	_state_remaining_sec = maxf(_queen_def.brood_windup_sec, 0.5)
	_swelling_model = get_visual_model_root()
	if is_instance_valid(_swelling_model):
		_resting_model_scale = _swelling_model.scale
	_brood_warning = Label3D.new()
	_brood_warning.name = "QueenBroodCountdown"
	_brood_warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_brood_warning.no_depth_test = true
	_brood_warning.font_size = 30
	_brood_warning.outline_size = 6
	_brood_warning.pixel_size = 0.28
	_brood_warning.position = Vector3.UP * (label_height + 22.0)
	_brood_warning.modulate = Color(0.95, 0.37, 0.72)
	add_child(_brood_warning)
	_update_brood_swelling()

func _begin_spores(target: Node3D, socket: BossWeaponSocket) -> void:
	var encounter_root: Node = get_tree().current_scene
	if encounter_root == null:
		_begin_recovery()
		return
	_attack_state = &"spores"
	_spore_zone = BugSporeZone.new()
	encounter_root.add_child(_spore_zone)
	_spore_zone.finished.connect(_on_spores_finished, CONNECT_ONE_SHOT)
	if not _spore_zone.start_zone(self, target, socket, _queen_def.spore_windup_sec, _queen_def.spore_radius, _queen_def.spore_pulse_count, "QUEEN'S SPORES", 8, 1):
		_spore_zone = null
		_begin_recovery()

func _begin_charge(target: Node3D, socket: BossWeaponSocket) -> void:
	var encounter_root: Node = get_tree().current_scene
	if encounter_root == null:
		_begin_recovery()
		return
	_attack_state = &"charge_windup"
	_charge_direction = (target.global_position - global_position).normalized()
	if _charge_direction.length_squared() <= 0.0001:
		_charge_direction = -global_basis.z.normalized()
	_charge_destination = target.global_position + _charge_direction * maxf(_queen_def.charge_overshoot, 0.0)
	_attack = EnemyAttackTelegraph.new()
	_attack.set_warning_style("QUEEN CHARGE", Color(0.75, 1.0, 0.22))
	encounter_root.add_child(_attack)
	_attack.resolved.connect(_on_charge_resolved, CONNECT_ONE_SHOT)
	_attack.start_attack(self, target, socket, _queen_def.charge_windup_sec, _queen_def.charge_radius, true, _charge_destination)

func _on_charge_resolved(_hit: bool) -> void:
	_attack = null
	if _dead:
		return
	if is_instance_valid(_active_socket):
		weapon_socket_fired.emit(_active_socket, _active_socket.weapon)
	_active_socket = null
	_attack_state = &"charge"
	_state_remaining_sec = maxf(_queen_def.charge_move_sec, 0.1)
	_charge_velocity = (_charge_destination - global_position) / _state_remaining_sec
	linear_velocity = _charge_velocity

func _on_spores_finished() -> void:
	_spore_zone = null
	if not _dead and _attack_state == &"spores":
		_begin_recovery()

func _release_brood() -> void:
	if is_instance_valid(_brood_spawner):
		var release_count: int = _queen_def.brood_release_count if _phase == 1 else _queen_def.phase_brood_release_count
		_brood_spawner.spawn_brood(release_count)
	_begin_recovery()

func _update_brood_swelling() -> void:
	var progress: float = 1.0 - clampf(_state_remaining_sec / maxf(_queen_def.brood_windup_sec, 0.5), 0.0, 1.0)
	if is_instance_valid(_swelling_model):
		_swelling_model.scale = _resting_model_scale * (1.0 + progress * 0.18)
	if is_instance_valid(_brood_warning):
		_brood_warning.text = "QUEEN BROOD  %.1f" % _state_remaining_sec

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
	_state_remaining_sec = maxf(_queen_def.recovery_sec, 0.1)

func _on_queen_died(_enemy: Enemy) -> void:
	_clear_encounter_runtime()

func _clear_encounter_runtime() -> void:
	# Detach the zone before cancel(), because finished is emitted synchronously.
	var zone: BugSporeZone = _spore_zone
	_spore_zone = null
	_attack_state = &"cadence"
	if is_instance_valid(zone):
		zone.cancel()
	if is_instance_valid(_attack):
		_attack.cancel()
	_attack = null
	_active_socket = null
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_restore_swelling()
	if is_instance_valid(_brood_spawner):
		_brood_spawner.clear_brood()

func _exit_tree() -> void:
	_clear_encounter_runtime()
	super._exit_tree()
