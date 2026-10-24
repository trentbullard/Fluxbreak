extends Node3D

const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const SPORELING: BugEnemyDef = preload("res://content/data/enemies/bug_sporeling_mk1.tres")
const CARAPACE: BugEnemyDef = preload("res://content/data/enemies/bug_carapace_mk1.tres")
const BROODMOTHER: BugEnemyDef = preload("res://content/data/enemies/bug_broodmother_mk1.tres")

var _ship: Ship = null
var _spawner: Spawner = null
var _enemies: Array[BugEnemy] = []
var _assertions: int = 0
var _failures: int = 0

func _ready() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Bug Validation":
		push_error("Bug checks require the isolated Fluxbreak Bug Validation project to protect production progress.")
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
	_test_committed_attacks()
	await _clear_enemies()
	await _test_brood_release_and_limits()
	await _clear_enemies()
	await _test_movement()
	await _clear_enemies()
	print("BUG_REGULAR_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _assertions, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_enemy(enemy_def: BugEnemyDef, position: Vector3, request: SpawnRequest = null) -> BugEnemy:
	var enemy: BugEnemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, enemy_def, position, request) as BugEnemy
	if enemy == null:
		_check(false, "%s spawns through the real Spawner" % enemy_def.id)
		return null
	_freeze_enemy(enemy)
	_enemies.append(enemy)
	return enemy

func _freeze_enemy(enemy: Enemy) -> void:
	enemy.freeze = true
	enemy.set_physics_process(false)
	enemy.collision_layer = 0
	enemy.collision_mask = 0
	enemy.explosion_scene = null
	enemy._stop_warp_in()
	if enemy._regen_timer != null:
		enemy._regen_timer.stop()
	# Fast headless checks can free a playing WAV before the audio worker ticks.
	for audio_node: Node in enemy.find_children("*", "AudioStreamPlayer3D", true, false):
		var audio: AudioStreamPlayer3D = audio_node as AudioStreamPlayer3D
		audio.stream = null

func _test_shipped_actors() -> void:
	for enemy_def: BugEnemyDef in [SPORELING, CARAPACE, BROODMOTHER]:
		var enemy: BugEnemy = _spawn_enemy(enemy_def, Vector3(0.0, 0.0, 90.0))
		if enemy == null:
			continue
		_check(enemy.def == enemy_def and enemy.get_faction_id() == &"bugs", "%s retains its shipped Bug identity" % enemy_def.id)
		_check(enemy._controlled_turrets.size() > 0, "%s exposes a configured controlled turret" % enemy_def.id)
		for turret: EnemyTurret in enemy._controlled_turrets:
			_check(not turret.is_physics_processing(), "%s cannot fire autonomously" % enemy_def.id)
			_check(turret.eff_base_range > 0.0 and turret.eff_damage_max > 0.0, "%s keeps the resolved weapon snapshot" % enemy_def.id)
		_check(enemy.get_visual_model_root() != null and enemy.get_muzzle_socket() != null, "%s has its shipped model and muzzle contract" % enemy_def.id)
		_check(enemy.eff_max_shield == 0.0, "%s uses a biological hull without shields" % enemy_def.id)
	_check(SPORELING.behavior.max_speed > CARAPACE.behavior.max_speed and CARAPACE.max_hull > SPORELING.max_hull, "Sporeling speed and Carapace durability are distinct")
	_check(BROODMOTHER.behavior.approach_range > CARAPACE.behavior.approach_range, "Broodmother has a longer standoff distance")
	print("BUG_REGULAR_CHECKS: shipped models, identities, snapshots and autonomous firing checked")

