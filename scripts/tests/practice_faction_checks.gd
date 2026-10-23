extends Node

# Use the isolated project created by run_practice_faction_checks.ps1. These
# checks intentionally complete real encounters, which must never alter a save.
const SHORT_BUTTON: NodePath = ^"CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/MercPracticeContainer/MercPractice"
const FULL_BUTTON: NodePath = ^"CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/PracticeContainer/Practice"
const FACTION_PICKER: NodePath = ^"CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/FactionContainer/Row/FactionPicker"
var _failures: Array[String] = []
var _checks: int = 0
var _ship: Ship = null
var _completed_count: int = 0
var _world_scene: PackedScene = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _process(_delta: float) -> void:
	# Run routing is tested independently of balance and automatic aim.
	if is_instance_valid(_ship):
		_ship.hull = _ship.eff_max_hull
		_ship.shield = _ship.eff_max_shield

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name")) != "Fluxbreak Practice Validation":
		push_error("Run practice faction checks in the isolated Fluxbreak Practice Validation project.")
		get_tree().quit(2)
		return
	get_tree().node_added.connect(_mute_test_audio)
	GameFlow.run_completed.connect(_on_run_completed)
	_world_scene = load("res://scenes/world/world.tscn") as PackedScene
	_check_factory_runs()
	for faction_def: PracticeFactionDef in PracticeRunFactory.get_factions():
		await _check_selected_faction(faction_def, true)
		await _check_selected_faction(faction_def, false)
	await _check_random_menu_launches()
	GameFlow._run_active = false
	GameFlow._clear_run_progression()
	get_tree().paused = false
	print("PRACTICE FACTION CHECKS: %s; %d assertions; four factions, short encounters, gateways, finales, and random launches" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	call_deferred("_finish_checks")

func _check_factory_runs() -> void:
	var factions: Array[PracticeFactionDef] = PracticeRunFactory.get_factions()
	_check(factions.size() == 4, "Exactly four available practice factions must be registered.")
	var known_ids: Dictionary = {}
	for faction_def: PracticeFactionDef in factions:
		_check(faction_def != null and faction_def.faction != null, "Every practice option needs a faction identity.")
		if faction_def == null or faction_def.faction == null:
			continue
		var faction_id: StringName = faction_def.faction.get_faction_id()
		_check(not known_ids.has(faction_id), "Practice registry contains a duplicate faction.")
		known_ids[faction_id] = true
		var seed_stage: StageDef = faction_def.short_run.get_stage(0)
		var lesson_tiers: PackedInt32Array = seed_stage.authored_tier_caps
		_check(lesson_tiers.size() == (3 if faction_id == &"machines" else 5), "Practice must teach each available faction archetype.")
		_check(faction_def.wave_cards.size() == lesson_tiers.size() * 2, "%s must expose two wave cards per lesson tier." % faction_id)
		var tier_counts: Dictionary = {}
		for card: WaveCard in faction_def.wave_cards:
			_check(card != null and card.get_faction_bias_id() == faction_id, "Registry deck mixes factions.")
			if card != null:
				tier_counts[card.min_enemy_tier] = int(tier_counts.get(card.min_enemy_tier, 0)) + 1
		for tier: int in lesson_tiers:
			_check(int(tier_counts.get(tier, 0)) == 2, "%s needs two cards for tier %d." % [faction_id, tier])
		var original_seed_id: StringName = seed_stage.stage_id
		var original_seed_cards: Array[WaveCard] = seed_stage.wave_cards.duplicate()
		var original_seed_hint: String = seed_stage.combat_hint
		var seen_cards: Dictionary = {}
		var seen_bosses: Dictionary = {}
		for seed_index in range(32):
			var seeded_rng: RandomNumberGenerator = RandomNumberGenerator.new()
			seeded_rng.seed = seed_index + 71
			var short_run: RunDefinition = PracticeRunFactory.create_run(faction_id, true, seeded_rng)
			_check(short_run != null and short_run != faction_def.short_run, "Factory must return a fresh short run.")
			if short_run == null:
				continue
			_check(short_run.enemy_faction == faction_def.faction, "Short run lost its selected faction.")
			_check(short_run.get_stage_count() == 1, "Short practice must have exactly one stage.")
			var short_stage: StageDef = short_run.get_stage(0)
			_check(short_stage != seed_stage, "Short practice must clone the cached stage.")
			_check(short_stage.ordered_wave_cards and short_stage.wave_cards.size() == lesson_tiers.size(), "Practice must resolve its authored lessons at launch.")
			_check(short_stage.boss_wave_index == lesson_tiers.size() + 1 and short_stage.should_end_run_on_boss_defeat(), "Practice must end with a boss after its lessons.")
			_check(short_stage.authored_tier_caps == lesson_tiers, "Practice must retain its faction's introductory tier caps.")
			_check(is_equal_approx(short_stage.wave_timeout_override_sec, 22.0) and is_equal_approx(short_stage.downtime_override_sec, 5.0), "Short practice must retain 22/5 pacing.")
			for card_index in short_stage.wave_cards.size():
				var drawn_card: WaveCard = short_stage.wave_cards[card_index]
				_check(drawn_card.min_enemy_tier == lesson_tiers[card_index], "A short lesson skips its enemy tier.")
				_check(drawn_card.get_faction_bias_id() == faction_id, "A short lesson switches faction.")
				if seed_index == 0:
					_check(is_zero_approx(drawn_card.in_wave_target_budget_scale) and drawn_card.downtime_target_point_budget == 0, "Short lessons must retain their brief, salvage-free pacing.")
					_check(not short_stage.pressure_reinforcements_enabled and not drawn_card.allow_pressure_spikes and drawn_card.pressure_enemy_point_budget == 0 and drawn_card.pressure_target_point_budget == 0, "Short lessons must suppress pressure reinforcements.")
				seen_cards[drawn_card.get_card_id()] = true
			_check_stage_bosses(short_stage, faction_id)
			_check(short_stage.get_boss_pool().size() == 1, "Practice must lock one boss when the run is created.")
			seen_bosses[short_stage.get_boss_pool()[0].id] = true
			# Mutating this run must not change its seed or subsequent factory runs.
			short_stage.combat_hint = "isolated runtime hint"
			short_stage.wave_cards.clear()
		_check(seen_cards.size() == faction_def.wave_cards.size(), "Seeded encounters did not cover every lesson variant.")
		_check(seen_bosses.size() == seed_stage.get_boss_pool().size(), "Seeded encounters did not cover the faction's Practice boss pool.")
		_check(seed_stage.stage_id == original_seed_id and seed_stage.wave_cards == original_seed_cards and seed_stage.combat_hint == original_seed_hint, "Factory mutated a cached short-stage resource.")
		var main_run: RunDefinition = PracticeRunFactory.create_run(faction_id, false)
		_check(main_run != null and main_run.get_stage_count() == 2, "Main Practice must retain two stages.")
		if main_run == null or main_run.get_stage_count() != 2:
			continue
		_check(main_run.enemy_faction == faction_def.faction, "Main Practice lost its selected faction.")
		var first_stage: StageDef = main_run.get_stage(0)
		var final_stage: StageDef = main_run.get_stage(1)
		if faction_id == &"mercs":
			_check(first_stage.get_boss_pool().size() == 1 and first_stage.get_boss_pool()[0].id == "merc_contract_enforcer_mk1", "Merc Campaign must use Contract Enforcer at its gateway.")
			_check(final_stage.get_boss_pool().size() == 1 and final_stage.get_boss_pool()[0].id == "merc_vanguard_flagship_mk1", "Merc Campaign must finish with Vanguard Flagship.")
		if faction_id == &"bugs":
			_check(first_stage.get_boss_pool().size() == 1 and first_stage.get_boss_pool()[0].id == "bug_nestbreaker_matron_mk1", "Bug Campaign must use Nestbreaker Matron at its gateway.")
			_check(final_stage.get_boss_pool().size() == 1 and final_stage.get_boss_pool()[0].id == "bug_first_queen_mk1", "Bug Campaign must finish with The First Queen.")
		if faction_id == &"greys":
			_check(first_stage.get_boss_pool().size() == 1 and first_stage.get_boss_pool()[0].id == "grey_witness_mk1", "Grey Campaign must use The Witness at its gateway.")
			_check(final_stage.get_boss_pool().size() == 1 and final_stage.get_boss_pool()[0].id == "grey_veiled_mind_mk1", "Grey Campaign must finish with The Veiled Mind.")
		_check(first_stage.should_open_gateway_on_boss_defeat() and first_stage.next_stage_id == final_stage.get_stage_id(), "Main Practice must connect its first boss gateway to the selected final stage.")
		_check(final_stage.should_end_run_on_boss_defeat(), "Main Practice must finish after its final boss.")
		for stage: StageDef in main_run.get_stages():
			_check(not stage.ordered_wave_cards and stage.get_wave_cards().size() == faction_def.wave_cards.size(), "Campaign must use the full faction deck.")
			_check(stage.boss_wave_index == 30, "Main Practice must retain its 30-wave stage length.")
			_check(stage.wave_timeout_override_sec <= 0.0 and stage.downtime_override_sec < 0.0, "Main Practice must retain normal wave pacing.")
			_check(stage.pressure_reinforcements_enabled, "Main Practice must retain regular pressure reinforcements.")
			_check(stage.authored_tier_caps.size() == stage.boss_wave_index - 1, "Main Practice must cap every regular wave in both stages.")
			for tier_cap in stage.authored_tier_caps:
				_check(tier_cap <= faction_def.max_enemy_tier, "A main stage requests an unimplemented faction tier.")
			_check_stage_bosses(stage, faction_id)
			for card: WaveCard in stage.get_wave_cards():
				_check(card.get_faction_bias_id() == faction_id, "Main Practice stage deck switches faction.")
				_check(card.in_wave_target_budget_scale > 0.0 and card.downtime_target_point_budget > 0, "Main Practice must retain in-wave and downtime salvage budgets.")
				_check(card.pressure_enemy_point_budget > 0, "Main Practice must retain its normal pressure enemy budget.")
		for source_card: WaveCard in faction_def.wave_cards:
			_check(is_zero_approx(source_card.in_wave_target_budget_scale) and source_card.downtime_target_point_budget == 0 and source_card.pressure_enemy_point_budget == 0, "Main economy tuning mutated a cached short-lesson card.")
	var random_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	random_rng.seed = 47119
	var random_counts: Dictionary = {}
	for roll_index in range(128):
		var rolled_run: RunDefinition = PracticeRunFactory.create_run(&"random", roll_index % 2 == 0, random_rng)
		_check(rolled_run != null and rolled_run.enemy_faction != null, "Random Practice must resolve a faction before starting.")
		if rolled_run != null and rolled_run.enemy_faction != null:
			var resolved_id: StringName = rolled_run.enemy_faction.get_faction_id()
			_check(known_ids.has(resolved_id), "Random Practice chose a faction without a playable roster.")
			random_counts[resolved_id] = int(random_counts.get(resolved_id, 0)) + 1
			for stage: StageDef in rolled_run.get_stages():
				_check(stage.boss_faction.get_faction_id() == resolved_id, "Random run re-rolled its faction between stages.")
	_check(random_counts.size() == 4, "Seeded random runs must cover all four supported factions.")
	var original_story: RunDefinition = load("res://content/data/runs/story_mode_intro.tres") as RunDefinition
	_check(original_story.get_stage(0).get_stage_id() == &"perimeter_breach" and original_story.get_stage(1).get_stage_id() == &"reactor_graveyard", "Practice factory must preserve the original story stage identities.")

func _check_stage_bosses(stage: StageDef, faction_id: StringName) -> void:
	_check(stage.boss_faction != null and stage.boss_faction.get_faction_id() == faction_id, "Stage boss faction differs from the run faction.")
	_check(not stage.get_boss_pool().is_empty(), "Every practice stage needs an affordable playable boss pool.")
	for boss_def: EnemyBossDef in stage.get_boss_pool():
		_check(boss_def.get_faction_id() == faction_id, "A boss pool contains another faction.")

func _create_world() -> Node3D:
	var world: Node3D = _world_scene.instantiate() as Node3D
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	_ship = world.get_node("Ship") as Ship
	return world

func _check_selected_faction(faction_def: PracticeFactionDef, short_practice: bool) -> void:
	var initial_failure_count: int = _failures.size()
	var faction_id: StringName = faction_def.faction.get_faction_id()
	var world: Node3D = _create_world()
	await get_tree().process_frame
	var menu: Control = world.get_node("MainMenuOverlay") as Control
	menu.call("set_practice_faction_id", &"unavailable_faction")
	_check(menu.call("get_practice_faction_id") == &"random", "An unavailable faction must recover to the playable Random option.")
	var picker: OptionButton = menu.get_node(FACTION_PICKER) as OptionButton
	_check(picker.item_count == 5, "The faction picker must expose Random and all four playable factions.")
	var selected_index: int = -1
	for item_index in picker.item_count:
		if StringName(picker.get_item_metadata(item_index)) == faction_id:
			selected_index = item_index
	_check(selected_index >= 0, "The actual picker omits %s." % faction_id)
	if selected_index >= 0:
		picker.select(selected_index)
		picker.item_selected.emit(selected_index)
	_check(menu.call("get_practice_faction_id") == faction_id, "Practice selector failed to select %s." % faction_id)
	var button: Button = menu.get_node(SHORT_BUTTON if short_practice else FULL_BUTTON) as Button
	_check(not button.disabled, "Selected practice run must launch with the default unlocked loadout.")
	_completed_count = 0
	button.pressed.emit()
	var active_run: RunDefinition = GameFlow.get_active_run_definition()
	_check(active_run != null and active_run.enemy_faction == faction_def.faction, "Actual menu button routed to the wrong faction.")
	_check(GameFlow.get_run_faction() == faction_def.faction, "GameFlow failed to preserve the resolved faction.")
	_check(active_run.get_stage_count() == (1 if short_practice else 2), "Actual menu button routed to the wrong run length.")
	var director: WaveDirector = world.get_node("StageRoot/WaveDirector") as WaveDirector
	var buyer: BudgetBuyer = world.get_node("StageRoot/BudgetBuyer") as BudgetBuyer
	var catalog: EnemyCatalog = world.get_node("StageRoot/EnemyCatalog") as EnemyCatalog
	_check_deck_budgets(faction_def, buyer, catalog)
	if not short_practice:
		_check_card_selection(director)
		_check_authored_deck_selection(director, faction_def)
	for stage_index in active_run.get_stage_count():
		var stage: StageDef = GameFlow.get_current_stage()
		_check(stage == active_run.get_stage(stage_index), "Gateway selected a stage outside the active cloned run.")
		_check(GameFlow.get_run_faction() == faction_def.faction, "Stage transition re-rolled the run faction.")
		# Use the actual request/boss machinery while skipping long combat timers.
		director._next_wave()
		await _wait_frames(35)
		_check(director._active_card != null and director._active_card.get_faction_bias_id() == faction_id, "Live wave selected a card outside the run faction.")
		_check_live_enemies(faction_id)
		director._wave_index = stage.boss_wave_index - 1
		director._next_wave()
		await _wait_frames(3)
		_check(director.is_boss_wave_active(), "Practice failed to create its selected faction boss.")
		var boss: Enemy = director._active_boss_instance
		if boss == null:
			continue
		_check(boss.def.get_faction_id() == faction_id, "Live boss differs from the selected run faction.")
		boss.explosion_scene = null
		boss.apply_damage(boss.hull + boss.shield + 1000.0)
		await _wait_frames(3)
		if stage_index < active_run.get_stage_count() - 1:
			_check(director.is_gateway_hold_active() and _completed_count == 0, "The first main boss must open a gateway without completing the run.")
			var gateway_manager: BossGatewayManager = world.get_node("StageRoot/BossGatewayManager") as BossGatewayManager
			var gateway: BossGateway = gateway_manager.get_active_gateway()
			_check(gateway != null, "Main Practice failed to spawn its actual docking gateway.")
			if gateway != null:
				_ship.global_position = gateway.global_position
				gateway_manager._process(gateway.get_docking_time() + 1.0)
				_check(GameFlow.get_active_stage_index() == stage_index and gateway_manager.is_briefing_open(), "A gateway must show its briefing instead of advancing on elapsed docking time.")
				_check(gateway_manager.get_active_gateways().size() == 2, "Campaign must offer both sector routes after its first boss.")
				_check(gateway_manager.confirm_gateway(), "Explicit gateway confirmation must accept the offered sector.")
				await _wait_frames(3)
			_check(GameFlow.get_active_stage_index() == stage_index + 1, "Confirmed sector did not advance to the next Campaign stage.")
			_check(director.get_wave_index() == 0, "Gateway did not reset the local wave index.")
			_check_no_stale_abilities()
		else:
			_check(_completed_count == 1, "Final boss defeat must complete its selected run exactly once.")
			_check_no_stale_abilities()
	# Let the real victory timer return to the menu, then verify the next menu
	# can build an independent run without retaining the completed stage.
	# Poll the real victory transition. A second SceneTreeTimer awaiting the
	# same transition adds an unrelated timer to repeated scene teardown.
	var return_frame_limit: int = int(ceil((GameFlow.VICTORY_RETURN_DELAY_SEC + 1.0) * 60.0))
	for frame_index in range(return_frame_limit):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene != world:
			break
	await _wait_frames(3)
	var returned_world: Node3D = get_tree().current_scene as Node3D
	_check(returned_world != null and returned_world != world, "Victory did not return to a fresh practice menu.")
	if returned_world != null:
		var returned_menu: Control = returned_world.get_node("MainMenuOverlay") as Control
		_check(returned_menu.call("get_practice_faction_id") == faction_id, "Victory lost the player's explicit practice faction selection.")
		var restart_run: RunDefinition = returned_menu.call("build_practice_run", short_practice) as RunDefinition
		_check(restart_run != null and restart_run != active_run and restart_run.enemy_faction == faction_def.faction, "Returned menu failed to build a fresh run for the selected faction.")
		await _dispose_world(returned_world)
	print("PRACTICE ROUTE: %s %s %s" % [String(faction_id), "short" if short_practice else "main", "PASS" if _failures.size() == initial_failure_count else "FAIL"])

func _check_deck_budgets(faction_def: PracticeFactionDef, buyer: BudgetBuyer, catalog: EnemyCatalog) -> void:
	var faction_id: StringName = faction_def.faction.get_faction_id()
	for card: WaveCard in faction_def.wave_cards:
		var lesson_tier: int = card.min_enemy_tier
		var lesson_stage: StageDef = faction_def.short_run.get_stage(0)
		var lesson_index: int = lesson_stage.authored_tier_caps.find(lesson_tier)
		var budget: int = lesson_stage.authored_enemy_budgets[lesson_index]
		var primaries: Array[EnemyDef] = catalog.get_pool(faction_def.faction, card.primary_role_bias, lesson_tier)
		_check(not catalog.get_affordable_pool(primaries, budget).is_empty(), "A wave card cannot afford its named primary at its introductory budget.")
		for sample_index in range(12):
			buyer.clear_history()
			var requests: Array[SpawnRequest] = buyer.buy_wave(budget, 0, card, lesson_tier)
			var cost: int = 0
			var primary_found: bool = false
			for request: SpawnRequest in requests:
				if request.enemy_def == null:
					continue
				var enemy_def: EnemyDef = request.enemy_def
				_check(enemy_def.get_faction_id() == faction_id and not enemy_def is EnemyBossDef, "A regular card bought a boss or another faction.")
				_check(enemy_def.tier <= lesson_tier, "A card bought an enemy above its allowed tier.")
				cost += enemy_def.threat_cost * request.count
				if request.package_label == "primary" and enemy_def.role != null and card.primary_role_bias != null and enemy_def.get_role_id() == card.primary_role_bias.get_role_id():
					primary_found = true
			_check(primary_found, "A wave omitted its affordable named primary role.")
			if card.min_primary_enemy_tier > 1:
				var anchor_id: String = str(buyer.get_last_wave_plan().get("primary_enemy_id", ""))
				var valid_anchor: bool = false
				for candidate: EnemyDef in primaries:
					if candidate.id == anchor_id and candidate.tier >= card.min_primary_enemy_tier:
						valid_anchor = true
				_check(valid_anchor, "A higher-tier card replaced its affordable teaching anchor with an earlier hull.")
			_check(cost > 0 and cost <= budget, "A deck purchase exceeded the authored wave budget or bought no enemies.")
		if card.primary_count_max > 0:
			for sample_index: int in range(20):
				buyer.clear_history()
				var requests: Array[SpawnRequest] = buyer.buy_wave(100, 0, card, faction_def.max_enemy_tier)
				var anchor_count: int = 0
				var primary_count: int = 0
				var cost: int = 0
				var anchor_id: String = str(buyer.get_last_wave_plan().get("primary_enemy_id", ""))
				for request: SpawnRequest in requests:
					if request.enemy_def != null:
						cost += request.count * request.enemy_def.threat_cost
						if request.enemy_def.id == anchor_id:
							anchor_count += request.count
						if request.package_label == "primary":
							primary_count += request.count
				_check(anchor_count > 0 and anchor_count <= card.primary_count_max and primary_count <= card.primary_count_max, "A late Campaign package violated its primary anchor cap.")
				_check(cost <= 100, "A large-budget capital package exceeded its allocation.")
		if card.min_primary_enemy_tier > 1:
			buyer.clear_history()
			_check(not buyer.buy_wave(3, 0, card, lesson_tier).is_empty(), "A temporarily unaffordable capital card produced an empty adaptive wave.")

func _check_card_selection(director: WaveDirector) -> void:
	var stage: StageDef = GameFlow.get_current_stage()
	var original_cards: Array[WaveCard] = stage.wave_cards.duplicate()
	var early_card: WaveCard = original_cards[0].duplicate() as WaveCard
	var late_card: WaveCard = original_cards[original_cards.size() - 1].duplicate() as WaveCard
	early_card.card_id = "validation_early"
	early_card.min_enemy_tier = 1
	early_card.weight = 0.05
	early_card.card_repeat_cooldown = 0
	late_card.card_id = "validation_late"
	late_card.min_enemy_tier = 3
	late_card.weight = 10.0
	late_card.card_repeat_cooldown = 1
	stage.wave_cards.assign([early_card, late_card])
	director._rng.seed = 519
	director._wave_index = 0
	director._state = RunState.State.DOWNTIME
	director._recent_card_ids.clear()
	for sample_index in range(24):
		_check(director._choose_card() == early_card, "A weighted card bypassed its tier gate during the first downtime.")
	director._wave_index = 20
	var late_picks: int = 0
	for sample_index in range(200):
		if director._choose_card() == late_card:
			late_picks += 1
	_check(late_picks > 180, "Director did not honor authored card weights after unlocking all tiers.")
	director._remember_card(late_card)
	_check(director._choose_card() == early_card, "Director ignored the last card's repeat cooldown.")
	for wave_index in range(1, stage.boss_wave_index):
		director._wave_index = wave_index
		_check(director._get_max_enemy_tier() <= 5, "Campaign can request unimplemented enemy tiers.")
	stage.wave_cards.assign(original_cards)
	director._wave_index = 0
	director._pending_card = null
	director._recent_card_ids.clear()

func _check_live_enemies(faction_id: StringName) -> void:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("targets"):
		var enemy: Enemy = node as Enemy
		if enemy != null:
			count += 1
			_check(enemy.def != null and enemy.def.get_faction_id() == faction_id, "A live wave spawned another faction.")
	_check(count > 0, "Actual opening wave failed to spawn enemies.")

func _check_authored_deck_selection(director: WaveDirector, faction_def: PracticeFactionDef) -> void:
	var stage: StageDef = GameFlow.get_current_stage()
	var seen_cards: Dictionary = {}
	director._rng.seed = 74192
	director._state = RunState.State.DOWNTIME
	for incoming_wave: int in range(1, stage.boss_wave_index):
		director._wave_index = incoming_wave - 1
		for sample_index: int in range(8):
			var card: WaveCard = director._choose_card()
			_check(card != null and card.get_faction_bias_id() == faction_def.faction.get_faction_id(), "The live Campaign deck selected another faction.")
			_check(card.min_enemy_tier <= stage.authored_tier_caps[incoming_wave - 1], "A Campaign composition bypassed its tier unlock.")
			seen_cards[card.get_card_id()] = true
			director._remember_card(card)
	_check(seen_cards.size() == faction_def.wave_cards.size(), "A seeded Campaign selection never reached an authored card.")
	director._wave_index = 0
	director._recent_card_ids.clear()
	director._pending_card = null

func _check_no_stale_abilities() -> void:
	for group_name: String in ["bug_brood", "bug_spore_zones", "grey_tethers", "grey_displacements", "enemy_attack_telegraphs", "merc_escorts"]:
		_check(get_tree().get_nodes_in_group(group_name).is_empty(), "Stage handoff left stale %s." % group_name)
	_check(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Stage handoff left a faction status on the player.")

func _check_random_menu_launches() -> void:
	var world: Node3D = _create_world()
	await get_tree().process_frame
	var menu: Control = world.get_node("MainMenuOverlay") as Control
	menu.call("set_practice_faction_id", &"random")
	_check(menu.call("get_practice_faction_id") == &"random", "Practice selector must offer Random.")
	var observed: Dictionary = {}
	for sample_index in range(64):
		var run: RunDefinition = menu.call("build_practice_run", sample_index % 2 == 0) as RunDefinition
		_check(run != null and run.enemy_faction != null, "Random menu selection did not create a playable run.")
		if run != null and run.enemy_faction != null:
			observed[run.enemy_faction.get_faction_id()] = true
	_check(observed.size() == 4, "Random menu launches reused a cached faction roll.")
	await _dispose_world(world)

func _dispose_world(world: Node) -> void:
	GameFlow._run_active = false
	GameFlow._clear_run_progression()
	_ship = null
	get_tree().paused = false
	world.queue_free()
	await _wait_frames(3)

func _wait_frames(count: int) -> void:
	for frame_index in range(count):
		await get_tree().process_frame

func _on_run_completed() -> void:
	_completed_count += 1

func _mute_test_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _finish_checks() -> void:
	get_tree().quit(0 if _failures.is_empty() else 1)
