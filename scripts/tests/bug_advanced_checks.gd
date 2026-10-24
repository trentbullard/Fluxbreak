extends Node3D

const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const DEVOURER: BugEnemyDef = preload("res://content/data/enemies/bug_devourer_mk1.tres")
const HIVE_QUEEN: BugEnemyDef = preload("res://content/data/enemies/bug_hive_queen_mk1.tres")
const BROODMOTHER: BugEnemyDef = preload("res://content/data/enemies/bug_broodmother_mk1.tres")
const SPORELING: BugEnemyDef = preload("res://content/data/enemies/bug_sporeling_mk1.tres")

var _ship: Ship = null
var _spawner: Spawner = null
var _assertions: int = 0
var _failures: int = 0

func _ready() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Bug Validation":
		push_error("Advanced Bug checks require the isolated Fluxbreak Bug Validation project.")
		get_tree().quit(2)
		return
	call_deferred("_run_checks")

func _run_checks() -> void:
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "AdvancedBugTestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.hull = 100000.0
	_ship.shield = 0.0
	_ship.eff_evasion = 0.0
	_ship.eff_damage_taken_mult = 1.0
	_silence_audio(_ship)
	_spawner = Spawner.new()
	_spawner.ship_path = NodePath("../AdvancedBugTestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	_spawner.min_distance_from_ship = 0.0
	add_child(_spawner)
	_test_shipped_actors()
	await _clear_enemies()
	await _test_devourer_charge()
	await _clear_enemies()
	await _test_hive_alternation()
	await _clear_enemies()
	await _test_spore_pulses_and_pause()
	await _clear_enemies()
	await _test_zone_caps_and_cleanup()
	await _clear_enemies()
	await _test_shared_brood_caps()
	await _clear_enemies()
	print("BUG_ADVANCED_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _assertions, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_enemy(enemy_def: BugEnemyDef, position: Vector3, request: SpawnRequest = null) -> BugEnemy:
	var enemy: BugEnemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, enemy_def, position, request) as BugEnemy
	_check(enemy != null, "%s spawns through the real Spawner" % enemy_def.id)
	if enemy != null:
		_freeze_enemy(enemy)
	return enemy

func _freeze_enemy(enemy: Enemy) -> void:
	enemy.freeze = true
	enemy.set_physics_process(false)
	enemy.explosion_scene = null
	enemy._stop_warp_in()
	if enemy._regen_timer != null:
		enemy._regen_timer.stop()
	_silence_audio(enemy)

func _silence_audio(root: Node) -> void:
	for audio_node: Node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		var audio: AudioStreamPlayer3D = audio_node as AudioStreamPlayer3D
		audio.stop()
		audio.stream = null

func _test_shipped_actors() -> void:
	for enemy_def: BugEnemyDef in [DEVOURER, HIVE_QUEEN]:
		var enemy: BugEnemy = _spawn_enemy(enemy_def, Vector3(0.0, 0.0, 240.0))
		if enemy == null:
			continue
		_check(enemy.def == enemy_def and enemy.get_faction_id() == &"bugs", "%s retains its shipped Bug identity" % enemy_def.id)
		_check(enemy.collision_layer == 8 and enemy.collision_mask == 0, "%s remains targetable and has no physical collision" % enemy_def.id)
		_check(enemy.get_visual_model_root() != null and enemy.get_muzzle_socket() != null, "%s retains its model and muzzle contracts" % enemy_def.id)
		_check(enemy.eff_max_shield == 0.0, "%s uses biological hull durability" % enemy_def.id)
		_check(not enemy._controlled_turrets.is_empty(), "%s has an authored weapon snapshot" % enemy_def.id)
		for turret: EnemyTurret in enemy._controlled_turrets:
			_check(not turret.is_physics_processing(), "%s cannot fire an unmarked autonomous shot" % enemy_def.id)
	_check(DEVOURER.tier == 4 and DEVOURER.behavior.mode == BugBehaviorDef.Mode.DEVOURER, "Devourer completes tier four with a distinct charge behavior")
	_check(HIVE_QUEEN.tier == 5 and HIVE_QUEEN.behavior.mode == BugBehaviorDef.Mode.HIVE_QUEEN, "Hive Queen completes tier five with a distinct command behavior")
	_check(HIVE_QUEEN.behavior.retreat_range <= 300.0, "Hive Queen's standoff remains reachable with the starter weapon")
	_check(HIVE_QUEEN.brood_child_def == SPORELING, "Hive Queen releases ordinary Sporelings")
	_check(BugBehaviorDef.Mode.SPORELING == 0 and BugBehaviorDef.Mode.CARAPACE == 1 and BugBehaviorDef.Mode.BROODMOTHER == 2, "Existing serialized Bug modes retain their values")

func _test_devourer_charge() -> void:
	_ship.global_position = Vector3.ZERO
	var enemy: BugEnemy = _spawn_enemy(DEVOURER, Vector3(0.0, 0.0, 220.0))
	if enemy == null:
		return
	_set_test_weapon(enemy._first_valid_turret(), 10.0)
	var hull_before: float = _ship.hull
	enemy._attack_cooldown_left = 0.0
	enemy._tick_devourer(0.01)
	var attack: EnemyAttackTelegraph = enemy._active_attack
	_check(is_instance_valid(attack), "Devourer begins a visible corridor warning in range")
	if not is_instance_valid(attack):
		return
	attack.set_physics_process(false)
	var locked_direction: Vector3 = enemy._charge_direction
	var endpoint: Vector3 = enemy._charge_endpoint
	_check(attack.get_attack_label().contains("DEVOURER CHARGE") and attack._corridor, "Devourer names and draws its committed corridor")
	_check(attack._locked_position.is_equal_approx(endpoint), "The warning includes the actual physical overshoot endpoint")
	_check((endpoint - _ship.global_position).dot(locked_direction) > 1.0, "Devourer's path overshoots the snapshotted player position")
	_check(is_equal_approx(_ship.hull, hull_before), "Starting the charge warning causes no damage")
	attack._physics_process(DEVOURER.behavior.attack_windup_sec * 0.5)
	enemy._tick_devourer(0.01)
	_check(is_equal_approx(_ship.hull, hull_before), "The charge remains harmless during contraction")
	_check(not enemy._animated_model.scale.is_equal_approx(enemy._rest_model_scale), "Devourer contracts its body during windup")
	_ship.global_position = Vector3(DEVOURER.behavior.attack_radius * 4.0, 0.0, 0.0)
	attack._physics_process(DEVOURER.behavior.attack_windup_sec)
	_check(is_equal_approx(_ship.hull, hull_before), "Leaving the locked charge corridor guarantees a dodge")
	_check(enemy._charge_time_left > 0.0 and enemy._active_attack == null, "Resolving the warning begins bounded physical travel")
	await get_tree().physics_frame
	enemy.freeze = false
	var start_position: Vector3 = enemy.global_position
	for frame: int in range(30):
		_ship.global_position = Vector3(300.0, 150.0, 0.0)
		enemy._tick_devourer(1.0 / 60.0)
		await get_tree().physics_frame
	_check((enemy.global_position - start_position).dot(locked_direction) > 20.0, "Devourer physically travels along its locked vector")
	_check(enemy._charge_direction.is_equal_approx(locked_direction) and enemy._charge_endpoint.is_equal_approx(endpoint), "Moving the player cannot redirect an active charge")
	_check(absf((enemy.global_position - start_position).cross(locked_direction).length()) < 1.0, "Committed travel does not curve toward the moving player")
	_check(is_equal_approx(_ship.hull, hull_before), "Physical travel and body overlap cannot add contact damage")
	for frame: int in range(240):
		if enemy._charge_time_left <= 0.0:
			break
		enemy._tick_devourer(1.0 / 60.0)
		await get_tree().physics_frame
	enemy.freeze = true
	_check(enemy._charge_time_left <= 0.0 and enemy._recovery_left > 0.0, "Charge travel expires into an exposed recovery")
	_check(enemy.linear_velocity.length_squared() < 0.1, "Devourer stops its committed motion for recovery")
	enemy._attack_cooldown_left = 0.0
	enemy._tick_devourer(0.01)
	_check(enemy._active_attack == null, "Devourer cannot attack during exposed recovery")
	_ship.global_position = Vector3.ZERO
	enemy.global_position = Vector3(0.0, 0.0, 220.0)
	enemy._recovery_left = 0.0
	enemy._attack_cooldown_left = 0.0
	_set_test_weapon(enemy._first_valid_turret(), 10.0)
	enemy._tick_devourer(0.01)
	attack = enemy._active_attack
	_check(is_instance_valid(attack), "Devourer can begin its next charge after recovery")
	if is_instance_valid(attack):
		attack.set_physics_process(false)
		_set_test_weapon(enemy._first_valid_turret(), 1000.0)
		attack._physics_process(DEVOURER.behavior.attack_windup_sec + 0.01)
		_check(is_equal_approx(hull_before - _ship.hull, 10.0), "Charge damage uses the immutable weapon snapshot")
		attack._physics_process(0.01)
		_check(is_equal_approx(hull_before - _ship.hull, 10.0), "One charge warning can resolve damage only once")
	_ship.visible = false
	enemy._physics_process(0.01)
	_check(enemy._charge_time_left <= 0.0 and enemy.linear_velocity.length_squared() < 0.1, "Losing the player cancels committed motion")
	_ship.visible = true

func _test_hive_alternation() -> void:
	_ship.global_position = Vector3.ZERO
	var hive: BugEnemy = _spawn_enemy(HIVE_QUEEN, Vector3(0.0, 0.0, 240.0))
	if hive == null:
		return
	_check(is_instance_valid(hive._brood), "Hive Queen owns the shared finite brood helper")
	hive._brood_interval_left = 0.0
	hive._zone_interval_left = 0.0
	hive._tick_hive_queen(0.01)
	_check(hive._brood_windup_left > 0.0 and hive._brood_label.visible, "Hive Queen advertises its first brood pulse")
	_check(hive._brood.get_total_spawned() == 0 and hive._active_zone == null, "Brood warning creates no early children or overlapping zone")
	hive._tick_hive_queen(HIVE_QUEEN.behavior.brood_windup_sec + 0.01)
	_check(hive._brood.get_total_spawned() == HIVE_QUEEN.behavior.brood_burst_count, "Finished Hive brood warning spends exactly its authored finite burst")
	_freeze_brood()
	_check(hive._hive_next_is_zone and hive._recovery_left > 0.0, "Hive alternates to a zone only after release recovery")
	hive._tick_hive_queen(0.01)
	_check(hive._active_zone == null, "Hive cannot skip its recovery to release a zone")
	hive._recovery_left = 0.0
	hive._tick_hive_queen(0.01)
	var zone: BugSporeZone = hive._active_zone
	_check(is_instance_valid(zone), "Hive's second major action is a visible fixed spore zone")
	if not is_instance_valid(zone):
		return
	zone.set_physics_process(false)
	_check(hive._zones_created == 1 and hive._brood_windup_left <= 0.0, "A zone spends its lifetime budget and cannot overlap brood gestation")
	hive._brood_interval_left = 0.0
	hive._recovery_left = 0.0
	hive._tick_hive_queen(0.01)
	_check(hive._brood_windup_left <= 0.0, "Active spore warning prevents another major action")
	_ship.global_position = Vector3(1000.0, 0.0, 0.0)
	_finish_zone(zone)
	_check(hive._active_zone == null and not hive._hive_next_is_zone and hive._recovery_left > 0.0, "Zone expiry returns Hive to brood turn with exposed recovery")
	_ship.global_position = Vector3.ZERO
	hive._recovery_left = 0.0
	hive._zones_created = HIVE_QUEEN.behavior.zone_total_cap
	hive._brood.setup(hive, SPORELING, 4, 0, 12, 50)
	hive._hive_next_is_zone = true
	for step: int in range(10):
		hive._zone_interval_left = 0.0
		hive._tick_hive_queen(1.0)
	_check(hive._active_zone == null and hive._brood_windup_left <= 0.0, "Hive cannot replenish exhausted zone or child lifetime budgets")
	var summoned_request: SpawnRequest = SpawnRequest.new()
	summoned_request.is_summoned = true
	var summoned: BugEnemy = _spawn_enemy(HIVE_QUEEN, Vector3(100.0, 0.0, 240.0), summoned_request)
	_check(summoned != null and summoned._brood == null, "A summoned Hive Queen cannot create another brood generation")
	await get_tree().process_frame

func _test_spore_pulses_and_pause() -> void:
	_ship.global_position = Vector3.ZERO
	var source: BugEnemy = _spawn_enemy(HIVE_QUEEN, Vector3(0.0, 0.0, 240.0))
	if source == null:
		return
	_set_test_weapon(source._first_valid_turret(), 10.0)
	var zone: BugSporeZone = _make_zone(source, 2)
	if zone == null:
		return
	_check(zone is EnemyAttackTelegraph and zone.is_in_group("enemy_attack_telegraphs"), "Spore zones integrate with existing HUD attack warnings")
	_check(zone.process_mode == Node.PROCESS_MODE_PAUSABLE, "Spore zones obey encounter pause")
	var remaining: float = zone.get_time_remaining()
	zone.set_physics_process(true)
	get_tree().paused = true
	for frame: int in range(4):
		await get_tree().physics_frame
	_check(is_equal_approx(zone.get_time_remaining(), remaining), "Pausing freezes the spore countdown")
	get_tree().paused = false
	zone.set_physics_process(false)
	var locked_center: Vector3 = zone._locked_position
	var hull_before: float = _ship.hull
	zone._physics_process(0.5)
	_check(is_equal_approx(_ship.hull, hull_before), "A spore pulse remains harmless before its full warning")
	_ship.global_position = Vector3(1000.0, 0.0, 0.0)
	zone._physics_process(1.0)
	_check(zone.get_pulses_resolved() == 1 and is_equal_approx(_ship.hull, hull_before), "Leaving the first sphere avoids the first pulse")
	_set_test_weapon(source._first_valid_turret(), 1000.0)
	zone._physics_process(0.2)
	_check(zone._locked_position.is_equal_approx(locked_center) and zone.global_position.is_equal_approx(locked_center), "Second pulse keeps the FIRST locked position despite player movement")
	_check(zone.get_time_remaining() >= 0.99, "The second pulse receives a fresh full warning")
	_ship.global_position = locked_center
	zone._physics_process(0.5)
	_check(is_equal_approx(_ship.hull, hull_before), "Entering the second sphere midway through its warning deals no early damage")
	zone._physics_process(0.6)
	_check(zone.get_pulses_resolved() == 2 and is_equal_approx(hull_before - _ship.hull, 10.0), "Second pulse resolves the original immutable damage at the original center")
	zone._physics_process(0.05)
	_check(is_equal_approx(hull_before - _ship.hull, 10.0), "A spore pulse cannot damage repeatedly during its flash")
	zone._physics_process(0.2)
	_check(zone._finished_emitted and zone.is_queued_for_deletion(), "The finite zone expires after its final release flash")
	await get_tree().process_frame
	_check(not is_instance_valid(zone), "Expired spore zones leave no lingering hazard node")

func _test_zone_caps_and_cleanup() -> void:
	_ship.global_position = Vector3.ZERO
	var owners: Array[BugEnemy] = []
	var zones: Array[BugSporeZone] = []
	for index: int in range(9):
		var owner: BugEnemy = _spawn_enemy(HIVE_QUEEN, Vector3(float(index) * 10.0, 0.0, 240.0))
		owners.append(owner)
		if index < 8:
			zones.append(_make_zone(owner, 1))
	_check(not BugSporeZone.can_spawn(owners[8]), "The ninth owner cannot exceed the shared eight-zone ceiling")
	_check(not BugSporeZone.can_spawn(owners[0]), "One owner cannot overlap a second spore zone by default")
	zones[0].cancel()
	_check(BugSporeZone.can_spawn(owners[8]), "Cancelling a zone immediately frees its global capacity")
	var zone: BugSporeZone = _make_zone(owners[8], 1)
	var hull_before: float = _ship.hull
	owners[8].apply_damage(1000000.0)
	await get_tree().process_frame
	_check(not is_instance_valid(zone) and is_equal_approx(_ship.hull, hull_before), "Killing the source cancels an unresolved spore zone without damage")
	zone = zones[1]
	owners[1].queue_free()
	await get_tree().process_frame
	_check(not is_instance_valid(zone), "Removing the source from the encounter also cancels its zone")
	var dying_charge: BugEnemy = _spawn_enemy(DEVOURER, Vector3(0.0, 0.0, 200.0))
	dying_charge._start_devourer_charge()
	var attack: EnemyAttackTelegraph = dying_charge._active_attack
	_check(is_instance_valid(attack), "Cleanup test starts during an actual Devourer charge warning")
	if is_instance_valid(attack):
		attack.set_physics_process(false)
	dying_charge.apply_damage(1000000.0)
	await get_tree().process_frame
	_check(not is_instance_valid(attack), "Killing a Devourer during its warning cancels the charge")

func _test_shared_brood_caps() -> void:
	var hive: BugEnemy = _spawn_enemy(HIVE_QUEEN, Vector3(-100.0, 0.0, 240.0))
	var mother: BugEnemy = _spawn_enemy(BROODMOTHER, Vector3(100.0, 0.0, 240.0))
	if hive == null or mother == null:
		return
	hive._brood.setup(hive, SPORELING, 3, 5, 3, 50)
	mother._brood.setup(mother, SPORELING, 3, 5, 3, 50)
	_check(hive._brood.spawn_brood(100) == 3, "Hive brood respects its requested living capacity")
	_freeze_brood()
	_check(mother._brood.spawn_brood(100) == 0, "Hive Queen and Broodmother share one global brood ceiling")
	for child: Node in get_tree().get_nodes_in_group("bug_brood"):
		var enemy: Enemy = child as Enemy
		_check(enemy._spawn_context.is_summoned and not enemy._spawn_context.grants_kill_rewards and not enemy._spawn_context.contributes_to_pressure, "Hive brood cannot create grandchildren, rewards, or adaptive kill pressure")
		_check(enemy.collision_layer == 8 and enemy.collision_mask == 0, "Hive brood remains targetable without physical collision")
	hive._brood.clear_brood()
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(hive._brood.get_total_spawned() == 3 and mother._brood.spawn_brood(100) == 3, "Clearing brood frees shared living slots without refunding lifetime budgets")
	_freeze_brood()
	var owner_id: int = mother.get_instance_id()
	mother.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	var remaining: int = 0
	for child: Node in get_tree().get_nodes_in_group("bug_brood"):
		if int(child.get_meta("brood_parent_id", 0)) == owner_id:
			remaining += 1
	_check(remaining == 0, "Exiting a brood owner removes every surviving owned child")

func _make_zone(source: BugEnemy, pulses: int) -> BugSporeZone:
	var zone: BugSporeZone = BugSporeZone.new()
	add_child(zone)
	var started: bool = zone.start_zone(source, _ship, source._first_valid_turret(), 1.0, 60.0, pulses)
	_check(started, "A legal spore-zone request starts within capacity")
	if not started:
		return null
	zone.set_physics_process(false)
	return zone

func _finish_zone(zone: BugSporeZone) -> void:
	for tick: int in range(8):
		if not is_instance_valid(zone) or zone.is_queued_for_deletion():
			return
		zone._physics_process(6.0)

func _set_test_weapon(turret: EnemyTurret, damage: float) -> void:
	turret.systems_bonus = 0.0
	turret.eff_base_accuracy = 1.0
	turret.eff_range_falloff = 0.0
	turret.eff_crit_chance = 0.0
	turret.eff_graze_on_hit = 0.0
	turret.eff_damage_min = damage
	turret.eff_damage_max = damage

func _freeze_brood() -> void:
	for node: Node in get_tree().get_nodes_in_group("bug_brood"):
		var enemy: Enemy = node as Enemy
		if enemy != null:
			_freeze_enemy(enemy)

func _clear_enemies() -> void:
	get_tree().paused = false
	for child: Node in get_children():
		if child is Enemy or child is EnemyAttackTelegraph or child is Projectile or child is NanobotSwarm:
			child.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(int(_spawner.get_alive_counts().get("enemies", 0)) == 0, "Owner and summon cleanup returns Spawner accounting to zero")

func _check(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("BUG_ADVANCED_CHECKS: " + description)
