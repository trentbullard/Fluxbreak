extends EnemyBoss
class_name GreyVeiledMind

enum Major { DISPLACEMENT, RUPTURE, TETHER }

const WARNING_TINT: Color = Color(0.68, 0.58, 1.0, 0.95)
const RETRY_SEC: float = 0.25

var _grey_def: GreyMindDef = null
var _attack: EnemyAttackTelegraph = null
var _displacement: GreyDisplacement = null
var _tether: GreyTether = null
var _active_socket: BossWeaponSocket = null
var _attack_state: StringName = &"cadence"
var _state_remaining_sec: float = 0.0
var _next_major: int = Major.RUPTURE
var _phase: int = 1
var _sequence_index: int = 0
var _socket_index: int = 0
var _relocation_side: float = 1.0
var _clearing_runtime: bool = false

func configure_enemy(d: EnemyDef, spawn_context: EnemySpawnContext = null) -> void:
	_clear_encounter_runtime()
	super.configure_enemy(d, spawn_context)
	_grey_def = d as GreyMindDef
	if _grey_def == null:
		_grey_def = GreyMindDef.new()
	_attack_state = &"cadence"
	_state_remaining_sec = _grey_def.initial_delay_sec
	_phase = 1
	_sequence_index = 0
	_socket_index = 0
	_relocation_side = 1.0
	_next_major = Major.RUPTURE
	set_meta("grey_phase", _phase)

func _ready() -> void:
	super._ready()
	about_to_die.connect(_on_mind_died, CONNECT_ONE_SHOT)

func get_phase() -> int:
	return _phase

func get_attack_state() -> StringName:
	return _attack_state

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not _is_target_available(player_ship):
		_clear_encounter_runtime()
		_attack_state = &"cadence"
		_state_remaining_sec = _grey_def.initial_delay_sec if _grey_def != null else 2.8
		return
	super._physics_process(delta)

func _update_movement(target_position: Vector3, delta: float) -> void:
	if _attack_state != &"cadence":
		# A stationary source preserves the locked volume and arrival silhouette.
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return
	super._update_movement(target_position, delta)

func _update_weapons(target: Node3D, delta: float) -> void:
	# Every hit comes from a delayed rupture; sockets never perform autofire.
	if _dead or _grey_def == null:
		return
	if not _is_target_available(target):
		_clear_encounter_runtime()
		_attack_state = &"cadence"
		_state_remaining_sec = _grey_def.initial_delay_sec
		return
	_update_phase()
	if _attack_state == &"displacement":
		if not is_instance_valid(_displacement) or _displacement.is_queued_for_deletion():
			_displacement = null
			_begin_recovery()
		return
	if _attack_state == &"rupture":
		if not is_instance_valid(_attack) or _attack.is_queued_for_deletion():
			_attack = null
			_begin_recovery()
		return
	if _attack_state == &"tether":
		if not is_instance_valid(_tether) or _tether.is_queued_for_deletion():
			_tether = null
			_begin_recovery()
		return
	_state_remaining_sec = maxf(_state_remaining_sec - delta, 0.0)
	if _state_remaining_sec > 0.0:
		return
	if _attack_state == &"recovery":
		_attack_state = &"cadence"
		_state_remaining_sec = _grey_def.cadence_sec * _get_cadence_multiplier()
		return
	_begin_attack(target)

func _update_phase() -> void:
	var next_phase: int = _phase
	var durability_fraction: float = (hull + shield) / maxf(eff_max_hull + eff_max_shield, 1.0)
	if durability_fraction <= _grey_def.phase_three_hull_threshold:
		next_phase = 3
	elif durability_fraction <= _grey_def.phase_two_hull_threshold:
		next_phase = maxi(_phase, 2)
	if next_phase <= _phase:
		return
	_phase = next_phase
	_sequence_index = 0
	_next_major = _get_sequence()[0]
	set_meta("grey_phase", _phase)
	EffectsBus.show_float(global_position, "VEIL SHIFT %d" % _phase, WARNING_TINT)
	# The active major and every recovery timer deliberately remain untouched.

func _get_sequence() -> Array[int]:
	match _phase:
		2:
			return [Major.DISPLACEMENT, Major.RUPTURE]
		3:
			return [Major.TETHER, Major.RUPTURE, Major.DISPLACEMENT, Major.RUPTURE]
	return [Major.RUPTURE, Major.RUPTURE]

func _get_cadence_multiplier() -> float:
	if _phase == 3:
		return _grey_def.phase_three_cadence_multiplier
	if _phase == 2:
		return _grey_def.phase_two_cadence_multiplier
	return 1.0

func _advance_sequence() -> void:
	var sequence: Array[int] = _get_sequence()
	_sequence_index = (_sequence_index + 1) % sequence.size()
	_next_major = sequence[_sequence_index]

func _begin_attack(target: Node3D) -> void:
	if _dead or is_queued_for_deletion() or not is_inside_tree() or _attack_state != &"cadence" or not _is_target_available(target):
		return
	if is_instance_valid(_attack) or is_instance_valid(_displacement) or is_instance_valid(_tether):
		return
	var started: bool = false
	match _next_major:
		Major.DISPLACEMENT:
			started = _begin_displacement(target)
		Major.RUPTURE:
			started = _begin_rupture(target)
		Major.TETHER:
			started = _begin_tether(target as Ship)
	if started:
		_advance_sequence()
	else:
		_state_remaining_sec = RETRY_SEC

