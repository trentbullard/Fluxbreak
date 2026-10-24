extends Node3D

## Observable spacing and live locomotion checks, isolated from player saves.
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const BASE_ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const TARGET_SCENE: PackedScene = preload("res://scenes/targets/target_object.tscn")
const CORVETTE: EnemyDef = preload("res://content/data/enemies/merc_corvette_mk1.tres")
const BOSS_PATHS: Array[String] = [
	"res://content/data/enemies/merc_contract_enforcer_mk1.tres",
	"res://content/data/enemies/merc_vanguard_flagship_mk1.tres",
	"res://content/data/enemies/bug_nestbreaker_matron_mk1.tres",
	"res://content/data/enemies/bug_first_queen_mk1.tres",
	"res://content/data/enemies/grey_witness_mk1.tres",
	"res://content/data/enemies/grey_veiled_mind_mk1.tres",
]

var _ship: Ship = null
var _arena: Node3D = null
var _service: EnemySeparation = null
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Separation Validation":
		push_error("Enemy separation checks require the isolated Fluxbreak Separation Validation project.")
		get_tree().quit(2)
		return
	get_tree().node_added.connect(_mute_audio)
	GameFlow.abandon_run()
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.hull = 100000.0
	_ship.shield = 100000.0
	await _new_arena()
	_check_nearest_and_single_use()
	await _new_arena()
	_check_ignored_objects_and_target()
	await _new_arena()
	_check_interval_and_stale_pulses()
	await _new_arena()
	_check_tight_pair_and_projection()
	await _new_arena()
	await _check_clearance_and_collision()
	await _new_arena()
	await _check_committed_states()
	await _new_arena()
	await _check_movement_family_hooks()
	await _new_arena()
	await _check_physical_crowd(2)
	await _new_arena()
	await _check_physical_crowd(50)
	await _new_arena()
	await _check_physical_crowd(100)
	_arena.queue_free()
	_ship.queue_free()
	await _wait_frames(3)
	print("ENEMY_SEPARATION_CHECKS: %s (%d checks, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _new_arena() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
		await _wait_frames(3)
	_arena = Node3D.new()
	_arena.name = "SeparationArena"
	add_child(_arena)
	_service = EnemySeparation.new()
	_arena.add_child(_service)
	_service.set_physics_process(false)
	_ship.global_position = Vector3.ZERO

func _fixture_enemy(at: Vector3, radius: float = 10.0) -> Enemy:
	var enemy: Enemy = Enemy.new()
	enemy.gravity_scale = 0.0
	enemy.freeze = true
	enemy.set_physics_process(false)
	enemy.player_ship = _ship
	enemy.def = EnemyDef.new()
	enemy.def.separation_radius = radius
	_add_visual(enemy, "VisualScene", 10.0, true)
	_arena.add_child(enemy)
	enemy.global_position = at
	return enemy

func _fixture_target(at: Vector3, radius: float = 10.0) -> TargetObject:
	var target: TargetObject = TargetObject.new()
	target.gravity_scale = 0.0
	target.freeze = true
	target.def = TargetDef.new()
	target.def.separation_radius = radius
	_add_visual(target, "VisualRoot", 12.0, false)
	_arena.add_child(target)
	target.global_position = at
	return target

func _add_visual(actor: Node3D, root_name: String, size: float, model_contract: bool) -> void:
	var visual: Node3D = Node3D.new()
	visual.name = root_name
	actor.add_child(visual)
	var model: Node3D = visual
	if model_contract:
		model = Node3D.new()
		model.name = "ModelRoot"
		visual.add_child(model)
		var muzzle: Marker3D = Marker3D.new()
		muzzle.name = "MuzzleSocket"
		model.add_child(muzzle)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE * size
	mesh.mesh = box
	model.add_child(mesh)

func _check_nearest_and_single_use() -> void:
	var source: Enemy = _fixture_enemy(Vector3(0.0, 0.0, -300.0))
	_fixture_enemy(Vector3(20.0, 0.0, -300.0))
	_fixture_enemy(Vector3(0.0, -30.0, -300.0))
	var position_before: Vector3 = source.global_position
	var basis_before: Basis = source.global_basis
	_service._scan_proximity()
	var pulse: Vector3 = _service.take_pulse(source)
	_check(pulse.length_squared() > 0.0 and pulse.normalized().dot(Vector3.LEFT) > 0.99, "Only the closest eligible neighbor determines the lateral pulse")
	_check(_service.take_pulse(source).is_zero_approx(), "A proximity result can be consumed only once")
	_check(source.global_position.is_equal_approx(position_before) and source.global_basis.is_equal_approx(basis_before), "Scanning and taking a pulse never change position or orientation")
	_check(pulse.length() <= 35.01, "Nearest-object correction has a bounded pulse speed")

func _check_ignored_objects_and_target() -> void:
	var source: Enemy = _fixture_enemy(Vector3(0.0, 0.0, -300.0))
	var dead: Enemy = _fixture_enemy(source.global_position + Vector3.RIGHT)
	dead._dead = true
	var hidden: Enemy = _fixture_enemy(source.global_position + Vector3.LEFT)
	hidden.hide()
	var queued: Enemy = _fixture_enemy(source.global_position + Vector3.UP)
	queued.queue_free()
	var poi: PoiInstance = PoiInstance.new()
	poi.position = source.position
	_arena.add_child(poi)
	_ship.global_position = source.global_position + Vector3.BACK
	_service._scan_proximity()
	_check(_service.take_pulse(source).is_zero_approx(), "Dead, hidden, queued enemies, the player and POIs are excluded")
	_ship.global_position = Vector3.ZERO
	var target: TargetObject = _fixture_target(source.global_position + Vector3.RIGHT * 20.0)
	var target_before: Transform3D = target.global_transform
	_service._scan_proximity()
	_check(_service.take_pulse(source).dot(Vector3.LEFT) > 0.0, "A live TargetObject repels a nearby enemy")
	_check(target.global_transform.is_equal_approx(target_before) and target.linear_velocity.is_zero_approx(), "The target remains stationary; only the enemy receives spacing")
	target._dead = true
	_service._scan_proximity()
	_check(_service.take_pulse(source).is_zero_approx(), "A destroyed target immediately stops contributing spacing")
	target._dead = false
	target.hide()
	_service._scan_proximity()
	_check(_service.take_pulse(source).is_zero_approx(), "A hidden target cannot produce a spacing pulse")

func _check_interval_and_stale_pulses() -> void:
	var source: Enemy = _fixture_enemy(Vector3(0.0, 0.0, -300.0))
	var neighbor: Enemy = _fixture_enemy(source.global_position + Vector3.RIGHT * 20.0)
	var before: int = _service.get_scan_count()
	_service._physics_process(0.001)
	_check(_service.get_scan_count() == before + 1, "The first update performs a proximity scan")
	for index: int in range(10):
		_service._physics_process(0.01)
	_check(_service.get_scan_count() == before + 1, "Short physics frames reuse the infrequent scan rather than repeat neighbor searches")
	_service._physics_process(0.55)
	_check(_service.get_scan_count() == before + 2, "The next scan occurs after the configured interval")
	_service._physics_process(5.0)
	_check(_service.get_scan_count() == before + 3, "A stalled frame runs a single scan without a catch-up loop")
	neighbor.hide()
	_check(_service.take_pulse(source).is_zero_approx(), "A pending result is discarded if its neighbor disappears")
	neighbor.show()
	_service._scan_proximity()
	neighbor.global_position += Vector3.RIGHT * 1000.0
	_check(_service.take_pulse(source).is_zero_approx(), "A pending result is discarded if its neighbor moved away")
	neighbor.global_position = source.global_position + Vector3.RIGHT * 20.0
	_service._scan_proximity()
	source._dead = true
	_check(_service.take_pulse(source).is_zero_approx(), "A dead recipient cannot consume an old pulse")

func _check_tight_pair_and_projection() -> void:
	var first: Enemy = _fixture_enemy(Vector3(0.0, 0.0, -300.0))
	var second: Enemy = _fixture_enemy(first.global_position)
	_service._scan_proximity()
	var a: Vector3 = _service.take_pulse(first)
	var b: Vector3 = _service.take_pulse(second)
	_check(not a.is_zero_approx() and not b.is_zero_approx(), "An exact overlap has a nonzero escape direction")
	_check(a.normalized().dot(b.normalized()) < -0.99, "An overlapping pair chooses opposite escape directions")
	_check(absf(a.z) < 0.001 and absf(b.z) < 0.001, "Overlap escape stays lateral to the approach direction")
	_service._scan_proximity()
	_check(_service.take_pulse(first).is_equal_approx(a) and _service.take_pulse(second).is_equal_approx(b), "Repeated scans retain the same tight-pair escape direction")
	second.global_position = first.global_position + Vector3(15.0, 20.0, -10.0)
	_service._scan_proximity()
	a = _service.take_pulse(first)
	var approach: Vector3 = (_ship.global_position - (first.global_position + second.global_position) * 0.5).normalized()
	var lateral_away: Vector3 = Vector3(-15.0, -20.0, 0.0).normalized()
	_check(absf(a.dot(approach)) < 0.001 and a.dot(lateral_away) > 0.0, "Ordinary spacing projects away from the neighbor without adding radial thrust")

func _check_clearance_and_collision() -> void:
	var enemy: Enemy = _fixture_enemy(Vector3(0.0, 0.0, -300.0), 31.0)
	var target: TargetObject = _fixture_target(Vector3(20.0, 0.0, -300.0), 47.0)
	_check(is_equal_approx(_service.get_clearance_radius(enemy), 31.0) and is_equal_approx(_service.get_clearance_radius(target), 47.0), "Authored clearance radii override mesh sizes for enemies and targets")
	var automatic: Enemy = _fixture_enemy(Vector3(200.0, 0.0, -300.0), 0.0)
	var detector: Area3D = Area3D.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 5000.0
	collider.shape = sphere
	detector.add_child(collider)
	automatic.add_child(detector)
	var radius: float = _service.get_clearance_radius(automatic)
	_check(radius >= 5.0 and radius < 50.0, "Automatic clearance comes from the visual hull rather than the large detection sphere")
	var layer_before: int = enemy.collision_layer
	var mask_before: int = enemy.collision_mask
	_service._scan_proximity()
	_service.take_pulse(enemy)
	_check(enemy.collision_layer == layer_before and enemy.collision_mask == mask_before, "Spacing never changes actor collision layers or masks")
	var corvette: Enemy = _spawn_actor(CORVETTE, Vector3(0.0, 0.0, -700.0))
	corvette.set_physics_process(false)
	_check(corvette.collision_layer == 8 and corvette.collision_mask == 0, "Shipped Mercs retain their targetable, noncolliding physics setup")
	var full_radius: float = _service.get_clearance_radius(corvette)
	corvette.play_warp_in()
	await _wait_frames(2)
	_check(corvette.get_visual_model_root().scale.x < 1.0 and is_equal_approx(_service.get_clearance_radius(corvette), full_radius), "Warp-in shrink preserves the cached full-size ship clearance")
	var wreck: TargetObject = TARGET_SCENE.instantiate() as TargetObject
	wreck.freeze = true
	wreck.player_ship = _ship
	wreck.configure_target(load("res://content/data/targets/wreck_medium.tres") as TargetDef)
	_arena.add_child(wreck)
	wreck.global_position = Vector3(500.0, 0.0, -300.0)
	var replacement_radius: float = _service.get_clearance_radius(wreck)
	await _wait_frames(2)
	_check(replacement_radius > 8.0 and is_equal_approx(_service.get_clearance_radius(wreck), replacement_radius), "Configured wreck clearance includes its replacement model and ignores the queued placeholder")

func _check_committed_states() -> void:
	for path: String in BOSS_PATHS:
		var definition: EnemyDef = load(path) as EnemyDef
		var boss: Enemy = _spawn_actor(definition, Vector3(0.0, 0.0, -500.0))
		boss.set_physics_process(false)
		boss.freeze = true
		_check(not boss.is_separation_locked(), "%s permits spacing during ordinary cadence" % definition.display_name)
		for state: StringName in [&"windup", &"charge", &"recovery", &"displacement", &"tether", &"brood"]:
			boss.set("_attack_state", state)
			_check(boss.is_separation_locked(), "%s preserves its committed %s state" % [definition.display_name, state])
		boss.set("_attack_state", &"cadence")
		boss.queue_free()
		await _wait_frames(2)
	var merc: MercEnemy = _spawn_actor(load("res://content/data/enemies/merc_destroyer_mk1.tres") as EnemyDef, Vector3(0.0, 0.0, -500.0)) as MercEnemy
	var bug: BugEnemy = _spawn_actor(load("res://content/data/enemies/bug_devourer_mk1.tres") as EnemyDef, Vector3(100.0, 0.0, -500.0)) as BugEnemy
	var grey: GreyEnemy = _spawn_actor(load("res://content/data/enemies/grey_seeker_mk1.tres") as EnemyDef, Vector3(-100.0, 0.0, -500.0)) as GreyEnemy
	for actor: Enemy in [merc, bug, grey]:
		actor.set_physics_process(false)
		actor.freeze = true
		_check(not actor.is_separation_locked(), "Regular %s permits spacing during locomotion" % actor.display_name)
	var tell: EnemyAttackTelegraph = EnemyAttackTelegraph.new()
	_arena.add_child(tell)
	merc._active_attack = tell
	bug._active_attack = tell
	grey._active_attack = tell
	_check(merc.is_separation_locked() and bug.is_separation_locked() and grey.is_separation_locked(), "All faction regulars protect an active attack warning")
	merc._active_attack = null
	bug._active_attack = null
	grey._active_attack = null
	bug._charge_time_left = 1.0
	_check(bug.is_separation_locked(), "Devourer travel stays locked to its warned charge corridor")
	bug._charge_time_left = 0.0
	grey._displacement = GreyDisplacement.new()
	_arena.add_child(grey._displacement)
	_check(grey.is_separation_locked(), "Grey displacement preserves its announced endpoints")
	grey._displacement.queue_free()
	grey._displacement = null
	merc._broadside_recovery_left = 1.0
	merc._escort_windup_left = 1.0
	bug._recovery_left = 1.0
	bug._brood_windup_left = 1.0
	grey._recovery_left = 1.0
	_check(merc.is_separation_locked() and bug.is_separation_locked() and grey.is_separation_locked(), "Stationary launch and recovery pauses stay stationary")
	# Consume while held, then release without a scan: no old request may fire.
	var blocker: TargetObject = _fixture_target(merc.global_position + Vector3.RIGHT * 20.0)
	merc.freeze = false
	await get_tree().physics_frame
	await get_tree().process_frame
	_service._scan_proximity()
	merc._apply_separation_pulse()
	merc._broadside_recovery_left = 0.0
	merc._escort_windup_left = 0.0
	merc._apply_separation_pulse()
	await get_tree().physics_frame
	await get_tree().process_frame
	_check(merc.linear_velocity.is_zero_approx(), "A pulse consumed during a committed hold cannot kick after the hold ends")
	blocker.queue_free()

func _check_movement_family_hooks() -> void:
	var paths: PackedStringArray = PackedStringArray([
		"res://content/data/enemies/machine_drone_mk1.tres",
		"res://content/data/enemies/merc_corvette_mk1.tres",
		"res://content/data/enemies/bug_sporeling_mk1.tres",
		"res://content/data/enemies/grey_probe_mk1.tres",
		"res://content/data/enemies/merc_contract_enforcer_mk1.tres",
	])
	for path: String in paths:
		var definition: EnemyDef = load(path) as EnemyDef
		var actor: Enemy = _spawn_actor(definition, Vector3(0.0, 0.0, -1200.0))
		actor.set_physics_process(false)
		if actor is MercEnemy:
			(actor as MercEnemy)._attack_cooldown_left = 1000.0
		elif actor is BugEnemy:
			(actor as BugEnemy)._attack_cooldown_left = 1000.0
		elif actor is GreyEnemy:
			(actor as GreyEnemy)._attack_cooldown_left = 1000.0
		var blocker: TargetObject = _fixture_target(actor.global_position + Vector3.RIGHT * 20.0)
		await get_tree().physics_frame
		await get_tree().process_frame
		var position_before: Vector3 = actor.global_position
		var layer_before: int = actor.collision_layer
		var mask_before: int = actor.collision_mask
		actor.linear_velocity = Vector3.ZERO
		actor.angular_velocity = Vector3.ZERO
		_service._scan_proximity()
		var planned: Vector3 = _service.take_pulse(actor)
		_service._scan_proximity()
		actor._physics_process(0.0)
		_check(_service.take_pulse(actor).is_zero_approx(), "%s consumes a scheduled pulse during normal movement" % definition.display_name)
		_check(actor.global_position.is_equal_approx(position_before), "%s spacing uses velocity without snapping its position" % definition.display_name)
		_check(actor.collision_layer == layer_before and actor.collision_mask == mask_before, "%s movement hook preserves collision settings" % definition.display_name)
		await get_tree().physics_frame
		await get_tree().process_frame
		_check(planned.length_squared() > 0.0 and actor.linear_velocity.dot(planned.normalized()) >= planned.length() * 0.9, "%s receives its spacing pulse through its existing movement callback" % definition.display_name)
		actor.queue_free()
		blocker.queue_free()
		await _wait_frames(3)

func _spawn_actor(definition: EnemyDef, at: Vector3) -> Enemy:
	var actor_scene: PackedScene = definition.actor_scene if definition.actor_scene != null else BASE_ENEMY_SCENE
	var actor: Enemy = actor_scene.instantiate() as Enemy
	actor.set_ship(_ship)
	var context: EnemySpawnContext = EnemySpawnContext.from_enemy_def(definition)
	context.is_summoned = true
	context.grants_kill_rewards = false
	context.contributes_to_pressure = false
	actor.configure_enemy(definition, context)
	actor.explosion_scene = null
	_arena.add_child(actor)
	actor.global_position = at
	return actor

func _check_physical_crowd(count: int) -> void:
	var actors: Array[Enemy] = []
	var start: Vector3 = Vector3(0.0, 0.0, -1200.0)
	for index: int in range(count):
		var actor: MercEnemy = _spawn_actor(CORVETTE, start) as MercEnemy
		actor._attack_cooldown_left = 1000.0
		actors.append(actor)
	_service.set_physics_process(true)
	for frame: int in range(300):
		await get_tree().physics_frame
	var nearest_sum: float = 0.0
	var lateral_sum: float = 0.0
	var forward_sum: float = 0.0
	var all_finite_and_bounded: bool = true
	var collision_unchanged: bool = true
	for actor: Enemy in actors:
		var nearest_sq: float = INF
		for other: Enemy in actors:
			if other != actor:
				nearest_sq = minf(nearest_sq, actor.global_position.distance_squared_to(other.global_position))
		nearest_sum += sqrt(nearest_sq)
		lateral_sum += Vector2(actor.global_position.x, actor.global_position.y).length()
		forward_sum += actor.global_position.z - start.z
		all_finite_and_bounded = all_finite_and_bounded and actor.global_position.is_finite() and actor.linear_velocity.is_finite() and actor.linear_velocity.length() < 180.0
		collision_unchanged = collision_unchanged and actor.collision_layer == 8 and actor.collision_mask == 0
	var nearest_mean: float = nearest_sum / float(count)
	print("SEPARATION_CROWD: %d Mercs, mean nearest %.2f m, mean lateral %.2f m, approach %.2f m, %d scans" % [count, nearest_mean, lateral_sum / float(count), forward_sum / float(count), _service.get_scan_count()])
	_check(nearest_mean > 1.0, "%d exactly overlapped live Mercs physically spread without collisions" % count)
	_check(lateral_sum / float(count) > 5.0, "%d Mercs gain visible lateral dispersion" % count)
	_check(forward_sum / float(count) > 20.0, "%d Mercs retain their approach locomotion while dispersing" % count)
	_check(all_finite_and_bounded, "%d Mercs remain numerically stable without runaway pulse speed" % count)
	_check(collision_unchanged, "%d Mercs keep collisions disabled throughout physical dispersion" % count)
	_check(_service.get_scan_count() >= 8 and _service.get_scan_count() <= 11, "%d Mercs share infrequent proximity scans rather than per-frame searches" % count)
	if count == 100:
		var start_usec: int = Time.get_ticks_usec()
		for sample: int in range(20):
			_service._scan_proximity()
		var mean_ms: float = float(Time.get_ticks_usec() - start_usec) / 20000.0
		print("SEPARATION_SCAN_COST: 100 live Mercs, 20 warmed scans, mean %.3f ms" % mean_ms)

func _wait_frames(count: int) -> void:
	for index: int in range(count):
		await get_tree().process_frame

func _mute_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("Enemy separation: " + message)
