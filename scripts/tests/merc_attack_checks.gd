extends Node

## Focused, deterministic combat checks. Run in an isolated user-data project:
## Godot --headless --path <validation-project> res://scripts/tests/merc_attack_checks.tscn

class DamageTarget extends Node3D:
	var damage_taken: float = 0.0
	var damage_calls: int = 0
	func apply_damage(amount: float, _context: CombatStatContext = null) -> void:
		damage_taken += amount
		damage_calls += 1
	func get_evasion() -> float:
		return 0.0
	func is_alive() -> bool:
		return true

class DeterministicWeaponHost extends Node3D:
	var systems_bonus: float = 0.0
	var eff_base_accuracy: float = 1.0
	var eff_range_falloff: float = 0.0
	var eff_crit_chance: float = 0.0
	var eff_graze_on_hit: float = 0.0
	var eff_graze_on_miss: float = 0.0
	var eff_crit_mult: float = 1.0
	var eff_graze_mult: float = 0.3
	var eff_damage_min: float = 10.0
	var eff_damage_max: float = 10.0
	var eff_base_range: float = 1200.0
	var eff_range_bonus_add: float = 0.0
	var eff_systems_bonus_add: float = 0.0

const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const SOURCE_DEF: EnemyDef = preload("res://content/data/enemies/merc_corvette_mk1.tres")
const BOSS_DEF: MercBossDef = preload("res://content/data/enemies/merc_contract_enforcer_mk1.tres")

