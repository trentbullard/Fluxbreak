extends RefCounted
class_name EnemyStatResolver

const Stat = StatTypes.Stat
const Phase = StatTypes.Phase
const Op = StatTypes.Op

static func resolve(enemy_def: EnemyDef, context: EnemySpawnContext) -> EnemyStatSnapshot:
	var snapshot: EnemyStatSnapshot = EnemyStatSnapshot.new()
	if enemy_def == null:
		return snapshot

	var safe_context: EnemySpawnContext = context if context != null else EnemySpawnContext.from_enemy_def(enemy_def)
	var wave_modifiers: Array[StatModifier] = _build_wave_modifiers(enemy_def, safe_context)
	var stage_modifiers: Array[StatModifier] = _build_stage_modifiers()
	var card_modifiers: Array[StatModifier] = _build_card_modifiers(safe_context.wave_card)
	var faction_modifiers: Array[StatModifier] = _build_faction_modifiers(enemy_def, safe_context)
	var elite_modifiers: Array[StatModifier] = _build_elite_modifiers(enemy_def, safe_context)
	var affix_modifiers: Array[StatModifier] = _build_affix_modifiers(enemy_def, safe_context)

	snapshot.faction_id = _resolve_faction_id(enemy_def, safe_context)
	snapshot.role_id = _resolve_role_id(enemy_def, safe_context)
	snapshot.max_hull = _resolve_stat_through_layers(Stat.MAX_HULL, enemy_def.max_hull, wave_modifiers, stage_modifiers, card_modifiers, faction_modifiers, elite_modifiers, affix_modifiers)
	snapshot.max_shield = _resolve_stat_through_layers(Stat.MAX_SHIELD, enemy_def.max_shield, wave_modifiers, stage_modifiers, card_modifiers, faction_modifiers, elite_modifiers, affix_modifiers)
	snapshot.shield_regen = _resolve_stat_through_layers(Stat.SHIELD_REGEN, enemy_def.shield_regen, wave_modifiers, stage_modifiers, card_modifiers, faction_modifiers, elite_modifiers, affix_modifiers)
	snapshot.evasion = clamp(_resolve_stat_through_layers(Stat.EVASION_BASE, enemy_def.evasion, wave_modifiers, stage_modifiers, card_modifiers, faction_modifiers, elite_modifiers, affix_modifiers), 0.0, 1.0)
	snapshot.thrust = max(0.0, _resolve_stat_through_layers(Stat.ENEMY_THRUST, enemy_def.thrust, wave_modifiers, stage_modifiers, card_modifiers, faction_modifiers, elite_modifiers, affix_modifiers))

	var compute_value: Callable = func(stat_id: int, base_value: float) -> float:
		return _resolve_stat_through_layers(stat_id, base_value, wave_modifiers, stage_modifiers, card_modifiers, faction_modifiers, elite_modifiers, affix_modifiers)
	snapshot.weapon_stats = WeaponStatResolver.resolve_snapshot(enemy_def.weapon, compute_value)

	_populate_layer_debug(snapshot, safe_context, wave_modifiers, stage_modifiers, card_modifiers, faction_modifiers, elite_modifiers, affix_modifiers)
	return snapshot

static func build_wave_debug_summary(card: WaveCard, wave_index: int, stage_index: int, elapsed_sec: float) -> Dictionary:
	var stage_modifiers: Array[StageModifierDef] = GameFlow.get_active_stage_modifiers()
	var active_stage_modifier_ids: PackedStringArray = PackedStringArray()
	var stage_enemy_modifier_count: int = 0
	for modifier in stage_modifiers:
		if modifier == null:
			continue
		active_stage_modifier_ids.append(String(modifier.get_modifier_id()))
		stage_enemy_modifier_count += modifier.enemy_modifiers.size()

	var card_enemy_modifier_count: int = 0
	if card != null:
		card_enemy_modifier_count = card.enemy_modifiers.size()

	return {
		"wave_index": wave_index,
		"stage_index": stage_index,
		"elapsed_sec": elapsed_sec,
		"stage_modifier_ids": active_stage_modifier_ids,
		"stage_enemy_modifier_count": stage_enemy_modifier_count,
		"card_enemy_modifier_count": card_enemy_modifier_count,
		"card_faction_bias_id": String(card.get_faction_bias_id()) if card != null else "",
		"card_role_bias_ids": card.get_role_bias_ids() if card != null else PackedStringArray(),
		"has_non_base_layers": stage_enemy_modifier_count > 0 or card_enemy_modifier_count > 0,
	}

static func _resolve_faction_id(enemy_def: EnemyDef, context: EnemySpawnContext) -> StringName:
	if context != null and context.faction != null:
		return context.faction.get_faction_id()
	if enemy_def != null:
		return enemy_def.get_faction_id()
	return &""

static func _resolve_role_id(enemy_def: EnemyDef, context: EnemySpawnContext) -> StringName:
	if context != null and context.role != null:
		return context.role.get_role_id()
	if enemy_def != null:
		return enemy_def.get_role_id()
	return &""

static func _resolve_stat_through_layers(stat_id: int, base_value: float, wave_modifiers: Array[StatModifier], stage_modifiers: Array[StatModifier], card_modifiers: Array[StatModifier], faction_modifiers: Array[StatModifier], elite_modifiers: Array[StatModifier], affix_modifiers: Array[StatModifier]) -> float:
	var value: float = base_value
	value = _apply_modifier_layer(stat_id, value, wave_modifiers)
	value = _apply_modifier_layer(stat_id, value, stage_modifiers)
	value = _apply_modifier_layer(stat_id, value, card_modifiers)
	value = _apply_modifier_layer(stat_id, value, faction_modifiers)
	value = _apply_modifier_layer(stat_id, value, elite_modifiers)
	value = _apply_modifier_layer(stat_id, value, affix_modifiers)
	return value

