extends Node3D

## Real rigid-body integration checks for the three evasive non-Machine scouts.
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const DEFINITIONS: Array[EnemyDef] = [
	preload("res://content/data/enemies/merc_corvette_mk1.tres"),
	preload("res://content/data/enemies/bug_sporeling_mk1.tres"),
	preload("res://content/data/enemies/grey_probe_mk1.tres"),
]

var _ship: Ship = null
var _spawner: Spawner = null
var _separation: EnemySeparation = null
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Tier One Locomotion Validation":
		push_error("Locomotion checks require the isolated validation project to protect player progress.")
		get_tree().quit(2)
		return
	GameFlow.abandon_run()
	get_tree().node_added.connect(_mute_audio)
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "TestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.hull = 100000.0
	_ship.shield = 100000.0
	_separation = EnemySeparation.new()
	add_child(_separation)
	_spawner = Spawner.new()
	_spawner.name = "TestSpawner"
	_spawner.ship_path = NodePath("../TestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	_spawner.min_distance_from_ship = 0.0
	add_child(_spawner)
	for definition: EnemyDef in DEFINITIONS:
		await _test_approach_and_orbit(definition)
		await _test_moving_player(definition)
		await _test_attack_movement(definition)
		await _test_natural_attack_cycles(definition)
	await _test_helper_vertical_and_overlap()
	for child: Node in get_children():
		child.queue_free()
	_ship = null
	_spawner = null
	_separation = null
	await _wait_frames(10)
	print("TIER1_LOCOMOTION_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn(definition: EnemyDef, at: Vector3, suppress_attacks: bool = true) -> Enemy:
	var enemy: Enemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, definition, at) as Enemy
	_check(enemy != null, "%s spawns through the real Spawner" % definition.id)
	if enemy == null:
		return null
	enemy.set_physics_process(false)
	enemy.freeze = false
	enemy.explosion_scene = null
	enemy._stop_warp_in()
	if suppress_attacks:
		enemy.set("_attack_cooldown_left", 10000.0)
	_check(enemy.collision_mask == 0, "%s still has no body collision" % definition.id)
	return enemy

func _test_approach_and_orbit(definition: EnemyDef) -> void:
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.ZERO
	var enemy: Enemy = _spawn(definition, Vector3(0.0, 0.0, 600.0))
	if enemy == null:
		return
	await _drive(enemy, 180)
	_check(enemy.global_position.distance_squared_to(_ship.global_position) < 450.0 * 450.0, "%s closes on a distant player under actual damping and thrust" % definition.id)
	var lateral_sum: float = 0.0
	var min_y: float = INF
	var max_y: float = -INF
	var max_distance: float = 0.0
	var max_speed: float = 0.0
	for frame: int in range(360):
		enemy._physics_process(1.0 / 60.0)
		await get_tree().physics_frame
		var radial: Vector3 = (_ship.global_position - enemy.global_position).normalized()
		var lateral: Vector3 = enemy.linear_velocity - radial * enemy.linear_velocity.dot(radial)
		lateral_sum += lateral.length()
		min_y = minf(min_y, enemy.global_position.y)
		max_y = maxf(max_y, enemy.global_position.y)
		max_distance = maxf(max_distance, enemy.global_position.length())
		max_speed = maxf(max_speed, enemy.linear_velocity.length())
	_check(lateral_sum / 360.0 > 70.0, "%s maintains chase-worthy lateral speed inside its combat area" % definition.id)
	_check(max_y - min_y > 8.0, "%s changes its orbit plane in three dimensions" % definition.id)
	_check(max_distance < 600.0 and enemy.global_position.is_finite() and enemy.linear_velocity.is_finite(), "%s remains bounded and finite instead of drifting away" % definition.id)
	print("TIER1_LOCOMOTION_CHECKS: %s mean lateral %.1f m/s, peak speed %.1f m/s, max radius %.1f m, vertical travel %.1f m" % [definition.id, lateral_sum / 360.0, max_speed, max_distance, max_y - min_y])
	await _remove_enemy(enemy)

func _test_moving_player(definition: EnemyDef) -> void:
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.RIGHT * 80.0
	var enemy: Enemy = _spawn(definition, Vector3(0.0, 0.0, 260.0))
	if enemy == null:
		return
	var max_gap: float = 0.0
	for frame: int in range(360):
		_ship.global_position += Vector3.RIGHT * (80.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		await get_tree().physics_frame
		max_gap = maxf(max_gap, enemy.global_position.distance_to(_ship.global_position))
	_check(enemy.global_position.x > 180.0 and max_gap < 600.0, "%s follows a continuously moving player without abandoning its orbit" % definition.id)
	_check(enemy.linear_velocity.length() > 70.0, "%s remains mobile while pursuing a moving combat center" % definition.id)
	_ship.linear_velocity = Vector3.ZERO
	await _remove_enemy(enemy)

func _test_attack_movement(definition: EnemyDef) -> void:
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.ZERO
	var start_distance: float = 70.0 if definition is BugEnemyDef else 180.0
	var enemy: Enemy = _spawn(definition, Vector3(0.0, 0.0, start_distance))
	if enemy == null:
		return
	# Enter from the actor's real cruise, rather than injecting velocity opposite
	# to its instance-specific orbit and measuring the resulting reversal.
	await _drive(enemy, 120)
	if enemy is MercEnemy:
		var corvette: MercEnemy = enemy as MercEnemy
		corvette._corvette_state = MercEnemy.CorvetteState.BURST
		corvette._burst_shots_left = 100
		corvette._burst_interval_left = 100.0
		await _drive(corvette, 45)
		_check(corvette.linear_velocity.length() > 80.0, "Corvette strafes during its firing burst")
		corvette._corvette_state = MercEnemy.CorvetteState.RETREAT
		corvette._retreat_time_left = 10.0
		await _drive(corvette, 60)
		var radial: Vector3 = (_ship.global_position - corvette.global_position).normalized()
		var lateral: Vector3 = corvette.linear_velocity - radial * corvette.linear_velocity.dot(radial)
		_check(lateral.length() > 50.0 and corvette.global_position.length() > start_distance, "Corvette retreats laterally instead of pausing after its burst")
	else:
		if enemy is BugEnemy:
			(enemy as BugEnemy)._start_attack(false, "MOVING SPORE STRIKE")
		else:
			(enemy as GreyEnemy)._start_pulse("MOVING PSIONIC PULSE")
		var warning: EnemyAttackTelegraph = enemy.get("_active_attack") as EnemyAttackTelegraph
		_check(is_instance_valid(warning), "%s begins its normal locked warning" % definition.id)
		if is_instance_valid(warning):
			warning.set_physics_process(false)
			var locked_position: Vector3 = warning._locked_position
			var locked_origin: Vector3 = warning._locked_shot_origin
			var origin: Vector3 = enemy.global_position
			await _drive(enemy, 30)
			_check(enemy.global_position.distance_squared_to(origin) > 30.0 * 30.0 and enemy.linear_velocity.length() > 80.0, "%s keeps physically strafing throughout its warning" % definition.id)
			_check(warning._locked_position.is_equal_approx(locked_position) and warning._locked_shot_origin.is_equal_approx(locked_origin), "%s movement never drags the committed hit volume or shot origin" % definition.id)
			_check(not enemy.is_separation_locked(), "%s keeps separation active during its moving warning" % definition.id)
			_ship.global_position = locked_position + Vector3.UP * warning._radius * 3.0
			var damage_before: float = _ship.hull + _ship.shield
			warning._physics_process(warning.get_time_remaining() + 0.01)
			_check(is_equal_approx(_ship.hull + _ship.shield, damage_before), "%s original warning remains avoidable after its source moves" % definition.id)
			enemy.set("_recovery_left", 1.0)
			enemy.set("_attack_cooldown_left", 0.0)
			await _drive(enemy, 30)
			_check(enemy.linear_velocity.length() > 80.0 and enemy.get("_active_attack") == null, "%s recovery suppresses new attacks without stopping locomotion" % definition.id)
	await _remove_enemy(enemy)

func _test_helper_vertical_and_overlap() -> void:
	var steering: EvasiveOrbitSteering = EvasiveOrbitSteering.new()
	for offset: Vector3 in [Vector3.ZERO, Vector3.UP * 200.0, Vector3.DOWN * 200.0]:
		var desired: Vector3 = steering.desired_velocity(1.0 / 60.0, offset, Vector3.ZERO, 100.0, 200.0, 225.0, 0.9, 1.0, 2.0, 0.8)
		_check(desired.is_finite() and desired.length() > 1.0 and desired.length() <= 225.01, "Exact overlap and polar approaches produce finite nonzero bounded steering")

func _test_natural_attack_cycles(definition: EnemyDef) -> void:
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.ZERO
	var enemy: Enemy = _spawn(definition, Vector3(0.0, 0.0, 600.0), false)
	if enemy == null:
		return
	# Leave the authored initial timer and every subsequent state/cooldown alone.
	# This catches high-speed orbit drift that could otherwise starve range gates.
	var cycles: int = 0
	var previous_burst: bool = false
	var last_warning_id: int = 0
	var combat_lateral_sum: float = 0.0
	var combat_samples: int = 0
	var max_late_radius_squared: float = 0.0
	var damage_before: float = _ship.hull + _ship.shield
	for frame: int in range(1440):
		enemy._physics_process(1.0 / 60.0)
		await get_tree().physics_frame
		if enemy is MercEnemy:
			var burst: bool = (enemy as MercEnemy)._corvette_state == MercEnemy.CorvetteState.BURST
			if burst and not previous_burst:
				cycles += 1
			previous_burst = burst
		else:
			var warning: EnemyAttackTelegraph = enemy.get("_active_attack") as EnemyAttackTelegraph
			if is_instance_valid(warning) and warning.get_instance_id() != last_warning_id:
				last_warning_id = warning.get_instance_id()
				cycles += 1
		if frame >= 360:
			var radial: Vector3 = (_ship.global_position - enemy.global_position).normalized()
			var lateral: Vector3 = enemy.linear_velocity - radial * enemy.linear_velocity.dot(radial)
			combat_lateral_sum += lateral.length()
			combat_samples += 1
			max_late_radius_squared = maxf(max_late_radius_squared, enemy.global_position.distance_squared_to(_ship.global_position))
	var mean_lateral: float = combat_lateral_sum / float(maxi(combat_samples, 1))
	_check(cycles >= 3, "%s naturally closes and repeats at least three attack cycles without forced states or timers" % definition.id)
	_check(_ship.hull + _ship.shield < damage_before, "%s naturally resolves damaging attacks against the stationary player" % definition.id)
	_check(mean_lateral > 70.0 and max_late_radius_squared < 600.0 * 600.0, "%s sustains bounded evasive movement throughout its normal attack cycle" % definition.id)
	print("TIER1_LOCOMOTION_CHECKS: %s natural attacks %d in 24 sec, combat mean lateral %.1f m/s, max late radius %.1f m" % [definition.id, cycles, mean_lateral, sqrt(max_late_radius_squared)])
	await _remove_enemy(enemy)

func _drive(enemy: Enemy, frames: int) -> void:
	for frame: int in range(frames):
		enemy._physics_process(1.0 / 60.0)
		await get_tree().physics_frame

func _remove_enemy(enemy: Enemy) -> void:
	enemy.queue_free()
	for warning: Node in get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		warning.queue_free()
	await _wait_frames(3)

func _wait_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame

func _mute_audio(node: Node) -> void:
	if node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null
	elif node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TIER1_LOCOMOTION_CHECKS: " + description)
