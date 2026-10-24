extends Node

const WORLD_SCENE: PackedScene = preload("res://scenes/world/world.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const BUTTONS: String = "CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/"

var _checks: int = 0
var _failures: int = 0
var _stage_changes: int = 0
var _world: Node3D = null
var _ship: Ship = null
var _director: WaveDirector = null
var _manager: BossGatewayManager = null
var _hud: BossGatewayHud = null
var _baseline_gain: float = 0.0
var _baseline_forward: float = 0.0
var _baseline_reverse: float = 0.0
var _baseline_range: float = 0.0
var _mouse_accept_gui_events: int = 0
var _survival_fixture: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Gateway Validation":
		push_error("Gateway checks require the isolated Fluxbreak Gateway Validation project.")
		get_tree().quit(2)
		return
	get_tree().root.size = Vector2i(1280, 900)
	get_tree().node_added.connect(_mute_test_audio)
	GameFlow.stage_changed.connect(_on_stage_changed)
	for faction: PracticeFactionDef in PracticeRunFactory.get_factions():
		for route_index: int in range(2):
			await _check_route(faction, route_index)
	GameFlow.abandon_run()
	get_tree().paused = false
	print("GATEWAY_CHOICE_CHECKS: %s; %d checks, %d failures; four factions, both routes, physical keyboard/controller confirmation and dismissal" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _launch_campaign(faction_id: StringName) -> void:
	GameFlow.abandon_run()
	PauseManager.is_paused = false
	get_tree().paused = false
	_world = WORLD_SCENE.instantiate() as Node3D
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	await _wait_frames(3)
	var menu: Control = _world.get_node("MainMenuOverlay") as Control
	menu.call("set_practice_faction_id", faction_id)
	(menu.get_node(BUTTONS + "PlayContainer/Play") as Button).pressed.emit()
	await _wait_frames(2)
	_check(menu.call("get_current_page") == &"play", "Actual Home Play button opens campaign configuration")
	(menu.get_node(BUTTONS + "PracticeContainer/Practice") as Button).pressed.emit()
	await _wait_frames(2)
	_check(not menu.visible and not get_tree().paused, "Actual Campaign button launches flight")
	_check(GameFlow.get_run_faction().get_faction_id() == faction_id and GameFlow.get_active_stage_index() == 0, "Actual Campaign launch retains its selected faction and approach stage")
	_ship = _world.get_node("Ship") as Ship
	_ship.freeze = true
	_ship.set_physics_process(false)
	_ship._regen_timer.stop()
	_director = _world.get_node("StageRoot/WaveDirector") as WaveDirector
	_director.set_process(false)
	_manager = _world.get_node("StageRoot/BossGatewayManager") as BossGatewayManager
	_hud = _world.get_node("HUD/ScreenRoot/BossGatewayHud") as BossGatewayHud
	_ship.stat_aggregator.set_stage_projection_enabled(false)
	_baseline_gain = _ship.eff_nanobot_gain_mult
	_baseline_forward = _ship.eff_max_speed_forward
	_baseline_reverse = _ship.eff_max_speed_reverse
	var turret: PlayerTurret = _first_player_turret()
	_baseline_range = turret.eff_base_range if turret != null else 0.0
	_ship.stat_aggregator.set_stage_projection_enabled(true)
	_check(turret != null and _baseline_range > 0.0, "Actual campaign ship retains its usable starter weapon")

func _check_route(faction: PracticeFactionDef, route_index: int) -> void:
	var failures_before: int = _failures
	await _launch_campaign(faction.faction.get_faction_id())
	var approach: StageDef = GameFlow.get_current_stage()
	_survival_fixture = _add_boss_survival_fixture(faction)
	await _start_and_defeat_gateway_boss(approach)
	await _wait_frames(3)
	var gateways: Array[BossGateway] = _manager.get_active_gateways()
	_check(gateways.size() == 2 and _director.is_gateway_hold_active(), "Defeating the actual Campaign boss creates both offered routes with surviving threats")
	if gateways.size() != 2:
		await _dispose_world()
		return
	var chosen: BossGateway = gateways[route_index]
	var other: BossGateway = gateways[1 - route_index]
	_check(chosen.get_marker_key() != other.get_marker_key() and chosen.get_marker_color() != other.get_marker_color(), "World gateways provide distinct route silhouettes and colors")
	_check(not _manager.confirm_gateway(), "Confirmation without an inspected gateway is rejected")
	_manager._process(10000.0)
	_check(GameFlow.get_active_stage_index() == 0 and not _manager.is_briefing_open(), "Elapsed time outside a gateway cannot inspect or transfer")
	await _inspect(other)
	var first_title: String = _hud._title.text
	var retained_attack: EnemyAttackTelegraph = _survival_fixture["attack"] as EnemyAttackTelegraph
	var paused_remaining: float = retained_attack.get_time_remaining() if is_instance_valid(retained_attack) else -1.0
	await _wait_physics_frames(3)
	_check(is_instance_valid(retained_attack) and is_equal_approx(retained_attack.get_time_remaining(), paused_remaining), "The gateway briefing freezes an existing survivor's attack windup")
	await _send_escape_with_unrelated_input()
	_check_dismissed("Physical Escape")
	await _wait_physics_frames(3)
	_check(is_instance_valid(retained_attack) and retained_attack.get_time_remaining() < paused_remaining, "Dismissing the briefing resumes the same surviving attack")
	_check_survival_fixture("Gateway dismissal")
	_manager._process(10000.0)
	_check(not _manager.is_briefing_open(), "A dismissed gateway cannot reopen while the ship remains inside it")
	_ship.global_position = other.global_position + Vector3.UP * (other.get_docking_radius() + _manager.gateway_rearm_margin * 0.5)
	_manager._process(10000.0)
	_ship.global_position = other.global_position
	_manager._process(10000.0)
	_check(not _manager.is_briefing_open(), "Leaving only the docking radius does not bypass the rearm margin")
	await _rearm_and_inspect(other)
	_ship.hull = _ship.eff_max_hull * 0.4
	_ship._nanobots = 2222
	_ship._hull_repair_cooldown_remaining = 0.0
	var before_cancel_hull: float = _ship.hull
	_ship.set_physics_process(true)
	await _send_joy(JOY_BUTTON_B)
	_ship.set_physics_process(false)
	_check_dismissed("Physical controller B")
	_check(is_equal_approx(_ship.hull, before_cancel_hull) and _ship.get_nanobots() == 2222, "Shared controller B cancels the briefing without repairing or spending nanobots")
	var repair_cost: int = _ship.get_hull_repair_cost()
	_ship.set_physics_process(true)
	await _send_joy(JOY_BUTTON_B)
	_ship.set_physics_process(false)
	_check(_ship.hull > before_cancel_hull and _ship.get_nanobots() == 2222 - repair_cost, "A later intentional controller B press still performs one normal hull repair")
	await _inspect(chosen)
	_check(_hud._title.text != first_title, "A declined gateway leaves the other route available for inspection")
	if route_index == 0:
		await _send_key(KEY_ENTER)
	else:
		await _send_joy(JOY_BUTTON_A)
	_check_dismissed("Accept on the safe default Not yet")
	await _rearm_and_inspect(chosen)
	var original_route: SectorRouteDef = chosen.get_route()
	var invalid_route: SectorRouteDef = SectorRouteDef.new()
	invalid_route.destination_stage = StageDef.new()
	invalid_route.destination_stage.stage_id = &"unoffered_gateway_destination"
	chosen.configure_route(invalid_route)
	_check(not _manager.confirm_gateway() and GameFlow.get_active_stage_index() == 0, "An unoffered destination is rejected without advancing")
	chosen.configure_route(original_route)
	_ship.global_position = chosen.global_position + Vector3.UP * (chosen.get_docking_radius() + 1.0)
	_check(not _manager.confirm_gateway(), "A confirmation after leaving docking range is rejected")
	_check_dismissed("Out-of-range rejection")
	await _rearm_and_inspect(chosen)
	await _send_key(KEY_ESCAPE)
	_check_dismissed("Preparing the final confirmation")
	await _exit_rearm_radius(chosen)
	# Actual runtime actors and warnings must be cleaned by the transfer, while
	# damaged health, currency, upgrade memory and existing weapons must carry.
	var source: Enemy = await _add_cleanup_fixture(chosen)
	var weapons: Array[WeaponDef] = _ship.hardpoint_manager.get_weapons().duplicate()
	var turret: PlayerTurret = _first_player_turret()
	var turret_id: int = turret.get_instance_id() if turret != null else 0
	_ship.hull = _ship.eff_max_hull * 0.4
	_ship.shield = _ship.eff_max_shield * 0.3
	_ship._nanobots = 2222
	_ship._hull_repair_cooldown_remaining = 1.7
	RunState.add_score(1234, "gateway validation")
	RunState.record_weapon_purchase()
	RunState.record_upgrade_purchase("gateway_carried_upgrade")
	var hull: float = _ship.hull
	var shield: float = _ship.shield
	var score: int = RunState.run_score
	var purchases: int = RunState.weapons_purchased
	var kill_rate_before_transfer: float = CombatStats.get_enemy_kill_rate()
	var changes_before: int = _stage_changes
	var destination_id: StringName = original_route.get_destination_id()
	await _inspect(chosen)
	_check(_ship.get_tether_source() == source and _ship.get_movement_slow_multiplier() < 1.0, "Final briefing begins with a genuine attached movement status")
	if route_index == 0:
		await _send_key(KEY_LEFT)
	else:
		await _send_joy(JOY_BUTTON_DPAD_LEFT)
	_check(get_viewport().gui_get_focus_owner() == _hud._enter_button, "Physical navigation moves from safe Not yet to explicit Enter this sector")
	if faction.faction.get_faction_id() == &"mercs" and route_index == 0:
		await _click_enter_button()
	elif route_index == 0:
		await _send_key(KEY_ENTER)
	else:
		await _send_joy(JOY_BUTTON_A)
	await _wait_frames(3)
	_check(GameFlow.get_active_stage_index() == 1 and GameFlow.get_current_stage().get_stage_id() == destination_id, "The physical confirmation enters exactly the selected sector")
	_check(_stage_changes == changes_before + 1, "A gateway confirmation advances the stage exactly once")
	_check(not _manager.confirm_gateway() and _stage_changes == changes_before + 1, "A repeated confirmation cannot advance again")
	_check(not _manager.is_briefing_open() and not _hud.visible and not get_tree().paused and not PauseManager.is_paused, "Successful confirmation closes the briefing and restores flight")
	_check(_manager.get_active_gateways().is_empty() and get_tree().get_nodes_in_group("boss_gateways").is_empty(), "Transfer removes both old gateways")
	_check(not is_instance_valid(source) and _warnings_empty(), "Transfer removes old actors, tether links, displacement markers and pending attacks")
	for key: String in ["source", "target", "attack", "drop", "projectile"]:
		_check(not is_instance_valid(_survival_fixture[key]), "Confirmed transfer removes the retained pre-boss %s" % key)
	for child_id: int in _survival_fixture["summon_ids"]:
		_check(not is_instance_id_valid(child_id), "Confirmed transfer removes a retained owned summon without waiting for its death")
	_check(_ship.get_tether_source() == null and is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Transfer clears the actual movement penalty")
	_check(is_equal_approx(_ship.hull, hull) and is_equal_approx(_ship.shield, shield), "Sector transfer preserves damaged hull and shield without healing")
	_check(_ship.get_nanobots() == 2222 and RunState.run_score == score and RunState.weapons_purchased == purchases, "Sector transfer preserves currency, score and weapon price progression")
	_check(get_tree().get_nodes_in_group("drops").is_empty() and CombatStats.get_enemy_kill_rate() <= kill_rate_before_transfer and is_zero_approx(CombatStats._frame_enemy_kills), "Transfer grants no synthetic nanobot drops or adaptive kills for retained actors")
	_check(RunState.get_purchased_upgrade_ids().has("gateway_carried_upgrade"), "Sector transfer preserves purchased upgrade memory")
	_check(_ship.hardpoint_manager.get_weapons() == weapons and _first_player_turret().get_instance_id() == turret_id, "Sector transfer preserves the exact weapon loadout and turret instances")
	_check(is_equal_approx(_ship.get_hull_repair_cooldown_remaining(), 1.7), "Sector transfer preserves the existing repair cooldown")
	_check(GameFlow.get_run_faction().get_faction_id() == faction.faction.get_faction_id(), "Both routes retain the chosen run faction")
	_check(_director.get_wave_index() == 0 and not _director.is_gateway_hold_active(), "The director restarts the new stage from its opening downtime")
	_check_route_stats(original_route)
	await _dispose_world()
	print("GATEWAY ROUTE: %s %s %s" % [faction.faction.get_faction_id(), original_route.get_route_id(), "PASS" if _failures == failures_before else "FAIL"])

func _add_boss_survival_fixture(faction: PracticeFactionDef) -> Dictionary:
	var catalog: EnemyCatalog = _world.get_node("StageRoot/EnemyCatalog") as EnemyCatalog
	var definition: EnemyDef = catalog.get_pool(faction.faction, null, 1)[0]
	if faction.faction.get_faction_id() == &"mercs":
		definition = load("res://content/data/enemies/merc_carrier_mk1.tres") as EnemyDef
	elif faction.faction.get_faction_id() == &"bugs":
		definition = load("res://content/data/enemies/bug_broodmother_mk1.tres") as EnemyDef
	var source: Enemy = _director._spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, definition, _ship.global_position + Vector3.RIGHT * 6000.0) as Enemy
	_freeze_survivor(source)
	source.hull = source.eff_max_hull * 0.6
	source.shield = source.eff_max_shield * 0.4
	var summons: Array[Enemy] = []
	if source is MercEnemy:
		var carrier: MercEnemy = source as MercEnemy
		_check(carrier._escort_wing != null and carrier._escort_wing.spawn_escorts(2) == 2, "The real Carrier launches its owned pre-boss escorts")
		if carrier._escort_wing != null:
			summons = carrier._escort_wing.get_living_escorts()
	elif source is BugEnemy:
		var mother: BugEnemy = source as BugEnemy
		_check(mother._brood != null and mother._brood.spawn_brood(2) == 2, "The real Broodmother launches its owned pre-boss children")
		for node: Node in get_tree().get_nodes_in_group("bug_brood"):
			if int(node.get_meta("brood_parent_id", 0)) == source.get_instance_id():
				summons.append(node as Enemy)
	# A second real summoner dies before the boss arrives. Its children must
	# survive both gateway dismissal and the boss, then leave with the sector.
	if source is MercEnemy or source is BugEnemy:
		var orphan_request: SpawnRequest = SpawnRequest.new()
		orphan_request.grants_kill_rewards = false
		orphan_request.contributes_to_pressure = false
		var former_owner: Enemy = _director._spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, definition, source.global_position + Vector3.RIGHT * 1000.0, orphan_request) as Enemy
		_freeze_survivor(former_owner)
		var independent_children: Array[Enemy] = []
		if former_owner is MercEnemy:
			var former_carrier: MercEnemy = former_owner as MercEnemy
			_check(former_carrier._escort_wing.spawn_escorts(2) == 2, "A second real Carrier creates the persistence fixture")
			independent_children = former_carrier._escort_wing.get_living_escorts()
		else:
			var former_mother: BugEnemy = former_owner as BugEnemy
			_check(former_mother._brood.spawn_brood(2) == 2, "A second real Broodmother creates the persistence fixture")
			for node: Node in get_tree().get_nodes_in_group("bug_brood"):
				if int(node.get_meta("brood_parent_id", 0)) == former_owner.get_instance_id():
					independent_children.append(node as Enemy)
		former_owner.apply_damage(former_owner.hull + former_owner.shield + 1000000.0)
		for child: Enemy in independent_children:
			_check(is_instance_valid(child) and not child._dead and not child.is_queued_for_deletion(), "Killing a real summoner leaves its existing children active before boss arrival")
			summons.append(child)
	var summon_ids: Array[int] = []
	for child: Enemy in summons:
		_freeze_survivor(child)
		child.hull *= 0.5
		summon_ids.append(child.get_instance_id())
	var target: TargetObject = _director._spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.TARGET, load("res://content/data/targets/asteroid_small.tres") as TargetDef, source.global_position + Vector3.UP * 1000.0) as TargetObject
	target.freeze = true
	target.process_mode = Node.PROCESS_MODE_DISABLED
	target.hull = target.max_hull * 0.6
	var attack: EnemyAttackTelegraph = EnemyAttackTelegraph.new()
	_world.add_child(attack)
	attack.start_attack(source, _ship, source, 1000.0, 36.0)
	var drop: NanobotSwarm = Enemy.NanobotSwarmScene.instantiate() as NanobotSwarm
	drop.process_mode = Node.PROCESS_MODE_DISABLED
	_world.add_child(drop)
	drop.global_position = source.global_position
	drop.value = 321
	var projectile: Projectile = Projectile.new()
	projectile.process_mode = Node.PROCESS_MODE_DISABLED
	projectile.configure_shot(source, _ship, WeaponCombatResolver.ShotResult.MISS, 0.0, 0.3, 1.0, [], false)
	_world.add_child(projectile)
	projectile.global_position = source.global_position
	return {"source": source, "source_hull": source.hull, "source_shield": source.shield, "summons": summons, "summon_ids": summon_ids, "target": target, "target_hull": target.hull, "attack": attack, "drop": drop, "projectile": projectile}

