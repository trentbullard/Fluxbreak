extends RefCounted
class_name PracticeRunFactory

const FACTION_PATHS: Array[String] = [
	"res://content/data/practice_factions/machines.tres",
	"res://content/data/practice_factions/mercs.tres",
	"res://content/data/practice_factions/bugs.tres",
	"res://content/data/practice_factions/greys.tres",
]
const MAIN_TEMPLATE: String = "res://content/data/runs/story_mode_intro.tres"
const SECTOR_MODIFIER_ROOT: String = "res://content/data/stages/modifiers/"
const SECTOR_POI_ROOT: String = "res://content/data/pois/sectors/"

static func get_factions() -> Array[PracticeFactionDef]:
	var factions: Array[PracticeFactionDef] = []
	for path: String in FACTION_PATHS:
		var definition: PracticeFactionDef = load(path) as PracticeFactionDef
		if definition != null and definition.faction != null and definition.short_run != null:
			factions.append(definition)
	return factions

## Resolve Random once at launch. Stages and cards are independent run copies.
static func create_run(faction_id: StringName = &"random", short_practice: bool = false, rng: RandomNumberGenerator = null) -> RunDefinition:
	var factions: Array[PracticeFactionDef] = get_factions()
	if factions.is_empty():
		return null
	var run_rng: RandomNumberGenerator = rng
	if run_rng == null:
		run_rng = RandomNumberGenerator.new()
		run_rng.randomize()
	var chosen: PracticeFactionDef = null
	if faction_id == &"random" or faction_id == &"":
		chosen = factions[run_rng.randi_range(0, factions.size() - 1)]
	else:
		for definition: PracticeFactionDef in factions:
			if definition.faction.get_faction_id() == faction_id:
				chosen = definition
				break
	if chosen == null:
		return null
	var deck: Array[WaveCard] = _matching_deck(chosen)
	if deck.is_empty():
		return null
	return _create_short_run(chosen, deck, run_rng) if short_practice else _create_main_run(chosen, deck)

static func _matching_deck(definition: PracticeFactionDef) -> Array[WaveCard]:
	var deck: Array[WaveCard] = []
	var faction_id: StringName = definition.faction.get_faction_id()
	for card: WaveCard in definition.wave_cards:
		if card != null and card.get_faction_bias_id() == faction_id:
			deck.append(card)
	return deck

static func _create_short_run(definition: PracticeFactionDef, deck: Array[WaveCard], rng: RandomNumberGenerator) -> RunDefinition:
	var seed_stage: StageDef = definition.short_run.get_stage(0)
	if seed_stage == null:
		return null
	var stage: StageDef = seed_stage.duplicate(false) as StageDef
	stage.wave_cards = []
	# Each faction's authored lessons remain ordered while compositions vary.
	var lesson_tiers: PackedInt32Array = seed_stage.authored_tier_caps
	if lesson_tiers.is_empty() or lesson_tiers.size() != seed_stage.boss_wave_index - 1:
		return null
	for tier: int in lesson_tiers:
		var choices: Array[WaveCard] = []
		for card: WaveCard in deck:
			if card.min_enemy_tier == tier:
				choices.append(card)
		if choices.is_empty():
			return null
		stage.wave_cards.append(_pick_card(choices, rng).duplicate(false) as WaveCard)
	stage.ordered_wave_cards = true
	stage.next_stage_id = &""
	stage.gateway_routes = []
	stage.completion_flow = StageDef.CompletionFlow.BOSS_FINALE
	stage.boss_faction = definition.faction
	stage.boss_pool = _copy_bosses(seed_stage.get_boss_pool(), definition.faction)
	if stage.boss_pool.is_empty():
		return null
	# Choose once at launch, including seeded runs; the Director receives one
	# boss rather than re-rolling a shared cached pool during an encounter.
	stage.boss_pool = [stage.boss_pool[rng.randi_range(0, stage.boss_pool.size() - 1)]]
	var run: RunDefinition = definition.short_run.duplicate(false) as RunDefinition
	run.run_id = StringName("short_practice_%s" % definition.faction.get_faction_id())
	run.display_name = "%s Practice" % definition.faction.get_display_name_or_default()
	run.run_mode = RunDefinition.RunMode.PRACTICE
	run.enemy_faction = definition.faction
	run.stages = [stage]
	run.loop_last_stage = false
	return run

