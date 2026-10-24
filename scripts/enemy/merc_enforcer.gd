extends EnemyBoss
class_name MercEnforcer

var _merc_def: MercBossDef = null
var _attack: EnemyAttackTelegraph = null
var _active_socket: BossWeaponSocket = null
var _attack_state: StringName = &"cadence"
var _state_remaining_sec: float = 0.0
var _next_corridor: bool = true
var _socket_index: int = 0
var _phase_two: bool = false
var _escort_attempted: bool = false
var _escort: Enemy = null

func configure_enemy(d: EnemyDef, spawn_context: EnemySpawnContext = null) -> void:
	super.configure_enemy(d, spawn_context)
	_merc_def = d as MercBossDef
	if _merc_def == null:
		_merc_def = MercBossDef.new()
	_state_remaining_sec = _merc_def.initial_delay_sec
	set_meta("merc_phase", 1)

func _ready() -> void:
	super._ready()
	about_to_die.connect(_on_enforcer_died, CONNECT_ONE_SHOT)

func get_attack_state() -> StringName:
	return _attack_state

func is_in_second_phase() -> bool:
	return _phase_two

func _update_weapons(target: Node3D, delta: float) -> void:
	# This replaces EnemyBoss autofire; every socket shot is a readable attack.
	if not is_instance_valid(target) or not target.visible or _merc_def == null:
		return
	if not _phase_two and hull <= eff_max_hull * _merc_def.phase_hull_threshold:
		_enter_second_phase()
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
		_state_remaining_sec = _merc_def.cadence_sec * (_merc_def.phase_cadence_multiplier if _phase_two else 1.0)
		return
	_begin_attack(target)

func _begin_attack(target: Node3D) -> void:
	if _weapon_sockets.is_empty():
		return
	var socket: BossWeaponSocket = _weapon_sockets[_socket_index % _weapon_sockets.size()]
	if not is_instance_valid(socket) or socket.weapon == null or not _is_target_in_range(socket, target):
		return
	_socket_index += 1
	_attack_state = &"windup"
	_active_socket = socket
	_attack = EnemyAttackTelegraph.new()
	get_tree().current_scene.add_child(_attack)
	_attack.resolved.connect(_on_attack_resolved, CONNECT_ONE_SHOT)
	var windup: float = _merc_def.broadside_windup_sec if _next_corridor else _merc_def.salvo_windup_sec
	var radius: float = _merc_def.broadside_radius if _next_corridor else _merc_def.salvo_radius
	_attack.start_attack(self, target, socket, windup, radius, _next_corridor)
	_next_corridor = not _next_corridor

func _on_attack_resolved(_hit: bool) -> void:
	if is_instance_valid(_active_socket):
		weapon_socket_fired.emit(_active_socket, _active_socket.weapon)
	_active_socket = null
	_attack = null
	_begin_recovery()

func _begin_recovery() -> void:
	_active_socket = null
	_attack_state = &"recovery"
	_state_remaining_sec = _merc_def.recovery_sec

func _enter_second_phase() -> void:
	_phase_two = true
	set_meta("merc_phase", 2)
	EffectsBus.show_float(global_position, "CONTRACT ESCALATED", Color(1.0, 0.6, 0.15))
	_spawn_single_escort()

func _spawn_single_escort() -> void:
	if _escort_attempted:
		return
	_escort_attempted = true
	if _merc_def.escort_def == null:
		return
	var spawner: Spawner = _find_spawner()
	if spawner == null:
		return
	var request: SpawnRequest = SpawnRequest.new()
	request.enemy_def = _merc_def.escort_def
	request.is_summoned = true
	request.grants_kill_rewards = false
	request.contributes_to_pressure = false
	if _spawn_context != null:
		request.wave_index = _spawn_context.wave_index
		request.stage_index = _spawn_context.stage_index
		request.elapsed_sec = _spawn_context.elapsed_sec
		request.wave_card = _spawn_context.wave_card
		request.enemy_combat_scaling = _spawn_context.enemy_combat_scaling
	var position: Vector3 = global_position + global_basis.x.normalized() * _merc_def.escort_offset
	_escort = spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, _merc_def.escort_def, position, request) as Enemy
	if _escort != null:
		_escort.set_meta("enforcer_escort", true)
		_escort.add_to_group(MercEscortWing.ESCORT_GROUP)
		_escort.set_meta(MercEscortWing.OWNER_META, get_instance_id())
		_escort.play_warp_in()

func _find_spawner() -> Spawner:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var spawners: Array[Node] = scene.find_children("*", "Spawner", true, false)
	if spawners.is_empty():
		return null
	return spawners[0] as Spawner

func _on_enforcer_died(_enemy: Enemy) -> void:
	_clear_encounter_runtime()

func _clear_encounter_runtime() -> void:
	if is_instance_valid(_attack):
		_attack.cancel()
	_attack = null
	_active_socket = null
	# A completed escort launch remains part of the battlefield after this owner.
	_escort = null

func _exit_tree() -> void:
	_clear_encounter_runtime()
	super._exit_tree()