func _test_committed_attacks() -> void:
	for enemy_def: BugEnemyDef in [SPORELING, CARAPACE, BROODMOTHER]:
		_ship.global_position = Vector3.ZERO
		var enemy: BugEnemy = _spawn_enemy(enemy_def, Vector3(0.0, 0.0, enemy_def.behavior.approach_range * 0.7))
		if enemy == null:
			continue
		var turret: EnemyTurret = enemy._first_valid_turret()
		turret.systems_bonus = 0.0
		turret.eff_base_accuracy = 1.0
		turret.eff_range_falloff = 0.0
		turret.eff_crit_chance = 0.0
		turret.eff_graze_on_hit = 0.0
		turret.eff_damage_min = 10.0
		turret.eff_damage_max = 10.0
		var hull_before: float = _ship.hull
		enemy._attack_cooldown_left = 0.0
		_tick_role(enemy, 0.01)
		var attack: EnemyAttackTelegraph = enemy._active_attack
		_check(is_instance_valid(attack), "%s starts a visible committed attack in range" % enemy_def.id)
		if not is_instance_valid(attack):
			continue
		_check(is_equal_approx(_ship.hull, hull_before), "%s causes no damage at warning start" % enemy_def.id)
		_check(attack.get_attack_label().contains("RAM") if enemy_def == CARAPACE else attack.get_attack_label().contains("SPORE"), "%s exposes a readable faction attack label" % enemy_def.id)
		attack.set_physics_process(false)
		attack._physics_process(enemy_def.behavior.attack_windup_sec * 0.5)
		_tick_role(enemy, 0.01)
		_check(is_equal_approx(_ship.hull, hull_before), "%s causes no damage midway through its windup" % enemy_def.id)
		_check(not enemy._animated_model.scale.is_equal_approx(enemy._rest_model_scale), "%s visibly contracts during windup" % enemy_def.id)
		_ship.global_position = Vector3(enemy_def.behavior.attack_radius * 3.0, 0.0, 0.0)
		attack._physics_process(enemy_def.behavior.attack_windup_sec)
		_check(is_equal_approx(_ship.hull, hull_before), "%s is avoided by leaving its locked volume" % enemy_def.id)
		_check(enemy._active_attack == null and enemy._recovery_left > 0.0, "%s exposes recovery after resolution" % enemy_def.id)
		enemy._attack_cooldown_left = 0.0
		_tick_role(enemy, 0.01)
		_check(enemy._active_attack == null, "%s cannot attack through its recovery window" % enemy_def.id)
		_ship.global_position = Vector3.ZERO
		enemy._recovery_left = 0.0
		enemy._attack_cooldown_left = 0.0
		_tick_role(enemy, 0.01)
		attack = enemy._active_attack
		if not is_instance_valid(attack):
			_check(false, "%s can begin a second legal attack" % enemy_def.id)
			continue
		attack.set_physics_process(false)
		turret.eff_damage_min = 1000.0
		turret.eff_damage_max = 1000.0
		attack._physics_process(enemy_def.behavior.attack_windup_sec + 0.01)
		_check(is_equal_approx(hull_before - _ship.hull, 10.0), "%s resolves exactly the immutable damage captured at windup" % enemy_def.id)
		attack._physics_process(0.05)
		_check(is_equal_approx(hull_before - _ship.hull, 10.0), "%s cannot damage twice from one committed attack" % enemy_def.id)
	_ship.global_position = Vector3.ZERO
	print("BUG_REGULAR_CHECKS: warning, contraction, dodge, recovery and immutable damage checked")

func _test_brood_release_and_limits() -> void:
	var scaling: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
	scaling.hull_multiplier = 1.5
	scaling.damage_multiplier = 2.0
	var request: SpawnRequest = SpawnRequest.new()
	request.enemy_combat_scaling = scaling
	var mother: BugEnemy = _spawn_enemy(BROODMOTHER, Vector3(0.0, 0.0, 350.0), request)
	if mother == null:
		return
	_check(is_instance_valid(mother._brood), "A normal Broodmother owns a finite brood helper")
	mother._attack_cooldown_left = 100.0
	mother._brood_interval_left = 0.0
	mother._tick_broodmother(0.01)
	_check(mother._brood_windup_left > 0.0 and mother._brood_label.visible, "Broodmother advertises its release countdown")
	_check(mother._brood.get_total_spawned() == 0, "Broodmother cannot release children before the warning")
	mother._tick_broodmother(BROODMOTHER.behavior.brood_windup_sec + 0.01)
	_check(mother._brood.get_total_spawned() == 2 and mother._brood.get_living_count() == 2, "One completed release produces the authored two Sporelings")
	_check(not mother._brood_label.visible and mother._brood_interval_left > 0.0, "A release hides the countdown and resets the interval")
	_check(int(_spawner.get_alive_counts().get("enemies", 0)) == 3, "Both brood children enter real Spawner accounting")
	var children: Array[Enemy] = _living_brood(mother)
	for child: Enemy in children:
		_check(child._spawn_context.is_summoned and not child._spawn_context.grants_kill_rewards and not child._spawn_context.contributes_to_pressure, "Each child is flagged against nested spawning, rewards and wave pressure")
		_check(is_equal_approx(child.eff_max_hull, SPORELING.max_hull * 1.5), "Brood hulls inherit the parent's enemy scaling")
		_check(is_equal_approx(child.get_effective_stat_snapshot().weapon_stats.damage_min, SPORELING.weapon.damage_min * 2.0), "Brood weapons inherit the parent's damage scaling")
	var score_before: int = RunState.run_score
	var drops_before: int = _nanobot_drop_count()
	var pressure_before: float = CombatStats._frame_enemy_kill_pressure
	children[0].apply_damage(1000000.0)
	_check(RunState.run_score == score_before and _nanobot_drop_count() == drops_before, "Defeating summoned brood grants no score or nanobot drops")
	_check(is_equal_approx(CombatStats._frame_enemy_kill_pressure, pressure_before), "Defeating summoned brood does not increase adaptive kill pressure")
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(mother._brood.get_living_count() == 1 and mother._brood.get_total_spawned() == 2, "A defeated child frees a living slot without refunding lifetime budget")
	_check(mother._brood.spawn_brood(50) == 3, "A large release is clamped to the four-child living ceiling")
	_living_brood(mother)
	_check(mother._brood.get_living_count() == 4 and mother._brood.spawn_brood(1) == 0, "A mother at its living cap cannot create another child")
	mother._brood.clear_brood()
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(mother._brood.spawn_brood(50) == 3, "The last release only spends the remaining lifetime budget")
	_living_brood(mother)
	_check(mother._brood.get_total_spawned() == 8, "A Broodmother spends at most eight children in its lifetime")
	mother._brood.clear_brood()
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(mother._brood.spawn_brood(1) == 0 and not mother._can_release_brood(), "Lifetime exhaustion is permanent after children are removed")
	var summoned_request: SpawnRequest = SpawnRequest.new()
	summoned_request.is_summoned = true
	var summoned_mother: BugEnemy = _spawn_enemy(BROODMOTHER, Vector3(0.0, 300.0, 350.0), summoned_request)
	_check(summoned_mother != null and summoned_mother._brood == null, "A summoned Broodmother cannot create grandchildren")
	var cleanup_mother: BugEnemy = _spawn_enemy(BROODMOTHER, Vector3(0.0, -300.0, 350.0))
	cleanup_mother._brood.spawn_brood(2)
	_living_brood(cleanup_mother)
	var owned_id: int = cleanup_mother.get_instance_id()
	cleanup_mother.apply_damage(1000000.0)
	await get_tree().process_frame
	await get_tree().physics_frame
	var children_remaining: int = 0
	for node: Node in get_tree().get_nodes_in_group("bug_brood"):
		if int(node.get_meta("brood_parent_id", 0)) == owned_id:
			children_remaining += 1
	_check(children_remaining == 0, "Killing a Broodmother cleans up every surviving owned child")
	print("BUG_REGULAR_CHECKS: visible release, caps, scaling, reward guards and source cleanup checked")

