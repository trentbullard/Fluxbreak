extends Node3D

const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const QUEEN_PATH: String = "res://content/data/enemies/bug_first_queen_mk1.tres"
const PRACTICE_PATH: String = "res://content/data/enemies/bug_first_queen_practice.tres"

var _ship: Ship = null
var _spawner: Spawner = null
var _definition: BugQueenDef = null
var _bosses: Array[BugFirstQueen] = []
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Bug Validation":
		push_error("Queen checks require the isolated Fluxbreak Bug Validation project.")
		get_tree().quit(2)
		return
	_definition = load(QUEEN_PATH) as BugQueenDef
	_expect(_definition != null, "The shipped First Queen definition loads")
	if _definition == null:
		get_tree().quit(1)
		return
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "TestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.eff_damage_taken_mult = 1.0
	_ship.eff_evasion = 0.0
	_ship.hull = 100000.0
	_ship.shield = 100000.0
	_spawner = Spawner.new()
	_spawner.name = "TestSpawner"
	_spawner.ship_path = NodePath("../TestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	add_child(_spawner)
	await _check_definition_and_phases()
	await _clear_bosses()
	await _check_brood_warning_and_repeated_releases()
	await _clear_bosses()
	await _check_spores_and_pause()
	await _clear_bosses()
	await _check_locked_charge()
	await _clear_bosses()
	await _check_cleanup()
	await _clear_bosses()
	print("BUG_QUEEN_CHECKS: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_boss(scaled: bool = false) -> BugFirstQueen:
	_ship.global_position = Vector3.ZERO
	_ship.visible = true
	_ship._dead = false
	_ship.hull = 100000.0
	_ship.shield = 100000.0
	var definition: BugQueenDef = _definition.duplicate(false) as BugQueenDef
	definition.charge_windup_sec = 0.35
	definition.charge_move_sec = 0.25
	definition.brood_windup_sec = 0.5
	definition.spore_windup_sec = 0.5
	definition.recovery_sec = 0.25
	definition.cadence_sec = 0.1
	var request: SpawnRequest = SpawnRequest.new()
	request.enemy_def = definition
	request.wave_index = 29
	request.stage_index = 2
	if scaled:
		var scaling: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
		scaling.hull_multiplier = 1.5
		scaling.damage_multiplier = 2.0
		request.enemy_combat_scaling = scaling
	var boss: BugFirstQueen = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, definition, Vector3(0.0, 0.0, -340.0), request) as BugFirstQueen
	_expect(boss != null, "First Queen spawns through the actual Spawner")
	if boss == null:
		return null
	boss.freeze = true
	boss.explosion_scene = null
	boss.process_mode = Node.PROCESS_MODE_PAUSABLE
	boss.set_physics_process(false)
	_bosses.append(boss)
	return boss

func _check_definition_and_phases() -> void:
	var practice: BugQueenDef = load(PRACTICE_PATH) as BugQueenDef
	_expect(practice != null and practice.max_hull < _definition.max_hull, "Practice uses a shorter Queen with the full campaign mechanics")
	_expect(_definition.max_shield == 0.0 and practice != null and practice.max_shield == 0.0, "Both organic Queen variants have no shield")
	_expect(_definition.charge_windup_sec >= 1.8 and _definition.spore_windup_sec >= 1.8 and _definition.recovery_sec >= 2.2, "Shipped warning and exposed recovery windows stay readable")
	var boss: BugFirstQueen = _spawn_boss(true)
	if boss == null:
		return
	_expect(boss.collision_layer == 8 and boss.collision_mask == 0, "Queen target volume stays enabled while the body is nonblocking")
	_expect(is_equal_approx(boss.eff_max_hull, _definition.max_hull * 1.5), "Queen hull inherits the normal encounter scaling")
	_expect(not boss._weapon_sockets.is_empty(), "Queen model has a configured boss weapon socket")
	for socket: BossWeaponSocket in boss._weapon_sockets:
		_expect(is_equal_approx(socket.eff_damage_min, socket.weapon.damage_min * 2.0), "Queen socket damage inherits encounter scaling")
	boss._update_weapons(_ship, 0.0)
	_expect(boss.get_phase() == 1, "The Queen begins in phase one")
	boss.apply_damage(boss.eff_max_hull * 0.31)
	boss._update_weapons(_ship, 0.0)
	_expect(boss.get_phase() == 2 and int(boss.get_meta("bug_phase")) == 2, "Actual hull crossing seventy percent adds phase two")
	boss.apply_damage(boss.eff_max_hull * 0.35)
	boss._update_weapons(_ship, 0.0)
	_expect(boss.get_phase() == 3, "Actual hull crossing thirty five percent adds the final phase")
	var before: float = boss.hull
	boss._begin_recovery()
	boss.apply_damage(1.0)
	_expect(is_equal_approx(boss.hull, before - 1.0), "Queen stays damageable during recovery and phase transitions")
	boss._update_weapons(_ship, 0.3)
	_expect(boss.get_attack_state() == &"cadence" and is_equal_approx(boss._state_remaining_sec, 0.1 * _definition.final_phase_cadence_multiplier), "Final phase shortens only the quiet cadence")
	boss._begin_recovery()
	_expect(is_equal_approx(boss._state_remaining_sec, 0.25), "Final phase retains the complete recovery window")
	boss._sequence_index = 0
	boss._begin_attack(_ship)
	_expect(boss.get_attack_state() == &"spores", "Final phase begins with a familiar marked spore attack")
	_expect(boss._attack == null and boss._brood_warning == null, "A spore attack never overlaps another major attack")
	await _wait(0.05)

func _check_brood_warning_and_repeated_releases() -> void:
	var boss: BugFirstQueen = _spawn_boss(true)
	if boss == null:
		return
	var health_before: float = _ship.hull + _ship.shield
	var original_scale: Vector3 = boss.get_visual_model_root().scale
	boss._begin_attack(_ship)
	_expect(boss.get_attack_state() == &"brood" and is_instance_valid(boss._brood_warning), "Opening brood attack announces a harmless swelling countdown")
	boss._update_weapons(_ship, 0.2)
	_expect(boss.get_brood_spawner().get_total_spawned() == 0, "Brood cannot appear before its warning completes")
	_expect(boss.get_visual_model_root().scale.x > original_scale.x, "Queen visibly swells during her brood warning")
	boss._update_weapons(_ship, 0.4)
	_quiet_brood()
	_expect(boss.get_brood_spawner().get_total_spawned() == _definition.brood_release_count, "Opening release produces the configured brood batch")
	_expect(boss.get_attack_state() == &"recovery" and boss.get_visual_model_root().scale.is_equal_approx(original_scale), "Brood release restores the silhouette and exposes a recovery")
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Brood release itself cannot deal hidden damage")
	var brood: BugBroodSpawner = boss.get_brood_spawner()
	for release: int in range(6):
		_expect(brood.spawn_brood(3) == 3, "Queen releases each complete batch beyond former living and lifetime limits")
		_quiet_brood()
	_expect(brood.get_living_count() == _definition.brood_release_count + 18, "All surviving Queen offspring remain independently alive")
	for node: Node in get_tree().get_nodes_in_group("bug_brood"):
		var child: Enemy = node as Enemy
		_expect(child._spawn_context.is_summoned and not child._spawn_context.grants_kill_rewards and not child._spawn_context.contributes_to_pressure, "Queen offspring cannot farm rewards or pressure")
		_expect(child._spawn_context.stage_index == 2 and child._spawn_context.wave_index == 29 and is_equal_approx(child.eff_max_hull, child.def.max_hull * 1.5), "Queen offspring inherit the resolved encounter context")
	var second: BugFirstQueen = _spawn_boss()
	if second != null:
		_expect(second.get_brood_spawner().spawn_brood(3) == 3, "Another Queen can release despite existing living brood")
		_quiet_brood()

func _check_spores_and_pause() -> void:
	var boss: BugFirstQueen = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	boss._sequence_index = 1
	boss._begin_attack(_ship)
	var zone: BugSporeZone = boss._spore_zone
	_expect(is_instance_valid(zone) and boss.get_attack_state() == &"spores", "Phase one teaches a shared marked spore sphere")
	if not is_instance_valid(zone):
		return
	var locked: Vector3 = zone.global_position
	var health_before: float = _ship.hull + _ship.shield
	_ship.global_position = Vector3(220.0, 240.0, 0.0)
	await _wait(0.15)
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Spore spheres cannot damage during their warning")
	var warning_left: float = zone.get_time_remaining()
	get_tree().paused = true
	await _wait(0.6)
	_expect(is_equal_approx(zone.get_time_remaining(), warning_left) and zone.get_pulses_resolved() == 0, "Pausing freezes the complete Queen spore sequence")
	get_tree().paused = false
	await _wait(0.45)
	_expect(zone.get_pulses_resolved() == 1 and zone.global_position.is_equal_approx(locked), "First spore release retains its immutable world position")
	boss._update_weapons(_ship, 100.0)
	_expect(boss.get_attack_state() == &"spores" and boss._attack == null and boss._brood_warning == null, "Queen waits for every spore pulse instead of overlapping the next attack")
	await _wait(0.85)
	_expect(not is_instance_valid(zone) and boss.get_attack_state() == &"recovery", "The finite two-pulse sphere expires before full exposed recovery")
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Escaping the sphere vertically avoids both pulses")
	_ship.global_position = Vector3.ZERO
	boss._sequence_index = 1
	boss._begin_attack(_ship)
	await _wait(1.6)
	_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 24.0), "Remaining inside receives exactly two configured pulses")
	await _wait(0.4)
	_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 24.0), "Expired spore spheres cannot deal further damage")