static func _create_main_run(definition: PracticeFactionDef, deck: Array[WaveCard]) -> RunDefinition:
	var template: RunDefinition = load(MAIN_TEMPLATE) as RunDefinition
	var short_stage: StageDef = definition.short_run.get_stage(0)
	if template == null or short_stage == null:
		return null
	var run: RunDefinition = template.duplicate(false) as RunDefinition
	var faction_id: StringName = definition.faction.get_faction_id()
	var faction_name: String = definition.faction.get_display_name_or_default()
	run.run_id = StringName("practice_%s" % faction_id)
	run.display_name = "%s Campaign" % faction_name
	run.description = "Two-stage campaign against %s. The faction stays fixed until the run ends." % faction_name
	run.run_mode = RunDefinition.RunMode.STORY
	run.enemy_faction = definition.faction
	run.loop_last_stage = false
	run.stages = []
	var boss_pool: Array[EnemyBossDef] = definition.main_boss_pool
	if boss_pool.is_empty():
		boss_pool = short_stage.get_boss_pool()
	for index: int in range(template.get_stage_count()):
		var stage: StageDef = template.get_stage(index).duplicate(false) as StageDef
		stage.stage_id = StringName("practice_%s_stage_%d" % [faction_id, index + 1])
		stage.gateway_routes = []
		stage.display_name = "%s %s" % [faction_name, "Approach" if index == 0 else "Stronghold"]
		stage.description = "Campaign stage %d against %s." % [index + 1, faction_name]
		stage.combat_hint = definition.combat_hint
		stage.boss_faction = definition.faction
		var stage_bosses: Array[EnemyBossDef] = definition.final_boss_pool if index == template.get_stage_count() - 1 and not definition.final_boss_pool.is_empty() else boss_pool
		stage.boss_pool = _copy_bosses(stage_bosses, definition.faction)
		if stage.boss_pool.is_empty():
			return null
		stage.ordered_wave_cards = false
		stage.wave_cards = []
		var pacing_cards: Array[WaveCard] = template.get_stage(index).get_wave_cards()
		for card_index: int in range(deck.size()):
			var card_copy: WaveCard = deck[card_index].duplicate(false) as WaveCard
			# Short lessons suppress salvage and pressure reinforcements. The
			# longer run retains its stage's existing economy and pressure tuning.
			if not pacing_cards.is_empty():
				var pacing: WaveCard = pacing_cards[clampi(card_copy.min_enemy_tier - 1, 0, pacing_cards.size() - 1)]
				card_copy.in_wave_target_budget_scale = pacing.in_wave_target_budget_scale
				card_copy.downtime_target_point_budget = pacing.downtime_target_point_budget
				card_copy.pressure_enemy_point_budget = pacing.pressure_enemy_point_budget
				card_copy.pressure_target_point_budget = pacing.pressure_target_point_budget
				card_copy.allow_pressure_spikes = pacing.allow_pressure_spikes
				card_copy.target_size_band_max = pacing.target_size_band_max
			stage.wave_cards.append(card_copy)
		stage.authored_enemy_budgets = PackedInt32Array()
		stage.authored_tier_caps = PackedInt32Array()
		for wave_offset: int in range(maxi(stage.boss_wave_index - 1, 0)):
			stage.authored_tier_caps.append(clampi(1 + int((wave_offset + 1) / 3) + index, 1, definition.max_enemy_tier))
		# Retain stage panoramas, modifiers, POIs and normal pacing; faction tint
		# follows its short encounter so enemy identity is visible in both stages.
		stage.ambient_light_color = short_stage.ambient_light_color
		stage.ambient_light_energy = short_stage.ambient_light_energy
		stage.star_light_color = short_stage.star_light_color
		stage.volumetric_fog_density = short_stage.volumetric_fog_density
		run.stages.append(stage)
	for index: int in range(run.stages.size()):
		var stage: StageDef = run.stages[index]
		if index + 1 < run.stages.size():
			stage.completion_flow = StageDef.CompletionFlow.BOSS_GATEWAY
			stage.next_stage_id = run.stages[index + 1].get_stage_id()
		else:
			stage.completion_flow = StageDef.CompletionFlow.BOSS_FINALE
			stage.next_stage_id = &""
	if run.stages.size() == 2:
		run.stages[0].gateway_routes = _create_sector_routes(run.stages[1], faction_name)
	return run