func _start_and_defeat_gateway_boss(stage: StageDef) -> void:
	_director._wave_index = stage.boss_wave_index
	_director._state = RunState.State.IN_WAVE
	_director._wave_timer = 0.0
	RunState.set_state(RunState.State.IN_WAVE)
	var pending: SpawnRequest = SpawnRequest.new()
	pending.enemy_def = (_survival_fixture["source"] as Enemy).def
	pending.count = 1
	pending.package_id = "obsolete_pressure_formation"
	# Exercise the real pending timer, not merely the cancellation flags.
	_director._run_requests_coroutine([pending], {"formation_schedule": [{"package_id": pending.package_id, "launch_at_sec": 0.05}]}, {}, _director._wave_token, "pressure", false)
	var score_before: int = RunState.run_score
	var drops_before: int = get_tree().get_nodes_in_group("drops").size()
	var kills_before: float = CombatStats._frame_enemy_kills
	_director._start_boss_wave()
	var boss: Enemy = _director._active_boss_instance
	_check(boss != null and _director.is_boss_wave_active(), "The actual Campaign boss starts while the existing battlefield remains alive")
	if boss == null:
		return
	_freeze_survivor(boss)
	_check(RunState.run_score == score_before and get_tree().get_nodes_in_group("drops").size() == drops_before and is_equal_approx(CombatStats._frame_enemy_kills, kills_before), "Boss arrival grants no synthetic score, drops or kill pressure")
	await get_tree().create_timer(0.10, false).timeout
	_check_survival_fixture("Boss arrival")
	var history: Array[Dictionary] = _director.get_delivery_history()
	var pressure: Dictionary = history.back() if not history.is_empty() else {}
	var reasons: Dictionary = pressure.get("cancel_reasons", {})
	_check(int(pressure.get("planned_units", 0)) == 1 and int(pressure.get("spawned_units", -1)) == 0 and int(pressure.get("pending_units", -1)) == 0 and int(pressure.get("cancelled_units", 0)) == 1 and int(reasons.get("boss_wave_started", 0)) == 1, "Boss arrival cancels every pending pressure unit before its timer can spawn it")
	# Boss rewards are legitimate; subsequent transfer checks take a fresh baseline.
	boss.apply_damage(boss.hull + boss.shield + 1000000.0)
	await _wait_frames(3)
	_check_survival_fixture("Boss defeat")
	_check(_director.is_gateway_hold_active() and GameFlow.get_active_stage_index() == 0, "Boss defeat opens the gateway hold immediately despite ordinary enemies and owned summons")
	_check(int(pressure.get("spawned_units", -1)) == 0, "The cancelled pre-boss pressure purchase remains cancelled in gateway hold")

