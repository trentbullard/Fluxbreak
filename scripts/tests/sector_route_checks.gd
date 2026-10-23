extends Node

## Configuration and progression checks run without spawning live encounters.
var _checks: int = 0
var _failures: int = 0
var _stage_changes: int = 0
var _run_completions: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name")) != "Fluxbreak Sector Validation":
		push_error("Sector checks require the isolated Fluxbreak Sector Validation project.")
		get_tree().quit(2)
		return
	GameFlow.stage_changed.connect(_on_stage_changed)
	GameFlow.run_completed.connect(_on_run_completed)
	_check_route_helpers()
	for faction: PracticeFactionDef in PracticeRunFactory.get_factions():
		_check_factory(faction)
		for route_index: int in range(2):
			_check_progression(faction.faction.get_faction_id(), route_index)
	_check_linear_compatibility()
	_check_invalid_route_declaration()
	_check_invalid_offered_faction()
	GameFlow.abandon_run()
	get_tree().paused = false
	print("SECTOR ROUTE CHECKS: %s; %d checks, %d failures; four factions, route isolation, previews, and explicit progression" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _check_route_helpers() -> void:
	var route: SectorRouteDef = SectorRouteDef.new()
	_check(route.get_destination_id() == &"", "A route without a destination has no target ID.")
	var destination: StageDef = StageDef.new()
	destination.stage_id = &"helper_destination"
	route.destination_stage = destination
	route.display_name = ""
	_check(route.get_route_id() == destination.stage_id and route.get_display_name() == "Helper Destination", "Unnamed route helpers fall back to their destination.")
	var source: StageDef = StageDef.new()
	source.stage_id = &"helper_source"
	source.gateway_routes = [null, route, route]
	var duplicate: SectorRouteDef = route.duplicate(false) as SectorRouteDef
	duplicate.route_id = &"duplicate_destination"
	source.gateway_routes.append(duplicate)
	_check(source.get_gateway_routes().size() == 1, "Gateway routes filter nulls and repeated destinations.")
	var self_route: SectorRouteDef = SectorRouteDef.new()
	self_route.destination_stage = source
	source.gateway_routes.append(self_route)
	_check(source.get_gateway_routes().size() == 1, "A gateway cannot offer its own current stage.")
	self_route.destination_stage = null
	source.gateway_routes.clear()
	_check(GameFlow.get_stage_modifiers_for(null).is_empty(), "Null briefings have no conditions.")

func _check_factory(faction: PracticeFactionDef) -> void:
	var faction_id: StringName = faction.faction.get_faction_id()
	var original_weights: Array[float] = []
	var original_target_scales: Array[float] = []
	for card: WaveCard in faction.wave_cards:
		original_weights.append(card.weight)
		original_target_scales.append(card.in_wave_target_budget_scale)
	var run: RunDefinition = PracticeRunFactory.create_run(faction_id, false)
	_check(run != null and run.get_stage_count() == 2, "%s Campaign retains exactly two played stages." % faction_id)
	if run == null or run.get_stage_count() != 2:
		return
	var gateway: StageDef = run.get_stage(0)
	var fallback: StageDef = run.get_stage(1)
	var routes: Array[SectorRouteDef] = gateway.get_gateway_routes()
	_check(routes.size() == 2, "%s offers two distinct sector choices." % faction_id)
	_check(fallback.gateway_routes.is_empty(), "The fallback finale remains a terminal stage.")
	var highest_tier: int = 1
	for card: WaveCard in fallback.wave_cards:
		highest_tier = maxi(highest_tier, card.min_enemy_tier)
	for route: SectorRouteDef in routes:
		var salvage: bool = route.marker_kind == SectorRouteDef.MarkerKind.SALVAGE
		var stage: StageDef = route.destination_stage
		_check(stage != fallback and stage != gateway, "Each offered sector owns its stage definition.")
		_check(stage.get_stage_id() != fallback.get_stage_id(), "Each offered sector has a unique progression identity.")
		_check(stage.should_end_run_on_boss_defeat() and stage.gateway_routes.is_empty() and stage.next_stage_id == &"", "Each chosen sector ends at the Campaign finale.")
		_check(stage.boss_faction.get_faction_id() == faction_id, "Sector bosses retain the selected faction.")
		_check(_boss_ids(stage) == _boss_ids(fallback), "Both routes retain the intended faction finale boss.")
		_check(stage.authored_tier_caps == fallback.authored_tier_caps and stage.boss_wave_index == fallback.boss_wave_index, "Route choice retains Campaign length and tier progression.")
		_check(stage.bonus_pool.is_empty() and stage.debuff_pool.is_empty() and stage.random_bonus_count == 0 and stage.random_debuff_count == 0, "Previewed sector conditions contain no undisclosed random rolls.")
		var expected_modifiers: PackedStringArray = PackedStringArray(["salvage_tide", "sensor_static"])
		if not salvage:
			expected_modifiers = PackedStringArray(["thruster_corridors", "armored_patrols"])
		_check(_modifier_ids(stage.guaranteed_modifiers) == expected_modifiers, "Each route exposes its authored condition pair.")
		_check(not route.threat_summary.is_empty() and not route.reward_summary.is_empty(), "Both drawbacks and rewards are disclosed.")
		_check(stage.wave_cards.size() == fallback.wave_cards.size(), "Each sector retains the entire faction wave deck.")
		for index: int in range(stage.wave_cards.size()):
			var card: WaveCard = stage.wave_cards[index]
			var original: WaveCard = fallback.wave_cards[index]
			_check(card != original and card.get_faction_bias_id() == faction_id, "Sector tuning owns its card and never mixes factions.")
			_check(card.get_card_id() == original.get_card_id() and card.min_enemy_tier == original.min_enemy_tier and card.min_primary_enemy_tier == original.min_primary_enemy_tier and card.primary_count_max == original.primary_count_max, "Sector cards preserve enemy eligibility and capital limits.")
			if salvage:
				_check(card.in_wave_target_budget_scale > original.in_wave_target_budget_scale and card.downtime_target_point_budget == original.downtime_target_point_budget + 2 and card.target_size_band_max >= 2, "Salvage route adds real wreck and target opportunities.")
				if card.min_enemy_tier <= 2:
					_check(card.inter_batch_sec < original.inter_batch_sec, "Salvage escorts arrive in tighter batches.")
			else:
				var heavy: bool = original.min_enemy_tier >= 4 or (highest_tier < 4 and original.min_enemy_tier == highest_tier)
				_check(card.weight > original.weight if heavy else card.weight < original.weight, "Assault weights favor existing heavy formations.")
				if faction_id == &"machines":
					_check(card.min_enemy_tier <= 3, "Machine routes do not invent tier4 or tier5 cards.")
		var poi_weights: Dictionary = {}
		for poi: PoiDef in stage.poi_defs:
			poi_weights[poi.poi_type] = poi.spawn_weight
			_check(poi.scene_override != null and not poi.upgrade_tags.is_empty(), "Sector stations retain real scenes and upgrade categories.")
		_check(poi_weights.size() == 3, "Every sector leaves all three shop categories available.")
		if poi_weights.size() == 3:
			_check(float(poi_weights[PoiDef.PoiType.UTILITY]) > float(poi_weights[PoiDef.PoiType.OFFENSE]) if salvage else float(poi_weights[PoiDef.PoiType.OFFENSE]) > float(poi_weights[PoiDef.PoiType.UTILITY]), "Route POI weights favor its advertised shops.")
	if routes.size() == 2:
		_check(routes[0].destination_stage != routes[1].destination_stage and routes[0].destination_stage.wave_cards[0] != routes[1].destination_stage.wave_cards[0], "Alternative sectors do not share mutable card snapshots.")
		routes[0].destination_stage.wave_cards[0].weight += 7.0
	for index: int in range(faction.wave_cards.size()):
		_check(is_equal_approx(faction.wave_cards[index].weight, original_weights[index]) and is_equal_approx(faction.wave_cards[index].in_wave_target_budget_scale, original_target_scales[index]), "Generating and changing sector cards leaves the cached faction deck intact.")
	var short_run: RunDefinition = PracticeRunFactory.create_run(faction_id, true)
	var short_stage: StageDef = short_run.get_stage(0)
	var seed: StageDef = faction.short_run.get_stage(0)
	_check(short_run.get_stage_count() == 1 and short_stage.gateway_routes.is_empty(), "Practice remains a single stage without sector choices.")
	_check(short_stage.boss_wave_index == seed.boss_wave_index and short_stage.authored_enemy_budgets == seed.authored_enemy_budgets and short_stage.authored_tier_caps == seed.authored_tier_caps, "Practice keeps its authored encounter sequence.")
	_check(is_equal_approx(short_stage.wave_timeout_override_sec, seed.wave_timeout_override_sec) and is_equal_approx(short_stage.downtime_override_sec, seed.downtime_override_sec), "Practice pacing remains unchanged.")

func _check_progression(faction_id: StringName, route_index: int) -> void:
	var source: RunDefinition = PracticeRunFactory.create_run(faction_id, false)
	var original_final: StageDef = source.get_stage(1)
	var original_final_id: StringName = original_final.get_stage_id()
	GameFlow.start_new_run(source)
	var active: RunDefinition = GameFlow.get_active_run_definition()
	var gateway: StageDef = GameFlow.get_current_stage()
	_check(active != source and gateway != source.get_stage(0), "Starting a run protects the caller's run and stage resources.")
	_check(GameFlow.has_next_stage(), "An offered sector counts as a next stage.")
	var route: SectorRouteDef = gateway.get_gateway_routes()[route_index]
	var preview_conditions: Array[StageModifierDef] = GameFlow.get_stage_modifiers_for(route.destination_stage)
	var rng_state: int = GameFlow._stage_modifier_rng.state
	for preview_index: int in range(5):
		_check(_modifier_ids(GameFlow.get_stage_modifiers_for(route.destination_stage)) == _modifier_ids(preview_conditions), "Opening or cancelling the briefing keeps the same condition roll.")
	_check(GameFlow._stage_modifier_rng.state == rng_state and GameFlow.get_active_stage_index() == 0, "Previewing does not consume another random roll or enter the sector.")
	var previous_changes: int = _stage_changes
	var previous_completions: int = _run_completions
	_check(not GameFlow.advance_to_next_stage(), "Routed Campaigns require an explicit choice.")
	_check(not GameFlow.advance_to_next_stage(original_final_id), "The hidden fallback finale is not an offered destination.")
	_check(not GameFlow.advance_to_next_stage(&"unoffered_destination"), "Unknown destination IDs fail safely.")
	_check(_stage_changes == previous_changes and _run_completions == previous_completions and GameFlow.get_current_stage() == gateway, "Invalid choices neither move nor complete the current run.")
	_check(GameFlow.advance_to_next_stage(route.get_destination_id()), "An offered explicit destination advances the run.")
	var entered: StageDef = GameFlow.get_current_stage()
	_check(GameFlow.get_active_stage_index() == 1 and active.stages.size() == 2, "A route replaces only the second played stage.")
	_check(entered != route.destination_stage and entered.get_stage_id() == route.get_destination_id(), "Entering owns a fresh destination snapshot with the chosen identity.")
	_check(_modifier_ids(GameFlow.get_active_stage_modifiers()) == _modifier_ids(preview_conditions), "The entered sector uses exactly the previewed conditions.")
	_check(GameFlow.get_run_faction().get_faction_id() == faction_id and entered.boss_faction.get_faction_id() == faction_id, "Faction identity survives sector transfer.")
	_check(source.get_stage(1) == original_final and original_final.get_stage_id() == original_final_id, "Choosing a route never overwrites the caller's fallback finale.")
	_check(not GameFlow.advance_to_next_stage(route.get_destination_id()) and _stage_changes == previous_changes + 1, "The same choice cannot transfer or emit a stage transition twice.")
	var offered_weight: float = route.destination_stage.wave_cards[0].weight
	entered.wave_cards[0].weight += 3.0
	_check(is_equal_approx(route.destination_stage.wave_cards[0].weight, offered_weight), "Runtime changes cannot mutate an offered briefing's cards.")
	GameFlow.abandon_run()
	_check(GameFlow.get_current_stage() == null and GameFlow.get_active_run_definition() == null and GameFlow.get_active_stage_modifiers().is_empty() and not GameFlow._run_active, "Abandoning clears active sector state before the menu opens.")

func _check_linear_compatibility() -> void:
	var source: RunDefinition = load("res://content/data/runs/story_mode_intro.tres") as RunDefinition
	GameFlow.start_new_run(source)
	_check(GameFlow.has_next_stage() and GameFlow.get_current_stage().gateway_routes.is_empty(), "Authored legacy runs remain linear.")
	_check(GameFlow.advance_to_next_stage() and GameFlow.get_active_stage_index() == 1, "A legacy gateway advances without a route ID.")
	GameFlow.abandon_run()
	GameFlow.start_new_run(source)
	_check(GameFlow.advance_to_next_stage(source.get_stage(1).get_stage_id()), "An explicit valid destination still works for a legacy run.")
	GameFlow.abandon_run()

func _check_invalid_offered_faction() -> void:
	GameFlow.start_new_run(PracticeRunFactory.create_run(&"mercs", false))
	var current: StageDef = GameFlow.get_current_stage()
	var route: SectorRouteDef = current.get_gateway_routes()[0]
	route.destination_stage.boss_faction = load("res://content/data/factions/bugs.tres") as FactionDef
	_check(not GameFlow.advance_to_next_stage(route.get_destination_id()) and GameFlow.get_current_stage() == current, "Even an offered route cannot switch the locked run faction.")
	GameFlow.abandon_run()

func _check_invalid_route_declaration() -> void:
	var source: RunDefinition = PracticeRunFactory.copy_run_for_play(load("res://content/data/runs/story_mode_intro.tres") as RunDefinition)
	source.get_stage(0).gateway_routes = [SectorRouteDef.new()]
	GameFlow.start_new_run(source)
	_check(not GameFlow.has_next_stage() and not GameFlow.advance_to_next_stage(), "A malformed route declaration cannot fall through to an automatic linear jump.")
	_check(GameFlow.get_active_stage_index() == 0, "Malformed routes leave the current stage intact.")
	GameFlow.abandon_run()

func _modifier_ids(modifiers: Array[StageModifierDef]) -> PackedStringArray:
	var identities: PackedStringArray = PackedStringArray()
	for modifier: StageModifierDef in modifiers:
		identities.append(String(modifier.get_modifier_id()))
	return identities

func _boss_ids(stage: StageDef) -> PackedStringArray:
	var identities: PackedStringArray = PackedStringArray()
	for boss: EnemyBossDef in stage.get_boss_pool():
		identities.append(boss.id)
	return identities

func _on_stage_changed(_stage: StageDef, _index: int) -> void:
	_stage_changes += 1

func _on_run_completed() -> void:
	_run_completions += 1

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