static func _create_sector_routes(final_stage: StageDef, faction_name: String) -> Array[SectorRouteDef]:
	var routes: Array[SectorRouteDef] = []
	for salvage: bool in [true, false]:
		var destination: StageDef = copy_stage_for_play(final_stage)
		var suffix: String = "salvage" if salvage else "assault"
		destination.stage_id = StringName("%s_%s" % [final_stage.get_stage_id(), suffix])
		destination.display_name = "%s %s" % [faction_name, "Salvage Corridor" if salvage else "Assault Lane"]
		destination.description = "A wreck-strewn recovery lane into the enemy stronghold." if salvage else "A direct assault through the stronghold's heavy formations."
		destination.next_stage_id = &""
		destination.gateway_routes = []
		destination.completion_flow = StageDef.CompletionFlow.BOSS_FINALE
		destination.guaranteed_modifiers = []
		var modifier_ids: Array[String] = ["salvage_tide", "sensor_static"]
		if not salvage:
			modifier_ids = ["thruster_corridors", "armored_patrols"]
		for modifier_id: String in modifier_ids:
			var modifier: StageModifierDef = load(SECTOR_MODIFIER_ROOT + modifier_id + ".tres") as StageModifierDef
			if modifier != null:
				destination.guaranteed_modifiers.append(modifier)
		destination.guaranteed_modifiers = _copy_stage_modifiers(destination.guaranteed_modifiers)
		destination.bonus_pool = []
		destination.debuff_pool = []
		destination.random_bonus_count = 0
		destination.random_debuff_count = 0
		destination.poi_defs = []
		for station: String in ["arms_factory", "shield_array", "repair_hangar"]:
			var poi: PoiDef = load(SECTOR_POI_ROOT + suffix + "_" + station + ".tres") as PoiDef
			if poi != null:
				var poi_copy: PoiDef = poi.duplicate(false) as PoiDef
				poi_copy.upgrade_tags = poi.upgrade_tags.duplicate()
				destination.poi_defs.append(poi_copy)
		_tune_sector_cards(destination, salvage)
		var route: SectorRouteDef = SectorRouteDef.new()
		route.route_id = StringName(suffix)
		route.display_name = "Salvage Corridor" if salvage else "Assault Lane"
		route.description = destination.description
		route.threat_summary = "-10% weapon range. Escort waves arrive in tighter batches." if salvage else "+15% enemy hull. Heavy formations appear more often."
		route.reward_summary = "+25% nanobot gain. More wrecks and repair/utility stations." if salvage else "+15% forward and reverse speed. More weapon and shield stations."
		route.marker_kind = SectorRouteDef.MarkerKind.SALVAGE if salvage else SectorRouteDef.MarkerKind.ASSAULT
		route.marker_color = Color(0.2, 0.86, 0.75, 1.0) if salvage else Color(0.97, 0.6, 0.2, 1.0)
		route.destination_stage = destination
		routes.append(route)
	return routes

static func _tune_sector_cards(stage: StageDef, salvage: bool) -> void:
	var highest_card_tier: int = 1
	for card: WaveCard in stage.wave_cards:
		if card != null:
			highest_card_tier = maxi(highest_card_tier, card.min_enemy_tier)
	for card: WaveCard in stage.wave_cards:
		if card == null:
			continue
		if salvage:
			card.in_wave_target_budget_scale = minf(maxf(card.in_wave_target_budget_scale * 1.5, card.in_wave_target_budget_scale + 0.12), 1.0)
			card.downtime_target_point_budget += 2
			card.pressure_target_point_budget += 1
			card.target_size_band_max = maxi(card.target_size_band_max, 2)
			if card.min_enemy_tier <= 2:
				card.inter_batch_sec = maxf(card.inter_batch_sec * 0.75, 0.15)
				card.pressure_enemy_point_budget += 1
		else:
			# Machines currently have no authored tier4/5 cards. Their heaviest
			# available formations gain weight without inventing missing units.
			var is_heavy: bool = card.min_enemy_tier >= 4 or (highest_card_tier < 4 and card.min_enemy_tier == highest_card_tier)
			card.weight = minf(card.weight * (1.8 if is_heavy else 0.85), 10.0)

## Own the run's mutable configuration while sharing immutable visual assets.
static func copy_run_for_play(source: RunDefinition) -> RunDefinition:
	if source == null:
		return null
	var copied: RunDefinition = source.duplicate(false) as RunDefinition
	copied.stages = []
	var memo: Dictionary = {}
	for stage: StageDef in source.get_stages():
		var stage_copy: StageDef = _copy_stage_tree(stage, memo, {})
		if stage_copy != null:
			copied.stages.append(stage_copy)
	return copied