func _freeze_survivor(enemy: Enemy) -> void:
	enemy.freeze = true
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.explosion_scene = null

func _check_survival_fixture(reason: String) -> void:
	var source: Enemy = _survival_fixture["source"] as Enemy
	var target: TargetObject = _survival_fixture["target"] as TargetObject
	var attack: EnemyAttackTelegraph = _survival_fixture["attack"] as EnemyAttackTelegraph
	_check(is_instance_valid(source) and not source._dead and not source.is_queued_for_deletion(), reason + " retains the exact living ordinary enemy")
	_check(is_instance_valid(source) and is_equal_approx(source.hull, float(_survival_fixture["source_hull"])) and is_equal_approx(source.shield, float(_survival_fixture["source_shield"])), reason + " preserves the enemy's damaged hull and shield")
	_check(is_instance_valid(target) and not target._dead and not target.is_queued_for_deletion() and is_equal_approx(target.hull, float(_survival_fixture["target_hull"])), reason + " retains the exact damaged stationary target")
	_check(is_instance_valid(attack) and not attack.is_queued_for_deletion() and attack.is_warning_for(_ship), reason + " preserves the survivor's real pending attack")
	_check(is_instance_valid(_survival_fixture["drop"]) and is_instance_valid(_survival_fixture["projectile"]), reason + " leaves the existing drop and projectile intact")
	for child: Enemy in _survival_fixture["summons"]:
		_check(is_instance_valid(child) and not child._dead and not child.is_queued_for_deletion() and is_equal_approx(child.hull, child.eff_max_hull * 0.5) and child._spawn_context.is_summoned, reason + " retains a damaged summon, including children whose owner already died")

