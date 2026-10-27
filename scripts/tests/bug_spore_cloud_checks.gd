extends Node3D

class DamageTarget extends Node3D:
	var damage_taken: float = 0.0
	var damage_calls: int = 0
	var dot_calls: int = 0
	var alive: bool = true
	var damage_values: Array[float] = []
	var contexts: Array[CombatStatContext] = []
	var damage_callback: Callable = Callable()
	func apply_damage(amount: float, context: CombatStatContext = null) -> void:
		damage_taken += amount
		damage_calls += 1
		damage_values.append(amount)
		contexts.append(context.duplicate_context() if context != null else null)
		if damage_callback.is_valid():
			damage_callback.call()
	func apply_damage_over_time(amount: float, context: CombatStatContext = null) -> void:
		dot_calls += 1
		apply_damage(amount, context)
	func is_alive() -> bool:
		return alive
	func get_evasion() -> float:
		return 1.0
	func reset_damage() -> void:
		damage_taken = 0.0
		damage_calls = 0
		dot_calls = 0
		damage_values.clear()
		contexts.clear()
		damage_callback = Callable()
		alive = true
		visible = true
		global_position = Vector3.ZERO

class FeedbackShip extends Ship:
	var flashes: int = 0
	var hit_sounds: int = 0
	func _flash_shield() -> void:
		flashes += 1
	func _play_hit_sound(_player: AudioStreamPlayer3D) -> void:
		hit_sounds += 1

class FinalizingShip extends FeedbackShip:
	func _die() -> void:
		_dead = true
		GameFlow._finalize_run_stats(true)

const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const SPORELING: BugEnemyDef = preload("res://content/data/enemies/bug_sporeling_mk1.tres")