## Copy a chosen destination without mutating the offered briefing snapshot.
static func copy_stage_for_play(source: StageDef) -> StageDef:
	return _copy_stage_tree(source, {}, {})

static func _copy_stage_tree(source: StageDef, memo: Dictionary, ancestors: Dictionary) -> StageDef:
	if source == null or ancestors.has(source.get_instance_id()):
		return null
	var key: int = source.get_instance_id()
	if memo.has(key):
		return memo[key] as StageDef
	var copied: StageDef = source.duplicate(false) as StageDef
	memo[key] = copied
	ancestors[key] = true
	copied.wave_cards = []
	for card: WaveCard in source.wave_cards:
		if card == null:
			continue
		var card_copy: WaveCard = card.duplicate(false) as WaveCard
		card_copy.tags = card.tags.duplicate()
		card_copy.enemy_modifiers = _copy_stat_modifiers(card.enemy_modifiers)
		copied.wave_cards.append(card_copy)
	copied.boss_pool = []
	for boss: EnemyBossDef in source.boss_pool:
		if boss != null:
			copied.boss_pool.append(boss.duplicate(false) as EnemyBossDef)
	copied.poi_defs = []
	for poi: PoiDef in source.poi_defs:
		if poi != null:
			var poi_copy: PoiDef = poi.duplicate(false) as PoiDef
			poi_copy.upgrade_tags = poi.upgrade_tags.duplicate()
			copied.poi_defs.append(poi_copy)
	copied.guaranteed_modifiers = _copy_stage_modifiers(source.guaranteed_modifiers)
	copied.bonus_pool = _copy_stage_modifiers(source.bonus_pool)
	copied.debuff_pool = _copy_stage_modifiers(source.debuff_pool)
	copied.panorama_options = source.panorama_options.duplicate()
	copied.authored_enemy_budgets = source.authored_enemy_budgets.duplicate()
	copied.authored_tier_caps = source.authored_tier_caps.duplicate()
	copied.gateway_routes = []
	for route: SectorRouteDef in source.gateway_routes:
		if route == null:
			copied.gateway_routes.append(null)
			continue
		var route_copy: SectorRouteDef = route.duplicate(false) as SectorRouteDef
		route_copy.destination_stage = _copy_stage_tree(route.destination_stage, memo, ancestors)
		# Retain a malformed route declaration so it cannot silently turn into
		# an automatic linear jump; the public helper omits unusable markers.
		copied.gateway_routes.append(route_copy)
	ancestors.erase(key)
	return copied

static func _copy_stage_modifiers(source: Array[StageModifierDef]) -> Array[StageModifierDef]:
	var copied: Array[StageModifierDef] = []
	for modifier: StageModifierDef in source:
		if modifier == null:
			continue
		var modifier_copy: StageModifierDef = modifier.duplicate(false) as StageModifierDef
		modifier_copy.player_modifiers = _copy_stat_modifiers(modifier.player_modifiers)
		modifier_copy.enemy_modifiers = _copy_stat_modifiers(modifier.enemy_modifiers)
		copied.append(modifier_copy)
	return copied

static func _copy_stat_modifiers(source: Array[StatModifier]) -> Array[StatModifier]:
	var copied: Array[StatModifier] = []
	for modifier: StatModifier in source:
		if modifier != null:
			copied.append(modifier.duplicate(false) as StatModifier)
	return copied

static func _copy_bosses(pool: Array[EnemyBossDef], faction: FactionDef) -> Array[EnemyBossDef]:
	var copies: Array[EnemyBossDef] = []
	for boss: EnemyBossDef in pool:
		if boss != null and boss.get_faction_id() == faction.get_faction_id():
			copies.append(boss.duplicate(false) as EnemyBossDef)
	return copies

static func _pick_card(cards: Array[WaveCard], rng: RandomNumberGenerator) -> WaveCard:
	var total: float = 0.0
	for card: WaveCard in cards:
		total += maxf(card.weight, 0.0)
	if total <= 0.0:
		return cards[rng.randi_range(0, cards.size() - 1)]
	var roll: float = rng.randf_range(0.0, total)
	for card: WaveCard in cards:
		roll -= maxf(card.weight, 0.0)
		if roll < 0.0:
			return card
	return cards[cards.size() - 1]
