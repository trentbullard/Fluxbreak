extends Node3D

const Stat = StatTypes.Stat
const Phase = StatTypes.Phase
const Op = StatTypes.Op
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const SHIP_DEF: ShipDef = preload("res://content/data/ships/starter_fighter.tres")
const TIDE: StageModifierDef = preload("res://content/data/stages/modifiers/salvage_tide.tres")
const CORRIDORS: StageModifierDef = preload("res://content/data/stages/modifiers/thruster_corridors.tres")
const STATIC: StageModifierDef = preload("res://content/data/stages/modifiers/sensor_static.tres")
const FLARE: StageModifierDef = preload("res://content/data/stages/modifiers/solar_flare_front.tres")
const ARMOR: StageModifierDef = preload("res://content/data/stages/modifiers/armored_patrols.tres")

var _ship: Ship = null
var _turret: PlayerTurret = null
var _checks: int = 0
var _failures: int = 0
var _base_forward: float = 0.0
var _base_reverse: float = 0.0
var _base_range: float = 0.0
var _base_regen: float = 0.0
var _base_nanobot_gain: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Sector Validation":
		push_error("Stage modifier checks require the isolated Fluxbreak Sector Validation project.")
		get_tree().quit(2)
		return
	get_tree().node_added.connect(_mute_test_audio)
	GameFlow._run_active = false
	GameFlow._clear_run_progression()
	GameFlow._meta_upgrade_levels.clear()
	_setup_ship()
	await _wait_frames(2)
	if not is_instance_valid(_turret):
		_finish()
		return
	_check_authored_resources()
	await _check_live_transitions()
	await _check_capacity_and_run_removal()
	_check_scopes_and_phase_semantics()
	await _check_restart_projection()
	GameFlow._run_active = false
	GameFlow._clear_run_progression()
	_ship.queue_free()
	await _wait_frames(3)
	_finish()

func _setup_ship() -> void:
	var definition: ShipDef = SHIP_DEF.duplicate(false) as ShipDef
	definition.max_hull = 500.0
	definition.max_shield = 250.0
	definition.shield_regen = 10.0
	definition.max_speed_forward = 100.0
	definition.max_speed_reverse = 40.0
	definition.nanobot_gain_mult = 1.0
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.ship_override = definition
	_ship.pilot_override = PilotDef.new()
	_ship.overheal = 0.0
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	var turrets: Array[Node] = _ship.find_children("*", "PlayerTurret", true, false)
	for node: Node in turrets:
		var turret: PlayerTurret = node as PlayerTurret
		if turret != null and turret.get_weapon() != null:
			_turret = turret
			break
	_check(_turret != null, "A shipped player loadout provides a real PlayerTurret")
	if _turret == null:
		return
	_ship.stat_aggregator.add_modifier(_modifier(Stat.WEAPON_BASE_RANGE, 1.1))
	_ship.stat_aggregator.add_modifier(_modifier(Stat.NANOBOT_GAIN_MULT, 1.2))
	_base_forward = _ship.eff_max_speed_forward
	_base_reverse = _ship.eff_max_speed_reverse
	_base_range = _turret.eff_base_range
	_base_regen = _ship.eff_shield_regen
	_base_nanobot_gain = _ship.eff_nanobot_gain_mult
	_check(is_equal_approx(_base_nanobot_gain, 1.2), "Permanent economy modifiers remain part of the player baseline")
	_check(_base_range > 0.0 and _base_regen > 0.0, "Live baseline exposes usable weapon range and shield regeneration")

func _check_authored_resources() -> void:
	_check_effect(TIDE, Stat.NANOBOT_GAIN_MULT, 1.25)
	_check_effect(CORRIDORS, Stat.MAX_SPEED_FORWARD, 1.15)
	_check_effect(CORRIDORS, Stat.MAX_SPEED_REVERSE, 1.15)
	_check_effect(STATIC, Stat.WEAPON_BASE_RANGE, 0.9)
	_check_effect(FLARE, Stat.SHIELD_REGEN, 0.85)
	_check(ARMOR.player_modifiers.is_empty() and ARMOR.enemy_modifiers.size() == 1, "Armored Patrols applies exclusively through enemy spawn modifiers")
	_check(ARMOR.enemy_modifiers[0].stat == Stat.MAX_HULL and is_equal_approx(ARMOR.enemy_modifiers[0].value, 1.15), "Armored Patrols authors exactly fifteen percent extra enemy hull")
	for modifier: StageModifierDef in [TIDE, CORRIDORS, STATIC, FLARE, ARMOR]:
		_check(not modifier.description.is_empty() and modifier.description.contains("%"), "Every shipped sector modifier states its actual numeric effect")
		_check(not modifier.description.contains("future") and not modifier.description.contains("candidate") and not modifier.description.contains("Intended hook"), "Sector descriptions contain no placeholder gameplay promises")