var _checks: int = 0
var _failures: int = 0
var _ship: Ship = null
var _target: DamageTarget = null
var _spawner: Spawner = null
var _source: BugEnemy = null
var _enemies: Array[Enemy] = []
var _clouds: Array[BugSporeCloud] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run_checks.call_deferred()

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Bug Validation":
		push_error("Spore cloud checks require the isolated Bug validation project.")
		get_tree().quit(2)
		return
	GameFlow.abandon_run()
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "TestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.hull = 100000.0
	_ship.shield = 0.0
	_ship.eff_evasion = 1.0
	_ship.eff_damage_taken_mult = 1.0
	for audio: Node in _ship.find_children("*", "AudioStreamPlayer3D", true, false):
		(audio as AudioStreamPlayer3D).stream = null
	_target = DamageTarget.new()
	add_child(_target)
	_spawner = Spawner.new()
	_spawner.name = "TestSpawner"
	_spawner.ship_path = NodePath("../TestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	_spawner.min_distance_from_ship = 0.0
	add_child(_spawner)
	_source = _spawn_source()
	_check_formula_and_timing()
	await _clear_clouds()
	_check_overlap_and_independence()
	await _clear_clouds()
	_check_entry_exit_and_locked_position()
	await _clear_clouds()
	_check_snapshot_and_scaling()
	await _clear_clouds()
	_check_large_steps_and_duration_boundaries()
	await _clear_clouds()
	_check_cancelled_catchup()
	await _clear_clouds()
	await _check_pause_and_cancellation()
	await _clear_clouds()
	_check_ship_damage_path()
	await _clear_clouds()
	_check_stacked_feedback()
	_check_queued_damage_attribution()
	for enemy: Enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_expect(int(_spawner.get_alive_counts().get("enemies", 0)) == 0, "Cloud tests leave no actors in Spawner accounting")
	GameFlow.abandon_run()
	print("BUG_SPORE_CLOUD_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_source(request: SpawnRequest = null) -> BugEnemy:
	var actual_request: SpawnRequest = request if request != null else SpawnRequest.new()
	actual_request.grants_kill_rewards = false
	actual_request.contributes_to_pressure = false
	var enemy: BugEnemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, SPORELING, Vector3(0.0, 0.0, 75.0), actual_request) as BugEnemy
	_expect(enemy != null, "A real Sporeling supplies cloud ownership and its resolved weapon")
	if enemy != null:
		_enemies.append(enemy)
		enemy.freeze = true
		enemy.set_physics_process(false)
		enemy._stop_warp_in()
		enemy.explosion_scene = null
		if enemy._regen_timer != null:
			enemy._regen_timer.stop()
		for audio: Node in enemy.find_children("*", "AudioStreamPlayer3D", true, false):
			(audio as AudioStreamPlayer3D).stream = null
	return enemy

func _cloud(duration: float = 3.0, damage: float = 10.0, target: Node3D = null, source: BugEnemy = null, interval: float = 0.5, multiplier: float = 1.2) -> BugSporeCloud:
	var actor: BugEnemy = source if source != null else _source
	var host: EnemyTurret = actor._first_valid_turret()
	host.eff_damage_min = damage
	host.eff_damage_max = damage
	return _cloud_from_host(actor, host, target if target != null else _target, duration, interval, multiplier)

func _cloud_from_host(source: BugEnemy, host: EnemyTurret, target: Node3D, duration: float = 3.0, interval: float = 0.5, multiplier: float = 1.2) -> BugSporeCloud:
	var cloud: BugSporeCloud = BugSporeCloud.new()
	add_child(cloud)
	cloud.set_warning_style("SPORE CLOUD", BugEnemy.ATTACK_COLOR)
	cloud.start_cloud(source, target, host, duration, 26.0, interval, multiplier)
	cloud.set_physics_process(false)
	_clouds.append(cloud)
	return cloud

func _check_formula_and_timing() -> void:
	_target.reset_damage()
	var cloud: BugSporeCloud = _cloud()
	var events: Dictionary = {"count": 0, "hit": false}
	cloud.resolved.connect(func(hit: bool) -> void:
		events["count"] = int(events["count"]) + 1
		events["hit"] = hit
	)
	_expect(_target.damage_calls == 1 and is_equal_approx(_target.damage_taken, 4.0), "A ten-damage strike becomes an immediate four-damage tick: 10 × 1.2 / 3")
	_expect(_target.dot_calls == 1 and _target.contexts[0] != null and _target.contexts[0].enemy_id == StringName(SPORELING.id), "The first tick uses DOT delivery with its enemy attribution")
	_expect(cloud.is_warning_for(_target) and cloud.get_attack_label().contains("SPORE") and is_equal_approx(cloud.get_time_remaining(), 3.0), "Active clouds retain shared HUD metadata and their full lifetime")
	var visual: BugSporeCloudVisual = cloud._attack_field as BugSporeCloudVisual
	_expect(visual != null and visual.material_override is StandardMaterial3D and is_equal_approx((visual.material_override as StandardMaterial3D).albedo_color.a, 0.5) and visual._spores != null and visual._spores.multimesh.instance_count == BugSporeCloudVisual.SPORE_COUNT and is_equal_approx((visual._spores.multimesh.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.a, 0.25) and cloud.find_children("*", "GPUParticles3D", true, false).is_empty() and cloud.find_children("*", "Label3D", true, false).is_empty(), "The cloud uses static batched sprites at quarter alpha and retains its half-alpha native boundary, without emitters or text")
	cloud._physics_process(0.499)
	_expect(_target.damage_calls == 1, "No second tick occurs before half a second")
	cloud._physics_process(0.001)
	_expect(_target.damage_calls == 2 and is_equal_approx(_target.damage_taken, 8.0), "The next tick occurs at the half-second boundary")
	for tick: int in range(4):
		cloud._physics_process(0.5)
	_expect(_target.damage_calls == 6 and is_equal_approx(_target.damage_taken, 24.0), "Three seconds provide six ticks at 0, .5, 1, 1.5, 2 and 2.5")
	cloud._physics_process(0.5)
	_expect(_target.damage_calls == 6 and int(events["count"]) == 1 and bool(events["hit"]), "Expiry emits completion once and causes no final strike or seventh tick")
	cloud._physics_process(EnemyAttackTelegraph.RELEASE_FLASH_SEC + 0.01)
	_expect(cloud.is_queued_for_deletion() and _target.damage_calls == 6 and int(events["count"]) == 1, "The existing terminal flash retires without damage or duplicate completion")

func _check_overlap_and_independence() -> void:
	_target.reset_damage()
	var first: BugSporeCloud = _cloud()
	var second: BugSporeCloud = _cloud()
	_expect(_target.damage_calls == 2 and is_equal_approx(_target.damage_taken, 8.0), "Two overlapping clouds each apply their own immediate tick")
	first._physics_process(0.5)
	second._physics_process(0.25)
	_expect(_target.damage_calls == 3, "One cloud's tick cannot advance another cloud's timer")
	second._physics_process(0.25)
	_expect(_target.damage_calls == 4 and is_equal_approx(_target.damage_taken, 16.0), "Both overlapping clouds continue to tick independently")
	first.cancel()
	second._physics_process(0.5)
	_expect(_target.damage_calls == 5, "Cancelling one cloud leaves the other's timer and damage active")
	_target.reset_damage()
	for cloud_index: int in range(12):
		_cloud()
	_expect(_target.damage_calls == 12 and is_equal_approx(_target.damage_taken, 48.0), "Sporeling clouds do not inherit the Hive spore zone's eight-volume cap")

func _check_entry_exit_and_locked_position() -> void:
	_target.reset_damage()
	var cloud: BugSporeCloud = _cloud()
	var position: Vector3 = cloud.global_position
	_target.global_position = Vector3.RIGHT * 80.0
	cloud._physics_process(1.1)
	_expect(_target.damage_calls == 1, "Time outside the cloud causes no poison damage")
	_source.global_position += Vector3.UP * 90.0
	_target.global_position = position
	cloud._physics_process(0.01)
	_expect(_target.damage_calls == 2, "Returning after the cloud's cooldown applies one immediate contact tick without outside backlog")
	_target.global_position = Vector3.RIGHT * 80.0
	cloud._physics_process(0.05)
	_target.global_position = position
	cloud._physics_process(0.05)
	_expect(_target.damage_calls == 2, "Rapidly crossing the cloud boundary cannot create extra immediate ticks")
	cloud._physics_process(0.4)
	_expect(_target.damage_calls == 3, "The same cloud resumes after its original half-second cooldown")
	_expect(cloud.global_position.is_equal_approx(position) and cloud._locked_position.is_equal_approx(position), "Source and target movement never drag the deposited cloud")
	_source.global_position = Vector3(0.0, 0.0, 75.0)
	_target.global_position = Vector3.ZERO

func _check_snapshot_and_scaling() -> void:
	_target.reset_damage()
	var cloud: BugSporeCloud = _cloud()
	var host: EnemyTurret = _source._first_valid_turret()
	host.eff_damage_min = 1000.0
	host.eff_damage_max = 1000.0
	cloud._physics_process(0.5)
	_expect(is_equal_approx(_target.damage_taken, 8.0), "Later weapon changes cannot alter a cloud's captured tick damage")
	var scaling: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
	scaling.damage_multiplier = 2.0
	var request: SpawnRequest = SpawnRequest.new()
	request.enemy_combat_scaling = scaling
	var source: BugEnemy = _spawn_source(request)
	var scaled_host: EnemyTurret = source._first_valid_turret()
	var minimum: float = scaled_host.eff_damage_min * 1.2 / 3.0
	var maximum: float = scaled_host.eff_damage_max * 1.2 / 3.0
	_expect(is_equal_approx(minimum, 3.84) and is_equal_approx(maximum, 6.72), "The twofold encounter damage snapshot enters the requested cloud formula once")
	_target.reset_damage()
	var scaled: BugSporeCloud = _cloud_from_host(source, scaled_host, _target)
	scaled._physics_process(0.5)
	var within_snapshot: bool = true
	for amount: float in _target.damage_values:
		within_snapshot = within_snapshot and amount >= minimum - 0.0001 and amount <= maximum + 0.0001
	_expect(_target.damage_calls == 2 and within_snapshot, "Each scaled poison tick uses the captured damage range without a second scaling pass")

func _check_large_steps_and_duration_boundaries() -> void:
	for steps: Array in [[3.0], [0.25, 0.25, 0.5, 0.75, 1.25], [0.1, 0.4, 0.5, 0.5, 0.5, 0.5, 0.5]]:
		_target.reset_damage()
		var cloud: BugSporeCloud = _cloud()
		for step: float in steps:
			cloud._physics_process(step)
		_expect(_target.damage_calls == 6 and is_equal_approx(_target.damage_taken, 24.0), "Different frame steps preserve six ticks with an exclusive expiry boundary")
		cloud.cancel()
	_target.reset_damage()
	var boundary: BugSporeCloud = _cloud(1.0, 10.0)
	boundary._physics_process(1.0)
	_expect(_target.damage_calls == 2 and is_equal_approx(_target.damage_taken, 24.0), "A one-second cloud gets ticks at zero and .5 without an expiry tick")
	boundary.cancel()

func _check_pause_and_cancellation() -> void:
	_target.reset_damage()
	var cloud: BugSporeCloud = _cloud()
	cloud.set_physics_process(true)
	get_tree().paused = true
	var remaining: float = cloud.get_time_remaining()
	for frame: int in range(4):
		await get_tree().process_frame
	_expect(is_equal_approx(cloud.get_time_remaining(), remaining) and _target.damage_calls == 1, "Pausing freezes cloud lifetime and poison ticks")
	get_tree().paused = false
	cloud.set_physics_process(false)
	cloud.cancel()
	_target.reset_damage()
	var source: BugEnemy = _spawn_source()
	var pending: BugSporeCloud = _cloud(3.0, 10.0, _target, source)
	source.apply_damage(1000000.0)
	_expect(pending.is_queued_for_deletion(), "Source death cancels its deposited cloud through existing attack ownership")
	await get_tree().process_frame
	var exiting_source: BugEnemy = _spawn_source()
	var exiting: BugSporeCloud = _cloud(3.0, 10.0, _target, exiting_source)
	exiting_source.queue_free()
	await get_tree().process_frame
	_expect(not is_instance_valid(exiting) or exiting.is_queued_for_deletion(), "Source exit leaves no orphaned cloud")
	_target.reset_damage()
	var hidden: BugSporeCloud = _cloud()
	_target.hide()
	hidden._physics_process(0.5)
	_expect(hidden.is_queued_for_deletion() and _target.damage_calls == 1, "A hidden or ended player cancels future poison ticks")
	_target.show()

func _check_cancelled_catchup() -> void:
	_target.reset_damage()
	var owner: Dictionary = {"cloud": null}
	_target.damage_callback = func() -> void:
		if _target.damage_calls == 2:
			(owner["cloud"] as BugSporeCloud).cancel()
	var cancelled: BugSporeCloud = _cloud()
	owner["cloud"] = cancelled
	cancelled._physics_process(3.0)
	_expect(_target.damage_calls == 2 and cancelled.is_queued_for_deletion(), "A target callback cancelling the cloud stops all remaining catch-up ticks")
	cancelled._physics_process(1.0)
	_expect(_target.damage_calls == 2, "A queued cloud cannot resume damage after cancellation during a tick")
	_target.reset_damage()
	_target.damage_callback = func() -> void:
		if _target.damage_calls == 2:
			_target.alive = false
	var terminal: BugSporeCloud = _cloud()
	terminal._physics_process(3.0)
	_expect(_target.damage_calls == 2 and terminal.is_queued_for_deletion(), "Target death during catch-up cancels the cloud before any later due tick")
	_target.reset_damage()

func _check_ship_damage_path() -> void:
	_ship.global_position = Vector3.ZERO
	_ship._dead = false
	_ship.hull = 100.0
	_ship.shield = 3.0
	_ship.eff_damage_taken_mult = 0.5
	var before: float = CombatStats._frame_damage_taken
	var cloud: BugSporeCloud = _cloud(3.0, 10.0, _ship)
	_expect(is_equal_approx(_ship.shield, 1.0) and is_equal_approx(_ship.hull, 100.0), "Poison ticks respect player damage reduction and shield absorption")
	cloud._physics_process(0.5)
	_expect(is_zero_approx(_ship.shield) and is_equal_approx(_ship.hull, 99.0), "Later poison ticks consume remaining shields before damaging hull")
	_expect(is_equal_approx(CombatStats._frame_damage_taken - before, 4.0), "Rate-limited cosmetic feedback preserves every applied damage report")
	_ship.hull = 100000.0
	_ship.eff_damage_taken_mult = 1.0

func _check_stacked_feedback() -> void:
	# No scene insertion is needed: only damage delivery and feedback are exercised.
	var ship: FeedbackShip = FeedbackShip.new()
	ship.hull = 100.0
	ship.shield = 100.0
	ship.eff_damage_taken_mult = 1.0
	var reported_before: float = CombatStats._frame_damage_taken
	for hit: int in range(3):
		ship.apply_damage_over_time(5.0)
	_expect(is_equal_approx(ship.shield, 85.0) and is_equal_approx(ship.hull, 100.0), "Three simultaneous DOT hits all apply their complete shield damage")
	_expect(ship.flashes == 1 and ship.hit_sounds == 1, "Rapidly stacked DOT hits share one shield-flash and sound window")
	ship.apply_damage(5.0)
	_expect(is_equal_approx(ship.shield, 80.0) and ship.flashes == 2 and ship.hit_sounds == 2, "Ordinary weapon hits retain immediate feedback during the DOT cosmetic cooldown")
	_expect(is_equal_approx(CombatStats._frame_damage_taken - reported_before, 20.0), "Shared DOT feedback never merges away damage statistics")
	ship.free()

func _clear_clouds() -> void:
	for cloud: BugSporeCloud in _clouds:
		if is_instance_valid(cloud):
			cloud.cancel()
	_clouds.clear()
	await get_tree().process_frame
	await get_tree().physics_frame

func _queued_context(enemy_id: StringName, weapon_id: StringName) -> CombatStatContext:
	var context: CombatStatContext = CombatStatContext.new()
	context.pilot_id = GameFlow._run_pilot_id
	context.ship_id = &"starter_fighter"
	context.weapon_direct_id = weapon_id
	context.equipped_weapon_ids.assign([&"pulse_mk1", &"laser_mk1"])
	context.enemy_id = enemy_id
	context.faction_id = &"bugs"
	context.role_id = &"brawler"
	return context

func _check_queued_damage_attribution() -> void:
	GameFlow.start_new_run(PracticeRunFactory.create_run(&"bugs", false))
	var pilot_id: String = String(GameFlow._run_pilot_id)
	var first: CombatStatContext = _queued_context(&"bug_sporeling_mk1", &"cloud_source_a")
	var second: CombatStatContext = _queued_context(&"bug_broodmother_mk1", &"cloud_source_b")
	GameFlow.queue_damage_taken(2.0, first)
	GameFlow.queue_damage_taken(3.0, first)
	GameFlow.queue_damage_taken(7.0, second)
	_expect(GameFlow._run_meta_stats_global.is_empty(), "Queued DOT defers stat-key work until its grouped flush")
	first.enemy_id = &"changed_after_queuing"
	GameFlow.record_damage_taken(1.0, second)
	_expect(is_equal_approx(float(GameFlow._run_meta_stats_global.get("damage_taken", 0.0)), 1.0), "Ordinary damage still updates run statistics immediately")
	GameFlow._flush_pending_damage_taken()
	var totals: Dictionary = GameFlow._run_meta_stats_global
	_expect(is_equal_approx(float(totals.get("damage_taken", 0.0)), 13.0) and is_equal_approx(float(totals.get("damage_taken|enemy|bug_sporeling_mk1", 0.0)), 5.0) and is_equal_approx(float(totals.get("damage_taken|enemy|bug_broodmother_mk1", 0.0)), 8.0), "Grouped DOT preserves exact global totals and distinct enemy attribution")
	_expect(is_equal_approx(float(totals.get("damage_taken|weapon_direct|cloud_source_a", 0.0)), 5.0) and is_equal_approx(float(totals.get("damage_taken|weapon_direct|cloud_source_b", 0.0)), 8.0) and not totals.has("damage_taken|enemy|changed_after_queuing"), "Queued contexts preserve separate source weapons and cannot be rewritten by the caller")
	var pilot_totals: Dictionary = GameFlow._run_meta_stats_by_pilot_id.get(pilot_id, {})
	_expect(is_equal_approx(float(pilot_totals.get("damage_taken", 0.0)), 13.0) and is_equal_approx(float(pilot_totals.get("damage_taken|enemy|bug_sporeling_mk1", 0.0)), 5.0), "Queued totals retain their pilot slice as well as global attribution")
	GameFlow._flush_pending_damage_taken()
	_expect(is_equal_approx(float(totals.get("damage_taken", 0.0)), 13.0), "Flushing the same frame twice cannot duplicate queued damage")
	GameFlow.abandon_run()
	# Exercise the actual Ship ordering: the final applied point is queued before
	# its death callback finalizes the run, without changing this test's scene.
	GameFlow.start_new_run(PracticeRunFactory.create_run(&"bugs", false))
	var lethal_context: CombatStatContext = _queued_context(&"bug_sporeling_mk1", &"lethal_cloud")
	var lifetime_before: int = GameFlow.get_meta_stat_value(GameFlow.META_STAT_DAMAGE_TAKEN)
	var lethal: FinalizingShip = FinalizingShip.new()
	lethal.hull = 3.0
	lethal.shield = 0.0
	lethal.eff_damage_taken_mult = 1.0
	lethal.apply_damage_over_time(8.0, lethal_context)
	_expect(not lethal.is_alive() and not GameFlow._run_active and GameFlow.get_meta_stat_value(GameFlow.META_STAT_DAMAGE_TAKEN) == lifetime_before + 3, "Lethal DOT flushes the final applied damage before immediate Campaign finalization")
	lethal.free()
	GameFlow.abandon_run()
	GameFlow.start_new_run(PracticeRunFactory.create_run(&"bugs", true))
	var saved_before: String = FileAccess.get_file_as_string(GameFlow.SAVE_PATH)
	var lifetime_totals: Dictionary = GameFlow._meta_stats_global.duplicate(true)
	GameFlow.queue_damage_taken(55.0, _queued_context(&"bug_sporeling_mk1", &"practice_cloud"))
	GameFlow._finalize_run_end(true)
	_expect(GameFlow._meta_stats_global == lifetime_totals and FileAccess.get_file_as_string(GameFlow.SAVE_PATH) == saved_before, "Practice finalization discards queued DOT without saved progression")
	GameFlow.start_new_run(PracticeRunFactory.create_run(&"bugs", false))
	GameFlow.queue_damage_taken(100.0, _queued_context(&"bug_sporeling_mk1", &"abandoned_cloud"))
	GameFlow.abandon_run()
	GameFlow.start_new_run(PracticeRunFactory.create_run(&"bugs", false))
	GameFlow.queue_damage_taken(2.0, _queued_context(&"bug_broodmother_mk1", &"fresh_cloud"))
	GameFlow._flush_pending_damage_taken()
	_expect(is_equal_approx(float(GameFlow._run_meta_stats_global.get("damage_taken", 0.0)), 2.0) and not GameFlow._run_meta_stats_global.has("damage_taken|weapon_direct|abandoned_cloud"), "Abandoning an encounter cannot leak pending DOT into the next run")
	GameFlow.queue_damage_taken(40.0, _queued_context(&"bug_sporeling_mk1", &"restarted_cloud"))
	GameFlow.start_new_run(PracticeRunFactory.create_run(&"bugs", false))
	GameFlow._flush_pending_damage_taken()
	_expect(GameFlow._run_meta_stats_global.is_empty(), "Starting a new encounter directly also clears its predecessor's pending DOT")
	GameFlow.abandon_run()

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("BUG_SPORE_CLOUD_CHECKS: " + message)
