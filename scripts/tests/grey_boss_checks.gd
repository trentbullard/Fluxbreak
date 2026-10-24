extends Node3D

## Shipped boss actors, immutable pattern geometry and real helper lifecycles.
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const WITNESS: GreyBossDef = preload("res://content/data/enemies/grey_witness_mk1.tres")
var _ship: Ship
var _spawner: Spawner
var _bosses: Array[EnemyBoss] = []
var _checks: int = 0
var _failures: int = 0

func _suite_name() -> String:
	return "GREY_BOSS_CHECKS"

func _definitions() -> Array[GreyBossDef]:
	return [WITNESS]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_silence)
	call_deferred("_run_checks")

func _silence(node: Node) -> void:
	if node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null
	elif node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null

func _physics_process(delta: float) -> void:
	if is_instance_valid(_ship) and not get_tree().paused:
		_ship._tick_tether_status(delta)

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Grey Validation":
		get_tree().quit(2)
		return
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "TestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.hull = 100000.0
	_ship.shield = 0.0
	_ship.eff_evasion = 0.0
	_ship.eff_damage_taken_mult = 1.0
	_spawner = Spawner.new()
	_spawner.ship_path = NodePath("../TestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	_spawner.min_distance_from_ship = 0.0
	add_child(_spawner)
	for definition: GreyBossDef in _definitions():
		_check_definitions(definition)
		await _check_patterns_and_phase(definition)
		await _clear()
		await _check_displacement_followup(definition)
		await _clear()
		await _check_directional_tether(definition)
		await _clear()
		await _check_cleanup(definition)
		await _clear()
	print("%s: %d checks, %d failures" % [_suite_name(), _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn(definition_source: GreyBossDef) -> EnemyBoss:
	_ship._dead = false
	_ship.visible = true
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.ZERO
	_ship.clear_tether_slow(null, false)
	_ship._tether_immunity_sec = 0.0
	var definition: GreyBossDef = definition_source.duplicate(false) as GreyBossDef
	definition.displacement_windup_sec = 0.3
	definition.rupture_windup_sec = 0.3
	definition.echo_gap_sec = 0.1
	definition.tether_windup_sec = 0.3
	definition.tether_duration_sec = 0.6
	definition.recovery_sec = 0.25
	definition.cadence_sec = 0.1
	var request: SpawnRequest = SpawnRequest.new()
	request.stage_index = 2
	request.wave_index = 30
	var scaling: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
	scaling.hull_multiplier = 1.5
	scaling.shield_multiplier = 1.5
	scaling.damage_multiplier = 2.0
	request.enemy_combat_scaling = scaling
	var boss: EnemyBoss = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, definition, Vector3(0.0, 0.0, -180.0), request) as EnemyBoss
	_expect(boss != null, "Shipped boss spawns through the real Spawner")
	if boss != null:
		_bosses.append(boss)
		boss.freeze = true
		boss.set_physics_process(false)
		boss.explosion_scene = null
		boss._stop_warp_in()
		if boss._regen_timer != null:
			boss._regen_timer.stop()
		for socket: BossWeaponSocket in boss._weapon_sockets:
			socket.eff_base_accuracy = 1.0
			socket.eff_range_falloff = 0.0
			socket.eff_crit_chance = 0.0
			socket.eff_graze_on_hit = 0.0
			socket.eff_graze_on_miss = 0.0
			socket.eff_damage_min = 12.0
			socket.eff_damage_max = 12.0
	return boss

func _check_definitions(definition: GreyBossDef) -> void:
	_expect(definition.rupture_windup_sec >= 1.6 and definition.recovery_sec >= 1.0, "Campaign/Practice retain full tells and exposed recovery")
	_expect(definition.tether_duration_sec <= 3.0 and definition.tether_movement_factor >= 0.65, "Tether remains finite and bounded")
	_expect(definition.forecast_lead_fraction == 1.0 and definition.forecast_max_lead >= 1000.0, "Prediction reaches ordinary player cruise velocity")
	_expect(definition.cadence_sec <= 1.0, "Heavy setup actions no longer dilute the damaging cadence")

func _check_patterns_and_phase(definition: GreyBossDef) -> void:
	for speed: float in [300.0, 400.0]:
		var boss: EnemyBoss = _spawn(definition)
		_expect(is_equal_approx(boss.eff_max_hull, definition.max_hull * 1.5) and is_equal_approx(boss.eff_max_shield, definition.max_shield * 1.5), "Both durability pools retain encounter scaling")
		_expect(boss._spawn_context.stage_index == 2 and boss._spawn_context.wave_index == 30, "Pattern actors preserve encounter attribution")
		_ship.linear_velocity = Vector3.RIGHT * speed
		boss.set("_next_major", 1)
		boss.call("_begin_attack", _ship)
		var primary: EnemyAttackTelegraph = boss.get("_attack") as EnemyAttackTelegraph
		_expect(primary != null, "Boss creates a fully warned damaging pattern")
		var warnings: Array[EnemyAttackTelegraph] = _warnings(boss)
		var steady_intersections: int = 0
		for warning: EnemyAttackTelegraph in warnings:
			warning.set_physics_process(false)
			if warning.contains_position(Vector3.RIGHT * speed * warning._windup_sec):
				steady_intersections += 1
			_expect(not warning.contains_position(Vector3.UP * 250.0), "Every initial pattern retains a vertical course-change escape")
		_expect(steady_intersections > 0, "Constant %dm/s flight intersects a release-time forecast" % int(speed))
		var locked: Vector3 = primary._locked_position
		var remaining: float = primary.get_time_remaining()
		_ship.global_position = Vector3.UP * 250.0
		_ship.linear_velocity = Vector3.UP * speed
		get_tree().paused = true
		await _wait(0.1)
		get_tree().paused = false
		_expect(primary._locked_position.is_equal_approx(locked) and is_equal_approx(primary.get_time_remaining(), remaining), "Prediction is locked and pause freezes its tell")
		_set_fraction(boss, 0.54 if not boss is GreyVeiledMind else 0.69)
		boss.call("_update_weapons", _ship, 0.0)
		_expect(int(boss.get_meta("grey_phase")) == 2, "Combined shields and hull trigger phase two before shield-heavy hull depletion")
		_expect(is_equal_approx(primary.get_time_remaining(), remaining), "Phase change cannot shorten a committed warning")
		var health: float = _ship.hull
		for warning: EnemyAttackTelegraph in warnings:
			warning._physics_process(warning._windup_sec + 0.01)
		_expect(_ship.hull == health and StringName(boss.call("get_attack_state")) == &"recovery", "Course change dodges the entire pattern and final release grants recovery")
		boss.hull = boss.eff_max_hull
		boss.shield = boss.eff_max_shield
		boss.call("_update_weapons", _ship, 0.0)
		_expect(int(boss.get_meta("grey_phase")) == 2, "Shield regeneration cannot reverse a phase")
		await _clear()
	if definition is GreyMindDef:
		for phase: int in [1, 2, 3]:
			var boss: EnemyBoss = _spawn(definition)
			boss.set("_phase", phase)
			boss.set("_next_major", 1)
			_ship.linear_velocity = Vector3.RIGHT * 400.0
			boss.call("_begin_attack", _ship)
			var warnings: Array[EnemyAttackTelegraph] = _warnings(boss)
			_expect(warnings.size() == phase, "Veiled Mind phase %d increases complementary damaging decisions" % phase)
			for warning: EnemyAttackTelegraph in warnings:
				warning.set_physics_process(false)
				_expect(not warning.contains_position(Vector3.UP * 300.0), "Later collapse preserves a clearly open 3D escape")
				if warning != warnings[0]:
					_expect(warning.contains_position(Vector3.RIGHT * 400.0 * warning._windup_sec), "Each later echo/lane forecasts its own release time")
			await _clear()

func _check_displacement_followup(definition: GreyBossDef) -> void:
	var boss: EnemyBoss = _spawn(definition)
	boss.set("_next_major", 0)
	boss.call("_begin_attack", _ship)
	var displacement: GreyDisplacement = boss.get("_displacement") as GreyDisplacement
	_expect(displacement != null, "Relocation announces both immutable endpoints")
	displacement.set_physics_process(false)
	var origin: Vector3 = boss.global_position
	var destination: Vector3 = displacement._destination
	var health: float = _ship.hull
	displacement._physics_process(0.1)
	_expect(boss.global_position == origin and boss.is_in_group("targets"), "Boss remains visible and targetable before relocation completes")
	displacement._physics_process(0.3)
	_expect(boss.global_position.is_equal_approx(destination) and _ship.hull == health, "Relocation itself remains harmless")
	_expect(float(boss.get("_state_remaining_sec")) == 0.0 and StringName(boss.call("get_attack_state")) == &"cadence", "Setup schedules damage without a whole empty recovery/cadence cycle")
	boss.call("_update_weapons", _ship, 0.0)
	var attack: EnemyAttackTelegraph = boss.get("_attack") as EnemyAttackTelegraph
	_expect(attack != null and attack.get_time_remaining() > 0.0 and _ship.hull == health, "Followup is a new full warning, never instant damage")
	boss.call("_clear_encounter_runtime")
	boss.set("_attack_state", &"cadence")
	boss.set("_next_major", 1)
	_ship.global_position = Vector3.RIGHT * 2500.0
	boss.linear_velocity = Vector3.RIGHT * 80.0
	boss.call("_begin_attack", _ship)
	_expect(is_equal_approx(boss.linear_velocity.x, 80.0) and StringName(boss.call("get_attack_state")) == &"cadence", "Failed out-of-range followup preserves approach velocity instead of freezing the boss")

func _check_directional_tether(definition: GreyBossDef) -> void:
	var boss: EnemyBoss = _spawn(definition)
	boss.set("_next_major", 2)
	boss.call("_begin_attack", _ship)
	var tether: GreyTether = boss.get("_tether") as GreyTether
	_expect(tether != null and tether._corridor, "Boss capture has directional warned geometry")
	tether.set_physics_process(false)
	_expect(_ship.get_movement_slow_multiplier() == 1.0, "No movement penalty exists before acquisition")
	tether._physics_process(0.31)
	_expect(tether.is_attached() and _ship.get_tether_source() == boss, "Standing in the marked corridor attaches the unique finite link")
	_expect(_ship.get_movement_slow_multiplier() >= 0.65 and _ship.get_tether_time_remaining() <= 3.0, "Attached link retains safety bounds")
	var remaining: float = _ship.get_tether_time_remaining()
	get_tree().paused = true
	await _wait(0.1)
	get_tree().paused = false
	_expect(is_equal_approx(_ship.get_tether_time_remaining(), remaining), "Pause freezes the real attached status")
	_ship.global_position = Vector3.RIGHT * 1000.0
	tether._physics_process(0.01)
	_expect(_ship.get_movement_slow_multiplier() == 1.0 and _ship.is_tether_immune(), "Distance escape breaks the link and grants immunity")
	_expect(float(boss.get("_state_remaining_sec")) == 0.0, "Ended link leads to a fresh warned collapse without an empty cooldown")

func _check_cleanup(definition: GreyBossDef) -> void:
	for major: int in [0, 1, 2]:
		var queued_boss: EnemyBoss = _spawn(definition)
		queued_boss.set("_next_major", major)
		queued_boss.queue_free()
		queued_boss.call("_begin_attack", _ship)
		queued_boss.call("_begin_rupture", _ship)
		_expect(queued_boss.get("_attack") == null and queued_boss.get("_displacement") == null and queued_boss.get("_tether") == null, "Queued boss major %d and direct rupture entry cannot create warnings before deferred scene exit" % major)
		await _clear()
	for major: int in [0, 1, 2]:
		for reason: int in [0, 1, 2]:
			var boss: EnemyBoss = _spawn(definition)
			boss.set("_next_major", major)
			boss.call("_begin_attack", _ship)
			var health: float = _ship.hull
			if reason == 0:
				boss.apply_damage(1000000.0)
			elif reason == 1:
				boss.queue_free()
			else:
				_ship._dead = true
				boss.call("_physics_process", 0.01)
			await _wait(0.1)
			var no_warnings: bool = _warnings(boss).is_empty() if is_instance_valid(boss) else get_tree().get_nodes_in_group("enemy_attack_telegraphs").is_empty()
			_expect(_ship.hull == health and no_warnings, "Death, source exit, or player loss cancels pending pattern %d/%d" % [major, reason])
			_expect(_ship.get_movement_slow_multiplier() == 1.0, "Cancelled helpers leave no stale movement status")
			await _clear()

func _set_fraction(boss: EnemyBoss, fraction: float) -> void:
	var pool: float = (boss.eff_max_hull + boss.eff_max_shield) * fraction
	boss.hull = minf(pool, boss.eff_max_hull)
	boss.shield = maxf(pool - boss.hull, 0.0)

func _warnings(boss: EnemyBoss) -> Array[EnemyAttackTelegraph]:
	var result: Array[EnemyAttackTelegraph] = []
	for node: Node in get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		var warning: EnemyAttackTelegraph = node as EnemyAttackTelegraph
		if warning != null and is_instance_valid(boss) and warning._source == boss and not warning.is_queued_for_deletion() and warning._active:
			result.append(warning)
	return result

func _clear() -> void:
	for boss: EnemyBoss in _bosses:
		if is_instance_valid(boss):
			boss.queue_free()
	_bosses.clear()
	_ship._dead = false
	_ship.visible = true
	await _wait(0.05)
	_expect(int(_spawner.get_alive_counts().get("enemies", 0)) == 0, "Source cleanup returns Spawner accounting to zero")

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(_suite_name() + ": " + description)
