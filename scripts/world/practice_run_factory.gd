extends RefCounted
class_name PracticeRunFactory

const FACTION_PATHS: Array[String] = [
	"res://content/data/practice_factions/machines.tres",
	"res://content/data/practice_factions/mercs.tres",
	"res://content/data/practice_factions/bugs.tres",
	"res://content/data/practice_factions/greys.tres",
]
const MAIN_TEMPLATE: String = "res://content/data/runs/story_mode_intro.tres"

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
	# The three lessons remain ordered while their compositions vary each run.
	for tier: int in range(1, 4):
		var choices: Array[WaveCard] = []
		for card: WaveCard in deck:
			if card.min_enemy_tier == tier:
				choices.append(card)
		if choices.is_empty():
			return null
		stage.wave_cards.append(_pick_card(choices, rng).duplicate(false) as WaveCard)
	stage.ordered_wave_cards = true
	stage.next_stage_id = &""
	stage.completion_flow = StageDef.CompletionFlow.BOSS_FINALE
	stage.boss_faction = definition.faction
	stage.boss_pool = _copy_bosses(seed_stage.get_boss_pool(), definition.faction)
	if stage.boss_pool.is_empty():
		return null
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
		stage.display_name = "%s %s" % [faction_name, "Approach" if index == 0 else "Stronghold"]
		stage.description = "Campaign stage %d against %s." % [index + 1, faction_name]
		stage.combat_hint = definition.combat_hint
		stage.boss_faction = definition.faction
		stage.boss_pool = _copy_bosses(boss_pool, definition.faction)
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
				var pacing: WaveCard = pacing_cards[int(card_index / 2) % pacing_cards.size()]
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
	return run

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
