extends Node3D

## Exercises shipped drops and both real death paths in a save-isolated project.
const SWARM_SCENE: PackedScene = preload("res://scenes/drops/nanobot_swarm.tscn")
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const TARGET_SCENE: PackedScene = preload("res://scenes/targets/target_object.tscn")
const ENEMY_DEF: EnemyDef = preload("res://content/data/enemies/machine_drone_mk1.tres")
const TARGET_DEF: TargetDef = preload("res://content/data/targets/wreck_medium.tres")

var _actors: Node3D = null
var _ship: Ship = null
var _spawner: Spawner = null
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Nanobot Swarm Validation":
		push_error("Nanobot checks require their isolated validation wrapper.")
		get_tree().quit(2)
		return
	GameFlow.abandon_run()
	get_tree().node_added.connect(_mute_audio)
	_actors = Node3D.new()
	_actors.name = "Actors"
	_actors.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_actors)
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "TestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	_actors.add_child(_ship)
	_ship.eff_nanobot_gain_mult = 1.25
	_spawner = Spawner.new()
	_spawner.ship_path = NodePath("../TestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.target_scene = TARGET_SCENE
	_spawner.directed_mode = true
	_spawner.min_distance_from_ship = 0.0
	_actors.add_child(_spawner)
	await _check_linear_value()
	await _check_independence_and_no_player()
	await _check_pause()
	await _check_magnet_and_pickup()
	await _check_terminal_races()
	await _check_death_paths()
	await _check_visual_fade()
	_actors.queue_free()
	_actors = null
	_ship = null
	_spawner = null
	await _wait_frames(5)
	print("NANOBOT_SWARM_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	call_deferred("_finish")

func _spawn(value: int, at: Vector3 = Vector3(10000.0, 0.0, 0.0)) -> NanobotSwarm:
	var swarm: NanobotSwarm = SWARM_SCENE.instantiate() as NanobotSwarm
	_check(swarm.initialize(value), "Explicit initialization succeeds before insertion")
	swarm.position = at
	_actors.add_child(swarm)
	swarm.set_process(false)
	return swarm

func _check_linear_value() -> void:
	var swarm: NanobotSwarm = _spawn(400)
	_check(is_equal_approx(swarm.lifetime_sec, 120.0), "Authored lifetime is 120 seconds")
	_check(swarm.get_remaining_value() == 400 and is_zero_approx(swarm.get_age_sec()), "Insertion preserves the full initialized value")
	_check(not swarm.initialize(9999), "Initialization cannot reset a live drop")
	swarm.value = 9999
	_check(swarm.get_remaining_value() == 400, "Later writes cannot reset original value")
	for index: int in range(1, 4):
		swarm._process(30.0)
		_check(swarm.get_remaining_value() == 400 - index * 100, "Exact remaining value at %d seconds" % (index * 30))
		_check(is_equal_approx(swarm.get_value_fraction(), 1.0 - float(index) * 0.25), "Value fraction follows linear decay")
		_check(swarm.is_active(), "A positive remaining value stays available")
	var before: int = _ship.get_nanobots()
	swarm._process(30.0)
	_check(swarm.get_remaining_value() == 0 and not swarm.is_active(), "At 120 seconds the swarm expires")
	_check(swarm.is_queued_for_deletion() and _ship.get_nanobots() == before, "Expiration removes the swarm without credit")
	await _wait_frames(2)
	for original: int in [1, 7, 101]:
		var small: NanobotSwarm = _spawn(original)
		small._process(30.0)
		_check(small.get_remaining_value() == int(ceil(float(original) * 0.75)), "Fractional payouts round upward while positive")
		small._process(89.999)
		_check(small.get_remaining_value() == 1 and small.is_active(), "Tiny positive drops survive until the deadline")
		small._process(0.01)
		_check(not small.is_active() and small.get_remaining_value() == 0, "Tiny drops expire at the same deadline")
	await _wait_frames(2)
	for original: int in [0, -100]:
		var empty: NanobotSwarm = _spawn(original)
		_check(not empty.is_active() and empty.get_remaining_value() == 0, "Zero or negative initialization leaves no immortal drop")
	await _wait_frames(2)

func _check_independence_and_no_player() -> void:
	var first: NanobotSwarm = _spawn(400)
	var second: NanobotSwarm = _spawn(800)
	first._process(30.0)
	second._process(60.0)
	_check(first.get_remaining_value() == 300 and second.get_remaining_value() == 400, "Overlapping swarms remain separate with independent ages")
	_check(first.get_instance_id() != second.get_instance_id(), "No merge replaces neighboring swarms")
	_ship.remove_from_group("player")
	first._player = null
	first._process(30.0)
	_check(is_equal_approx(first.get_age_sec(), 60.0) and first.get_remaining_value() == 200, "Decay continues with no valid player")
	_ship.add_to_group("player")
	_check(_ship.get_nanobots() == 0, "Uncollected drops never automatically credit the player")
	first.queue_free()
	second.queue_free()
	await _wait_frames(2)

func _check_pause() -> void:
	var swarm: NanobotSwarm = _spawn(10000)
	swarm.set_process(true)
	await _wait_frames(3)
	var age_before: float = swarm.get_age_sec()
	var value_before: int = swarm.get_remaining_value()
	get_tree().paused = true
	await _wait_frames(6)
	_check(is_equal_approx(swarm.get_age_sec(), age_before) and swarm.get_remaining_value() == value_before, "Gameplay pause suspends decay")
	get_tree().paused = false
	await _wait_frames(3)
	_check(swarm.get_age_sec() > age_before and swarm.get_remaining_value() <= value_before, "Decay resumes with gameplay")
	swarm.queue_free()
	await _wait_frames(2)

func _check_magnet_and_pickup() -> void:
	var original_range: float = _ship.eff_pickup_range
	_ship.eff_pickup_range = 100.0
	var swarm: NanobotSwarm = _spawn(400, Vector3(150.0, 0.0, 0.0))
	_check(is_equal_approx(swarm.pickup_distance, 5.0) and is_equal_approx(swarm.move_towards_player_speed, 120.0), "Pickup distance and attraction movement remain authored")
	_check(is_equal_approx(swarm.magnet_delay, 0.6) and is_equal_approx(swarm.ramp_time, 0.5), "Magnet delay and ramp remain unchanged")
	swarm._process(30.0)
	_check(not swarm._magnet_on and swarm.position.is_equal_approx(Vector3(150.0, 0.0, 0.0)) and swarm.get_remaining_value() == 300, "Out-of-range drops age without moving or activating magnet")
	swarm.queue_free()
	var attracting: NanobotSwarm = _spawn(12000, Vector3(90.0, 0.0, 0.0))
	attracting._process(0.3)
	_check(attracting._magnet_on and attracting.position.is_equal_approx(Vector3(90.0, 0.0, 0.0)), "The same pickup range starts the existing magnet delay")
	attracting._process(0.4)
	_check(is_equal_approx(attracting._collection_pos.x, 42.0) and is_equal_approx(attracting.position.x, 42.0), "Collection point and visuals retain 120 m/s attraction")
	_check(attracting.get_remaining_value() == 11930, "Decay continues throughout attraction")
	attracting.queue_free()
	_ship.eff_pickup_range = original_range
	await _wait_frames(2)

func _check_terminal_races() -> void:
	var committed: NanobotSwarm = _spawn(400)
	committed._process(60.0)
	committed._collection_pos = _ship.global_position
	var before: int = _ship.get_nanobots()
	committed._process(0.0)
	_check(not committed.is_active(), "Pickup commits a terminal state before deferred credit")
	committed._process(121.0)
	committed.value = 999999
	committed._on_picked()
	committed._on_picked()
	await _wait_frames(2)
	_check(_ship.get_nanobots() - before == 250, "The captured 200-value payout receives its 1.25 modifier exactly once")
	var expired: NanobotSwarm = _spawn(400)
	expired._process(119.99)
	expired._collection_pos = _ship.global_position
	before = _ship.get_nanobots()
	expired._process(0.02)
	expired._on_picked()
	await _wait_frames(2)
	_check(_ship.get_nanobots() == before, "Expiration wins when the lifetime ends before pickup commits")
	var lost_player: NanobotSwarm = _spawn(400)
	lost_player._collection_pos = _ship.global_position
	lost_player._process(0.0)
	lost_player._player = null
	await _wait_frames(2)
	_check(_ship.get_nanobots() == before + 500, "Pickup retains its captured recipient when the live player reference changes")
	var temporary_ship: Ship = SHIP_SCENE.instantiate() as Ship
	temporary_ship.freeze = true
	temporary_ship.process_mode = Node.PROCESS_MODE_DISABLED
	_actors.add_child(temporary_ship)
	temporary_ship.hull = 10.0
	var invalid_recipient: NanobotSwarm = _spawn(400)
	invalid_recipient._player = temporary_ship
	invalid_recipient._collection_pos = temporary_ship.global_position
	invalid_recipient._process(0.0)
	before = _ship.get_nanobots()
	temporary_ship.queue_free()
	await _wait_frames(2)
	_check(_ship.get_nanobots() == before, "Removal of the committed recipient grants no invalid or redirected award")

func _check_death_paths() -> void:
	var enemy: Enemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, ENEMY_DEF, Vector3(10000.0, 0.0, 0.0)) as Enemy
	_check(enemy != null, "Real enemy spawn path is available")
	if enemy != null:
		enemy.freeze = true
		enemy.set_physics_process(false)
		enemy.explosion_scene = null
		var drops_before: Array[Node] = get_tree().get_nodes_in_group("drops")
		enemy.apply_damage(enemy.hull + enemy.shield + 100000.0)
		var enemy_drop: NanobotSwarm = _find_new_drop(drops_before)
		_check(enemy_drop != null, "Enemy death creates a real nanobot swarm")
		if enemy_drop != null:
			_check(enemy_drop.is_active() and enemy_drop.get_remaining_value() > 0 and is_zero_approx(enemy_drop.get_age_sec()), "Enemy payout is initialized before its ready callback")
			enemy_drop.set_process(false)
			var original: int = enemy_drop.get_remaining_value()
			enemy_drop._process(60.0)
			_check(enemy_drop.get_remaining_value() == int(ceil(float(original) * 0.5)), "Actual enemy drops decay from their awarded value")
			enemy_drop.queue_free()
		enemy.queue_free()
	await _wait_frames(3)
	var target: TargetObject = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.TARGET, TARGET_DEF, Vector3(10000.0, 0.0, 0.0)) as TargetObject
	_check(target != null, "Real stationary-target spawn path is available")
	if target != null:
		target.freeze = true
		target.explosion_scene = null
		var drops_before: Array[Node] = get_tree().get_nodes_in_group("drops")
		target.apply_damage(target.hull + target.shield + 100000.0)
		var target_drop: NanobotSwarm = _find_new_drop(drops_before)
		_check(target_drop != null, "Target death creates a real nanobot swarm")
		if target_drop != null:
			var original: int = RunState.calc_target_nanobots(TARGET_DEF)
			_check(target_drop.get_remaining_value() == original and is_zero_approx(target_drop.get_age_sec()), "Target payout is initialized at its unchanged value before ready")
			target_drop.set_process(false)
			target_drop._process(90.0)
			_check(target_drop.get_remaining_value() == int(ceil(float(original) * 0.25)), "Actual target drops use the same 120-second decay")
			target_drop.queue_free()
	await _wait_frames(3)