func _inspect(gateway: BossGateway) -> void:
	_ship.global_position = gateway.global_position
	_manager._process(10000.0)
	await _wait_frames(2)
	_check(_manager.get_briefing_gateway() == gateway and _hud.visible, "Entering a gateway opens the actual route briefing")
	_check(get_tree().paused and not PauseManager.is_paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "The route briefing pauses combat without opening the ordinary pause menu")
	_check(GameFlow.get_active_stage_index() == 0 and _manager.get_docking_timer() == 0.0, "Elapsed docking time never transfers before explicit confirmation")
	_check(get_viewport().gui_get_focus_owner() == _hud._not_yet_button, "Every briefing starts on the safe Not yet action")
	_check(not _hud._title.text.is_empty() and not _hud._description.text.is_empty() and not _hud._threats.text.is_empty() and not _hud._rewards.text.is_empty(), "The paused briefing presents its route, threats and opportunities")
	_check(_hud._conditions.text.contains("%") and _hud._destination.text.contains(GameFlow.get_run_faction().get_display_name_or_default()), "The briefing discloses numeric conditions and the retained faction")
	_check(get_viewport().get_visible_rect().encloses(_hud._panel.get_global_rect()), "The whole briefing panel fits the supported 1280 by 900 viewport")

func _check_dismissed(reason: String) -> void:
	_check(not _manager.is_briefing_open() and not _hud.visible and not get_tree().paused, reason + " closes the modal and returns to flight")
	_check(GameFlow.get_active_stage_index() == 0 and not PauseManager.is_paused, reason + " cannot choose a sector or accidentally open pause")