func _begin_displacement(target: Node3D) -> bool:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	var radial: Vector3 = global_position - target.global_position
	if radial.length_squared() <= 0.0001:
		radial = Vector3.FORWARD
	radial = radial.normalized().rotated(Vector3.UP, deg_to_rad(75.0) * _relocation_side)
	_relocation_side *= -1.0
	var destination: Vector3 = target.global_position + radial * clampf(_grey_def.displacement_distance, 170.0, 190.0)
	_displacement = GreyDisplacement.new()
	_displacement.name = "VeiledMindRelocation"
	get_tree().current_scene.add_child(_displacement)
	if not _displacement.start_displacement(self, destination, _grey_def.displacement_windup_sec):
		_displacement.cancel()
		_displacement = null
		return false
	_displacement.completed.connect(_on_displacement_completed, CONNECT_ONE_SHOT)
	_attack_state = &"displacement"
	return true

func _begin_rupture(target: Node3D) -> bool:
	if _dead or is_queued_for_deletion() or not is_inside_tree() or _weapon_sockets.is_empty():
		return false
	var socket: BossWeaponSocket = _weapon_sockets[_socket_index % _weapon_sockets.size()]
	if not is_instance_valid(socket) or socket.weapon == null or not _is_target_in_range(socket, target):
		return false
	var shape: GreyAttackPattern.Shape = GreyAttackPattern.Shape.CONVERGENCE if _phase == 3 else (GreyAttackPattern.Shape.ECHO_PAIR if _phase == 2 else GreyAttackPattern.Shape.FORECAST)
	var pattern: EnemyAttackTelegraph = GreyAttackPattern.start(self, target, socket, "VEIL COLLAPSE %d" % _phase, shape, _grey_def.rupture_windup_sec, _grey_def.rupture_radius, _grey_def.forecast_lead_fraction, _grey_def.forecast_max_lead, _grey_def.corridor_half_length, _grey_def.corridor_radius, _grey_def.echo_gap_sec)
	if pattern == null:
		return false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_socket_index += 1
	_active_socket = socket
	_attack_state = &"rupture"
	_attack = pattern
	_attack.name = "VeiledMindRupture"
	_attack.resolved.connect(_on_rupture_resolved, CONNECT_ONE_SHOT)
	return true

func _begin_tether(target: Ship) -> bool:
	if target == null:
		return false
	if target.is_tether_immune() or target.get_tether_time_remaining() > 0.0:
		return _begin_rupture(target)
	_tether = GreyTether.new()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_tether.name = "VeiledMindTether"
	get_tree().current_scene.add_child(_tether)
	var velocity: Vector3 = GreyAttackGeometry.target_velocity(target)
	var center: Vector3 = GreyAttackGeometry.forecast(target.global_position, velocity, _grey_def.tether_windup_sec, _grey_def.forecast_lead_fraction, _grey_def.forecast_max_lead)
	var axis: Vector3 = GreyAttackGeometry.crossing_axis(velocity, target.global_position - global_position)
	if not _tether.start_tether(self, target, _grey_def.tether_windup_sec, _grey_def.tether_duration_sec, _grey_def.tether_movement_factor, _grey_def.tether_break_distance, minf(_grey_def.tether_radius, _grey_def.corridor_radius), center + axis * _grey_def.corridor_half_length, center - axis * _grey_def.corridor_half_length):
		_tether.cancel()
		_tether = null
		return false
	_tether.completed.connect(_on_tether_completed, CONNECT_ONE_SHOT)
	_attack_state = &"tether"
	return true

func _on_displacement_completed(_moved: bool) -> void:
	_displacement = null
	if not _dead and not _clearing_runtime:
		_begin_followup()

func _on_rupture_resolved(_hit: bool) -> void:
	if is_instance_valid(_active_socket):
		weapon_socket_fired.emit(_active_socket, _active_socket.weapon)
	_active_socket = null
	_attack = null
	if not _dead and not _clearing_runtime:
		_begin_recovery()

func _on_tether_completed(_attached: bool) -> void:
	_tether = null
	if not _dead and not _clearing_runtime:
		_begin_followup()

func _begin_followup() -> void:
	# Setup actions immediately schedule a separately warned collapse. The
	# sequence advances once that collapse starts, so setup never dilutes DPS.
	_attack_state = &"cadence"
	_next_major = Major.RUPTURE
	_state_remaining_sec = 0.0

func _begin_recovery() -> void:
	_active_socket = null
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_attack_state = &"recovery"
	_state_remaining_sec = _grey_def.recovery_sec

func _is_target_available(target: Node3D) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.visible:
		return false
	return not target.has_method("is_alive") or bool(target.call("is_alive"))

func _on_mind_died(_enemy: Enemy) -> void:
	_clear_encounter_runtime()

func _clear_encounter_runtime() -> void:
	_clearing_runtime = true
	if is_instance_valid(_attack):
		_attack.cancel()
	if is_instance_valid(_displacement):
		_displacement.cancel()
	if is_instance_valid(_tether):
		_tether.cancel()
	_attack = null
	_displacement = null
	_tether = null
	_active_socket = null
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_clearing_runtime = false

func _exit_tree() -> void:
	_clear_encounter_runtime()
	super._exit_tree()