func _test_movement() -> void:
	_ship.global_position = Vector3.ZERO
	var sporeling: BugEnemy = _spawn_enemy(SPORELING, Vector3(0.0, 0.0, 600.0))
	sporeling.freeze = false
	sporeling._attack_cooldown_left = 100.0
	for frame in range(18):
		sporeling._tick_sporeling()
		await get_tree().physics_frame
	_check(sporeling.linear_velocity.dot((_ship.global_position - sporeling.global_position).normalized()) > 1.0, "Sporeling physically accelerates toward a distant player")
	sporeling.freeze = true
	var mother: BugEnemy = _spawn_enemy(BROODMOTHER, Vector3(0.0, 0.0, 180.0))
	mother.freeze = false
	mother._attack_cooldown_left = 100.0
	for frame in range(18):
		mother._tick_broodmother(1.0 / 60.0)
		await get_tree().physics_frame
	_check(mother.linear_velocity.dot((_ship.global_position - mother.global_position).normalized()) < -1.0, "Broodmother physically retreats when the player crosses its standoff band")
	print("BUG_REGULAR_CHECKS: pursuit and standoff movement checked")

func _tick_role(enemy: BugEnemy, delta: float) -> void:
	match enemy._behavior.mode:
		BugBehaviorDef.Mode.SPORELING:
			enemy._tick_sporeling()
		BugBehaviorDef.Mode.CARAPACE:
			enemy._tick_carapace()
		BugBehaviorDef.Mode.BROODMOTHER:
			enemy._tick_broodmother(delta)

func _living_brood(mother: BugEnemy) -> Array[Enemy]:
	var children: Array[Enemy] = []
	for node: Node in get_tree().get_nodes_in_group("bug_brood"):
		var child: Enemy = node as Enemy
		if child != null and int(child.get_meta("brood_parent_id", 0)) == mother.get_instance_id() and not child._dead and not child.is_queued_for_deletion():
			_freeze_enemy(child)
			children.append(child)
	return children

func _nanobot_drop_count() -> int:
	var count: int = 0
	for child: Node in get_children():
		if child is NanobotSwarm:
			count += 1
	return count

func _clear_enemies() -> void:
	for enemy: BugEnemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	for node: Node in get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		node.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(int(_spawner.get_alive_counts().get("enemies", 0)) == 0, "Source and brood cleanup returns Spawner accounting to zero")

func _check(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("BUG_REGULAR_CHECKS: " + description)