func _check_live_transitions() -> void:
	var salvage: StageDef = _stage(&"stat_salvage", [TIDE, STATIC])
	var assault: StageDef = _stage(&"stat_assault", [CORRIDORS, ARMOR])
	var flare: StageDef = _stage(&"stat_flare", [FLARE])
	var neutral: StageDef = _stage(&"stat_neutral", [])
	var run: RunDefinition = _run([salvage, assault, flare, neutral])
	_ship.hull = 125.0
	_ship.shield = 60.0
	_ship._nanobots = 1000
	GameFlow.start_new_run(run)
	RunState.add_score(500, "sector validation")
	RunState.record_weapon_purchase()
	RunState.record_upgrade_purchase("sector_test_permanent")
	var weapons_before: Array[WeaponDef] = _ship.hardpoint_manager.get_weapons().duplicate()
	var turret_id: int = _turret.get_instance_id()
	var persistent_mod_count: int = _ship.stat_aggregator.get_modifier_copies_for_context(StatAggregator.Context.PLAYER).size() - 2
	_check(is_equal_approx(_ship.eff_nanobot_gain_mult, _base_nanobot_gain * 1.25), "Salvage Tide changes the live Ship nanobot gain multiplier")
	_check(is_equal_approx(_turret.eff_base_range, _base_range * 0.9), "Sensor Static changes the actual PlayerTurret effective base range")
	_ship.collect_nanobots(100)
	_check(_ship.get_nanobots() == 1150, "The real pickup path awards 150 nanobots with permanent and sector multipliers")
	_check(is_equal_approx(_ship.eff_max_speed_forward, _base_forward), "Salvage modifiers cannot leak mobility effects")
	for repeat_index: int in range(4):
		GameFlow.stage_changed.emit(GameFlow.get_current_stage(), 0)
		_check(is_equal_approx(_ship.eff_nanobot_gain_mult, _base_nanobot_gain * 1.25) and is_equal_approx(_turret.eff_base_range, _base_range * 0.9), "Repeated stage notification cannot multiply sector bonuses again")
	_check(_ship.stat_aggregator.get_modifier_copies_for_context(StatAggregator.Context.PLAYER).size() == persistent_mod_count + 2, "Stage effects are projected once rather than appended as permanent upgrades")
	_check_enemy_hull(100.0)
	GameFlow._emit_stage_changed(1)
	_check(is_equal_approx(_ship.eff_max_speed_forward, _base_forward * 1.15), "Thruster Corridors changes actual forward top speed")
	_check(is_equal_approx(_ship.eff_max_speed_reverse, _base_reverse * 1.15), "Thruster Corridors changes actual reverse top speed")
	_check(is_equal_approx(_ship.eff_nanobot_gain_mult, _base_nanobot_gain), "Leaving Salvage Tide removes its economy multiplier")
	_check(is_equal_approx(_turret.eff_base_range, _base_range), "Leaving Sensor Static restores the existing upgraded weapon range")
	_check_enemy_hull(115.0)
	_check(_ship.hull == 125.0 and _ship.shield == 60.0, "Changing sector neither heals damaged hull nor refills shield")
	_check(_ship.get_nanobots() == 1150 and RunState.run_score == 500, "Changing sector preserves nanobots and score")
	_check(RunState.weapons_purchased == 1 and RunState.get_purchased_upgrade_ids() == ["sector_test_permanent"], "Changing sector preserves weapon prices and purchased upgrade memory")
	_check(_ship.hardpoint_manager.get_weapons() == weapons_before and _turret.get_instance_id() == turret_id, "Changing sector keeps the exact live loadout and turret instances")
	_ship.collect_nanobots(100)
	_check(_ship.get_nanobots() == 1270, "Pickup gain returns to the permanent multiplier after leaving Salvage Tide")
	GameFlow._emit_stage_changed(2)
	_check(is_equal_approx(_ship.eff_shield_regen, _base_regen * 0.85), "Solar Flare Front changes actual player shield regeneration")
	_ship._on_regen_tick()
	_check(is_equal_approx(_ship.shield, 60.0 + _base_regen * 0.85), "The real shield regeneration tick consumes the reduced sector stat")
	_ship.shield = 60.0
	_check(is_equal_approx(_ship.eff_max_speed_forward, _base_forward) and is_equal_approx(_ship.eff_max_speed_reverse, _base_reverse), "New sector removes the previous mobility bonuses")
	_check_enemy_hull(100.0)
	GameFlow._emit_stage_changed(3)
	_check(is_equal_approx(_ship.eff_shield_regen, _base_regen), "A neutral sector removes the previous regeneration penalty")
	_check(_ship.hull == 125.0 and _ship.shield == 60.0 and _ship.get_nanobots() == 1270, "All transitions retain damaged health and carried currency")
	_check(TIDE.player_modifiers[0].value == 1.25 and STATIC.player_modifiers[0].value == 0.9, "Projection leaves cached authoring resources unchanged")
	await _wait_frames(2)

