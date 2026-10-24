extends Node3D

const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const PROBE: GreyEnemyDef = preload("res://content/data/enemies/grey_probe_mk1.tres")
const SEEKER: GreyEnemyDef = preload("res://content/data/enemies/grey_seeker_mk1.tres")
const VESSEL: GreyEnemyDef = preload("res://content/data/enemies/grey_vessel_mk1.tres")

var _ship: Ship = null
var _spawner: Spawner = null
var _enemies: Array[GreyEnemy] = []
var _assertions: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Grey Validation":
		push_error("Grey checks require the isolated Fluxbreak Grey Validation project to protect production progress.")
		get_tree().quit(2)
		return
	call_deferred("_run_checks")

func _run_checks() -> void:
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "TestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.global_position = Vector3.ZERO
	_ship.hull = 100000.0
	_ship.shield = 0.0
	_ship.eff_evasion = 0.0
	_ship.eff_damage_taken_mult = 1.0
	_spawner = Spawner.new()
	_spawner.name = "TestSpawner"
	_spawner.ship_path = NodePath("../TestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	_spawner.min_distance_from_ship = 0.0
	add_child(_spawner)
	_test_shipped_actors()
	await _clear_enemies()
	_test_pulses()
	await _clear_enemies()
	_test_seeker_displacement()
	await _clear_enemies()
	await _test_vessel_tether()
	await _clear_enemies()
	await _test_movement_and_reacquisition()
	await _clear_enemies()
	print("GREY_REGULAR_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _assertions, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_enemy(enemy_def: GreyEnemyDef, position: Vector3, request: SpawnRequest = null) -> GreyEnemy:
	var enemy: GreyEnemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, enemy_def, position, request) as GreyEnemy
	if enemy == null:
		_check(false, "%s spawns through the real Spawner" % enemy_def.id)
		return null
	enemy.freeze = true
	enemy.set_physics_process(false)
	enemy.collision_layer = 0
	enemy.collision_mask = 0
	enemy.explosion_scene = null
	enemy._stop_warp_in()
	if enemy._regen_timer != null:
		enemy._regen_timer.stop()
	for audio_node: Node in enemy.find_children("*", "AudioStreamPlayer3D", true, false):
		var audio: AudioStreamPlayer3D = audio_node as AudioStreamPlayer3D
		audio.stream = null
	_enemies.append(enemy)
	return enemy

func _test_shipped_actors() -> void:
	var scaling: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
	scaling.hull_multiplier = 1.5
	scaling.damage_multiplier = 2.0
	var request: SpawnRequest = SpawnRequest.new()
	request.enemy_combat_scaling = scaling
	for enemy_def: GreyEnemyDef in [PROBE, SEEKER, VESSEL]:
		var enemy: GreyEnemy = _spawn_enemy(enemy_def, Vector3(0.0, 0.0, 220.0), request)
		if enemy == null:
			continue
		_check(enemy.def == enemy_def and enemy.get_faction_id() == &"greys", "%s retains its shipped Grey identity" % enemy_def.id)
		_check(enemy.is_in_group("targets") and enemy.visible, "%s remains targetable" % enemy_def.id)
		_check(enemy._spawn_context.grants_kill_rewards and enemy._spawn_context.contributes_to_pressure, "%s keeps ordinary reward and wave pressure accounting" % enemy_def.id)
		_check(is_equal_approx(enemy.eff_max_hull, enemy_def.max_hull * 1.5), "%s resolves combat hull scaling" % enemy_def.id)
		_check(enemy.get_visual_model_root() != null and enemy.get_muzzle_socket() != null, "%s satisfies the model and muzzle contract" % enemy_def.id)
		_check(enemy._controlled_turrets.size() > 0, "%s exposes a controlled turret" % enemy_def.id)
		for turret: EnemyTurret in enemy._controlled_turrets:
			_check(not turret.is_physics_processing(), "%s cannot fire hidden autonomous shots" % enemy_def.id)
			_check(is_equal_approx(turret.eff_damage_min, enemy_def.weapon.damage_min * 2.0), "%s keeps the scaled weapon snapshot" % enemy_def.id)
	_check(PROBE.behavior.max_speed > VESSEL.behavior.max_speed and PROBE.max_hull < VESSEL.max_hull, "Probe and Vessel retain distinct speed and durability")
	print("GREY_REGULAR_CHECKS: shipped models, identities, scaling, targeting and controlled weapons checked")

func _prepare_turret(enemy: GreyEnemy) -> void:
	var turret: EnemyTurret = enemy._first_valid_turret()
	turret.systems_bonus = 0.0
	turret.eff_base_accuracy = 1.0
	turret.eff_range_falloff = 0.0
	turret.eff_crit_chance = 0.0
	turret.eff_graze_on_hit = 0.0
	turret.eff_damage_min = 10.0
	turret.eff_damage_max = 10.0

func _test_pulses() -> void:
	for enemy_def: GreyEnemyDef in [PROBE, SEEKER, VESSEL]:
		_ship.global_position = Vector3.ZERO
		var enemy: GreyEnemy = _spawn_enemy(enemy_def, Vector3(0.0, 0.0, 220.0))
		if enemy == null:
			continue
		_prepare_turret(enemy)
		var hull_before: float = _ship.hull
		enemy._start_pulse("TEST PULSE")
		var pulse: EnemyAttackTelegraph = enemy._active_attack
		_check(is_instance_valid(pulse), "%s starts a visible delayed sphere" % enemy_def.id)
		if not is_instance_valid(pulse):
			continue
		pulse.set_physics_process(false)
		_check(pulse.is_warning_for(_ship) and pulse.get_attack_label() == "TEST PULSE", "%s exposes its warning to the HUD" % enemy_def.id)
		_check(is_equal_approx(_ship.hull, hull_before), "%s causes no damage at warning start" % enemy_def.id)
		pulse._physics_process(enemy_def.behavior.attack_windup_sec * 0.5)
		_check(is_equal_approx(_ship.hull, hull_before), "%s causes no damage midway through windup" % enemy_def.id)
		_ship.global_position = Vector3(enemy_def.behavior.attack_radius * 3.0, 0.0, 0.0)
		pulse._physics_process(enemy_def.behavior.attack_windup_sec)
		_check(is_equal_approx(_ship.hull, hull_before), "%s pulse can be avoided by leaving the locked volume" % enemy_def.id)
		_check(enemy._active_attack == null and enemy._recovery_left > 0.0, "%s exposes recovery after its pulse" % enemy_def.id)
		_ship.global_position = Vector3.ZERO
		enemy._recovery_left = 0.0
		enemy._start_pulse("TEST PULSE")
		pulse = enemy._active_attack
		pulse.set_physics_process(false)
		enemy._first_valid_turret().eff_damage_min = 1000.0
		enemy._first_valid_turret().eff_damage_max = 1000.0
		pulse._physics_process(enemy_def.behavior.attack_windup_sec + 0.01)
		_check(is_equal_approx(hull_before - _ship.hull, 10.0), "%s pulse retains the immutable damage captured at windup" % enemy_def.id)
		pulse._physics_process(0.05)
		_check(is_equal_approx(hull_before - _ship.hull, 10.0), "%s pulse cannot apply damage twice" % enemy_def.id)
	_ship.global_position = Vector3.ZERO
	print("GREY_REGULAR_CHECKS: locked pulse warning, dodge, recovery and immutable damage checked")

func _test_seeker_displacement() -> void:
	_ship.global_position = Vector3.ZERO
	var seeker: GreyEnemy = _spawn_enemy(SEEKER, Vector3(0.0, 0.0, 240.0))
	if seeker == null:
		return
	var origin: Vector3 = seeker.global_position
	var destination: Vector3 = seeker._pick_displacement_destination()
	var hull_before: float = _ship.hull
	_check(destination.distance_squared_to(origin) <= pow(SEEKER.behavior.displacement_distance + 0.01, 2.0), "Seeker displacement has a bounded travel distance")
	_check(destination.distance_squared_to(_ship.global_position) >= pow(SEEKER.behavior.displacement_min_player_distance - 0.01, 2.0), "Seeker destination preserves its requested player clearance")
	seeker._displacement_cooldown_left = 0.0
	seeker._tick_seeker()
	var displacement: GreyDisplacement = seeker._displacement
	_check(is_instance_valid(displacement) and displacement.is_active(), "Seeker starts an advertised displacement before moving")
	if not is_instance_valid(displacement):
		return
	displacement.set_physics_process(false)
	_check(displacement.find_children("*", "MeshInstance3D", true, false).size() > 0 and displacement._origin.is_equal_approx(origin) and displacement._destination.is_equal_approx(destination), "Both displacement endpoints are locked in the visible marker geometry")
	_check(seeker.is_in_group("targets") and seeker.visible, "Seeker stays targetable throughout displacement")
	displacement._physics_process(SEEKER.behavior.displacement_windup_sec * 0.5)
	_check(seeker.global_position.is_equal_approx(origin) and seeker._active_attack == null, "Seeker cannot teleport or attack during the endpoint warning")
	_ship.global_position = Vector3(0.0, 60.0, 0.0)
	displacement._physics_process(SEEKER.behavior.displacement_windup_sec)
	_check(seeker.global_position.is_equal_approx(destination), "Seeker moves to the originally marked destination after the full warning")
	_check(is_equal_approx(_ship.hull, hull_before), "Displacement itself causes no damage")
	_check(seeker._post_displacement_pulse and seeker._active_attack == null, "Relocation completes before a separate pulse can begin")
	seeker._tick_seeker()
	_check(is_instance_valid(seeker._active_attack) and seeker._active_attack.get_time_remaining() > 0.0, "Seeker follows relocation with a fresh dodgeable pulse countdown")
	_check(is_equal_approx(_ship.hull, hull_before), "The new post-displacement pulse still causes no instant damage")
	seeker._cancel_specials()
	seeker._post_displacement_pulse = true
	_ship.global_position = Vector3.RIGHT * 2000.0
	seeker._tick_seeker()
	_check(not seeker._post_displacement_pulse and seeker._active_attack == null, "Outrunning a relocation releases its pending followup so the Seeker resumes approach")
	_ship.global_position = Vector3.ZERO
	seeker._post_displacement_pulse = false
	seeker._recovery_left = 0.0
	seeker._displacement_cooldown_left = 0.0
	seeker._tick_seeker()
	displacement = seeker._displacement
	seeker.apply_damage(1000000.0)
	_check(not is_instance_valid(displacement) or displacement.is_queued_for_deletion(), "Killing a Seeker removes its pending endpoint warning")
	_ship.global_position = Vector3.ZERO
	print("GREY_REGULAR_CHECKS: locked displacement, targetability, harmless arrival and separate pulse checked")

func _test_vessel_tether() -> void:
	_ship.global_position = Vector3.ZERO
	var vessel: GreyEnemy = _spawn_enemy(VESSEL, Vector3(0.0, 0.0, 240.0))
	if vessel == null:
		return
	var hull_before: float = _ship.hull
	vessel._attack_cooldown_left = 0.0
	vessel._tick_vessel()
	var tether: GreyTether = vessel._tether
	_check(is_instance_valid(tether) and tether.is_active(), "Vessel starts one visible tether windup")
	if not is_instance_valid(tether):
		return
	tether.set_physics_process(false)
	_check(tether.is_warning_for(_ship) and not tether.is_attached(), "Vessel tether exposes a warning before attaching")
	_check(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Vessel applies no slow during the warning")
	tether._physics_process(VESSEL.behavior.tether_windup_sec * 0.5)
	_check(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Vessel cannot slow midway through its dodge window")
	_ship.global_position = Vector3(VESSEL.behavior.tether_radius * 3.0, 0.0, 0.0)
	tether._physics_process(VESSEL.behavior.tether_windup_sec)
	_check(not tether.is_attached() and is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Leaving the locked sphere avoids the tether entirely")
	_check(vessel._tether == null and vessel._recovery_left > 0.0, "Failed tether returns the Vessel to exposed recovery")
	# Start another capture before the failed helper leaves the tree. Its stale
	# exit callback must not clear a new link owned by this same Vessel.
	_ship.global_position = Vector3.ZERO
	vessel._vessel_next_pulse = false
	vessel._recovery_left = 0.0
	vessel._attack_cooldown_left = 0.0
	vessel._tick_vessel()
	tether = vessel._tether
	tether.set_physics_process(false)
	tether._physics_process(VESSEL.behavior.tether_windup_sec + 0.01)
	_check(tether.is_attached() and vessel._tether == tether, "Standing in the warning permits exactly one active tether")
	_check(_ship.get_movement_slow_multiplier() >= 0.65 and _ship.get_movement_slow_multiplier() < 1.0, "Attached tether slows movement within the shared safety bound")
	_check(_ship.get_tether_time_remaining() <= 3.0 and _ship.get_tether_time_remaining() > 0.0, "The slow carries a finite duration")
	_check(is_equal_approx(_ship.hull, hull_before) and vessel._active_attack == null, "Tether attachment causes no damage or overlapping Vessel pulse")
	var remaining_before_pause: float = _ship.get_tether_time_remaining()
	get_tree().paused = true
	for frame in range(5):
		await get_tree().process_frame
	get_tree().paused = false
	_check(tether.is_attached() and is_equal_approx(_ship.get_tether_time_remaining(), remaining_before_pause), "Pausing preserves the active tether countdown")
	_ship.global_position = vessel.global_position + Vector3.RIGHT * (VESSEL.behavior.tether_break_distance + 20.0)
	tether._physics_process(0.02)
	_check(not tether.is_attached() and is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Crossing the tether distance immediately restores normal movement")
	_check(_ship.is_tether_immune(), "A broken tether gives the player a recovery window before another capture")
	_check(vessel._vessel_next_pulse and vessel._recovery_left > 0.0, "Vessel alternates the ended tether with its pulse after recovery")
	_ship.global_position = Vector3.ZERO
	vessel._recovery_left = 0.0
	vessel._attack_cooldown_left = 0.0
	vessel._tick_vessel()
	_check(is_instance_valid(vessel._active_attack) and vessel._tether == null, "Vessel pulse has its own visible windup after the ended tether")
	vessel.player_ship = null
	vessel._target_scan_left = 10.0
	vessel._physics_process(0.01)
	_check(vessel._active_attack == null and vessel._tether == null, "Losing the player cancels every in-progress Vessel action")
	vessel.player_ship = _ship
	print("GREY_REGULAR_CHECKS: tether warning, dodge, pause, bounded slow, break, immunity and alternating pulse checked")

func _test_movement_and_reacquisition() -> void:
	_ship.global_position = Vector3.ZERO
	var probe: GreyEnemy = _spawn_enemy(PROBE, Vector3(0.0, 0.0, 600.0))
	probe.freeze = false
	probe._attack_cooldown_left = 100.0
	for frame in range(18):
		probe._tick_probe()
		await get_tree().physics_frame
	_check(probe.linear_velocity.dot((_ship.global_position - probe.global_position).normalized()) > 1.0, "Probe physically closes toward its standoff band")
	probe.freeze = true
	var vessel: GreyEnemy = _spawn_enemy(VESSEL, Vector3(0.0, 0.0, 100.0))
	vessel.freeze = false
	vessel._attack_cooldown_left = 100.0
	for frame in range(18):
		vessel._tick_vessel()
		await get_tree().physics_frame
	_check(vessel.linear_velocity.dot((_ship.global_position - vessel.global_position).normalized()) < -1.0, "Vessel physically retreats from close range")
	vessel.freeze = true
	vessel.player_ship = null
	vessel._target_scan_left = 0.0
	vessel._physics_process(0.01)
	_check(vessel.player_ship == _ship, "A Grey can reacquire a living player after a missing target reference")
	print("GREY_REGULAR_CHECKS: standoff movement and missing-target reacquisition checked")

func _clear_enemies() -> void:
	for enemy: GreyEnemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	for node: Node in get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		node.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(int(_spawner.get_alive_counts().get("enemies", 0)) == 0, "Grey cleanup returns Spawner accounting to zero")
	_check(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Grey cleanup cannot leave a persistent slow")

func _check(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("GREY_REGULAR_CHECKS: " + description)