var _failures: int = 0
var _checks: int = 0
var _ship: Ship = null
var _source: Enemy = null
var _target: DamageTarget = null
var _host: DeterministicWeaponHost = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Merc Validation":
		push_error("Merc combat checks require the isolated Fluxbreak Merc Validation project.")
		get_tree().quit(2)
		return
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "TestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_source = ENEMY_SCENE.instantiate() as Enemy
	_source.freeze = true
	_source.explosion_scene = null
	_source.set_ship(_ship)
	_source.configure_enemy(SOURCE_DEF.duplicate(false) as EnemyDef)
	add_child(_source)
	_source.set_physics_process(false)
	var turret: EnemyTurret = _source.get_node("Turret") as EnemyTurret
	turret.set_physics_process(false)
	_target = DamageTarget.new()
	add_child(_target)
	_host = DeterministicWeaponHost.new()
	add_child(_host)
	await _check_delayed_snapshot_and_single_hit()
	await _check_sphere_escape()
	await _check_corridor_escape()
	await _check_pause()
	await _check_source_death()
	await _check_boss_escort_and_scaling()
	print("MERC_ATTACK_CHECKS: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _reset_target() -> void:
	_target.global_position = Vector3(0.0, 0.0, -200.0)
	_target.damage_taken = 0.0
	_target.damage_calls = 0
	_host.eff_damage_min = 10.0
	_host.eff_damage_max = 10.0

func _start_attack(corridor: bool = false, windup: float = 0.35) -> EnemyAttackTelegraph:
	var attack: EnemyAttackTelegraph = EnemyAttackTelegraph.new()
	add_child(attack)
	attack.start_attack(_source, _target, _host, windup, 40.0, corridor)
	return attack

func _check_delayed_snapshot_and_single_hit() -> void:
	_reset_target()
	var attack: EnemyAttackTelegraph = _start_attack()
	var result: Dictionary = {"count": 0, "hit": false}
	attack.resolved.connect(func(hit: bool) -> void:
		result["count"] = int(result["count"]) + 1
		result["hit"] = hit
	)
	await _wait(0.12)
	_expect(_target.damage_calls == 0 and int(result["count"]) == 0, "No damage or completion before the windup")
	# Changing the actual host mid-charge must not rewrite the committed shot.
	_host.eff_damage_min = 100.0
	_host.eff_damage_max = 100.0
	await _wait(0.35)
	_expect(is_equal_approx(_target.damage_taken, 10.0), "The resolved shot keeps the weapon stats captured when charging began")
	_expect(_target.damage_calls == 1 and int(result["count"]) == 1 and bool(result["hit"]), "A successful charge damages and emits completion exactly once")
	await _wait(0.25)
	_expect(_target.damage_calls == 1 and int(result["count"]) == 1, "No second hit after the release flash")

func _check_sphere_escape() -> void:
	_reset_target()
	var attack: EnemyAttackTelegraph = _start_attack()
	var result: Dictionary = {"hit": true}
	attack.resolved.connect(func(hit: bool) -> void: result["hit"] = hit)
	await _wait(0.1)
	_target.global_position.y += 80.0
	await _wait(0.4)
	_expect(_target.damage_calls == 0 and not bool(result["hit"]), "Moving vertically out of the locked sphere always avoids its damage")

func _check_corridor_escape() -> void:
	_reset_target()
	var attack: EnemyAttackTelegraph = _start_attack(true)
	var result: Dictionary = {"hit": true}
	attack.resolved.connect(func(hit: bool) -> void: result["hit"] = hit)
	await _wait(0.1)
	_target.global_position = Vector3(90.0, 90.0, -150.0)
	await _wait(0.4)
	_expect(_target.damage_calls == 0 and not bool(result["hit"]), "Moving out of the locked three-dimensional corridor avoids its damage")
	_reset_target()
	_start_attack(true)
	await _wait(0.1)
	_target.global_position = Vector3(0.0, 0.0, -150.0)
	await _wait(0.4)
	_expect(_target.damage_calls == 1, "Remaining inside the fixed corridor still allows its normal hit roll")

func _check_pause() -> void:
	_reset_target()
	_start_attack(false, 0.4)
	await _wait(0.1)
	get_tree().paused = true
	await _wait(0.55)
	_expect(_target.damage_calls == 0, "Pausing longer than the windup does not resolve an attack")
	get_tree().paused = false
	await _wait(0.1)
	_expect(_target.damage_calls == 0, "Unpausing preserves the unfinished part of the windup")
	await _wait(0.3)
	_expect(_target.damage_calls == 1, "An attack completes normally after its remaining unpaused windup")

func _check_source_death() -> void:
	_reset_target()
	var attack: EnemyAttackTelegraph = _start_attack()
	var result: Dictionary = {"count": 0}
	attack.resolved.connect(func(_hit: bool) -> void: result["count"] = int(result["count"]) + 1)
	await _wait(0.1)
	_source.apply_damage(1000000.0)
	await _wait(0.45)
	_expect(_target.damage_calls == 0 and int(result["count"]) == 0, "Killing the real source during windup cancels damage and completion")
	_expect(not is_instance_valid(attack), "Source death removes the warning visual")

func _check_boss_escort_and_scaling() -> void:
	var spawner: Spawner = Spawner.new()
	spawner.name = "TestSpawner"
	spawner.ship_path = NodePath("../TestShip")
	spawner.enemy_scene = ENEMY_SCENE
	spawner.directed_mode = true
	add_child(spawner)
	var scaling: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
	scaling.hull_multiplier = 1.5
	scaling.damage_multiplier = 2.0
	var request: SpawnRequest = SpawnRequest.new()
	request.enemy_def = BOSS_DEF
	request.enemy_combat_scaling = scaling
	var boss: MercEnforcer = spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, BOSS_DEF, Vector3(0.0, 0.0, -340.0), request) as MercEnforcer
	_expect(boss != null, "The shipped Enforcer definition spawns through the actual Spawner")
	if boss == null:
		return
	boss.freeze = true
	boss.explosion_scene = null
	_expect(boss._weapon_sockets.size() == 2, "The shipped boss model exposes both weapon sockets")
	if not boss._weapon_sockets.is_empty():
		var base_damage: float = boss._weapon_sockets[0].weapon.damage_min
		_expect(is_equal_approx(boss._weapon_sockets[0].eff_damage_min, base_damage * 2.0), "Boss socket weapons inherit enemy spawn damage scaling")
	_expect(int(spawner.get_alive_counts()["enemies"]) == 1, "Spawner accounts for the boss")
	boss.apply_damage(boss.shield + boss.eff_max_hull * 0.5)
	await _wait(0.1)
	_expect(boss.is_in_second_phase(), "Crossing the hull threshold starts the second phase while the boss stays damageable")
	_expect(int(spawner.get_alive_counts()["enemies"]) == 2, "The phase escort goes through real Spawner accounting")
	var escorts: Array[Node] = []
	for node in get_tree().get_nodes_in_group("targets"):
		if node is Enemy and node.has_meta("enforcer_escort"):
			escorts.append(node)
	_expect(escorts.size() == 1, "The phase adds exactly one escort")
	if not escorts.is_empty():
		var escort: Enemy = escorts[0] as Enemy
		_expect(is_equal_approx(escort.eff_max_hull, escort.def.max_hull * 1.5), "The escort inherits the boss encounter's spawn scaling")
		# Killing the escort cannot create an endless replacement loop.
		escort.explosion_scene = null
		escort.apply_damage(1000000.0)
	await _wait(0.15)
	_expect(int(spawner.get_alive_counts()["enemies"]) == 1, "A killed escort is never replaced")
	# A second encounter exercises cleanup while its escort is still alive.
	boss.queue_free()
	await _wait(0.1)
	boss = spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, BOSS_DEF, Vector3(0.0, 0.0, -340.0), request) as MercEnforcer
	boss.freeze = true
	boss.explosion_scene = null
	boss.apply_damage(boss.shield + boss.eff_max_hull * 0.5)
	await _wait(0.1)
	_expect(int(spawner.get_alive_counts()["enemies"]) == 2, "The cleanup test has an active boss and escort")
	boss.apply_damage(1000000.0)
	await _wait(0.15)
	_expect(int(spawner.get_alive_counts()["enemies"]) == 0, "Boss death removes its live escort and returns Spawner accounting to zero")
	spawner.queue_free()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("FAIL: " + description)