func _check_capacity_and_run_removal() -> void:
	var capacity: StageModifierDef = StageModifierDef.new()
	capacity.modifier_id = &"test_capacity"
	capacity.player_modifiers = [_modifier(Stat.MAX_HULL, 2.0), _modifier(Stat.MAX_SHIELD, 1.5)]
	var boosted: StageDef = _stage(&"stat_capacity", [capacity, TIDE])
	var neutral: StageDef = _stage(&"stat_capacity_neutral", [])
	GameFlow.start_new_run(_run([boosted, neutral]))
	_check(_ship.eff_max_hull == 1000.0 and _ship.eff_max_shield == 375.0, "Temporary capacity changes project into real Ship limits")
	_check(_ship.hull == 125.0 and _ship.shield == 60.0, "Increasing sector capacities provides no free healing or shield refill")
	_ship.hull = 900.0
	_ship.shield = 340.0
	GameFlow._emit_stage_changed(1)
	_check(_ship.hull == 500.0 and _ship.shield == 250.0, "Removing a temporary capacity clamps only health above the restored limits")
	_ship.hull = 125.0
	_ship.shield = 60.0
	GameFlow._emit_stage_changed(0)
	GameFlow._run_active = false
	GameFlow._clear_run_progression()
	_check(is_equal_approx(_ship.stat_aggregator.compute_for_context(Stat.NANOBOT_GAIN_MULT, 1.0, StatAggregator.Context.PLAYER), _base_nanobot_gain), "Clearing progression immediately removes the live stage stat projection")
	await _wait_frames(2)
	_check(_ship.eff_max_hull == 500.0 and _ship.eff_max_shield == 250.0, "Run exit refreshes cached capacities even without a stage change signal")
	_check(is_equal_approx(_ship.eff_nanobot_gain_mult, _base_nanobot_gain), "Run exit refreshes the cached economy multiplier")
	_check(_ship.hull == 125.0 and _ship.shield == 60.0 and _ship.get_nanobots() == 1270, "Removing run projection cannot refill health or reset currency")

func _check_scopes_and_phase_semantics() -> void:
	var player_only: StatModifier = _modifier(Stat.WEAPON_DAMAGE_MIN, 1.5)
	var minion_only: StatModifier = _modifier(Stat.WEAPON_DAMAGE_MAX, 2.0)
	minion_only.applies_to_player = false
	minion_only.applies_to_minions = true
	var both: StatModifier = _modifier(Stat.WEAPON_BASE_RANGE, 0.9)
	both.applies_to_minions = true
	var scoped: StageModifierDef = StageModifierDef.new()
	scoped.modifier_id = &"test_scope"
	scoped.player_modifiers = [player_only, minion_only, both]
	var stage: StageDef = _stage(&"stat_scope", [scoped])
	GameFlow.start_new_run(_run([stage]))
	var active_scope: StageModifierDef = GameFlow.get_active_stage_modifiers()[0]
	_check(active_scope != scoped, "Live stat checks use the independent modifier snapshot cloned for the active run")
	var source: StatAggregator = _ship.stat_aggregator
	var minion: StatAggregator = StatAggregator.new()
	source.copy_modifiers_to(minion, StatAggregator.Context.MINION)
	_check(is_equal_approx(source.compute_for_context(Stat.WEAPON_DAMAGE_MIN, 10.0, StatAggregator.Context.PLAYER), 15.0), "Player-only sector scope applies to player damage")
	_check(is_equal_approx(minion.compute(Stat.WEAPON_DAMAGE_MIN, 10.0), 10.0), "Player-only sector effects are excluded from inherited drone stats")
	_check(is_equal_approx(source.compute_for_context(Stat.WEAPON_DAMAGE_MAX, 10.0, StatAggregator.Context.PLAYER), 10.0), "Minion-only stage effects cannot modify player damage")
	_check(is_equal_approx(minion.compute(Stat.WEAPON_DAMAGE_MAX, 10.0), 20.0), "Minion-only stage effects are included in inherited drone stats")
	_check(is_equal_approx(minion.compute(Stat.WEAPON_BASE_RANGE, 100.0), 90.0), "A copied minion projection applies the stage exactly once")
	source.copy_modifiers_to(minion, StatAggregator.Context.MINION)
	_check(is_equal_approx(minion.compute(Stat.WEAPON_BASE_RANGE, 100.0), 90.0), "Refreshing minion copies replaces the previous projection without stacking")
	minion.free()
	var phase_source: StatAggregator = StatAggregator.new()
	phase_source.set_stage_projection_enabled(true)
	var post_override: StatModifier = _modifier(Stat.WEAPON_BASE_RANGE, 400.0)
	post_override.op = Op.OVERRIDE
	post_override.phase = Phase.POST_OVERRIDE
	phase_source.add_modifier(post_override)
	_check(is_equal_approx(phase_source.compute_for_context(Stat.WEAPON_BASE_RANGE, 100.0, StatAggregator.Context.PLAYER), 400.0), "Stage multipliers participate before existing post overrides")
	var clamp_mod: StatModifier = _modifier(Stat.WEAPON_BASE_RANGE, 350.0)
	clamp_mod.op = Op.CLAMP_MAX
	clamp_mod.phase = Phase.FINAL_CLAMP
	active_scope.player_modifiers.append(clamp_mod)
	_check(is_equal_approx(phase_source.compute_for_context(Stat.WEAPON_BASE_RANGE, 100.0, StatAggregator.Context.PLAYER), 350.0), "Stage final clamps participate in normal phase precedence")
	var hard_set: StatModifier = _modifier(Stat.WEAPON_BASE_RANGE, 333.0)
	hard_set.op = Op.HARD_SET
	hard_set.phase = Phase.FINAL_CLAMP
	active_scope.player_modifiers.append(hard_set)
	_check(is_equal_approx(phase_source.compute_for_context(Stat.WEAPON_BASE_RANGE, 100.0, StatAggregator.Context.PLAYER), 333.0), "Stage hard-set precedence matches the established stat evaluator")
	phase_source.set_stage_projection_enabled(false)
	_check(is_equal_approx(phase_source.compute(Stat.WEAPON_BASE_RANGE, 100.0), 400.0), "Disabling projection preserves permanent modifiers and removes the stage")
	phase_source.free()

