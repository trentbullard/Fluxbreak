extends EnemyBoss
class_name MercFlagship

enum Major { BROADSIDE, SALVO }

var _flagship_def: MercFlagshipDef = null
var _escort_wing: MercEscortWing = null
var _attack: EnemyAttackTelegraph = null
var _active_socket: BossWeaponSocket = null
var _attack_state: StringName = &"cadence"
var _state_remaining_sec: float = 0.0
var _support_remaining_sec: float = 0.0
var _phase: int = 1
var _major_index: int = 0
var _socket_index: int = 0
var _arrival_wing_requested: bool = false
var _shutting_down: bool = false
var _shield_pulses: int = 0
var _attacks_started: int = 0

func configure_enemy(d: EnemyDef, spawn_context: EnemySpawnContext = null) -> void:
	_clear_encounter_runtime()
	super.configure_enemy(d, spawn_context)
	_flagship_def = d as MercFlagshipDef
	if _flagship_def == null:
		_flagship_def = MercFlagshipDef.new()
	_shutting_down = false
	_phase = 1
	_major_index = 0
	_socket_index = 0
	_attack_state = &"cadence"
	_arrival_wing_requested = false
	_shield_pulses = 0
	_attacks_started = 0
	_state_remaining_sec = _flagship_def.initial_delay_sec
	_support_remaining_sec = _flagship_def.escort_shield_interval_sec
	if is_instance_valid(_escort_wing):
		_escort_wing.clear_escorts()
		_escort_wing.queue_free()
	_escort_wing = MercEscortWing.new()
	_escort_wing.name = "EscortWing"
	add_child(_escort_wing)
	_escort_wing.setup(self, _flagship_def.escort_def, _flagship_def.escort_living_cap, _flagship_def.escort_lifetime_cap, 10, 50, _flagship_def.escort_offset)
	set_meta("merc_phase", _phase)
	set_meta("flagship_phase", _phase)

func _ready() -> void:
	super._ready()
	about_to_die.connect(_on_flagship_died, CONNECT_ONE_SHOT)

func get_attack_state() -> StringName:
	return _attack_state

func get_phase() -> int:
	return _phase

func get_living_escort_count() -> int:
	return _escort_wing.get_living_count() if is_instance_valid(_escort_wing) else 0

func get_total_escorts_spawned() -> int:
	return _escort_wing.get_total_spawned() if is_instance_valid(_escort_wing) else 0

func get_shield_pulse_count() -> int:
	return _shield_pulses

func get_attacks_started() -> int:
	return _attacks_started

func _update_weapons(target: Node3D, delta: float) -> void:
	# Replace automatic socket fire: each major owns one immutable warning.
	if _dead or _shutting_down or _flagship_def == null or not is_instance_valid(target) or not target.visible:
		return
	if not _arrival_wing_requested:
		_arrival_wing_requested = true
		_request_escort_wing()
	_update_phase()
	_update_escort_support(delta)
	if _attack_state == &"windup":
		if not is_instance_valid(_attack) or _attack.is_queued_for_deletion():
			_attack = null
			_begin_recovery()
		return
	_state_remaining_sec = maxf(_state_remaining_sec - delta, 0.0)
	if _state_remaining_sec > 0.0:
		return
	if _attack_state == &"recovery":
		_attack_state = &"cadence"
		_state_remaining_sec = _flagship_def.cadence_sec * _get_cadence_multiplier()
		return
	_begin_attack(target)

func _update_phase() -> void:
	if _phase == 1 and hull <= eff_max_hull * _flagship_def.phase_two_hull_threshold:
		_enter_phase(2)
	if _phase == 2 and hull <= eff_max_hull * _flagship_def.phase_three_hull_threshold:
		_enter_phase(3)

func _enter_phase(next_phase: int) -> void:
	_phase = next_phase
	_major_index = 0
	set_meta("merc_phase", _phase)
	set_meta("flagship_phase", _phase)
	# An already committed shot retains its full warning and recovery.
	_request_escort_wing()
	EffectsBus.show_float(global_position, "VANGUARD RESERVES" if _phase == 2 else "FINAL BROADSIDE", Color(1.0, 0.6, 0.15))

func _get_cadence_multiplier() -> float:
	if _phase == 3:
		return _flagship_def.phase_three_cadence_multiplier
	if _phase == 2:
		return _flagship_def.phase_two_cadence_multiplier
	return 1.0