func _check_locked_charge() -> void:
	var boss: BugFirstQueen = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	boss.hull = boss.eff_max_hull * 0.6
	boss._update_weapons(_ship, 0.0)
	boss._sequence_index = 2
	boss._begin_attack(_ship)
	_expect(boss.get_attack_state() == &"charge_windup" and is_instance_valid(boss._attack), "Phase two adds a separate fully warned charge corridor")
	var health_before: float = _ship.hull + _ship.shield
	var destination: Vector3 = boss._charge_destination
	_expect(boss._attack.contains_position(destination), "Charge warning includes the entire committed overshoot endpoint")
	await _wait(0.1)
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Charge warning applies no damage before release")
	_ship.global_position = Vector3(200.0, 200.0, 0.0)
	boss.freeze = false
	var start: Vector3 = boss.global_position
	await _wait(0.35)
	_expect(boss.get_attack_state() == &"charge", "Warned charge release begins committed travel")
	_expect(boss._charge_destination.is_equal_approx(destination) and absf(boss.linear_velocity.x) < 0.01 and absf(boss.linear_velocity.y) < 0.01, "Moving the player cannot steer the locked charge")
	_expect(boss.global_position.z > start.z + 25.0, "The Queen physically follows the warned corridor")
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Leaving the three dimensional corridor avoids the charge")
	boss._update_weapons(_ship, 0.3)
	boss.freeze = true
	_expect(boss.get_attack_state() == &"recovery" and boss.linear_velocity.is_zero_approx(), "Committed charge ends in a stationary exposed recovery")
	await _clear_bosses()
	boss = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	boss.hull = boss.eff_max_hull * 0.6
	boss._update_weapons(_ship, 0.0)
	boss._sequence_index = 2
	boss._begin_attack(_ship)
	health_before = _ship.hull + _ship.shield
	await _wait(0.45)
	_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 12.0), "Remaining inside the corridor receives exactly one hit")
	await _wait(0.4)
	_expect(is_equal_approx(health_before - _ship.hull - _ship.shield, 12.0), "Queen travel cannot add contact damage")

