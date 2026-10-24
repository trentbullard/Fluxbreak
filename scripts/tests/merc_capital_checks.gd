extends Node3D

const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const CORVETTE: MercEnemyDef = preload("res://content/data/enemies/merc_corvette_mk1.tres")
const CRUISER: MercEnemyDef = preload("res://content/data/enemies/merc_cruiser_mk1.tres")
const CARRIER: MercEnemyDef = preload("res://content/data/enemies/merc_carrier_mk1.tres")
const MACHINES: FactionDef = preload("res://content/data/factions/machines.tres")

var _ship: Ship = null
var _spawner: Spawner = null
var _enemies: Array[MercEnemy] = []
var _assertions: int = 0
var _failures: int = 0

func _ready() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Merc Validation":
		push_error("Merc capital checks require the isolated Fluxbreak Merc Validation project to protect production progress.")
		get_tree().quit(2)
		return
	call_deferred("_run_checks")

func _run_checks() -> void:
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "CapitalTestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.hull = 100000.0
	_ship.shield = 0.0
	_ship.eff_evasion = 0.0
	_ship.eff_damage_taken_mult = 1.0
	_silence_audio(_ship)
	_spawner = Spawner.new()
	_spawner.name = "CapitalTestSpawner"
	_spawner.ship_path = NodePath("../CapitalTestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	_spawner.min_distance_from_ship = 0.0
	add_child(_spawner)
	_test_shipped_capitals()
	await _clear_enemies()
	await _test_cruiser_broadside()
	await _clear_enemies()
	await _test_carrier_launch_and_lifetime()
	await _clear_enemies()
	await _test_multiple_launchers()
	await _clear_enemies()
	await _test_owner_loss_persistence()
	await _clear_enemies()
	await _test_movement()
	await _clear_enemies()
	print("MERC_CAPITAL_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _assertions, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_enemy(enemy_def: MercEnemyDef, position: Vector3, request: SpawnRequest = null) -> MercEnemy:
	var enemy: MercEnemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, enemy_def, position, request) as MercEnemy
	if enemy == null:
		_check(false, "%s spawns through the real Spawner" % enemy_def.id)
		return null
	_freeze_enemy(enemy)
	_enemies.append(enemy)
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

func _test_shipped_capitals() -> void:
	for enemy_def: MercEnemyDef in [CRUISER, CARRIER]:
		var enemy: MercEnemy = _spawn_enemy(enemy_def, Vector3(0.0, 0.0, 250.0))
		if enemy == null:
			continue
		_check(enemy.def == enemy_def and enemy.get_faction_id() == &"mercs", "%s keeps its shipped Merc identity" % enemy_def.id)
		_check(enemy.collision_layer == 8 and enemy.collision_mask == 0, "%s remains targetable without physical collision" % enemy_def.id)
		_check(enemy._controlled_turrets.size() > 0, "%s has an authored weapon host" % enemy_def.id)
		for turret: EnemyTurret in enemy._controlled_turrets:
			_check(not turret.is_physics_processing(), "%s cannot fire outside its controlled cadence" % enemy_def.id)
		_check(enemy.get_visual_model_root() != null and enemy.get_muzzle_socket() != null, "%s keeps the model and muzzle contract" % enemy_def.id)
		_check(enemy_def.behavior.retreat_range <= 300.0, "%s remains approachable with the starter weapon" % enemy_def.id)
	_check(CRUISER.tier == 4 and CARRIER.tier == 5, "Cruiser and Carrier complete Merc tiers four and five")
	_check(CRUISER.behavior.mode == MercBehaviorDef.Mode.CRUISER and CARRIER.behavior.mode == MercBehaviorDef.Mode.CARRIER, "Capital resources select distinct tactical roles")
	_check(CARRIER.behavior.escort_child_def == CORVETTE, "Carrier launches the ordinary Merc Corvette")

func _test_cruiser_broadside() -> void:
	var cruiser: MercEnemy = _spawn_enemy(CRUISER, Vector3(0.0, 0.0, 250.0))
	if cruiser == null:
		return
	_ship.global_position = Vector3.ZERO
	var turret: EnemyTurret = cruiser._first_valid_turret()
	_set_test_weapon(turret, 10.0)
	var hull_before: float = _ship.hull
	cruiser._attack_cooldown_left = 0.0
	cruiser._tick_cruiser(0.01)
	var side_before: float = cruiser._broadside_side
	var attack: EnemyAttackTelegraph = cruiser._active_attack
	_check(is_instance_valid(attack), "Cruiser starts a marked broadside in weapon range")
	if not is_instance_valid(attack):
		return
	var first_label: String = attack.get_attack_label()
	_check(first_label.contains("BROADSIDE"), "Cruiser advertises its broadside rather than an unmarked special hit")
	_check(is_equal_approx(hull_before, _ship.hull), "Starting a broadside warning deals no damage")
	attack.set_physics_process(false)
	attack._physics_process(CRUISER.behavior.broadside_windup_sec * 0.5)
	_check(is_equal_approx(hull_before, _ship.hull), "Broadside remains harmless during its countdown")
	_ship.global_position = Vector3(CRUISER.behavior.broadside_radius * 4.0, 0.0, 0.0)
	attack._physics_process(CRUISER.behavior.broadside_windup_sec)
	_check(is_equal_approx(hull_before, _ship.hull), "Moving clear of the locked broadside corridor guarantees a dodge")
	_check(cruiser._broadside_shots_left == CRUISER.behavior.broadside_shots - 1, "Resolved round spends exactly one round from its volley")
	_ship.global_position = Vector3.ZERO
	cruiser._tick_cruiser(CRUISER.behavior.broadside_interval_sec * 0.5)
	_check(not is_instance_valid(cruiser._active_attack), "There is a quiet interval between broadside warnings")
	for round_index: int in range(1, CRUISER.behavior.broadside_shots):
		_set_test_weapon(turret, 10.0)
		cruiser._tick_cruiser(CRUISER.behavior.broadside_interval_sec + 0.01)
		attack = cruiser._active_attack
		_check(is_instance_valid(attack), "Broadside round %d receives a fresh warning" % (round_index + 1))
		if not is_instance_valid(attack):
			continue
		_check(attack.get_attack_label() == first_label, "Every round in one volley uses the committed flank")
		attack.set_physics_process(false)
		_set_test_weapon(turret, 1000.0)
		var before_round: float = _ship.hull
		attack._physics_process(CRUISER.behavior.broadside_windup_sec + 0.01)
		_check(is_equal_approx(before_round - _ship.hull, 10.0), "A broadside resolves the damage captured at warning start")
		attack._physics_process(0.01)
		_check(is_equal_approx(before_round - _ship.hull, 10.0), "A committed broadside round can damage only once")
	_check(cruiser._broadside_shots_left == 0 and cruiser._broadside_recovery_left > 0.0, "Cruiser exposes recovery after its finite volley")
	_check(cruiser._broadside_side == -side_before, "Cruiser alternates its next broadside to the opposite flank")
	cruiser._attack_cooldown_left = 0.0
	cruiser._tick_cruiser(0.01)
	_check(not is_instance_valid(cruiser._active_attack), "Cruiser cannot fire through its exposed recovery turn")
	cruiser._tick_cruiser(CRUISER.behavior.broadside_recovery_sec + 0.01)
	cruiser._tick_cruiser(0.01)
	attack = cruiser._active_attack
	_check(is_instance_valid(attack) and attack.get_attack_label() != first_label, "The next legal volley advertises its opposite broadside")
	if is_instance_valid(attack):
		attack.set_physics_process(false)
		var before_death: float = _ship.hull
		cruiser.apply_damage(1000000.0)
		await get_tree().process_frame
		_check(not is_instance_valid(attack) and is_equal_approx(_ship.hull, before_death), "Killing a winding-up Cruiser cancels its committed attack")
	_ship.global_position = Vector3.ZERO

func _test_carrier_launch_and_lifetime() -> void:
	var scaling: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
	scaling.hull_multiplier = 1.5
	scaling.damage_multiplier = 2.0
	var request: SpawnRequest = SpawnRequest.new()
	request.enemy_combat_scaling = scaling
	var carrier: MercEnemy = _spawn_enemy(CARRIER, Vector3(0.0, 0.0, 250.0), request)
	if carrier == null:
		return
	_check(is_instance_valid(carrier._escort_wing), "An ordinary Carrier owns an independent escort launcher")
	_check(carrier._escort_interval_left > 0.0, "The first Carrier launch waits an authored interval")
	carrier._attack_cooldown_left = 100.0
	carrier._escort_interval_left = 0.0
	carrier._tick_carrier(0.01)
	_check(carrier._escort_windup_left > 0.0 and carrier._escort_label.visible, "Carrier advertises its escort launch countdown")
	_check(carrier._escort_wing.get_total_spawned() == 0, "Starting a launch warning does not create escorts")
	carrier._tick_carrier(CARRIER.behavior.escort_windup_sec * 0.5)
	_check(carrier._escort_wing.get_total_spawned() == 0, "Escorts remain in reserve halfway through the warning")
	carrier._tick_carrier(CARRIER.behavior.escort_windup_sec)
	var wing: MercEscortWing = carrier._escort_wing
	_check(wing.get_living_count() == 2 and wing.get_total_spawned() == 2, "A completed launch releases the authored two Corvettes")
	_check(not carrier._escort_label.visible and carrier._escort_interval_left > 0.0, "Launch resets its warning and interval")
	_check(int(_spawner.get_alive_counts().get("enemies", 0)) == 3, "Escorts count toward the real encounter Spawner")
	var escorts: Array[Enemy] = _freeze_escorts(wing)
	for escort: Enemy in escorts:
		_check(escort.def == CORVETTE and escort.get_faction_id() == &"mercs", "Carrier escorts keep the Merc Corvette identity")
		_check(escort.collision_layer == 8 and escort.collision_mask == 0, "An escort remains targetable with physical collision disabled")
		_check(escort._spawn_context.is_summoned and not escort._spawn_context.grants_kill_rewards and not escort._spawn_context.contributes_to_pressure, "Escorts cannot farm rewards, pressure, or nested summons")
		_check(is_equal_approx(escort.eff_max_hull, CORVETTE.max_hull * 1.5), "Escort hulls inherit the encounter's enemy scaling")
		_check(is_equal_approx(escort.get_effective_stat_snapshot().weapon_stats.damage_min, CORVETTE.weapon.damage_min * 2.0), "Escort weapons inherit enemy damage scaling")
	var score_before: int = RunState.run_score
	var drops_before: int = _drop_count()
	var pressure_before: float = CombatStats._frame_enemy_kill_pressure
	escorts[0].apply_damage(1000000.0)
	_check(RunState.run_score == score_before and _drop_count() == drops_before, "Defeating an escort grants no score or nanobot drops")
	_check(is_equal_approx(CombatStats._frame_enemy_kill_pressure, pressure_before), "Defeating an escort does not inflate adaptive kill pressure")
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(wing.get_living_count() == 1 and wing.get_total_spawned() == 2, "Destroyed escorts leave accurate independent child accounting")
	for launch: int in range(5):
		carrier._escort_interval_left = 0.0
		carrier._tick_carrier(0.01)
		_check(carrier._escort_windup_left > 0.0, "Every repeated launch retains the visible launch warning")
		carrier._tick_carrier(CARRIER.behavior.escort_windup_sec + 0.01)
		_freeze_escorts(wing)
	_check(wing.get_total_spawned() == 12 and wing.get_living_count() == 11, "Carrier continues full authored batches beyond its former living and lifetime limits")
	_check(carrier._can_release_escorts(), "Living escorts do not stop future Carrier launches")
	var summoned_request: SpawnRequest = SpawnRequest.new()
	summoned_request.is_summoned = true
	var summoned_carrier: MercEnemy = _spawn_enemy(CARRIER, Vector3(100.0, 0.0, 250.0), summoned_request)
	_check(summoned_carrier != null and summoned_carrier._escort_wing == null, "A summoned Carrier cannot launch another generation")

func _test_multiple_launchers() -> void:
	var first: MercEnemy = _spawn_enemy(CARRIER, Vector3(-100.0, 0.0, 250.0))
	var second: MercEnemy = _spawn_enemy(CARRIER, Vector3(100.0, 0.0, 250.0))
	if first == null or second == null:
		return
	for launch: int in range(13):
		_check(first._escort_wing.spawn_escorts(2) == 2 and second._escort_wing.spawn_escorts(2) == 2, "Multiple Carriers retain their full batch without source or shared minion ceilings")
		_freeze_escorts(first._escort_wing)
		_freeze_escorts(second._escort_wing)
	_check(int(_spawner.get_alive_counts().get("enemies", 0)) == 54, "Escorts remain fully accounted beyond the former fifty-enemy summon ceiling")
	var wrong_faction: MercEnemyDef = CORVETTE.duplicate() as MercEnemyDef
	wrong_faction.faction = MACHINES
	second._escort_wing.setup(second, wrong_faction)
	_check(second._escort_wing.spawn_escorts(1) == 0, "A wing rejects child definitions from another faction")

func _test_owner_loss_persistence() -> void:
	var carrier: MercEnemy = _spawn_enemy(CARRIER, Vector3(0.0, 0.0, 250.0))
	if carrier == null:
		return
	carrier._escort_wing.spawn_escorts(2)
	var independent_escorts: Array[Enemy] = _freeze_escorts(carrier._escort_wing)
	var owner_id: int = carrier.get_instance_id()
	carrier.apply_damage(1000000.0)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(_owned_escort_count(owner_id) == 2, "Killing a Carrier preserves all previously launched escorts")
	var independent_score: int = RunState.run_score
	var independent_drops: int = _drop_count()
	independent_escorts[0].apply_damage(1000000.0)
	await get_tree().process_frame
	_check(_owned_escort_count(owner_id) == 1, "A parentless escort stays killable on its own")
	_check(RunState.run_score == independent_score and _drop_count() == independent_drops, "Parentless escorts retain their reward exclusions")
	var departing: MercEnemy = _spawn_enemy(CARRIER, Vector3(0.0, 0.0, 250.0))
	departing._escort_wing.spawn_escorts(2)
	_freeze_escorts(departing._escort_wing)
	owner_id = departing.get_instance_id()
	var score_before: int = RunState.run_score
	var drops_before: int = _drop_count()
	departing.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(_owned_escort_count(owner_id) == 2, "Removing a Carrier leaves its launched escorts alive")
	_check(RunState.run_score == score_before and _drop_count() == drops_before, "Owner-exit cleanup awards no kills or drops")
	var interrupted: MercEnemy = _spawn_enemy(CARRIER, Vector3(0.0, 0.0, 250.0))
	interrupted._escort_interval_left = 0.0
	interrupted._attack_cooldown_left = 100.0
	interrupted._tick_carrier(0.01)
	owner_id = interrupted.get_instance_id()
	_check(interrupted._escort_windup_left > 0.0, "A cleanup test starts during an actual launch warning")
	interrupted.apply_damage(1000000.0)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(_owned_escort_count(owner_id) == 0, "Destroying a winding-up Carrier prevents its pending launch")

func _test_movement() -> void:
	_ship.global_position = Vector3.ZERO
	for enemy_def: MercEnemyDef in [CRUISER, CARRIER]:
		var enemy: MercEnemy = _spawn_enemy(enemy_def, Vector3(0.0, 0.0, 650.0))
		if enemy == null:
			continue
		enemy._attack_cooldown_left = 100.0
		enemy._escort_interval_left = 100.0
		await get_tree().physics_frame
		enemy.freeze = false
		for frame: int in range(18):
			_tick_capital(enemy, 1.0 / 60.0)
			await get_tree().physics_frame
		_check(enemy.linear_velocity.dot((_ship.global_position - enemy.global_position).normalized()) > 1.0, "%s accelerates toward a distant player" % enemy_def.id)
		enemy.freeze = true
		enemy.global_position = Vector3(0.0, 0.0, 100.0)
		enemy.linear_velocity = Vector3.ZERO
		await get_tree().physics_frame
		enemy.freeze = false
		for frame: int in range(18):
			_tick_capital(enemy, 1.0 / 60.0)
			await get_tree().physics_frame
		_check(enemy.linear_velocity.dot((_ship.global_position - enemy.global_position).normalized()) < -1.0, "%s retreats when approached inside its formation band" % enemy_def.id)
		enemy.freeze = true

func _tick_capital(enemy: MercEnemy, delta: float) -> void:
	if enemy._behavior.mode == MercBehaviorDef.Mode.CRUISER:
		enemy._tick_cruiser(delta)
	else:
		enemy._tick_carrier(delta)

func _set_test_weapon(turret: EnemyTurret, damage: float) -> void:
	turret.systems_bonus = 0.0
	turret.eff_base_accuracy = 1.0
	turret.eff_range_falloff = 0.0
	turret.eff_crit_chance = 0.0
	turret.eff_graze_on_hit = 0.0
	turret.eff_damage_min = damage
	turret.eff_damage_max = damage

func _freeze_escorts(wing: MercEscortWing) -> Array[Enemy]:
	var escorts: Array[Enemy] = wing.get_living_escorts()
	for escort: Enemy in escorts:
		_freeze_enemy(escort)
	return escorts

func _owned_escort_count(owner_id: int) -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(MercEscortWing.ESCORT_GROUP):
		if int(node.get_meta(MercEscortWing.OWNER_META, 0)) == owner_id:
			count += 1
	return count

func _drop_count() -> int:
	var count: int = 0
	for child: Node in get_children():
		if child is NanobotSwarm:
			count += 1
	return count

func _clear_enemies() -> void:
	for child: Node in get_children():
		if child is Enemy or child is EnemyAttackTelegraph or child is Projectile or child is NanobotSwarm:
			child.queue_free()
	_enemies.clear()
	await get_tree().process_frame
	await get_tree().physics_frame

func _check(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("MERC_CAPITAL_CHECKS: " + description)