func _exit_rearm_radius(gateway: BossGateway) -> void:
	_ship.global_position = gateway.global_position + Vector3.UP * (gateway.get_docking_radius() + _manager.gateway_rearm_margin + 10.0)
	_manager._process(0.0)
	await _wait_frames(1)

func _rearm_and_inspect(gateway: BossGateway) -> void:
	await _exit_rearm_radius(gateway)
	await _inspect(gateway)

func _add_cleanup_fixture(gateway: BossGateway) -> Enemy:
	_ship.global_position = gateway.global_position + Vector3.UP * (gateway.get_docking_radius() + _manager.gateway_rearm_margin + 10.0)
	var source: Enemy = ENEMY_SCENE.instantiate() as Enemy
	source.freeze = true
	source.process_mode = Node.PROCESS_MODE_DISABLED
	source.explosion_scene = null
	_world.add_child(source)
	var definition: EnemyDef = EnemyDef.new()
	definition.weapon = load("res://content/data/weapons/pulse_mk1.tres") as WeaponDef
	source.configure_enemy(definition)
	source.global_position = _ship.global_position + Vector3.RIGHT * 5.0
	var tether: GreyTether = GreyTether.new()
	_world.add_child(tether)
	_check(tether.start_tether(source, _ship, 0.05, 3.0, 0.7, 600.0, 36.0), "Cleanup fixture starts a real tether acquisition")
	await _wait_frames(8)
	_check(tether.is_attached(), "Cleanup fixture attaches through the actual GreyTether helper")
	var attack: EnemyAttackTelegraph = EnemyAttackTelegraph.new()
	_world.add_child(attack)
	attack.start_attack(source, _ship, source, 50.0, 36.0)
	var displacement: GreyDisplacement = GreyDisplacement.new()
	_world.add_child(displacement)
	_check(displacement.start_displacement(source, source.global_position + Vector3.RIGHT * 100.0, 50.0), "Cleanup fixture starts a marked pending displacement")
	return source

