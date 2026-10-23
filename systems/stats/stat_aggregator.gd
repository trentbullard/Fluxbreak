# scripts/stats/stat_aggregator.gd (godot 4.6.3)
extends Node
class_name StatAggregator

const Phase = StatTypes.Phase
const Op = StatTypes.Op
const Stat = StatTypes.Stat

signal stats_changed(affected: Array[Stat])

enum Context {
	ANY,
	PLAYER,
	MINION,
}

const PHASE_ORDER: Dictionary = {
	Phase.PRE_OVERRIDE: 0,
	Phase.ADD_MULT: 1,
	Phase.POST_OVERRIDE: 2,
	Phase.FINAL_CLAMP: 3,
}

var _mods: Dictionary = {}
var _base_values: Dictionary = {}
var _stage_projection_enabled: bool = false
var _observed_stage: StageDef = null

func _ready() -> void:
	set_process(_stage_projection_enabled)

## Only the player's source aggregator projects stage effects. Minion copies
## receive matching modifiers through copy_modifiers_to, without a second layer.
func set_stage_projection_enabled(enabled: bool) -> void:
	if _stage_projection_enabled == enabled:
		return
	_stage_projection_enabled = enabled
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(enabled)
	if enabled:
		if not GameFlow.stage_changed.is_connected(_on_stage_changed):
			GameFlow.stage_changed.connect(_on_stage_changed)
		if not GameFlow.run_completed.is_connected(_on_run_completed):
			GameFlow.run_completed.connect(_on_run_completed)
	else:
		if GameFlow.stage_changed.is_connected(_on_stage_changed):
			GameFlow.stage_changed.disconnect(_on_stage_changed)
		if GameFlow.run_completed.is_connected(_on_run_completed):
			GameFlow.run_completed.disconnect(_on_run_completed)
	_observed_stage = GameFlow.get_current_stage() if enabled else null
	notify_changed()

func _process(_delta: float) -> void:
	# Death/menu exits can clear progression without emitting stage_changed.
	# Notify caches once on that identity change, including while paused.
	var current_stage: StageDef = GameFlow.get_current_stage()
	if current_stage != _observed_stage:
		_observed_stage = current_stage
		notify_changed()

func _on_stage_changed(stage: StageDef, _stage_index: int) -> void:
	_observed_stage = stage
	notify_changed()

func _on_run_completed() -> void:
	_observed_stage = GameFlow.get_current_stage()
	notify_changed()

func _get_stage_player_modifiers() -> Array[StatModifier]:
	var modifiers: Array[StatModifier] = []
	if not _stage_projection_enabled or GameFlow.get_current_stage() == null:
		return modifiers
	for stage_modifier: StageModifierDef in GameFlow.get_active_stage_modifiers():
		if stage_modifier == null:
			continue
		for modifier: StatModifier in stage_modifier.player_modifiers:
			if modifier != null and modifier.enabled:
				modifiers.append(modifier)
	return modifiers

func set_base_value(stat_id: int, value: float) -> void:
	_base_values[stat_id] = value

func set_base_values(map: Dictionary) -> void:
	_base_values = map.duplicate()

func clear() -> void:
	_mods.clear()
	var affected: Array[Stat] = []
	stats_changed.emit(affected)

func add_modifier(m: StatModifier) -> void:
	if m == null or not m.enabled:
		return

	var arr: Array = _mods.get(m.stat, [])
	arr.append(m)
	_mods[m.stat] = arr
	
	var affected: Array[Stat] = [m.stat]
	stats_changed.emit(affected)
	_broadcast_stats(affected)

func add_upgrade(upgrade: Upgrade) -> void:
	if upgrade == null:
		return
	
	var affected: Array[Stat] = []
	for m in upgrade.modifiers:
		if m == null:
			continue
		if m.source_id == "":
			m.source_id = upgrade.id
		add_modifier(m)
		if not affected.has(m.stat):
			affected.append(m.stat)
	
	if not affected.is_empty():
		stats_changed.emit(affected)
		_broadcast_stats(affected)

func add_meta_upgrade(upgrade: MetaUpgradeDef, tier_count: int) -> void:
	if upgrade == null:
		return
	if tier_count <= 0:
		return

	var source_id: String = upgrade.id.strip_edges()
	if source_id == "":
		push_warning("Ignoring meta upgrade with empty id: %s" % upgrade.resource_path)
		return

	var affected: Array[Stat] = []
	for m: StatModifier in upgrade.modifiers_per_tier:
		if m == null or not m.enabled:
			continue

		if m.op != Op.ADD and m.op != Op.MULT:
			push_warning("Skipping unsupported meta upgrade op for %s stat %d" % [source_id, int(m.stat)])
			continue

		var mod_copy: StatModifier = m.duplicate(true) as StatModifier
		if mod_copy == null:
			continue

		mod_copy.source_id = source_id
		if mod_copy.op == Op.ADD:
			mod_copy.value = m.value * float(tier_count)
		else:
			mod_copy.value = 1.0 + ((m.value - 1.0) * float(tier_count))

		var arr: Array = _mods.get(mod_copy.stat, [])
		arr.append(mod_copy)
		_mods[mod_copy.stat] = arr
		if not affected.has(mod_copy.stat):
			affected.append(mod_copy.stat)

	if not affected.is_empty():
		stats_changed.emit(affected)
		_broadcast_stats(affected)

