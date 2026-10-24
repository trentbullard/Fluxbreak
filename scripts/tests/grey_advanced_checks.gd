extends Node3D

const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const HARBINGER: GreyEnemyDef = preload("res://content/data/enemies/grey_harbinger_mk1.tres")
const MOTHERSHIP: GreyEnemyDef = preload("res://content/data/enemies/grey_mothership_mk1.tres")
const PROBE: GreyEnemyDef = preload("res://content/data/enemies/grey_probe_mk1.tres")
const VESSEL: GreyEnemyDef = preload("res://content/data/enemies/grey_vessel_mk1.tres")

var _ship: Ship = null
var _spawner: Spawner = null
var _enemies: Array[GreyEnemy] = []
var _assertions: int = 0
var _failures: int = 0

func _ready() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Grey Validation":
		push_error("Advanced Grey checks require the isolated Fluxbreak Grey Validation project.")
		get_tree().quit(2)
		return
	call_deferred("_run_checks")

func _run_checks() -> void:
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "AdvancedGreyTestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.hull = 100000.0
	_ship.shield = 0.0
	_ship.eff_evasion = 0.0
	_ship.eff_damage_taken_mult = 1.0
	_silence_audio(_ship)
	_spawner = Spawner.new()
	_spawner.ship_path = NodePath("../AdvancedGreyTestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	_spawner.min_distance_from_ship = 0.0
	add_child(_spawner)
	_test_shipped_actors()
	await _clear_enemies()
	_test_sequential_ruptures()
	await _clear_enemies()
	_test_mothership_cycle()
	await _clear_enemies()
	await _test_encounter_threat_limits()
	await _clear_enemies()
	await _test_cancellation_and_pause()
	await _clear_enemies()
	print("GREY_ADVANCED_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _assertions, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_enemy(enemy_def: GreyEnemyDef, position: Vector3 = Vector3(0.0, 0.0, 180.0)) -> GreyEnemy:
	var enemy: GreyEnemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, enemy_def, position) as GreyEnemy
	_check(enemy != null, "%s spawns through the real Spawner" % enemy_def.id)
	if enemy == null:
		return null
	_enemies.append(enemy)
	enemy.freeze = true
	enemy.set_physics_process(false)
	enemy.explosion_scene = null
	enemy._stop_warp_in()
	if enemy._regen_timer != null:
		enemy._regen_timer.stop()
	_silence_audio(enemy)
	var turret: EnemyTurret = enemy._first_valid_turret()
	if turret != null:
		turret.systems_bonus = 0.0
		turret.eff_base_accuracy = 1.0
		turret.eff_range_falloff = 0.0
		turret.eff_crit_chance = 0.0
		turret.eff_graze_on_hit = 0.0
		turret.eff_graze_on_miss = 0.0
		turret.eff_damage_min = 10.0
		turret.eff_damage_max = 10.0
	return enemy

func _silence_audio(root: Node) -> void:
	for node: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		var audio: AudioStreamPlayer3D = node as AudioStreamPlayer3D
		audio.stop()
		audio.stream = null

func _test_shipped_actors() -> void:
	for enemy_def: GreyEnemyDef in [HARBINGER, MOTHERSHIP]:
		var enemy: GreyEnemy = _spawn_enemy(enemy_def)
		if enemy == null:
			continue
		_check(enemy.def == enemy_def and enemy.get_faction_id() == &"greys", "%s retains its Grey identity" % enemy_def.id)
		_check(enemy.collision_layer == 8 and enemy.collision_mask == 0, "%s is targetable without body collisions" % enemy_def.id)
		_check(enemy.is_in_group("targets") and enemy.visible, "%s stays targetable" % enemy_def.id)
		_check(enemy.get_visual_model_root() != null and enemy.get_muzzle_socket() != null, "%s satisfies the model and muzzle contract" % enemy_def.id)
		_check(enemy._spawn_context.grants_kill_rewards and enemy._spawn_context.contributes_to_pressure, "%s participates in normal rewards and wave pressure" % enemy_def.id)
		_check(enemy._controlled_turrets.size() > 0, "%s has an authored weapon" % enemy_def.id)
		for turret: EnemyTurret in enemy._controlled_turrets:
			_check(not turret.is_physics_processing(), "%s cannot fire autonomous hidden shots" % enemy_def.id)
		_check(enemy_def.behavior.retreat_range <= 190.0, "%s stays in starter-gun reach" % enemy_def.id)
	_check(HARBINGER.tier == 4 and HARBINGER.behavior.mode == GreyBehaviorDef.Mode.HARBINGER, "Harbinger completes tier four with sequential ruptures")
	_check(MOTHERSHIP.tier == 5 and MOTHERSHIP.behavior.mode == GreyBehaviorDef.Mode.MOTHERSHIP, "Mothership completes tier five with coordinated actions")
	_check(GreyBehaviorDef.Mode.PROBE == 0 and GreyBehaviorDef.Mode.SEEKER == 1 and GreyBehaviorDef.Mode.VESSEL == 2, "Existing serialized Grey modes retain their values")

func _test_sequential_ruptures() -> void:
	_ship.global_position = Vector3.ZERO
	var enemy: GreyEnemy = _spawn_enemy(HARBINGER)
	if enemy == null:
		return
	var hull_before: float = _ship.hull
	enemy._attack_cooldown_left = 0.0
	enemy._tick_harbinger()
	var first: EnemyAttackTelegraph = enemy._active_attack
	_check(is_instance_valid(first), "Harbinger starts its first visible rupture")
	if not is_instance_valid(first):
		return
	first.set_physics_process(false)
	_check(first.get_attack_label() == "RUPTURE I" and not first._corridor, "First rupture clearly names its locked sphere")
	_check(first._locked_position.is_equal_approx(Vector3.ZERO), "First rupture locks the original player position")
	_check(first.get_time_remaining() >= HARBINGER.behavior.attack_windup_sec, "First rupture grants the full authored warning")
	first._physics_process(HARBINGER.behavior.attack_windup_sec * 0.5)
	_check(is_equal_approx(_ship.hull, hull_before), "First rupture deals no damage during warning")
	_ship.global_position = Vector3(HARBINGER.behavior.attack_radius * 2.5, 0.0, 0.0)
	var next_lock: Vector3 = _ship.global_position
	first._physics_process(HARBINGER.behavior.attack_windup_sec)
	_check(is_equal_approx(_ship.hull, hull_before), "Moving out of the first sphere guarantees a dodge")
	_check(enemy._active_attack == null and enemy._rupture_pulses_remaining == 1, "First rupture queues exactly one later warning")
	_check(enemy._rupture_gap_left >= HARBINGER.behavior.rupture_second_gap_sec, "The second lock waits for the quiet inter-rupture gap")
	enemy._tick_harbinger()
	_check(enemy._active_attack == null, "Second rupture cannot start in the first resolution callback")
	enemy._physics_process(HARBINGER.behavior.rupture_second_gap_sec * 0.5)
	_check(enemy._active_attack == null, "Second rupture waits through the gap")
	enemy._physics_process(maxf(HARBINGER.behavior.rupture_second_gap_sec, HARBINGER.behavior.attack_recovery_sec) + 0.01)
	var second: EnemyAttackTelegraph = enemy._active_attack
	_check(is_instance_valid(second), "Harbinger creates the second separately warned rupture after its gap")
	if not is_instance_valid(second):
		return
	second.set_physics_process(false)
	_check(second.get_attack_label() == "RUPTURE II" and second != first, "Second rupture has a distinct warning instance and name")
	_check(second._locked_position.is_equal_approx(next_lock), "Second rupture locks the player's later position")
	_check(second.get_time_remaining() >= HARBINGER.behavior.attack_windup_sec, "Second rupture grants another complete dodge window")
	_check(not second.contains_position(Vector3.ZERO), "Leaving the second lock remains a valid escape even at the first location")
	enemy._first_valid_turret().eff_damage_min = 1000.0
	enemy._first_valid_turret().eff_damage_max = 1000.0
	second._physics_process(HARBINGER.behavior.attack_windup_sec + 0.01)
	_check(is_equal_approx(hull_before - _ship.hull, 10.0), "Second rupture uses its immutable damage snapshot")
	second._physics_process(0.01)
	_check(is_equal_approx(hull_before - _ship.hull, 10.0), "Second rupture resolves damage only once")
	_check(enemy._rupture_pulses_remaining == 0 and enemy._recovery_left >= HARBINGER.behavior.attack_recovery_sec, "Two ruptures finish in full exposed recovery")
	enemy._attack_cooldown_left = 0.0
	enemy._tick_harbinger()
	_check(enemy._active_attack == null, "Harbinger cannot bypass its final recovery")
	_ship.global_position = Vector3.ZERO
	enemy._recovery_left = 0.0
	enemy._attack_cooldown_left = 0.0
	enemy._tick_harbinger()
	first = enemy._active_attack
	if is_instance_valid(first):
		first.set_physics_process(false)
		_ship.global_position = Vector3(10000.0, 0.0, 0.0)
		first._physics_process(HARBINGER.behavior.attack_windup_sec + 0.01)
		enemy._physics_process(0.01)
		_check(enemy._rupture_pulses_remaining == 0 and enemy._active_attack == null and enemy._recovery_left > 0.0, "Leaving weapon reach safely cancels the second rupture")
	_ship.global_position = Vector3.ZERO

func _test_mothership_cycle() -> void:
	_ship.global_position = Vector3.ZERO
	var enemy: GreyEnemy = _spawn_enemy(MOTHERSHIP)
	if enemy == null:
		return
	var hull_before: float = _ship.hull
	enemy._attack_cooldown_left = 0.0
	enemy._tick_mothership()
	var pulse: EnemyAttackTelegraph = enemy._active_attack
	_check(is_instance_valid(pulse) and enemy._tether == null and enemy._displacement == null, "Mothership begins with one isolated rupture warning")
	if not is_instance_valid(pulse):
		return
	pulse.set_physics_process(false)
	_ship.global_position = Vector3.UP * (MOTHERSHIP.behavior.attack_radius + 10.0)
	pulse._physics_process(MOTHERSHIP.behavior.attack_windup_sec + 0.01)
	_check(is_equal_approx(_ship.hull, hull_before), "The Mothership rupture remains dodgeable")
	_check(enemy._mothership_next_action == 1 and enemy._recovery_left >= MOTHERSHIP.behavior.mothership_action_gap_sec, "Rupture exposes recovery before the separate displacement")
	enemy._attack_cooldown_left = 0.0
	enemy._tick_mothership()
	_check(enemy._displacement == null, "Mothership cannot displace during rupture recovery")
	_ship.global_position = Vector3.ZERO
	enemy._recovery_left = 0.0
	enemy._tick_mothership()
	var displacement: GreyDisplacement = enemy._displacement
	_check(is_instance_valid(displacement), "Mothership's second action advertises both displacement endpoints")
	if not is_instance_valid(displacement):
		return
	displacement.set_physics_process(false)
	var destination: Vector3 = displacement._destination
	var origin: Vector3 = enemy.global_position
	_check(destination.distance_squared_to(origin) <= pow(MOTHERSHIP.behavior.displacement_distance + 0.01, 2.0), "Mothership displacement has bounded travel")
	_check(destination.distance_squared_to(_ship.global_position) <= 190.0 * 190.0, "Mothership's locked arrival stays in starter-gun reach")
	_check(enemy.is_in_group("targets") and enemy.visible, "Mothership stays targetable during relocation")
	displacement._physics_process(MOTHERSHIP.behavior.displacement_windup_sec * 0.5)
	_check(enemy.global_position.is_equal_approx(origin) and enemy._tether == null, "The endpoint warning creates no early move or capture")
	displacement._physics_process(MOTHERSHIP.behavior.displacement_windup_sec)
	_check(enemy.global_position.is_equal_approx(destination) and is_equal_approx(_ship.hull, hull_before), "Arrival is locked and completely harmless")
	_check(enemy._mothership_next_action == 2 and enemy._recovery_left > 0.0 and not enemy._post_displacement_pulse, "Arrival recovers before a separately warned tether rather than a Seeker pulse")
	enemy._attack_cooldown_left = 0.0
	enemy._tick_mothership()
	_check(enemy._tether == null, "Mothership cannot capture during displacement recovery")
	enemy._recovery_left = 0.0
	enemy._tick_mothership()
	var tether: GreyTether = enemy._tether
	_check(is_instance_valid(tether) and not tether.is_attached(), "Mothership's third action begins a fresh tether warning")
	if not is_instance_valid(tether):
		return
	tether.set_physics_process(false)
	_check(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Tether warning causes no immediate slow")
	tether._physics_process(MOTHERSHIP.behavior.tether_windup_sec + 0.01)
	_check(tether.is_attached() and _ship.get_tether_time_remaining() <= 3.0, "Standing in the capture allows a finite tether")
	_check(_ship.get_movement_slow_multiplier() >= 0.65 and is_equal_approx(_ship.hull, hull_before), "Mothership tether respects slow limits and causes no damage")
	_ship.global_position = enemy.global_position + Vector3.RIGHT * (MOTHERSHIP.behavior.tether_break_distance + 20.0)
	tether._physics_process(0.01)
	_check(enemy._tether == null and enemy._mothership_next_action == 0 and enemy._recovery_left > 0.0, "Breaking the tether recovers before the next rupture cycle")
	_check(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Breaking the link restores normal movement")
	_ship.global_position = Vector3.ZERO
	_ship._tether_immunity_sec = 0.0

func _test_encounter_threat_limits() -> void:
	_ship.global_position = Vector3.ZERO
	var probe: GreyEnemy = _spawn_enemy(PROBE)
	var harbinger: GreyEnemy = _spawn_enemy(HARBINGER)
	var vessel: GreyEnemy = _spawn_enemy(VESSEL)
	var mothership: GreyEnemy = _spawn_enemy(MOTHERSHIP)
	if probe == null or harbinger == null or vessel == null or mothership == null:
		return
	_check(probe._start_pulse("FIRST SLOT") and harbinger._start_pulse("SECOND SLOT"), "Two different Grey actors can fill the two major volume slots")
	probe._active_attack.set_physics_process(false)
	harbinger._active_attack.set_physics_process(false)
	_check(not mothership._start_pulse("THIRD SLOT") and mothership._active_attack == null, "A third actor cannot exceed the encounter-wide volume cap")
	_check(mothership._attack_cooldown_left >= GreyEnemy.THREAT_RETRY_SEC, "A full encounter schedules a bounded retry instead of a frame-by-frame busy retry")
	_check(not vessel._start_tether() and vessel._tether == null, "Capture warnings also consume the two-volume budget")
	probe._cancel_specials()
	harbinger._cancel_specials()
	_check(vessel._start_tether(), "A freed volume slot allows one new tether warning")
	var tether: GreyTether = vessel._tether
	if not is_instance_valid(tether):
		return
	tether.set_physics_process(false)
	_check(not mothership._start_tether() and mothership._tether == null, "A pending tether reserves the unique encounter tether slot")
	_check(mothership._start_pulse("BESIDE CAPTURE"), "One damage warning may coexist with one capture warning")
	mothership._active_attack.set_physics_process(false)
	_check(not harbinger._start_pulse("OVERFLOW"), "Capture plus damage still blocks a third major volume")
	tether._physics_process(VESSEL.behavior.tether_windup_sec + 0.01)
	_check(tether.is_attached(), "The capped capture may resolve into an attached link")
	mothership._cancel_specials()
	_check(GreyThreatLimiter.can_start_pulse(harbinger), "An attached tether leaves exactly one damage slot available")
	_check(not GreyThreatLimiter.can_start_tether(mothership), "An attached tether retains the unique tether slot")
	_check(harbinger._start_pulse("ALONGSIDE LINK"), "A damage warning can use the remaining slot beside an attached link")
	harbinger._active_attack.set_physics_process(false)
	_check(not probe._start_pulse("LINK OVERFLOW"), "An attached link counts toward the volume cap")
	harbinger._cancel_specials()
	tether.cancel()
	_ship._tether_immunity_sec = 0.0
	_check(GreyThreatLimiter.can_start_tether(mothership), "Ending a link immediately releases its slot, before queued cleanup")
	_check(probe._start_pulse("RESOLUTION FLASH"), "A fresh warning may begin after cleanup")
	var flash: EnemyAttackTelegraph = probe._active_attack
	flash.set_physics_process(false)
	_ship.global_position = Vector3.UP * 200.0
	flash._physics_process(PROBE.behavior.attack_windup_sec + 0.01)
	_check(flash._has_resolved and not flash._active, "The old warning becomes only a resolved visual flash")
	_check(harbinger._start_pulse("AFTER FLASH ONE") and mothership._start_pulse("AFTER FLASH TWO"), "A resolved flash does not consume either active danger slot")
	harbinger._active_attack.set_physics_process(false)
	mothership._active_attack.set_physics_process(false)
	_check(not GreyThreatLimiter.can_start_pulse(vessel), "Two replacement warnings still consume both active slots")
	harbinger._dead = true
	_check(GreyThreatLimiter.can_start_pulse(vessel), "Dead sources cannot reserve lingering threat slots")
	harbinger._dead = false
	await get_tree().process_frame
	_ship.global_position = Vector3.ZERO

func _test_cancellation_and_pause() -> void:
	_ship.global_position = Vector3.ZERO
	var enemy: GreyEnemy = _spawn_enemy(HARBINGER)
	if enemy == null:
		return
	enemy._attack_cooldown_left = 0.0
	enemy._tick_harbinger()
	var pulse: EnemyAttackTelegraph = enemy._active_attack
	if not is_instance_valid(pulse):
		return
	var remaining: float = pulse.get_time_remaining()
	get_tree().paused = true
	for frame: int in range(5):
		await get_tree().process_frame
	get_tree().paused = false
	_check(is_equal_approx(pulse.get_time_remaining(), remaining), "Pausing preserves the Harbinger warning countdown")
	pulse.set_physics_process(false)
	_ship.global_position = Vector3.UP * 200.0
	pulse._physics_process(HARBINGER.behavior.attack_windup_sec + 0.01)
	_check(enemy._rupture_pulses_remaining == 1, "First resolution prepares the pending second warning")
	_ship.visible = false
	enemy._physics_process(0.01)
	_check(enemy._active_attack == null and enemy._rupture_pulses_remaining == 0 and enemy._rupture_gap_left <= 0.0, "Losing the player cancels the queued second rupture")
	_ship.visible = true
	_ship.global_position = Vector3.ZERO
	enemy._recovery_left = 0.0
	enemy._attack_cooldown_left = 0.0
	enemy._tick_harbinger()
	pulse = enemy._active_attack
	if is_instance_valid(pulse):
		pulse.set_physics_process(false)
		_ship.global_position = Vector3.UP * 200.0
		pulse._physics_process(HARBINGER.behavior.attack_windup_sec + 0.01)
	enemy.apply_damage(1000000.0)
	_check(enemy._rupture_pulses_remaining == 0 and enemy._active_attack == null, "Death cancels future rupture locks")
	_ship.global_position = Vector3.ZERO
	var mothership: GreyEnemy = _spawn_enemy(MOTHERSHIP)
	if mothership == null:
		return
	mothership._mothership_next_action = 1
	mothership._attack_cooldown_left = 0.0
	mothership._tick_mothership()
	var displacement: GreyDisplacement = mothership._displacement
	_check(is_instance_valid(displacement), "Cleanup test starts a displacement")
	mothership._cancel_specials()
	_check(mothership._displacement == null and mothership._mothership_next_action == 0 and not mothership._post_displacement_pulse, "Cancelling a displacement cannot requeue an action through its completion signal")
	_check(not is_instance_valid(displacement) or displacement.is_queued_for_deletion(), "Cancelled displacement removes both arrival markers")
	mothership._mothership_next_action = 2
	mothership._recovery_left = 0.0
	mothership._attack_cooldown_left = 0.0
	mothership._tick_mothership()
	var tether: GreyTether = mothership._tether
	_check(is_instance_valid(tether), "Cleanup test starts a tether capture")
	if is_instance_valid(tether):
		tether.set_physics_process(false)
		tether._physics_process(MOTHERSHIP.behavior.tether_windup_sec + 0.01)
		_check(tether.is_attached(), "Cleanup test attaches the finite link")
	mothership.queue_free()
	await get_tree().process_frame
	_check(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Owner exit cannot leave a persistent tether slow")
	_check(not is_instance_valid(tether) or tether.is_queued_for_deletion(), "Owner exit removes the active tether warning")
	_ship._tether_immunity_sec = 0.0

func _clear_enemies() -> void:
	for enemy: GreyEnemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	for node: Node in get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		node.queue_free()
	for node: Node in get_tree().get_nodes_in_group("grey_displacements"):
		node.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(int(_spawner.get_alive_counts().get("enemies", 0)) == 0, "Advanced Grey cleanup restores Spawner counts")
	_check(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Advanced Grey cleanup leaves no movement slow")
	_ship._tether_immunity_sec = 0.0

func _check(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("GREY_ADVANCED_CHECKS: " + description)