func _check_route_stats(route: SectorRouteDef) -> void:
	var salvage: bool = route.marker_kind == SectorRouteDef.MarkerKind.SALVAGE
	_check(is_equal_approx(_ship.eff_nanobot_gain_mult, _baseline_gain * (1.25 if salvage else 1.0)), "The confirmed route applies exactly its advertised economy multiplier")
	_check(is_equal_approx(_ship.eff_max_speed_forward, _baseline_forward * (1.0 if salvage else 1.15)) and is_equal_approx(_ship.eff_max_speed_reverse, _baseline_reverse * (1.0 if salvage else 1.15)), "The confirmed route applies exactly its advertised mobility modifiers")
	_check(is_equal_approx(_first_player_turret().eff_base_range, _baseline_range * (0.9 if salvage else 1.0)), "The confirmed route applies or removes its actual weapon range penalty")

func _first_player_turret() -> PlayerTurret:
	for node: Node in _ship.find_children("*", "PlayerTurret", true, false):
		var turret: PlayerTurret = node as PlayerTurret
		if turret != null and turret.get_weapon() != null:
			return turret
	return null

func _warnings_empty() -> bool:
	for group: StringName in [&"enemy_attack_telegraphs", &"grey_displacements", &"grey_tethers"]:
		if not get_tree().get_nodes_in_group(group).is_empty():
			return false
	return true