func remove_by_source(stat_id: Stat, source_id: String) -> void:
	if not _mods.has(stat_id):
		return
	var arr: Array[StatModifier] = _mods[stat_id]
	for i in range(arr.size() - 1, -1, -1):
		var m: StatModifier = arr[i]
		if m.source_id == source_id:
			arr.remove_at(i)
	
	if arr.is_empty():
		_mods.erase(stat_id)
	else:
		_mods[stat_id] = arr

	var affected: Array[Stat] = [stat_id]
	stats_changed.emit(affected)
	_broadcast_stats(affected)

func notify_changed(affected: Array[Stat] = []) -> void:
	# Call this after batch updates when external code modifies multiple modifiers.
	stats_changed.emit(affected)
	_broadcast_stats(affected)

func compute(stat_id: int, base_value: float) -> float:
	return compute_for_context(stat_id, base_value, Context.ANY)

func compute_for_context(stat_id: int, base_value: float, context: int) -> float:
	var arr: Array = _mods.get(stat_id, []).duplicate()
	for stage_modifier: StatModifier in _get_stage_player_modifiers():
		if stage_modifier.stat == stat_id:
			arr.append(stage_modifier)
	if arr.is_empty():
		return base_value
	
	var pre: Array = []
	var add_mult: Array = []
	var post: Array = []
	var clamps: Array = []
	
	var hard_best: StatModifier = null
	var hard_best_phase_rank: int = -1
	var hard_best_priority: int = -2147483648
	
	for m in arr:
		var mm: StatModifier = m
		if not mm.enabled or not _modifier_applies_to_context(mm, context):
			continue
		
		if mm.op == Op.HARD_SET:
			var phase_rank: int = PHASE_ORDER.get(mm.phase, -1)
			if phase_rank > hard_best_phase_rank or (phase_rank == hard_best_phase_rank and mm.priority > hard_best_priority):
				hard_best = mm
				hard_best_phase_rank = phase_rank
				hard_best_priority = mm.priority
			continue
		
		match mm.phase:
			Phase.PRE_OVERRIDE:
				pre.append(mm)
			Phase.ADD_MULT:
				add_mult.append(mm)
			Phase.POST_OVERRIDE:
				post.append(mm)
			Phase.FINAL_CLAMP:
				clamps.append(mm)
	
	if hard_best != null:
		return hard_best.value
	
	_sort_by_priority(pre)
	_sort_by_priority(add_mult)
	_sort_by_priority(post)
	_sort_by_priority(clamps)
	
	var val: float = base_value
	
	val = _apply_phase(pre, val)
	val = _apply_phase(add_mult, val)
	val = _apply_phase(post, val)
	val = _apply_phase(clamps, val)
	
	return val

func get_modifier_copies_for_context(context: int) -> Array[StatModifier]:
	var copies: Array[StatModifier] = []
	var active_modifiers: Array[StatModifier] = []
	for stat_id in _mods.keys():
		var mods_for_stat: Array = _mods[stat_id]
		for modifier_variant in mods_for_stat:
			var modifier: StatModifier = modifier_variant as StatModifier
			if modifier != null:
				active_modifiers.append(modifier)
	active_modifiers.append_array(_get_stage_player_modifiers())
	for modifier: StatModifier in active_modifiers:
		if not modifier.enabled or not _modifier_applies_to_context(modifier, context):
			continue
		var modifier_copy: StatModifier = modifier.duplicate(true) as StatModifier
		if modifier_copy != null:
			copies.append(modifier_copy)
	return copies

func copy_modifiers_to(target: StatAggregator, context: int) -> void:
	if target == null:
		return

	target._mods.clear()
	var affected: Array[Stat] = []
	for modifier in get_modifier_copies_for_context(context):
		var arr: Array = target._mods.get(modifier.stat, [])
		arr.append(modifier)
		target._mods[modifier.stat] = arr
		if not affected.has(modifier.stat):
			affected.append(modifier.stat)

	target.notify_changed(affected)

func _modifier_applies_to_context(modifier: StatModifier, context: int) -> bool:
	if modifier == null:
		return false

	match context:
		Context.PLAYER:
			return modifier.applies_to_player
		Context.MINION:
			return modifier.applies_to_minions
		_:
			return true

func _sort_by_priority(arr: Array) -> void:
	if arr.is_empty():
		return
	arr.sort_custom(func(a: StatModifier, b: StatModifier) -> bool: return a.priority < b.priority)

func _apply_phase(mods: Array, current: float) -> float:
	if mods.is_empty():
		return current
	
	for m in mods:
		match m.op:
			Op.ADD:
				current += m.value
			Op.MULT:
				current *= m.value
			Op.OVERRIDE:
				current = m.value
			Op.CLAMP_MIN:
				if current < m.value:
					current = m.value
			Op.CLAMP_MAX:
				if current > m.value:
					current = m.value
	
	return current

func _broadcast_stats(affected: Array[Stat]) -> void:
	var payload: Dictionary = {}
	
	if affected.is_empty():
		for stat_id in _mods.keys():
			var base_val: float = _base_values.get(stat_id, 0.0)
			payload[stat_id] = compute(stat_id, base_val)
	else:
		for stat_id in affected:
			var base_val: float = _base_values.get(stat_id, 0.0)
			payload[stat_id] = compute(stat_id, base_val)

	if payload.is_empty():
		return
