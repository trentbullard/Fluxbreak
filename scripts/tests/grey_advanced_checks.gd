extends Node3D

const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const PROBE: GreyEnemyDef = preload("res://content/data/enemies/grey_probe_mk1.tres")
const SEEKER: GreyEnemyDef = preload("res://content/data/enemies/grey_seeker_mk1.tres")
const VESSEL: GreyEnemyDef = preload("res://content/data/enemies/grey_vessel_mk1.tres")
const HARBINGER: GreyEnemyDef = preload("res://content/data/enemies/grey_harbinger_mk1.tres")
const MOTHERSHIP: GreyEnemyDef = preload("res://content/data/enemies/grey_mothership_mk1.tres")
const WITNESS: GreyBossDef = preload("res://content/data/enemies/grey_witness_mk1.tres")
const MIND: GreyMindDef = preload("res://content/data/enemies/grey_veiled_mind_mk1.tres")

var _ship: Ship
var _spawner: Spawner
var _enemies: Array[Enemy] = []
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

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
	_check_geometry()
	await _check_forecast_and_corridor()
	await _clear()
	await _check_paired_echoes()
	await _clear()
	await _check_mothership_coordination()
	await _clear()
	await _check_independent_attack_timing()
	await _clear()
	await _check_concurrent_capture_warnings()
	await _clear()
	print("GREY_ADVANCED_CHECKS: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn(definition: EnemyDef) -> Enemy:
	var enemy: Enemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, definition, Vector3(0.0, 0.0, 180.0)) as Enemy
	_expect(enemy != null, "%s spawns using the authored actor" % definition.id)
	if enemy != null:
		_enemies.append(enemy)
		enemy.freeze = true
		enemy.set_physics_process(false)
		enemy.explosion_scene = null
		enemy._stop_warp_in()
		if enemy._regen_timer != null:
			enemy._regen_timer.stop()
		for audio: Node in enemy.find_children("*", "AudioStreamPlayer3D", true, false):
			(audio as AudioStreamPlayer3D).stream = null
	return enemy

func _check_geometry() -> void:
	var prediction: Vector3 = GreyAttackGeometry.forecast(Vector3.ZERO, Vector3.RIGHT * 100.0, 1.6, 0.9, 420.0)
	_expect(prediction.is_equal_approx(Vector3.RIGHT * 144.0), "Forecast uses a bounded snapshot of velocity and full windup")
	_expect(GreyAttackGeometry.forecast(Vector3.ZERO, Vector3.RIGHT * 10000.0, 2.0, 1.0, 420.0).length() <= 420.01, "Prediction clamps extreme player speeds")
	for velocity: Vector3 in [Vector3.ZERO, Vector3.RIGHT * 100.0, Vector3.UP * 100.0]:
		var axis: Vector3 = GreyAttackGeometry.crossing_axis(velocity, Vector3.FORWARD)
		_expect(axis.is_finite() and is_equal_approx(axis.length(), 1.0), "Crossing axis handles stationary and vertical motion")
		if velocity.length_squared() > 1.0:
			_expect(absf(axis.dot(velocity.normalized())) < 0.001, "Capture corridor crosses travel instead of following it")

func _check_forecast_and_corridor() -> void:
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.RIGHT * 400.0
	var seeker: GreyEnemy = _spawn(SEEKER) as GreyEnemy
	seeker._displacement_cooldown_left = 100.0
	seeker._attack_cooldown_left = 0.0
	seeker._tick_seeker()
	var warning: EnemyAttackTelegraph = seeker._active_attack
	_expect(warning != null and warning.get_attack_label() == "FORECAST RUPTURE", "Seeker uses the forecast attack in live decision code")
	warning.set_physics_process(false)
	var locked: Vector3 = warning._locked_position
	var steady_endpoint: Vector3 = Vector3.RIGHT * 400.0 * SEEKER.behavior.attack_windup_sec
	_expect(warning.contains_position(steady_endpoint), "Constant forward movement reaches the forecast danger volume")
	_ship.global_position = Vector3.UP * 100.0
	_ship.linear_velocity = Vector3.UP * 100.0
	_expect(warning._locked_position.is_equal_approx(locked), "Changing heading never drags a committed warning")
	_expect(not warning.contains_position(_ship.global_position), "A course change escapes the forecast sphere")
	var health: float = _ship.hull
	warning._physics_process(SEEKER.behavior.attack_windup_sec + 0.01)
	_expect(is_equal_approx(_ship.hull, health), "Leaving the real forecast volume guarantees no damage")
	await _clear()
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.RIGHT * 400.0
	var vessel: GreyEnemy = _spawn(VESSEL) as GreyEnemy
	_expect(vessel._start_tether(), "Vessel can start a directional capture")
	var tether: GreyTether = vessel._tether
	tether.set_physics_process(false)
	_expect(tether._corridor and tether.get_attack_label() == "CAPTURE CORRIDOR", "Vessel displays a cylinder and directional response hint")
	_expect(tether.contains_position(Vector3.RIGHT * 400.0 * VESSEL.behavior.tether_windup_sec), "Constant travel encounters the capture corridor")
	var center: Vector3 = (tether._locked_position + tether._locked_origin) * 0.5
	_expect(not tether.contains_position(center + Vector3.UP * 100.0), "Vertical steering remains an open escape from the lane")
	_ship.global_position = center + Vector3.UP * 100.0
	tether._physics_process(VESSEL.behavior.tether_windup_sec + 0.01)
	_expect(not tether.is_attached() and _ship.get_movement_slow_multiplier() == 1.0, "Escaping directional capture leaves movement unchanged")