func _check_restart_projection() -> void:
	var stage: StageDef = _stage(&"stat_restart", [TIDE, STATIC])
	var run: RunDefinition = _run([stage])
	for restart_index: int in range(5):
		GameFlow.start_new_run(run)
		_check(is_equal_approx(_ship.eff_nanobot_gain_mult, _base_nanobot_gain * 1.25), "Restart projects one fresh Salvage Tide without accumulation")
		_check(is_equal_approx(_turret.eff_base_range, _base_range * 0.9), "Restart projects one Sensor Static penalty without accumulation")
	GameFlow._run_active = false
	GameFlow._clear_run_progression()
	get_tree().paused = true
	await _wait_frames(2)
	_check(is_equal_approx(_ship.eff_nanobot_gain_mult, _base_nanobot_gain) and is_equal_approx(_turret.eff_base_range, _base_range), "Paused menu cleanup removes cached player and weapon stage effects")
	get_tree().paused = false

func _check_enemy_hull(expected: float) -> void:
	var enemy: EnemyDef = EnemyDef.new()
	enemy.max_hull = 100.0
	var snapshot: EnemyStatSnapshot = EnemyStatResolver.resolve(enemy, EnemySpawnContext.from_enemy_def(enemy))
	_check(is_equal_approx(snapshot.max_hull, expected), "Actual enemy stat resolution follows current sector hull modifiers")

func _check_effect(definition: StageModifierDef, stat_id: int, expected: float) -> void:
	var found: bool = false
	for modifier: StatModifier in definition.player_modifiers:
		if modifier.stat == stat_id:
			found = modifier.enabled and modifier.op == Op.MULT and is_equal_approx(modifier.value, expected) and modifier.applies_to_player and not modifier.applies_to_minions
	_check(found, "Shipped %s authors the intended live player stat multiplier" % definition.display_name)

func _modifier(stat_id: int, value: float) -> StatModifier:
	var modifier: StatModifier = StatModifier.new()
	modifier.stat = stat_id as Stat
	modifier.op = Op.MULT
	modifier.value = value
	modifier.source_id = "stage_check_permanent"
	return modifier

func _stage(id: StringName, modifiers: Array[StageModifierDef]) -> StageDef:
	var stage: StageDef = StageDef.new()
	stage.stage_id = id
	stage.guaranteed_modifiers = modifiers
	return stage

func _run(stages: Array[StageDef]) -> RunDefinition:
	var run: RunDefinition = RunDefinition.new()
	run.run_id = &"stage_modifier_validation"
	run.run_mode = RunDefinition.RunMode.PRACTICE
	run.stages = stages
	return run

func _mute_test_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _wait_frames(count: int) -> void:
	for index: int in range(count):
		await get_tree().process_frame

func _finish() -> void:
	print("STAGE_MODIFIER_CHECKS: %s; %d checks, %d failures" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error(description)