func _find_new_drop(previous: Array[Node]) -> NanobotSwarm:
	for node: Node in get_tree().get_nodes_in_group("drops"):
		if node is NanobotSwarm and not previous.has(node):
			return node as NanobotSwarm
	return null

func _check_visual_fade() -> void:
	var camera: Camera3D = Camera3D.new()
	camera.far = 10000.0
	_actors.add_child(camera)
	camera.make_current()
	var swarm: NanobotSwarm = _spawn(400, Vector3(0.0, 0.0, -1000.0))
	var visuals: NanobotSwarmVisuals = swarm.get_node("SwarmVisuals") as NanobotSwarmVisuals
	_check(swarm.particles.amount == 1000, "Cloud readability does not increase the particle count")
	_check(is_equal_approx(swarm.pickup_distance, 5.0) and is_equal_approx(swarm.attract_radius_start, 30.0), "Visual enlargement does not change collection geometry")
	_check(visuals.get_class() == &"Node3D" and not swarm.has_node("ReadabilityCore"), "Swarms use particles rather than a separate central badge")
	_check(swarm.particles.draw_pass_1 is PointMesh, "The original point-particle cloud geometry is preserved")
	for distance: float in [100.0, 1000.0, 3000.0]:
		swarm.position = Vector3(0.0, 0.0, -distance)
		var before: Transform3D = swarm.transform
		visuals.refresh_visuals()
		_check(visuals.get_visual_strength() > 0.99, "Fresh particle clouds remain visible through 3000 metres")
		_check(swarm.transform.is_equal_approx(before), "Readability updates never scale the swarm or collection geometry")
	swarm.position = Vector3(0.0, 0.0, -1000.0)
	visuals.refresh_visuals()
	var fresh_strength: float = visuals.get_visual_strength()
	swarm._process(90.0)
	visuals.refresh_visuals()
	_check(visuals.get_visual_strength() > 0.0 and visuals.get_visual_strength() < fresh_strength, "An aged swarm remains readable while visibly dimmer")
	swarm.position = Vector3(0.0, 0.0, -3500.0)
	visuals.refresh_visuals()
	_check(is_zero_approx(visuals.get_visual_strength()), "World visuals fade out at 3500 metres")
	swarm.position = Vector3(0.0, 0.0, 100.0)
	visuals.refresh_visuals()
	_check(is_zero_approx(visuals.get_visual_strength()), "Behind-camera particle clouds are hidden")
	_check(NanobotSwarmVisuals.value_visual_strength(1.0) > NanobotSwarmVisuals.value_visual_strength(0.25) and is_zero_approx(NanobotSwarmVisuals.value_visual_strength(0.0)), "Shared world and edge-icon strength fades with remaining value")
	swarm.queue_free()
	camera.queue_free()
	await _wait_frames(3)

func _mute_audio(node: Node) -> void:
	if node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _wait_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("NANOBOT_SWARM_CHECKS: " + message)

func _finish() -> void:
	get_tree().quit(0 if _failures == 0 else 1)