func _get_major_sequence() -> Array[int]:
	if _phase == 3:
		return [Major.SALVO, Major.BROADSIDE, Major.BROADSIDE, Major.SALVO]
	if _phase == 2:
		return [Major.BROADSIDE, Major.SALVO, Major.BROADSIDE]
	return [Major.BROADSIDE, Major.SALVO]

func _begin_attack(target: Node3D) -> void:
	if _dead or _shutting_down or _attack_state != &"cadence" or not is_instance_valid(target) or not target.visible:
		return
	var sequence: Array[int] = _get_major_sequence()
	var major: int = sequence[_major_index % sequence.size()]
	var socket: BossWeaponSocket = _select_socket(major)
	if not is_instance_valid(socket) or not _is_target_in_range(socket, target):
		return
	_major_index += 1
	_socket_index += 1
	_attack_state = &"windup"
	_active_socket = socket
	_attack = EnemyAttackTelegraph.new()
	get_tree().current_scene.add_child(_attack)
	var corridor: bool = major == Major.BROADSIDE
	_attack.set_warning_style("HEAVY BROADSIDE" if corridor else "VANGUARD SALVO", Color(1.0, 0.58, 0.13, 0.9))
	_attack.resolved.connect(_on_attack_resolved, CONNECT_ONE_SHOT)
	var windup: float = _flagship_def.broadside_windup_sec if corridor else _flagship_def.salvo_windup_sec
	var radius: float = _flagship_def.broadside_radius if corridor else _flagship_def.salvo_radius
	_attack.start_attack(self, target, socket, windup, radius, corridor)
	_attacks_started += 1
	set_meta("flagship_attacks_started", _attacks_started)

func _select_socket(major: int) -> BossWeaponSocket:
	var candidates: Array[BossWeaponSocket] = []
	var keyword: String = "Broadside" if major == Major.BROADSIDE else "Salvo"
	for socket: BossWeaponSocket in _weapon_sockets:
		if is_instance_valid(socket) and socket.weapon != null and String(socket.name).contains(keyword):
			candidates.append(socket)
	if candidates.is_empty():
		for socket: BossWeaponSocket in _weapon_sockets:
			if is_instance_valid(socket) and socket.weapon != null:
				candidates.append(socket)
	if candidates.is_empty():
		return null
	return candidates[_socket_index % candidates.size()]

func _on_attack_resolved(_hit: bool) -> void:
	if _dead or _shutting_down:
		return
	if is_instance_valid(_active_socket):
		weapon_socket_fired.emit(_active_socket, _active_socket.weapon)
	_attack = null
	_begin_recovery()

func _begin_recovery() -> void:
	_active_socket = null
	_attack_state = &"recovery"
	_state_remaining_sec = _flagship_def.recovery_sec

func _request_escort_wing() -> void:
	if is_instance_valid(_escort_wing):
		_escort_wing.spawn_escorts(_flagship_def.escorts_per_wing)

func _update_escort_support(delta: float) -> void:
	_support_remaining_sec = maxf(_support_remaining_sec - delta, 0.0)
	if _support_remaining_sec > 0.0:
		return
	_support_remaining_sec = maxf(_flagship_def.escort_shield_interval_sec, 2.0)
	_restore_escort_shields()

func _restore_escort_shields() -> void:
	if _dead or _shutting_down or not is_instance_valid(_escort_wing):
		return
	var restored: bool = false
	var radius_sq: float = _flagship_def.escort_shield_radius * _flagship_def.escort_shield_radius
	for escort: Enemy in _escort_wing.get_living_escorts():
		if global_position.distance_squared_to(escort.global_position) > radius_sq:
			continue
		var previous: float = escort.shield
		escort.shield = minf(escort.eff_max_shield, escort.shield + maxf(_flagship_def.escort_shield_restore, 0.0))
		if escort.shield > previous:
			restored = true
			EffectsBus.show_float(escort.global_position, "SHIELD SUPPORT", Color(0.2, 0.8, 1.0))
	if restored:
		_shield_pulses += 1
		set_meta("flagship_shield_pulses", _shield_pulses)

func _on_flagship_died(_enemy: Enemy) -> void:
	_clear_encounter_runtime()

func _clear_encounter_runtime() -> void:
	_shutting_down = true
	if is_instance_valid(_attack):
		_attack.cancel()
	_attack = null
	_active_socket = null
	if is_instance_valid(_escort_wing):
		_escort_wing.clear_escorts()

func _exit_tree() -> void:
	_clear_encounter_runtime()
	super._exit_tree()
