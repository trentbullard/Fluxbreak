extends Node3D

# Run this scene in an isolated project user-data directory. These checks use
# the real player scene and shipped Merc resources, with input/auto-combat off.
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const CORVETTE: MercEnemyDef = preload("res://content/data/enemies/merc_corvette_mk1.tres")
const FRIGATE: MercEnemyDef = preload("res://content/data/enemies/merc_frigate_mk1.tres")
const DESTROYER: MercEnemyDef = preload("res://content/data/enemies/merc_destroyer_mk1.tres")
const MACHINES: FactionDef = preload("res://content/data/factions/machines.tres")

var _ship: Ship = null
var _enemies: Array[MercEnemy] = []
var _failures: int = 0
var _assertions: int = 0

func _ready() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Merc Validation":
		push_error("Merc checks require the isolated Fluxbreak Merc Validation project to protect production progress.")
		get_tree().quit(2)
		return
	call_deferred("_run_checks")

func _run_checks() -> void:
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.global_position = Vector3.ZERO
	_test_shipped_actor_and_weapon_cadence()
	await _clear_enemies()
	_test_shield_support_contract()
	await _clear_enemies()
	await _test_tactical_movement()
	await _clear_enemies()
	print("MERC_REGULAR_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _assertions, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn_enemy(enemy_def: MercEnemyDef, position: Vector3) -> MercEnemy:
	var enemy: MercEnemy = enemy_def.actor_scene.instantiate() as MercEnemy
	enemy.set_ship(_ship)
	enemy.configure_enemy(enemy_def)
	enemy.freeze = true
	add_child(enemy)
	enemy.global_position = position
	enemy.set_physics_process(false)
	enemy.collision_layer = 0
	enemy.collision_mask = 0
	enemy._regen_timer.stop()
	_enemies.append(enemy)
	return enemy

func _test_shipped_actor_and_weapon_cadence() -> void:
	for enemy_def: MercEnemyDef in [CORVETTE, FRIGATE, DESTROYER]:
		var enemy: MercEnemy = _spawn_enemy(enemy_def, Vector3(0.0, 0.0, 190.0))
		_check(enemy.def == enemy_def, "%s retains its shipped definition" % enemy_def.id)
		_check(enemy._controlled_turrets.size() > 0, "%s has a configured turret" % enemy_def.id)
		for turret: EnemyTurret in enemy._controlled_turrets:
			_check(not turret.is_physics_processing(), "%s cannot fire autonomously" % enemy_def.id)
			_check(turret.eff_base_range > 0.0 and turret.eff_damage_max > 0.0, "%s retains resolved weapon stats" % enemy_def.id)
		_check(enemy.get_visual_model_root() != null and enemy.get_muzzle_socket() != null, "%s has the real model and muzzle" % enemy_def.id)
	var corvette: MercEnemy = _enemies[0]
	corvette._attack_cooldown_left = 0.0
	corvette._tick_corvette(0.01)
	_check(corvette._corvette_state == MercEnemy.CorvetteState.BURST, "Corvette begins burst only after closing into attack range")
	var projectiles_before: int = _count_projectiles()
	for shot in range(CORVETTE.behavior.burst_shots):
		corvette._tick_corvette(CORVETTE.behavior.burst_interval_sec + 0.01)
	_check(_count_projectiles() - projectiles_before == CORVETTE.behavior.burst_shots, "Corvette launches the complete authored burst")
	_check(corvette._corvette_state == MercEnemy.CorvetteState.RETREAT, "Corvette pulls back after its burst")
	_check(corvette._attack_cooldown_left > 0.0, "Corvette has a recovery window")
	var projectiles_after: int = _count_projectiles()
	corvette._tick_corvette(0.5)
	_check(_count_projectiles() == projectiles_after, "Corvette does not fire while retreating")
	print("MERC_REGULAR_CHECKS: shipped actors and Corvette cadence checked")

func _test_shield_support_contract() -> void:
	var frigate: MercEnemy = _spawn_enemy(FRIGATE, Vector3.ZERO)
	var second_frigate: MercEnemy = _spawn_enemy(FRIGATE, Vector3(0.0, 0.0, 10.0))
	var corvette: MercEnemy = _spawn_enemy(CORVETTE, Vector3(50.0, 0.0, 0.0))
	var destroyer: MercEnemy = _spawn_enemy(DESTROYER, Vector3(100.0, 0.0, 0.0))
	var third_recipient: MercEnemy = _spawn_enemy(CORVETTE, Vector3(150.0, 0.0, 0.0))
	var far_recipient: MercEnemy = _spawn_enemy(CORVETTE, Vector3(1000.0, 0.0, 0.0))
	var other_def: MercEnemyDef = CORVETTE.duplicate() as MercEnemyDef
	other_def.faction = MACHINES
	var other_faction: MercEnemy = _spawn_enemy(other_def, Vector3(20.0, 0.0, 0.0))
	# Also poison the discovery group: identity checks must still reject this ship.
	other_faction.add_to_group("faction_mercs")
	for recipient: MercEnemy in [corvette, destroyer, third_recipient, far_recipient, other_faction]:
		recipient.shield = 0.0
	frigate._pulse_allied_shields()
	_check(corvette.shield > 0.0 and destroyer.shield > 0.0, "Frigate restores nearby allied shields")
	_check(corvette.shield <= corvette.eff_max_shield * FRIGATE.behavior.shield_restore_fraction + 0.001, "Frigate obeys the recipient capacity fraction")
	_check(destroyer.shield <= FRIGATE.behavior.shield_restore_amount + 0.001, "A shield pulse cannot exceed its authored amount")
	_check(is_zero_approx(third_recipient.shield), "A pulse obeys its maximum of two recipients")
	_check(is_zero_approx(far_recipient.shield), "Shield restoration cannot reach outside support range")
	_check(is_zero_approx(other_faction.shield), "Shield restoration rejects a different faction even in the discovery group")
	_check(frigate._support_links.size() == 2, "Each successful restoration has a visible support link")
	var after_first_pulse: float = destroyer.shield
	second_frigate._pulse_allied_shields()
	_check(is_equal_approx(destroyer.shield, after_first_pulse), "A second Frigate cannot stack restoration on the same recipient")
	frigate._pulse_allied_shields()
	_check(is_equal_approx(destroyer.shield, after_first_pulse), "Repeated pulses cannot bypass the recipient cooldown")
	# Expire only the recipient guard to exercise successive legal pulses quickly.
	destroyer.set_meta(MercEnemy.SHIELD_RECIPIENT_COOLDOWN, 0)
	frigate._pulse_allied_shields()
	_check(destroyer.shield <= destroyer.eff_max_shield * FRIGATE.behavior.shield_restore_fraction + 0.001, "Successive legal pulses remain bounded by recipient capacity")
	var capacity_after_second: float = destroyer.shield
	destroyer.set_meta(MercEnemy.SHIELD_RECIPIENT_COOLDOWN, 0)
	frigate._pulse_allied_shields()
	_check(is_equal_approx(destroyer.shield, capacity_after_second), "Support cannot repeatedly fill a shield beyond its support cap")
	_check(frigate._pick_escort() == destroyer, "Frigate escorts the heavier attack hull")
	print("MERC_REGULAR_CHECKS: shield limits, faction identity, escort, and stacking checked")

func _test_tactical_movement() -> void:
	var corvette: MercEnemy = _spawn_enemy(CORVETTE, Vector3(0.0, 0.0, 600.0))
	corvette.freeze = false
	corvette._attack_cooldown_left = 10.0
	await _drive_corvette(corvette, 18)
	_check(corvette.linear_velocity.dot((_ship.global_position - corvette.global_position).normalized()) > 1.0, "Approaching Corvette physically accelerates toward the player")
	corvette.freeze = true
	corvette.global_position = Vector3(0.0, 0.0, 150.0)
	corvette.linear_velocity = Vector3.ZERO
	corvette._corvette_state = MercEnemy.CorvetteState.RETREAT
	corvette._retreat_time_left = 2.0
	await get_tree().physics_frame
	corvette.freeze = false
	await _drive_corvette(corvette, 18)
	_check(corvette.linear_velocity.dot((_ship.global_position - corvette.global_position).normalized()) < -1.0, "Retreating Corvette physically accelerates away from the player")
	corvette.freeze = true
	corvette.global_position = Vector3(3000.0, 0.0, 0.0)
	var frigate: MercEnemy = _spawn_enemy(FRIGATE, Vector3(0.0, 0.0, 260.0))
	var destroyer: MercEnemy = _spawn_enemy(DESTROYER, Vector3(0.0, 0.0, 300.0))
	frigate.freeze = false
	frigate._attack_cooldown_left = 10.0
	frigate._shield_pulse_left = 10.0
	for frame in range(18):
		frigate._tick_frigate(1.0 / 60.0)
		await get_tree().physics_frame
	_check(frigate._escort == destroyer, "Moving Frigate maintains its heavy-ship escort")
	_check(frigate.linear_velocity.z > 1.0, "Frigate moves behind the escorted Destroyer instead of charging the player")
	print("MERC_REGULAR_CHECKS: distinct approach, retreat, and escort movement checked")

func _drive_corvette(corvette: MercEnemy, frames: int) -> void:
	for frame in range(frames):
		corvette._tick_corvette(1.0 / 60.0)
		await get_tree().physics_frame

func _count_projectiles() -> int:
	var count: int = 0
	for child: Node in get_children():
		if child is Projectile:
			count += 1
	return count

func _clear_enemies() -> void:
	for enemy: MercEnemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	for child: Node in get_children():
		if child is Projectile:
			child.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame

func _check(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("MERC_REGULAR_CHECKS: " + description)
