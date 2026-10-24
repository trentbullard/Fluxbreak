extends EnemyBoss
class_name GreyWitness

enum Major { DISPLACEMENT, RUPTURE, TETHER }

const WARNING_TINT: Color = Color(0.76, 0.48, 1.0, 0.9)

var _grey_def: GreyBossDef = null
var _attack: EnemyAttackTelegraph = null
var _displacement: GreyDisplacement = null
var _tether: GreyTether = null
var _active_socket: BossWeaponSocket = null
var _attack_state: StringName = &"cadence"
var _state_remaining_sec: float = 0.0
var _next_major: int = Major.DISPLACEMENT
var _socket_index: int = 0
var _phase_two: bool = false
var _relocation_side: float = 1.0
var _rupture_then_relocate: bool = false

func configure_enemy(d: EnemyDef, spawn_context: EnemySpawnContext = null) -> void:
	_clear_encounter_runtime()
	super.configure_enemy(d, spawn_context)
	_grey_def = d as GreyBossDef
	if _grey_def == null:
		_grey_def = GreyBossDef.new()
	_attack_state = &"cadence"
	_state_remaining_sec = _grey_def.initial_delay_sec
	_next_major = Major.DISPLACEMENT
	_socket_index = 0
	_phase_two = false
	_relocation_side = 1.0
	_rupture_then_relocate = false
	set_meta("grey_phase", 1)

func _ready() -> void:
	super._ready()
	about_to_die.connect(_on_witness_died, CONNECT_ONE_SHOT)

func get_attack_state() -> StringName:
	return _attack_state

func is_in_second_phase() -> bool:
	return _phase_two

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(player_ship) or not player_ship.visible or not player_ship.is_alive():
		_clear_encounter_runtime()
		_attack_state = &"cadence"
		if _grey_def != null:
			_state_remaining_sec = _grey_def.initial_delay_sec
		return
	super._physics_process(delta)

func _update_movement(target_position: Vector3, delta: float) -> void:
	if _attack_state != &"cadence":
		# A fixed source makes each destination, rupture, and tether easy to read.
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return
	super._update_movement(target_position, delta)

func _update_weapons(target: Node3D, delta: float) -> void:
	# Every damaging sphere/crossing lane is visibly committed; no socket autofire.
	if _dead or _grey_def == null or not is_instance_valid(target) or not target.visible:
		return
	if not _phase_two and hull + shield <= (eff_max_hull + eff_max_shield) * _grey_def.phase_hull_threshold:
		_phase_two = true
		set_meta("grey_phase", 2)
		EffectsBus.show_float(global_position, "WITNESS AWAKENED", WARNING_TINT)
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
		_state_remaining_sec = _grey_def.cadence_sec * (_grey_def.phase_cadence_multiplier if _phase_two else 1.0)
		return
	_begin_attack(target)

func _begin_attack(target: Node3D) -> void:
	if _dead or is_queued_for_deletion() or not is_inside_tree() or _attack_state != &"cadence" or not is_instance_valid(target):
		return
	if is_instance_valid(_attack) or is_instance_valid(_displacement) or is_instance_valid(_tether):
		return
	match _next_major:
		Major.DISPLACEMENT:
			_begin_displacement(target)
		Major.RUPTURE:
			_begin_rupture(target)
		Major.TETHER:
			_begin_tether(target as Ship)

func _begin_displacement(target: Node3D) -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	var radial: Vector3 = global_position - target.global_position
	if radial.length_squared() <= 0.0001:
		radial = Vector3.FORWARD
	radial = radial.normalized().rotated(Vector3.UP, deg_to_rad(70.0) * _relocation_side)
	_relocation_side *= -1.0
	var destination: Vector3 = target.global_position + radial * clampf(_grey_def.displacement_distance, 170.0, 190.0)
	_displacement = GreyDisplacement.new()
	_displacement.name = "WitnessRelocation"
	get_tree().current_scene.add_child(_displacement)
	_displacement.completed.connect(_on_displacement_completed, CONNECT_ONE_SHOT)
	_attack_state = &"displacement"
	_next_major = Major.RUPTURE
	if not _displacement.start_displacement(self, destination, _grey_def.displacement_windup_sec):
		_displacement.cancel()
		_displacement = null
		_begin_recovery()