func _send_key(code: Key) -> void:
	var press: InputEventKey = InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await _wait_frames(2)
	var release: InputEventKey = InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	release.pressed = false
	Input.parse_input_event(release)
	await _wait_frames(2)

func _send_escape_with_unrelated_input() -> void:
	var press: InputEventKey = InputEventKey.new()
	press.keycode = KEY_ESCAPE
	press.physical_keycode = KEY_ESCAPE
	press.pressed = true
	Input.parse_input_event(press)
	# Keep the consumed Escape stamp live while unrelated inputs reach the
	# now-hidden modal's unhandled-input path in this exact same frame.
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(1.0, 0.0)
	Input.parse_input_event(motion)
	var axis: InputEventJoypadMotion = InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = 0.1
	Input.parse_input_event(axis)
	# Dispatch this accumulated batch together even when the caller resumed from
	# physics_frame; the next process_frame can precede normal input dispatch.
	Input.flush_buffered_events()
	_check(not get_tree().paused and not PauseManager.is_paused and not (_world.get_node("PauseMenu") as CanvasLayer).visible, "Consumed Escape followed by same-frame mouse and stick motion cannot reopen pause")
	await _wait_frames(2)
	var release: InputEventKey = InputEventKey.new()
	release.keycode = KEY_ESCAPE
	release.physical_keycode = KEY_ESCAPE
	release.pressed = false
	Input.parse_input_event(release)
	axis = InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = 0.0
	Input.parse_input_event(axis)
	await _wait_frames(2)
	_check(not (_world.get_node("PauseMenu") as CanvasLayer).visible, "Same-frame unrelated input regression leaves the ordinary pause menu hidden")

func _send_joy(button: JoyButton) -> void:
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.button_index = button
	press.pressed = true
	Input.parse_input_event(press)
	await _wait_frames(2)
	var release: InputEventJoypadButton = InputEventJoypadButton.new()
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)
	await _wait_frames(2)

func _click_enter_button() -> void:
	var before_events: int = _mouse_accept_gui_events
	_hud._enter_button.gui_input.connect(_on_enter_button_gui_input)
	var center: Vector2 = _hud._enter_button.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	Input.parse_input_event(motion)
	await _wait_frames(2)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = center
	press.global_position = center
	press.pressed = true
	Input.parse_input_event(press)
	await _wait_frames(2)
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = center
	release.global_position = center
	release.pressed = false
	Input.parse_input_event(release)
	await _wait_frames(2)
	_check(_mouse_accept_gui_events > before_events, "Actual viewport mouse input reaches the Enter this sector button through the HUD layers")

func _on_enter_button_gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		_mouse_accept_gui_events += 1

func _dispose_world() -> void:
	GameFlow.abandon_run()
	PauseManager.is_paused = false
	get_tree().paused = false
	_world.queue_free()
	await _wait_frames(4)
	_check(get_tree().get_nodes_in_group("boss_gateways").is_empty() and _warnings_empty(), "Leaving the world cleans route gateways and every pending combat warning")
	_world = null
	_ship = null
	_manager = null
	_hud = null
	_director = null
	_survival_fixture = {}

func _on_stage_changed(_stage: StageDef, _index: int) -> void:
	_stage_changes += 1

func _mute_test_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _wait_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _wait_physics_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().physics_frame

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