func _check_paired_echoes() -> void:
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.RIGHT * 400.0
	var harbinger: GreyEnemy = _spawn(HARBINGER) as GreyEnemy
	harbinger._attack_cooldown_left = 0.0
	harbinger._tick_harbinger()
	var first: EnemyAttackTelegraph = harbinger._active_attack
	_expect(first != null and first._companions.size() == 1, "Harbinger announces both complementary echoes together")
	first.set_physics_process(false)
	var second: EnemyAttackTelegraph = first._companions[0]
	second.set_physics_process(false)
	var locked: Vector3 = second._locked_position
	_expect(first._locked_position.distance_squared_to(locked) > 100.0, "Paired echoes cover different positions")
	_expect(second.get_time_remaining() >= HARBINGER.behavior.attack_windup_sec, "Second echo has its own full warning")
	_expect(second.contains_position(Vector3.RIGHT * 400.0 * second._windup_sec), "Harbinger forecast catches constant 400m/s flight at its own release time")
	_ship.global_position = Vector3.UP * 250.0
	var remaining: float = second.get_time_remaining()
	get_tree().paused = true
	await get_tree().process_frame
	get_tree().paused = false
	_expect(is_equal_approx(second.get_time_remaining(), remaining), "Pausing freezes both warnings")
	first._physics_process(HARBINGER.behavior.attack_windup_sec + 0.01)
	_expect(harbinger._active_attack == first and harbinger._recovery_left == 0.0, "First release cannot prematurely finish the whole pattern")
	second._physics_process(second._windup_sec + 0.01)
	_expect(harbinger._active_attack == null and harbinger._recovery_left > 0.0, "Full exposed recovery begins after the final release")
	harbinger._recovery_left = 0.0
	harbinger._attack_cooldown_left = 0.0
	harbinger._tick_harbinger()
	first = harbinger._active_attack
	harbinger.apply_damage(1000000.0)
	_expect(first.is_queued_for_deletion(), "Source death cancels all complementary warning members")
	for node: Node in get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		_expect(node.is_queued_for_deletion() or not (node as EnemyAttackTelegraph)._active, "No companion can outlive its killed source")

func _check_mothership_coordination() -> void:
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.RIGHT * 400.0
	var ally: GreyEnemy = _spawn(PROBE) as GreyEnemy
	ally._attack_cooldown_left = 2.0
	var mother: GreyEnemy = _spawn(MOTHERSHIP) as GreyEnemy
	mother._attack_cooldown_left = 0.0
	mother._tick_mothership()
	_expect(mother._active_attack != null and mother._active_attack._corridor, "Mothership owns the directional half of the coordinated pattern")
	_expect(ally._active_attack != null and ally._active_attack.get_attack_label() == "COORDINATED FORECAST", "Mothership advances an idle ally's ordinary cooldown for its complementary forecast")
	_expect(ally._coordination_cooldown_left > 0.0, "Coordination cannot repeatedly accelerate the same ally")
	mother._cancel_specials()
	ally._cancel_specials()
	mother._attack_cooldown_left = 0.0
	mother._recovery_left = 0.0
	mother._mothership_next_action = 1
	mother._tick_mothership()
	var displacement: GreyDisplacement = mother._displacement
	_expect(displacement != null, "Mothership still announces harmless relocation")
	displacement.set_physics_process(false)
	displacement._physics_process(MOTHERSHIP.behavior.displacement_windup_sec + 0.01)
	_expect(mother._post_displacement_pulse and mother._attack_cooldown_left == 0.0, "Relocation immediately schedules a new fully warned collapse")
	mother._tick_mothership()
	_expect(mother._active_attack != null and mother._active_attack.get_time_remaining() > 0.0, "Relocation followup never deals instant damage")
	mother._cancel_specials()
	mother._post_displacement_pulse = true
	_ship.global_position = Vector3.RIGHT * 2500.0
	mother._tick_mothership()
	_expect(not mother._post_displacement_pulse, "Outrunning a Mothership arrival releases its abandoned followup")

