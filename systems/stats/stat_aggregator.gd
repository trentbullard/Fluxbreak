# scripts/stats/stat_aggregator.gd (godot 4.5)
extends Node
class_name StatAggregator

const Phase = StatTypes.Phase
const Op = StatTypes.Op
const Stat = StatTypes.Stat

signal stats_changed(affected: Array[Stat])

const PHASE_ORDER: Dictionary = {
	Phase.PRE_OVERRIDE: 0,
	Phase.ADD_MULT: 1,
	Phase.POST_OVERRIDE: 2,
	Phase.FINAL_CLAMP: 3,
}

var _mods: Dictionary = {}
var _base_values: Dictionary = {}

func _ready() -> void:
	# Example wiring for upgrades from EventBus:
	# EventBus.add_bulkhead_requested.connect(add_upgrade)
	# EventBus.add_shield_requested.connect(add_upgrade)
	# EventBus.add_targeting_requested.connect(add_upgrade)
	# EventBus.add_systems_requested.connect(add_upgrade)
	pass

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
	if not _mods.has(stat_id):
		return base_value
	
	var arr: Array = _mods[stat_id]
	
	var pre: Array = []
	var add_mult: Array = []
	var post: Array = []
	var clamps: Array = []
	
	var hard_best: StatModifier = null
	var hard_best_phase_rank: int = -1
	var hard_best_priority: int = -2147483648
	
	for m in arr:
		var mm: StatModifier = m
		if not mm.enabled:
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
