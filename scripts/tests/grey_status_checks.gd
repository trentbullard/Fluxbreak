extends Node3D

## Real Ship physics and helper lifecycles run in a separate save namespace.
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const SOURCE_DEF: GreyEnemyDef = preload("res://content/data/enemies/grey_probe_mk1.tres")

var _ship: Ship = null
var _spawner: Spawner = null
var _sources: Array[Enemy] = []
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Grey Validation":
		push_error("Grey status checks require the isolated Fluxbreak Grey Validation project to protect player progress.")
		get_tree().quit(2)
		return
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "TestShip"
	_ship.process_mode = Node.PROCESS_MODE_PAUSABLE
	_ship.freeze = true
	add_child(_ship)
	_ship.collision_layer = 0
	_ship.collision_mask = 0
	_ship.explosion_scene = null
	_ship.hull = 10000.0
	_ship.shield = 10000.0
	for child_name: String in ["ControllerFlightController", "MouseFlightController", "VisualRoot", "TurretController", "CameraPivot"]:
		_ship.get_node(child_name).process_mode = Node.PROCESS_MODE_DISABLED
	_spawner = Spawner.new()
	_spawner.name = "TestSpawner"
	_spawner.ship_path = NodePath("../TestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	add_child(_spawner)
	await _check_bounds_ownership_and_immunity()
	await _check_break_conditions_and_stage_reset()
	await _check_helper_races_and_pause()
	await _check_real_movement()
	_release_input()
	_ship.reset_for_stage_transition()
	for source: Enemy in _sources:
		if is_instance_valid(source):
			source.queue_free()
	await _wait(0.1)
	print("GREY_STATUS_CHECKS: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_source(offset: Vector3 = Vector3(0.0, 0.0, 100.0)) -> Enemy:
	var request: SpawnRequest = SpawnRequest.new()
	request.grants_kill_rewards = false
	request.contributes_to_pressure = false
	var source: Enemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, SOURCE_DEF, _ship.global_position + offset, request) as Enemy
	_expect(source != null, "A real Grey actor supplies the status source")
	if source != null:
		source.process_mode = Node.PROCESS_MODE_DISABLED
		source.freeze = true
		source.explosion_scene = null
		source.collision_layer = 0
		source.collision_mask = 0
		_sources.append(source)
	return source

func _fresh_status() -> void:
	_ship.freeze = true
	_ship.reset_for_stage_transition()
	_ship.set_target_angular_rates(Vector3.ZERO)
	_release_input()

func _check_bounds_ownership_and_immunity() -> void:
	_fresh_status()
	var first: Enemy = _spawn_source()
	var second: Enemy = _spawn_source(Vector3(0.0, 0.0, -150.0))
	var normal_caps: Vector2 = _ship.get_speed_caps()
	var normal_accel: float = _ship.get_effective_accel_forward()
	var normal_turn: Vector3 = _ship.get_effective_max_angular_rates()
	var normal_boost: float = _ship.get_effective_boost_mult()
	_expect(_ship.get_movement_slow_multiplier() == 1.0 and not _ship.is_tether_immune(), "Normal ships begin with unchanged movement and no immunity")
	_expect(_ship.try_apply_tether_slow(first, 0.01, 100.0, 10000.0), "A living nearby source can attach the bounded status")
	_expect(is_equal_approx(_ship.get_movement_slow_multiplier(), 0.65), "Extreme slow values clamp to 65 percent movement")
	_expect(is_equal_approx(_ship.get_tether_time_remaining(), 3.0), "Extreme duration values clamp to three simulated seconds")
	_expect(_ship.get_speed_caps().is_equal_approx(normal_caps * 0.65), "Both exposed forward and reverse speed caps use the bounded status")
	_expect(is_equal_approx(_ship.get_effective_accel_forward(), normal_accel) and _ship.get_effective_max_angular_rates().is_equal_approx(normal_turn) and is_equal_approx(_ship.get_effective_boost_mult(), normal_boost), "The temporary status preserves permanent acceleration, turning, and boost stats")
	await _wait(0.2)
	var remaining: float = _ship.get_tether_time_remaining()
	_expect(not _ship.try_apply_tether_slow(first, 0.9, 3.0, 600.0), "The same source cannot refresh an active duration")
	_expect(not _ship.try_apply_tether_slow(second, 0.65, 3.0, 600.0), "Another source cannot stack or replace an attached slow")
	_expect(is_equal_approx(_ship.get_tether_time_remaining(), remaining) and _ship.get_tether_source() == first, "Rejected applications preserve the original duration and owner")
	_ship.clear_tether_slow(second)
	_expect(_ship.get_tether_source() == first, "A different source cannot clear the active owner's link")
	_ship.clear_tether_slow(first)
	_expect(_ship.get_movement_slow_multiplier() == 1.0 and _ship.get_speed_caps().is_equal_approx(normal_caps), "Clearing the owner immediately restores normal movement caps")
	_expect(_ship.is_tether_immune() and not _ship.try_apply_tether_slow(second, 0.75, 1.0, 600.0), "A broken link protects against immediate reattachment")
	await _wait(1.0)
	var immunity_before: float = _ship._tether_immunity_sec
	get_tree().paused = true
	await _wait(0.6)
	_expect(is_equal_approx(_ship._tether_immunity_sec, immunity_before), "Pause cannot consume post-break immunity")
	get_tree().paused = false
	await _wait(1.8)
	_expect(_ship.is_tether_immune(), "Immunity remains active before three simulated seconds have passed")
	await _wait(0.3)
	_expect(not _ship.is_tether_immune() and _ship.try_apply_tether_slow(second, 0.75, 0.3, 600.0), "A new source can attach after three simulated seconds")
	await _wait(0.4)
	_expect(_ship.get_movement_slow_multiplier() == 1.0 and _ship.is_tether_immune(), "Natural timeout restores movement and grants immunity")

func _check_break_conditions_and_stage_reset() -> void:
	_fresh_status()
	var source: Enemy = _spawn_source()
	_expect(_ship.try_apply_tether_slow(source, 0.75, 3.0, 200.0), "A distance-bounded link starts inside its escape range")
	_ship.global_position = Vector3(600.0, 0.0, 0.0)
	await _wait(0.05)
	_expect(_ship.get_movement_slow_multiplier() == 1.0 and _ship.is_tether_immune(), "Crossing the escape distance breaks the status in actual Ship processing")
	_fresh_status()
	_expect(_ship.try_apply_tether_slow(source, 0.75, 3.0, 600.0), "A reset ship can be tethered again")
	_ship.reset_for_stage_transition()
	_expect(_ship.get_tether_time_remaining() == 0.0 and not _ship.is_tether_immune() and _ship.get_movement_slow_multiplier() == 1.0, "Stage transition clears both slow and immunity state")
	_expect(_ship.global_transform.is_equal_approx(Transform3D.IDENTITY) and _ship.linear_velocity.is_zero_approx(), "Stage reset retains its ordinary position and velocity reset")
	var distant: Enemy = _spawn_source(Vector3(0.0, 0.0, 700.0))
	_expect(not _ship.try_apply_tether_slow(distant, 0.75, 3.0, 10000.0), "The hard maximum range rejects a distant source despite extreme requested range")
	_expect(_ship.try_apply_tether_slow(source, 0.75, 3.0, 600.0), "A valid live actor attaches before its destruction")
	source.apply_damage(1000000.0)
	await _wait(0.05)
	_expect(_ship.get_movement_slow_multiplier() == 1.0 and _ship.is_tether_immune(), "Actual source death breaks the status and restores movement")
	_fresh_status()
	source = _spawn_source()
	_ship.try_apply_tether_slow(source, 0.75, 3.0, 600.0)
	source.queue_free()
	await _wait(0.05)
	_expect(_ship.get_movement_slow_multiplier() == 1.0 and _ship.get_tether_source() == null, "Source tree exit cannot leave a stale movement penalty")
	_fresh_status()
	source = _spawn_source()
	_ship.try_apply_tether_slow(source, 0.75, 3.0, 600.0)
	_ship.hide()
	await _wait(0.05)
	_expect(_ship.get_movement_slow_multiplier() == 1.0, "An inactive hidden player cannot retain the status")
	_ship.show()
	_fresh_status()

func _check_helper_races_and_pause() -> void:
	var source: Enemy = _spawn_source()
	var first: GreyTether = _new_tether(source, 0.3)
	var second: GreyTether = _new_tether(source, 0.3)
	_expect(first.is_active() and second.is_active(), "Two simultaneous capture warnings may begin before either owns a link")
	await _wait(0.1)
	var remaining: float = first.get_time_remaining()
	get_tree().paused = true
	await _wait(0.5)
	_expect(is_equal_approx(first.get_time_remaining(), remaining), "Pause freezes an in-progress tether capture")
	_expect(_ship.get_movement_slow_multiplier() == 1.0, "No tether can attach while the game is paused")
	get_tree().paused = false
	await _wait(0.25)
	var attached_count: int = 0
	for node: Node in get_tree().get_nodes_in_group("grey_tethers"):
		var link: GreyTether = node as GreyTether
		if link != null and link.is_attached():
			attached_count += 1
	_expect(attached_count == 1 and _ship.get_tether_source() == source, "Overlapping warnings produce one attached link without stacking")
	remaining = _ship.get_tether_time_remaining()
	get_tree().paused = true
	await _wait(0.5)
	_expect(is_equal_approx(_ship.get_tether_time_remaining(), remaining), "Pause freezes an attached link's bounded status duration")
	get_tree().paused = false
	for node: Node in get_tree().get_nodes_in_group("grey_tethers"):
		(node as GreyTether).cancel()
	await _wait(0.05)
	_fresh_status()
	var dodged: GreyTether = _new_tether(source, 0.3)
	_ship.global_position = Vector3(150.0, 150.0, 0.0)
	await _wait(0.4)
	_expect(not is_instance_valid(dodged) and _ship.get_movement_slow_multiplier() == 1.0 and not _ship.is_tether_immune(), "Dodging the locked capture sphere avoids slow without consuming immunity")
	_fresh_status()
	# Reproduce a same-source race without relying on frame-order luck: an old
	# failed capture is queued, then a new legitimate link attaches before exit.
	var stale: GreyTether = _new_tether(source, 1.0)
	stale.cancel()
	_expect(_ship.try_apply_tether_slow(source, 0.75, 1.0, 600.0), "A later same-source link can attach after a canceled capture")
	await _wait(0.05)
	_expect(_ship.get_tether_source() == source and _ship.get_tether_time_remaining() > 0.0, "Queued exit of a canceled helper cannot clear a newer same-source link")
	_fresh_status()
	var linked: GreyTether = _new_tether(source, 0.2)
	await _wait(0.25)
	_expect(linked.is_attached(), "Source death cleanup begins with an attached helper")
	source.apply_damage(1000000.0)
	await _wait(0.05)
	_expect(not is_instance_valid(linked) and _ship.get_movement_slow_multiplier() == 1.0, "Source death removes the visible helper and the actual movement status")
	_fresh_status()

func _new_tether(source: Enemy, windup: float) -> GreyTether:
	var tether: GreyTether = GreyTether.new()
	add_child(tether)
	_expect(tether.start_tether(source, _ship, windup, 2.0, 0.75, 600.0, 36.0), "The shared tether helper starts with valid source ownership")
	return tether

func _check_real_movement() -> void:
	var source: Enemy = _spawn_source()
	var normal_speed: float = await _measure_forward(source, false, false)
	var slowed_speed: float = await _measure_forward(source, true, false)
	_expect(normal_speed > 1.0 and slowed_speed < normal_speed * 0.72 and slowed_speed > normal_speed * 0.58, "Real rigid-body acceleration responds to the 65 percent tether multiplier")
	var boosted_speed: float = await _measure_forward(source, false, true)
	var slowed_boosted_speed: float = await _measure_forward(source, true, true)
	_expect(boosted_speed > normal_speed * 1.1 and slowed_boosted_speed > slowed_speed * 1.1, "Boost continues to accelerate both normal and tethered ships")
	_expect(slowed_boosted_speed < boosted_speed * 0.72 and slowed_boosted_speed > boosted_speed * 0.58, "Boosted acceleration keeps the same bounded slow rather than bypassing or compounding it")
	var normal_cap: float = await _measure_forward(source, false, false, _ship.eff_max_speed_forward * 1.5, 4)
	var slowed_cap: float = await _measure_forward(source, true, false, _ship.eff_max_speed_forward * 1.5, 4)
	_expect(is_equal_approx(normal_cap, _ship.eff_max_speed_forward), "Normal physics preserves the existing maximum forward speed")
	_expect(is_equal_approx(slowed_cap, _ship.eff_max_speed_forward * 0.65), "Actual rigid-body speed clamps to the temporary movement cap")
	var normal_turn: float = await _measure_turn(source, false)
	var slowed_turn: float = await _measure_turn(source, true)
	_expect(normal_turn > 0.1 and is_equal_approx(normal_turn, slowed_turn), "Tethered ships retain their normal angular steering response")
	var restored_speed: float = await _measure_forward(source, false, false, 0.0, 12, true)
	_expect(absf(restored_speed - normal_speed) < 0.2, "Clearing a tether restores ordinary acceleration in real physics (normal %.3f, restored %.3f)" % [normal_speed, restored_speed])
	_fresh_status()

func _measure_forward(source: Enemy, slowed: bool, boosted: bool, start_speed: float = 0.0, frames: int = 12, clear_before_moving: bool = false) -> float:
	# Each measurement starts at the same render/physics boundary so the first
	# integration tick is counted identically, even after a physics timer wait.
	await get_tree().process_frame
	_fresh_status()
	source.global_position = Vector3(0.0, 0.0, 100.0)
	_ship.linear_velocity = Vector3(0.0, 0.0, -start_speed)
	if slowed or clear_before_moving:
		_ship.try_apply_tether_slow(source, 0.65, 3.0, 600.0)
	if clear_before_moving:
		_ship.clear_tether_slow(source)
	_ship.freeze = false
	Input.action_press("thrust")
	if boosted:
		Input.action_press("boost")
	await _physics_frames(frames)
	var forward_speed: float = -(_ship.transform.basis.inverse() * _ship.linear_velocity).z
	_ship.freeze = true
	_release_input()
	return forward_speed

func _measure_turn(source: Enemy, slowed: bool) -> float:
	await get_tree().process_frame
	_fresh_status()
	source.global_position = Vector3(0.0, 0.0, 100.0)
	if slowed:
		_ship.try_apply_tether_slow(source, 0.65, 3.0, 600.0)
	_ship.set_target_angular_rates(Vector3(0.0, 0.6, 0.0))
	_ship.freeze = false
	await _physics_frames(12)
	var turn_speed: float = (_ship.transform.basis.inverse() * _ship.angular_velocity).y
	_ship.freeze = true
	return turn_speed

func _physics_frames(count: int) -> void:
	for frame in range(count):
		await get_tree().physics_frame

func _release_input() -> void:
	for action: String in ["thrust", "reverse", "boost"]:
		Input.action_release(action)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("GREY_STATUS_CHECKS: " + description)