func _check_independent_attack_timing() -> void:
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.ZERO
	var probes: Array[GreyEnemy] = []
	for index: int in range(16):
		probes.append(_spawn(PROBE) as GreyEnemy)
	for probe: GreyEnemy in probes:
		probe._attack_cooldown_left = 0.0
		probe._tick_probe()
		_expect(probe._active_attack != null, "Every ready Probe attacks on its own timing despite other active warnings")
	_expect(_active_warning_count() == 16, "More than eight ordinary Grey warnings can exist together")
	var first_countdown: float = probes[0]._active_attack.get_time_remaining()
	var harbingers: Array[GreyEnemy] = []
	for index: int in range(4):
		var heavy: GreyEnemy = _spawn(HARBINGER) as GreyEnemy
		heavy._attack_cooldown_left = 0.0
		heavy._tick_harbinger()
		_expect(heavy._active_attack != null and heavy._active_attack._companions.size() == 1, "Each Harbinger independently commits its entire two-volume pattern")
		harbingers.append(heavy)
	for index: int in range(2):
		var mother: GreyEnemy = _spawn(MOTHERSHIP) as GreyEnemy
		mother._post_displacement_pulse = true
		mother._attack_cooldown_left = 0.0
		mother._tick_mothership()
		_expect(mother._active_attack != null and mother._active_attack._companions.size() == 1, "Each Mothership collapse starts independently alongside all other patterns")
	var witness: GreyWitness = _spawn(WITNESS) as GreyWitness
	witness._next_major = GreyWitness.Major.RUPTURE
	witness._begin_attack(_ship)
	_expect(witness._attack != null and witness._attack._companions.size() == 1, "Witness starts both warning volumes without waiting for ordinary ships")
	var mind: GreyVeiledMind = _spawn(MIND) as GreyVeiledMind
	mind._phase = 3
	mind._next_major = GreyVeiledMind.Major.RUPTURE
	mind._begin_attack(_ship)
	_expect(mind._attack != null and mind._attack._companions.size() == 2, "Veiled Mind independently starts its complete three-part collapse")
	_expect(_active_warning_count() == 33, "Sixteen singles, six heavy pairs and both boss patterns coexist without a shared volume limit")
	_expect(is_equal_approx(probes[0]._active_attack.get_time_remaining(), first_countdown), "Other ships starting attacks never reset an existing warning's timing")
	_freeze_warnings()
	var unrelated: EnemyAttackTelegraph = probes[1]._active_attack
	var unrelated_remaining: float = unrelated.get_time_remaining()
	probes[0]._cancel_specials()
	_expect(_active_warning_count() == 32 and unrelated.is_warning_for(_ship), "Cancelling one ship's attack preserves every unrelated warning")
	var newcomer: GreyEnemy = _spawn(PROBE) as GreyEnemy
	newcomer._attack_cooldown_left = 0.0
	newcomer._tick_probe()
	_expect(newcomer._active_attack != null and _active_warning_count() == 33, "A new ship starts immediately while more than eight other warnings remain")
	newcomer._active_attack.set_physics_process(false)
	var primary: EnemyAttackTelegraph = harbingers[0]._active_attack
	var companion: EnemyAttackTelegraph = primary._companions[0]
	_ship.global_position = Vector3.UP * 1000.0
	primary._physics_process(primary._windup_sec + 0.01)
	companion._physics_process(companion._windup_sec + 0.01)
	_expect(harbingers[0]._active_attack == null and harbingers[0]._recovery_left > 0.0, "Finishing a multipart pattern retains its own final recovery")
	_expect(unrelated.is_warning_for(_ship) and is_equal_approx(unrelated.get_time_remaining(), unrelated_remaining), "Another ship finishing its pattern cannot resolve or delay unrelated warnings")
	_ship.global_position = Vector3.ZERO
	var next_heavy: GreyEnemy = _spawn(HARBINGER) as GreyEnemy
	next_heavy._attack_cooldown_left = 0.0
	next_heavy._tick_harbinger()
	_expect(next_heavy._active_attack != null and next_heavy._active_attack._companions.size() == 1 and _active_warning_count() == 33, "A new heavy pattern starts immediately after another finishes without admission bookkeeping")
	_freeze_warnings()
	await get_tree().process_frame