static func _apply_modifier_layer(stat_id: int, current_value: float, layer_modifiers: Array[StatModifier]) -> float:
	if layer_modifiers.is_empty():
		return current_value

	var relevant: Array[StatModifier] = []
	for modifier in layer_modifiers:
		if modifier == null or not modifier.enabled:
			continue
		if modifier.stat == stat_id:
			relevant.append(modifier)
	if relevant.is_empty():
		return current_value

	var pre: Array[StatModifier] = []
	var add_mult: Array[StatModifier] = []
	var post: Array[StatModifier] = []
	var clamps: Array[StatModifier] = []
	var hard_best: StatModifier = null
	var hard_best_phase_rank: int = -1
	var hard_best_priority: int = -2147483648

	for modifier in relevant:
		if modifier.op == Op.HARD_SET:
			var phase_rank: int = _get_phase_rank(modifier.phase)
			if phase_rank > hard_best_phase_rank or (phase_rank == hard_best_phase_rank and modifier.priority > hard_best_priority):
				hard_best = modifier
				hard_best_phase_rank = phase_rank
				hard_best_priority = modifier.priority
			continue

		match modifier.phase:
			Phase.PRE_OVERRIDE:
				pre.append(modifier)
			Phase.ADD_MULT:
				add_mult.append(modifier)
			Phase.POST_OVERRIDE:
				post.append(modifier)
			Phase.FINAL_CLAMP:
				clamps.append(modifier)

	if hard_best != null:
		return hard_best.value

	_sort_modifiers(pre)
	_sort_modifiers(add_mult)
	_sort_modifiers(post)
	_sort_modifiers(clamps)

	var value: float = current_value
	value = _apply_modifier_phase(pre, value)
	value = _apply_modifier_phase(add_mult, value)
	value = _apply_modifier_phase(post, value)
	value = _apply_modifier_phase(clamps, value)
	return value

static func _apply_modifier_phase(modifiers: Array[StatModifier], current_value: float) -> float:
	var value: float = current_value
	for modifier in modifiers:
		match modifier.op:
			Op.ADD:
				value += modifier.value
			Op.MULT:
				value *= modifier.value
			Op.OVERRIDE:
				value = modifier.value
			Op.CLAMP_MIN:
				if value < modifier.value:
					value = modifier.value
			Op.CLAMP_MAX:
				if value > modifier.value:
					value = modifier.value
	return value

static func _get_phase_rank(phase: int) -> int:
	match phase:
		Phase.PRE_OVERRIDE:
			return 0
		Phase.ADD_MULT:
			return 1
		Phase.POST_OVERRIDE:
			return 2
		Phase.FINAL_CLAMP:
			return 3
	return -1

static func _sort_modifiers(modifiers: Array[StatModifier]) -> void:
	if modifiers.is_empty():
		return
	modifiers.sort_custom(func(left: StatModifier, right: StatModifier) -> bool: return left.priority < right.priority)

static func _build_wave_modifiers(_enemy_def: EnemyDef, _context: EnemySpawnContext) -> Array[StatModifier]:
	return []

static func _build_stage_modifiers() -> Array[StatModifier]:
	var flattened: Array[StatModifier] = []
	for stage_modifier in GameFlow.get_active_stage_modifiers():
		if stage_modifier == null:
			continue
		for modifier in stage_modifier.enemy_modifiers:
			if modifier == null:
				continue
			var modifier_copy: StatModifier = modifier.duplicate(true) as StatModifier
			if modifier_copy != null:
				flattened.append(modifier_copy)
	return flattened

static func _build_card_modifiers(card: WaveCard) -> Array[StatModifier]:
	if card == null:
		return []
	var flattened: Array[StatModifier] = []
	for modifier in card.enemy_modifiers:
		if modifier == null:
			continue
		var modifier_copy: StatModifier = modifier.duplicate(true) as StatModifier
		if modifier_copy != null:
			flattened.append(modifier_copy)
	return flattened

static func _build_faction_modifiers(_enemy_def: EnemyDef, _context: EnemySpawnContext) -> Array[StatModifier]:
	return []

static func _build_elite_modifiers(_enemy_def: EnemyDef, _context: EnemySpawnContext) -> Array[StatModifier]:
	return []

static func _build_affix_modifiers(_enemy_def: EnemyDef, _context: EnemySpawnContext) -> Array[StatModifier]:
	return []

static func _populate_layer_debug(snapshot: EnemyStatSnapshot, context: EnemySpawnContext, wave_modifiers: Array[StatModifier], stage_modifiers: Array[StatModifier], card_modifiers: Array[StatModifier], faction_modifiers: Array[StatModifier], elite_modifiers: Array[StatModifier], affix_modifiers: Array[StatModifier]) -> void:
	if snapshot == null:
		return
	var active_layers: PackedStringArray = PackedStringArray()
	if not wave_modifiers.is_empty():
		active_layers.append("wave")
	if not stage_modifiers.is_empty():
		active_layers.append("stage")
	if not card_modifiers.is_empty():
		active_layers.append("card")
	if not faction_modifiers.is_empty():
		active_layers.append("faction")
	if not elite_modifiers.is_empty():
		active_layers.append("elite")
	if not affix_modifiers.is_empty():
		active_layers.append("affix")

	snapshot.active_layers = active_layers
	snapshot.layer_counts = {
		"wave": wave_modifiers.size(),
		"stage": stage_modifiers.size(),
		"card": card_modifiers.size(),
		"faction": faction_modifiers.size(),
		"elite": elite_modifiers.size(),
		"affix": affix_modifiers.size(),
	}
	if context != null:
		snapshot.source_tags = PackedStringArray(context.source_tags)