func _check_cleanup() -> void:
	var boss: BugFirstQueen = _spawn_boss()
	if boss == null:
		return
	_make_socket_deterministic(boss)
	boss.get_brood_spawner().spawn_brood(2)
	_quiet_brood()
	boss._sequence_index = 1
	boss._begin_attack(_ship)
	var zone: BugSporeZone = boss._spore_zone
	var health_before: float = _ship.hull + _ship.shield
	boss.apply_damage(1000000.0)
	await _wait(0.7)
	_expect(not is_instance_valid(zone) and get_tree().get_nodes_in_group("bug_spore_zones").is_empty(), "Queen death cancels every pending spore pulse")
	_expect(is_equal_approx(_ship.hull + _ship.shield, health_before), "Dead Queen attacks cannot damage the player")
	_expect(int(_spawner.get_alive_counts()["enemies"]) == 2, "Queen death retains her living brood in real Spawner accounting")
	boss = _spawn_boss()
	if boss == null:
		return
	boss.get_brood_spawner().spawn_brood(2)
	_quiet_brood()
	boss._sequence_index = 1
	boss._begin_attack(_ship)
	zone = boss._spore_zone
	_ship._dead = true
	boss.set_physics_process(true)
	await _wait(0.1)
	_expect(not is_instance_valid(zone) and boss.get_brood_spawner().get_living_count() == 2, "Player death cancels Queen attacks while children await actual run teardown")
	boss.set_physics_process(false)
	_ship._dead = false
	boss.get_brood_spawner().spawn_brood(2)
	_quiet_brood()
	boss._sequence_index = 1
	boss._begin_attack(_ship)
	zone = boss._spore_zone
	boss.queue_free()
	await _wait(0.7)
	_expect(not is_instance_valid(zone) and int(_spawner.get_alive_counts()["enemies"]) == 6, "Removing a Queen cancels her warnings while existing children persist")

func _make_socket_deterministic(boss: BugFirstQueen) -> void:
	for socket: BossWeaponSocket in boss._weapon_sockets:
		socket.eff_base_accuracy = 1.0
		socket.eff_range_falloff = 0.0
		socket.eff_crit_chance = 0.0
		socket.eff_graze_on_hit = 0.0
		socket.eff_graze_on_miss = 0.0
		socket.eff_damage_min = 12.0
		socket.eff_damage_max = 12.0

func _quiet_brood() -> void:
	for node: Node in get_tree().get_nodes_in_group("bug_brood"):
		var child: Enemy = node as Enemy
		child.freeze = true
		child.process_mode = Node.PROCESS_MODE_DISABLED
		child.explosion_scene = null

func _clear_bosses() -> void:
	for child: Node in get_tree().get_nodes_in_group("bug_brood"):
		child.queue_free()
	for boss: BugFirstQueen in _bosses:
		if is_instance_valid(boss) and not boss.is_queued_for_deletion():
			boss.queue_free()
	_bosses.clear()
	await _wait(0.1)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("BUG_QUEEN_CHECKS: " + description)