func _check_concurrent_capture_warnings() -> void:
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.ZERO
	var vessels: Array[GreyEnemy] = []
	var captures: Array[GreyTether] = []
	for index: int in range(3):
		var vessel: GreyEnemy = _spawn(VESSEL) as GreyEnemy
		vessel._attack_cooldown_left = 0.0
		vessel._tick_vessel()
		_expect(vessel._tether != null and vessel._tether.is_active(), "Each ready Vessel may show its own capture warning before a link attaches")
		vessel._tether.set_physics_process(false)
		vessels.append(vessel)
		captures.append(vessel._tether)
	_expect(_active_warning_count() == 3 and _ship.get_tether_time_remaining() == 0.0, "Multiple pending captures coexist without a shared reservation or an early slow")
	var probe: GreyEnemy = _spawn(PROBE) as GreyEnemy
	probe._attack_cooldown_left = 0.0
	probe._tick_probe()
	_expect(probe._active_attack != null and _active_warning_count() == 4, "Concurrent capture warnings do not prevent ordinary damage warnings")
	probe._active_attack.set_physics_process(false)
	captures[0]._physics_process(captures[0]._windup_sec + 0.01)
	var remaining: float = _ship.get_tether_time_remaining()
	var multiplier: float = _ship.get_movement_slow_multiplier()
	_expect(captures[0].is_attached() and _ship.get_tether_source() == vessels[0], "The first successful capture attaches the ordinary Ship-owned movement status")
	for index: int in range(1, captures.size()):
		captures[index]._physics_process(captures[index]._windup_sec + 0.01)
		_expect(not captures[index].is_attached(), "A later overlapping capture cannot replace or stack the active slow")
	_expect(_ship.get_tether_source() == vessels[0] and is_equal_approx(_ship.get_tether_time_remaining(), remaining) and is_equal_approx(_ship.get_movement_slow_multiplier(), multiplier), "Rejected overlapping captures preserve the original owner, duration and slow strength")
	_expect(probe._active_attack.is_warning_for(_ship), "Tether resolution leaves unrelated damage warnings active")
	var active_fallback: GreyEnemy = _spawn(VESSEL) as GreyEnemy
	active_fallback._attack_cooldown_left = 0.0
	active_fallback._tick_vessel()
	_expect(active_fallback._tether == null and active_fallback._active_attack != null, "A Vessel uses its damaging pattern when the player already has an active tether")
	var witness: GreyWitness = _spawn(WITNESS) as GreyWitness
	witness._next_major = GreyWitness.Major.TETHER
	witness._begin_attack(_ship)
	_expect(witness._tether == null and witness._attack != null, "Witness uses a damaging pattern instead of applying a second slow")
	var mind: GreyVeiledMind = _spawn(MIND) as GreyVeiledMind
	mind._phase = 3
	mind._next_major = GreyVeiledMind.Major.TETHER
	mind._begin_attack(_ship)
	_expect(mind._tether == null and mind._attack != null and mind._attack._companions.size() == 2, "Veiled Mind's active-tether fallback keeps the full independent collapse")
	_freeze_warnings()
	captures[0].cancel()
	_expect(_ship.get_tether_time_remaining() == 0.0 and _ship.is_tether_immune(), "Ending the actual link restores movement and preserves post-break immunity")
	var immune_fallback: GreyEnemy = _spawn(VESSEL) as GreyEnemy
	immune_fallback._attack_cooldown_left = 0.0
	immune_fallback._tick_vessel()
	_expect(immune_fallback._tether == null and immune_fallback._active_attack != null, "Immunity routes a new Vessel into its damage pattern without a shared capture reservation")
	_freeze_warnings()
	await get_tree().process_frame

func _active_warning_count() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		var warning: EnemyAttackTelegraph = node as EnemyAttackTelegraph
		if warning != null and not warning.is_queued_for_deletion() and warning._active and not warning._has_resolved:
			count += 1
	return count

func _freeze_warnings() -> void:
	for node: Node in get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		node.set_physics_process(false)

func _clear() -> void:
	for enemy: Enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	await get_tree().process_frame
	await get_tree().physics_frame
	_ship.clear_tether_slow(null, false)
	_ship._tether_immunity_sec = 0.0
	_ship.global_position = Vector3.ZERO
	_ship.linear_velocity = Vector3.ZERO
	_expect(int(_spawner.get_alive_counts().get("enemies", 0)) == 0, "Cleanup restores real Spawner accounting")

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("GREY_ADVANCED_CHECKS: " + description)