func _begin_rupture(target: Node3D) -> void:
	if _dead or is_queued_for_deletion() or not is_inside_tree() or _weapon_sockets.is_empty():
		return
	var socket: BossWeaponSocket = _weapon_sockets[_socket_index % _weapon_sockets.size()]
	if not is_instance_valid(socket) or socket.weapon == null or not _is_target_in_range(socket, target):
		return
	var pattern: EnemyAttackTelegraph = GreyAttackPattern.start(self, target, socket, "WITNESS PHASE CROSS", GreyAttackPattern.Shape.PHASE_CROSS, _grey_def.rupture_windup_sec, _grey_def.rupture_radius, _grey_def.forecast_lead_fraction, _grey_def.forecast_max_lead, _grey_def.corridor_half_length, _grey_def.corridor_radius, _grey_def.echo_gap_sec)
	if pattern == null:
		return
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_socket_index += 1
	_active_socket = socket
	_attack_state = &"rupture"
	_next_major = Major.DISPLACEMENT if _rupture_then_relocate else Major.TETHER
	_rupture_then_relocate = false
	_attack = pattern
	_attack.resolved.connect(_on_rupture_resolved, CONNECT_ONE_SHOT)

func _begin_tether(target: Ship) -> void:
	if target == null:
		return
	if target.is_tether_immune() or target.get_tether_time_remaining() > 0.0:
		_rupture_then_relocate = true
		_begin_rupture(target)
		return
	_tether = GreyTether.new()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_tether.name = "WitnessTether"
	get_tree().current_scene.add_child(_tether)
	_tether.completed.connect(_on_tether_completed, CONNECT_ONE_SHOT)
	_attack_state = &"tether"
	_next_major = Major.DISPLACEMENT
	var velocity: Vector3 = GreyAttackGeometry.target_velocity(target)
	var center: Vector3 = GreyAttackGeometry.forecast(target.global_position, velocity, _grey_def.tether_windup_sec, _grey_def.forecast_lead_fraction, _grey_def.forecast_max_lead)
	var axis: Vector3 = GreyAttackGeometry.crossing_axis(velocity, target.global_position - global_position)
	if not _tether.start_tether(self, target, _grey_def.tether_windup_sec, _grey_def.tether_duration_sec, _grey_def.tether_movement_factor, _grey_def.tether_break_distance, minf(_grey_def.tether_radius, _grey_def.corridor_radius), center + axis * _grey_def.corridor_half_length, center - axis * _grey_def.corridor_half_length):
		_tether.cancel()
		_tether = null
		_begin_recovery()

func _on_displacement_completed(_moved: bool) -> void:
	_displacement = null
	if not _dead:
		# Relocation is a setup, followed by a fresh full warning, not a whole
		# empty attack/recovery/cadence cycle.
		_attack_state = &"cadence"
		_next_major = Major.RUPTURE
		_state_remaining_sec = 0.0

func _on_rupture_resolved(_hit: bool) -> void:
	if is_instance_valid(_active_socket):
		weapon_socket_fired.emit(_active_socket, _active_socket.weapon)
	_active_socket = null
	_attack = null
	if not _dead:
		_begin_recovery()

func _on_tether_completed(_attached: bool) -> void:
	_tether = null
	if not _dead:
		_rupture_then_relocate = true
		_attack_state = &"cadence"
		_next_major = Major.RUPTURE
		_state_remaining_sec = 0.0

func _begin_recovery() -> void:
	_active_socket = null
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_attack_state = &"recovery"
	_state_remaining_sec = _grey_def.recovery_sec

func _on_witness_died(_enemy: Enemy) -> void:
	_clear_encounter_runtime()

func _clear_encounter_runtime() -> void:
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

func _exit_tree() -> void:
	_clear_encounter_runtime()
	super._exit_tree()
