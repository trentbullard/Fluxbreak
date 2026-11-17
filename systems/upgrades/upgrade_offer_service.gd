extends RefCounted
class_name UpgradeOfferService

## Shared POI offer rules. The POI owns its cached stock; RunState owns uses/bans.
const UPGRADE_COST_VARIANCE: float = 0.05
const TIER_PROGRESS_WAVE_SPAN: float = 10.0

var available_upgrades: Array[Upgrade] = []
var available_weapons: Array[WeaponDef] = []
var offer_memory_def: UpgradeOfferMemoryDef = null
var num_upgrade_choices: int = 3
var _upgrade_choices: Array[Upgrade] = []
var _last_offer_debug: Dictionary = {}
var _transient_offer: Dictionary = {}

func configure(upgrades: Array[Upgrade], weapons: Array[WeaponDef], memory: UpgradeOfferMemoryDef, default_choice_count: int) -> void:
	if available_upgrades != upgrades or available_weapons != weapons or offer_memory_def != memory or num_upgrade_choices != maxi(default_choice_count, 1):
		# Transient callers have no POI identity. A changed catalog is a new source,
		# while real POI stock remains stable until an explicit action or new run.
		_transient_offer.clear()
	available_upgrades = upgrades.duplicate()
	available_weapons = weapons.duplicate()
	offer_memory_def = memory
	num_upgrade_choices = maxi(default_choice_count, 1)

## Returns isolated containers around shared upgrade/weapon resources.
## A return visit preserves choices and base prices; bans repair affected slots.
func get_or_create_offer(poi: PoiInstance) -> Dictionary:
	var offer: Dictionary = _get_cached_offer(poi)
	if offer.is_empty() or int(offer.get("run_generation", -1)) != RunState.get_run_generation():
		offer = _generate_offer(poi)
	else:
		offer = _repair_blacklisted_slots(poi, offer)
	_store_offer(poi, offer)
	_last_offer_debug = (offer.get("debug", {}) as Dictionary).duplicate(true)
	return offer.duplicate(true)

## Does not consume a use or random numbers. Prices/order alone are not a refresh.
func can_refresh_stock(poi: PoiInstance) -> bool:
	var offer: Dictionary = _get_cached_offer(poi)
	if offer.is_empty() or int(offer.get("run_generation", -1)) != RunState.get_run_generation():
		return false
	var old_ids: Dictionary = _upgrade_ids(offer.get("upgrades", []))
	for upgrade: Upgrade in _build_upgrade_pool_for_poi(poi):
		if not old_ids.has(_upgrade_id(upgrade)):
			return true
	return false

## Prefer every possible fresh choice, filling with current stock only as needed.
## The weapon offer is not part of this operation.
func refresh_stock(poi: PoiInstance) -> bool:
	if RunState.get_refresh_stock_remaining() <= 0:
		return false
	var offer: Dictionary = get_or_create_offer(poi)
	if not can_refresh_stock(poi):
		return false
	var old_ids: Dictionary = _upgrade_ids(offer.get("upgrades", []))
	var fresh: Array[Upgrade] = []
	var repeated: Array[Upgrade] = []
	for upgrade: Upgrade in _build_upgrade_pool_for_poi(poi):
		if old_ids.has(_upgrade_id(upgrade)):
			repeated.append(upgrade)
		else:
			fresh.append(upgrade)
	_last_offer_debug.clear()
	var count: int = _get_upgrade_choice_count_for_poi(poi)
	var choices: Array[Upgrade] = _pick_weighted_upgrade_choices(fresh, count, poi)
	if choices.size() < count:
		choices.append_array(_pick_weighted_upgrade_choices(repeated, count - choices.size(), poi))
	var has_fresh_choice: bool = false
	for upgrade: Upgrade in choices:
		if not old_ids.has(_upgrade_id(upgrade)):
			has_fresh_choice = true
			break
	if not has_fresh_choice:
		return false
	var replacement: Dictionary = _make_offer(choices, offer.get("weapon") as WeaponDef, _costs_by_id(offer))
	# Store first so synchronous counter/UI listeners observe the committed stock.
	_store_offer(poi, replacement)
	if not RunState.try_use_refresh_stock():
		_store_offer(poi, offer)
		return false
	return true

## Excludes the whole family for this run, including future POIs and every tier.
## Previously purchased upgrades are never removed or refunded.
func blacklist_upgrade(poi: PoiInstance, upgrade: Upgrade) -> bool:
	if not _is_eligible_upgrade(upgrade) or RunState.get_blacklist_remaining() <= 0:
		return false
	var offer: Dictionary = get_or_create_offer(poi)
	if not _upgrade_ids(offer.get("upgrades", [])).has(_upgrade_id(upgrade)):
		return false
	if not RunState.try_blacklist_upgrade_family(_get_upgrade_family(upgrade)):
		return false
	# A synchronous listener may already have repaired this stock. Repairing again
	# leaves unaffected choices/prices alone and never grants another free roll.
	offer = _repair_blacklisted_slots(poi, _get_cached_offer(poi))
	_store_offer(poi, offer)
	return true

func get_last_offer_debug() -> Dictionary:
	return _last_offer_debug.duplicate(true)

func get_upgrade_family(upgrade: Upgrade) -> String:
	return _get_upgrade_family(upgrade)

func _get_cached_offer(poi: PoiInstance) -> Dictionary:
	return poi.upgrade_offer if is_instance_valid(poi) else _transient_offer

func _store_offer(poi: PoiInstance, offer: Dictionary) -> void:
	if is_instance_valid(poi):
		poi.upgrade_offer = offer
	else:
		_transient_offer = offer
	_last_offer_debug = (offer.get("debug", {}) as Dictionary).duplicate(true)

func _generate_offer(poi: PoiInstance) -> Dictionary:
	_last_offer_debug.clear()
	var candidates: Array[Upgrade] = _build_upgrade_pool_for_poi(poi)
	var choices: Array[Upgrade] = _pick_weighted_upgrade_choices(candidates, _get_upgrade_choice_count_for_poi(poi), poi)
	var weapon: WeaponDef = null
	var weapons: Array[WeaponDef] = []
	for candidate: WeaponDef in available_weapons:
		if candidate != null:
			weapons.append(candidate)
	if not weapons.is_empty():
		weapons.shuffle()
		weapon = weapons[0]
	return _make_offer(choices, weapon)

func _make_offer(choices: Array[Upgrade], weapon: WeaponDef, existing_costs: Dictionary = {}) -> Dictionary:
	var costs: Array[int] = []
	for upgrade: Upgrade in choices:
		var id: String = _upgrade_id(upgrade)
		costs.append(int(existing_costs[id]) if existing_costs.has(id) else _roll_upgrade_offer_cost(upgrade))
	_upgrade_choices = choices
	_append_offer_debug_choices()
	return {
		"upgrades": choices.duplicate(),
		"costs": costs,
		"weapon": weapon,
		"debug": _last_offer_debug.duplicate(true),
		"run_generation": RunState.get_run_generation(),
	}

func _repair_blacklisted_slots(poi: PoiInstance, offer: Dictionary) -> Dictionary:
	var original: Array = offer.get("upgrades", [])
	var removed: int = 0
	var retained_ids: Dictionary = {}
	for upgrade: Upgrade in original:
		if _is_eligible_upgrade(upgrade):
			retained_ids[_upgrade_id(upgrade)] = true
		else:
			removed += 1
	if removed == 0:
		return offer
	var candidates: Array[Upgrade] = []
	for upgrade: Upgrade in _build_upgrade_pool_for_poi(poi):
		if not retained_ids.has(_upgrade_id(upgrade)):
			candidates.append(upgrade)
	_last_offer_debug.clear()
	var replacements: Array[Upgrade] = _pick_weighted_upgrade_choices(candidates, removed, poi)
	var result: Array[Upgrade] = []
	var replacement_index: int = 0
	for upgrade: Upgrade in original:
		if _is_eligible_upgrade(upgrade):
			result.append(upgrade)
		elif replacement_index < replacements.size():
			result.append(replacements[replacement_index])
			replacement_index += 1
	return _make_offer(result, offer.get("weapon") as WeaponDef, _costs_by_id(offer))

func _costs_by_id(offer: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var choices: Array = offer.get("upgrades", [])
	var costs: Array = offer.get("costs", [])
	for index: int in range(mini(choices.size(), costs.size())):
		var upgrade: Upgrade = choices[index] as Upgrade
		if upgrade != null:
			result[_upgrade_id(upgrade)] = int(costs[index])
	return result

func _upgrade_ids(choices: Array) -> Dictionary:
	var result: Dictionary = {}
	for upgrade: Upgrade in choices:
		if upgrade != null:
			result[_upgrade_id(upgrade)] = true
	return result

func _upgrade_id(upgrade: Upgrade) -> String:
	return upgrade.id.strip_edges().to_lower() if upgrade != null else ""

func _is_eligible_upgrade(upgrade: Upgrade) -> bool:
	return upgrade != null and not _upgrade_id(upgrade).is_empty() and not RunState.is_upgrade_family_blacklisted(_get_upgrade_family(upgrade))

func _pick_weighted_upgrade_choices(pool: Array[Upgrade], count: int, poi: PoiInstance) -> Array[Upgrade]:
	var results: Array[Upgrade] = []
	if pool.is_empty() or count <= 0:
		return results

	var remaining: Array[Upgrade] = []
	var seen_ids: Dictionary = {}
	for upgrade: Upgrade in pool:
		if not _is_eligible_upgrade(upgrade) or seen_ids.has(_upgrade_id(upgrade)):
			continue
		seen_ids[_upgrade_id(upgrade)] = true
		remaining.append(upgrade)
	var context: Dictionary = _build_upgrade_context(poi)
	var desired: int = mini(count, remaining.size())

	while results.size() < desired and not remaining.is_empty():
		var family_weight_data: Dictionary = _build_family_weight_data(remaining, context)
		context["family_multipliers"] = family_weight_data.get("family_multipliers", {})
		if _last_offer_debug.is_empty():
			_last_offer_debug = family_weight_data.get("debug", {}).duplicate(true)
		var total_weight: float = 0.0
		var weights: Array[float] = []
		for upgrade: Upgrade in remaining:
			var weight: float = max(_get_upgrade_offer_weight(upgrade, context), 0.0)
			weights.append(weight)
			total_weight += weight

		if total_weight <= 0.0:
			break

		var pick: float = randf() * total_weight
		var accum: float = 0.0
		var picked_index: int = max(weights.size() - 1, 0)
		for i in weights.size():
			accum += weights[i]
			if pick <= accum:
				picked_index = i
				break

		results.append(remaining[picked_index])
		remaining.remove_at(picked_index)

	return results


func _build_upgrade_context(poi: PoiInstance) -> Dictionary:
	var purchased_ids: Array[String] = []
	if RunState.has_method("get_purchased_upgrade_ids"):
		purchased_ids = RunState.get_purchased_upgrade_ids()

	var counts_by_id: Dictionary = {}
	var highest_tier_by_family: Dictionary = {}
	for raw_id: String in purchased_ids:
		var id: String = raw_id.strip_edges().to_lower()
		if id == "":
			continue
		counts_by_id[id] = int(counts_by_id.get(id, 0)) + 1

		var family: String = _extract_upgrade_family_from_id(id)
		var tier: int = _extract_tier_from_id(id)
		var best_tier: int = int(highest_tier_by_family.get(family, 0))
		if tier > best_tier:
			highest_tier_by_family[family] = tier

	var wave_index: int = 1
	if RunState.has_method("get_progression_wave_index"):
		wave_index = max(1, int(RunState.get_progression_wave_index()))
	elif RunState.has_method("get_wave_index"):
		wave_index = max(1, int(RunState.get_wave_index()))
	var wave_progress: float = clamp(float(wave_index - 1) / TIER_PROGRESS_WAVE_SPAN, 0.0, 1.0)
	var poi_type: int = _get_poi_type(poi)
	var poi_purchase_memory: Dictionary = {}
	if RunState.has_method("get_upgrade_purchase_memory_for_poi_type"):
		poi_purchase_memory = RunState.get_upgrade_purchase_memory_for_poi_type(poi_type)

	return {
		"counts_by_id": counts_by_id,
		"highest_tier_by_family": highest_tier_by_family,
		"wave_progress": wave_progress,
		"wave_index": wave_index,
		"poi_type": poi_type,
		"poi_purchase_memory": poi_purchase_memory,
		"stickiness_intensity": _compute_offer_memory_intensity(wave_index),
		"family_multipliers": {},
	}


func _get_upgrade_offer_weight(upgrade: Upgrade, context: Dictionary) -> float:
	var weight: float = _get_base_upgrade_offer_weight(upgrade, context)
	if upgrade == null:
		return weight
	var family: String = _get_upgrade_family(upgrade)
	var family_multipliers: Dictionary = context.get("family_multipliers", {})
	weight *= float(family_multipliers.get(family, 1.0))
	return max(weight, 0.0)


func _get_base_upgrade_offer_weight(upgrade: Upgrade, context: Dictionary) -> float:
	if upgrade == null:
		return 0.0

	var id: String = upgrade.id.strip_edges().to_lower()
	var tier: int = _get_upgrade_tier(upgrade)
	var family: String = _get_upgrade_family(upgrade)

	var counts_by_id: Dictionary = context.get("counts_by_id", {})
	var highest_tier_by_family: Dictionary = context.get("highest_tier_by_family", {})
	var wave_progress: float = float(context.get("wave_progress", 0.0))

	var weight: float = 1.0
	if tier <= 1:
		weight *= lerp(1.85, 0.65, wave_progress)
	elif tier == 2:
		weight *= lerp(0.70, 1.55, wave_progress)
	else:
		weight *= lerp(0.40, 1.80, wave_progress)

	var owned_same_count: int = int(counts_by_id.get(id, 0))
	if owned_same_count > 0:
		weight *= pow(0.35, owned_same_count)

	var highest_family_tier: int = int(highest_tier_by_family.get(family, 0))
	if highest_family_tier > 0:
		if tier == highest_family_tier + 1:
			weight *= 1.85
		elif tier <= highest_family_tier:
			weight *= 0.55
		else:
			weight *= 0.8
	elif tier > 1:
		weight *= lerp(0.55, 1.15, wave_progress)

	return max(weight, 0.0)


func _build_family_weight_data(pool: Array[Upgrade], context: Dictionary) -> Dictionary:
	var family_base_weights: Dictionary = {}
	var family_highest_candidate_tier: Dictionary = {}
	var family_has_repeat_candidates: Dictionary = {}
	var family_has_next_tier_candidates: Dictionary = {}
	var highest_tier_by_family: Dictionary = context.get("highest_tier_by_family", {})
	var poi_purchase_memory: Dictionary = context.get("poi_purchase_memory", {})
	var purchased_family_counts: Dictionary = poi_purchase_memory.get("counts_by_family", {})
	var intensity: float = float(context.get("stickiness_intensity", 0.0))

	for upgrade: Upgrade in pool:
		if upgrade == null:
			continue
		var family: String = _get_upgrade_family(upgrade)
		var tier: int = _get_upgrade_tier(upgrade)
		var base_weight: float = _get_base_upgrade_offer_weight(upgrade, context)
		family_base_weights[family] = float(family_base_weights.get(family, 0.0)) + base_weight
		family_highest_candidate_tier[family] = max(int(family_highest_candidate_tier.get(family, 0)), tier)
		var highest_owned_tier: int = int(highest_tier_by_family.get(family, 0))
		if highest_owned_tier > 0:
			if tier == highest_owned_tier + 1:
				family_has_next_tier_candidates[family] = true
			elif tier <= highest_owned_tier:
				family_has_repeat_candidates[family] = true

	var adjusted_family_weights: Dictionary = {}
	var family_multipliers: Dictionary = {}
	var debug_family_weights: Dictionary = {}
	var purchased_total: float = 0.0
	var unpurchased_total: float = 0.0

	for family_variant in family_base_weights.keys():
		var family: String = String(family_variant)
		var base_family_weight: float = float(family_base_weights.get(family, 0.0))
		var raw_multiplier: float = 1.0
		var purchase_count: int = int(purchased_family_counts.get(family, 0))
		var is_purchased: bool = purchase_count > 0
		if is_purchased and offer_memory_def != null:
			raw_multiplier += intensity * offer_memory_def.owned_family_base_bonus
			raw_multiplier += intensity * float(purchase_count) * offer_memory_def.owned_family_count_bonus
			if bool(family_has_repeat_candidates.get(family, false)):
				raw_multiplier += intensity * offer_memory_def.same_family_repeat_bonus
			if bool(family_has_next_tier_candidates.get(family, false)):
				raw_multiplier += intensity * offer_memory_def.same_family_next_tier_bonus

		var adjusted_weight: float = base_family_weight * max(raw_multiplier, 0.0)
		adjusted_family_weights[family] = adjusted_weight
		if is_purchased:
			purchased_total += adjusted_weight
		else:
			unpurchased_total += adjusted_weight

		debug_family_weights[family] = {
			"base_weight": base_family_weight,
			"raw_multiplier": raw_multiplier,
			"raw_weight": adjusted_weight,
			"purchase_count": purchase_count,
			"is_purchased": is_purchased,
			"has_repeat_candidate": bool(family_has_repeat_candidates.get(family, false)),
			"has_next_tier_candidate": bool(family_has_next_tier_candidates.get(family, false)),
			"highest_candidate_tier": int(family_highest_candidate_tier.get(family, 0)),
			"highest_owned_tier": int(highest_tier_by_family.get(family, 0)),
		}

	var purchased_scale: float = 1.0
	var unpurchased_scale: float = 1.0
	var total_weight: float = purchased_total + unpurchased_total
	if total_weight > 0.0 and purchased_total > 0.0 and unpurchased_total > 0.0 and offer_memory_def != null:
		var max_purchased_share: float = clamp(offer_memory_def.purchased_family_share_cap, 0.0, 1.0)
		var min_unpurchased_share: float = clamp(offer_memory_def.non_purchased_family_share_floor, 0.0, 1.0)
		max_purchased_share = min(max_purchased_share, 1.0 - min_unpurchased_share)

		var current_purchased_share: float = purchased_total / total_weight
		if current_purchased_share > max_purchased_share and current_purchased_share > 0.0:
			purchased_scale = max_purchased_share / current_purchased_share
			var current_unpurchased_share: float = unpurchased_total / total_weight
			var target_unpurchased_share: float = 1.0 - max_purchased_share
			if current_unpurchased_share > 0.0:
				unpurchased_scale = target_unpurchased_share / current_unpurchased_share

	for family_variant in adjusted_family_weights.keys():
		var family: String = String(family_variant)
		var base_family_weight: float = float(family_base_weights.get(family, 0.0))
		var family_debug: Dictionary = debug_family_weights.get(family, {})
		var is_purchased: bool = bool(family_debug.get("is_purchased", false))
		var capped_weight: float = float(adjusted_family_weights.get(family, 0.0))
		capped_weight *= purchased_scale if is_purchased else unpurchased_scale
		family_multipliers[family] = (capped_weight / base_family_weight) if base_family_weight > 0.0 else 1.0
		family_debug["capped_weight"] = capped_weight
		family_debug["final_multiplier"] = family_multipliers[family]
		debug_family_weights[family] = family_debug

	return {
		"family_multipliers": family_multipliers,
		"debug": {
			"poi_type": _get_poi_type_label(int(context.get("poi_type", PoiDef.PoiType.OFFENSE))),
			"stickiness_intensity": intensity,
			"purchased_families": PackedStringArray(poi_purchase_memory.get("families", PackedStringArray())),
			"purchase_counts_by_family": purchased_family_counts.duplicate(true),
			"family_weights": debug_family_weights,
			"purchased_family_share_cap": offer_memory_def.purchased_family_share_cap if offer_memory_def != null else 1.0,
			"non_purchased_family_share_floor": offer_memory_def.non_purchased_family_share_floor if offer_memory_def != null else 0.0,
		},
	}


func _extract_tier_from_id(raw_id: String) -> int:
	var id: String = raw_id.strip_edges().to_lower()
	if id == "":
		return 1
	var parts: PackedStringArray = id.split("_")
	if parts.is_empty():
		return 1
	var suffix: String = parts[parts.size() - 1]
	if suffix.is_valid_int():
		return max(suffix.to_int(), 1)
	return 1


func _extract_upgrade_family_from_id(raw_id: String) -> String:
	var id: String = raw_id.strip_edges().to_lower()
	if id == "":
		return "unknown"
	var parts: PackedStringArray = id.split("_")
	if parts.size() <= 1:
		return id
	var suffix: String = parts[parts.size() - 1]
	if not suffix.is_valid_int():
		return id
	parts.remove_at(parts.size() - 1)
	if parts.is_empty():
		return id
	return "_".join(parts)


func _get_upgrade_tier(upgrade: Upgrade) -> int:
	if upgrade == null:
		return 1
	var tier: int = max(upgrade.tier, 1)
	var id_tier: int = _extract_tier_from_id(upgrade.id)
	if id_tier > tier:
		tier = id_tier
	return tier


func _get_upgrade_family(upgrade: Upgrade) -> String:
	if upgrade == null:
		return "unknown"
	var explicit_family: String = upgrade.family_id.strip_edges().to_lower()
	if explicit_family != "":
		return explicit_family
	return _extract_upgrade_family_from_id(upgrade.id)


func _roll_upgrade_offer_cost(upgrade: Upgrade) -> int:
	if upgrade == null:
		return 1
	var base_cost: int = max(upgrade.cost, 1)
	var variance: float = randf_range(1.0 - UPGRADE_COST_VARIANCE, 1.0 + UPGRADE_COST_VARIANCE)
	return max(int(round(float(base_cost) * variance)), 1)


func _build_upgrade_pool_for_poi(poi: PoiInstance) -> Array[Upgrade]:
	var filtered: Array[Upgrade] = []
	var fallback: Array[Upgrade] = []
	var poi_tags: Array[String] = _get_poi_upgrade_tags(poi)
	var seen_ids: Dictionary = {}

	for upgrade: Upgrade in available_upgrades:
		if not _is_eligible_upgrade(upgrade) or seen_ids.has(_upgrade_id(upgrade)):
			continue
		seen_ids[_upgrade_id(upgrade)] = true
		if poi_tags.is_empty():
			filtered.append(upgrade)
			continue

		var upgrade_tags: Array[String] = _get_upgrade_tags(upgrade)
		if _tags_overlap(upgrade_tags, poi_tags):
			filtered.append(upgrade)
		else:
			fallback.append(upgrade)

	if filtered.is_empty():
		return fallback

	var desired: int = _get_upgrade_choice_count_for_poi(poi)
	if filtered.size() < desired:
		for upgrade: Upgrade in fallback:
			if not filtered.has(upgrade):
				filtered.append(upgrade)

	return filtered


func _get_upgrade_choice_count_for_poi(poi: PoiInstance) -> int:
	var default_count: int = max(num_upgrade_choices, 1)
	if poi == null or poi.poi_def == null:
		return default_count
	return max(1, poi.poi_def.upgrade_choices)


func _get_poi_upgrade_tags(poi: PoiInstance) -> Array[String]:
	var tags: Array[String] = []
	if poi == null or poi.poi_def == null:
		return tags

	for raw_tag: String in poi.poi_def.upgrade_tags:
		_append_normalized_tag(tags, raw_tag)

	return tags


func _get_upgrade_tags(upgrade: Upgrade) -> Array[String]:
	var tags: Array[String] = []
	if upgrade == null:
		return tags

	for raw_tag: String in upgrade.tags:
		_append_normalized_tag(tags, raw_tag)
	if not tags.is_empty():
		return tags

	var id: String = upgrade.id.to_lower()
	if "bulkhead" in id or "hull" in id:
		_append_normalized_tag(tags, "defense")
		_append_normalized_tag(tags, "hull")
	if "shield" in id:
		_append_normalized_tag(tags, "defense")
		_append_normalized_tag(tags, "shields")
	if "targeting" in id or "precision" in id or "capacitor" in id or "weapon" in id or "damage" in id:
		_append_normalized_tag(tags, "offense")
		_append_normalized_tag(tags, "weapons")
		_append_normalized_tag(tags, "damage")
	if "systems" in id:
		_append_normalized_tag(tags, "utility")
		_append_normalized_tag(tags, "misc")
	if "salvage" in id or "magnet" in id:
		_append_normalized_tag(tags, "utility")
		_append_normalized_tag(tags, "misc")
	if "thruster" in id or "vectoring" in id:
		_append_normalized_tag(tags, "utility")
		_append_normalized_tag(tags, "misc")

	return tags


func _append_normalized_tag(target: Array[String], raw_tag: String) -> void:
	var normalized: String = raw_tag.strip_edges().to_lower()
	if normalized == "" or target.has(normalized):
		return
	target.append(normalized)


func _tags_overlap(left: Array[String], right: Array[String]) -> bool:
	if left.is_empty() or right.is_empty():
		return false

	for tag: String in left:
		if right.has(tag):
			return true
	return false


func _append_offer_debug_choices() -> void:
	if _last_offer_debug.is_empty():
		return
	var family_weights: Dictionary = _last_offer_debug.get("family_weights", {})
	var offered_upgrades: Array[Dictionary] = []
	for upgrade: Upgrade in _upgrade_choices:
		if upgrade == null:
			continue
		var family: String = _get_upgrade_family(upgrade)
		var family_entry: Dictionary = family_weights.get(family, {})
		offered_upgrades.append({
			"id": upgrade.id,
			"family": family,
			"tier": _get_upgrade_tier(upgrade),
			"final_family_multiplier": float(family_entry.get("final_multiplier", 1.0)),
		})
	_last_offer_debug["offered_upgrades"] = offered_upgrades

func _compute_offer_memory_intensity(wave_index: int) -> float:
	if offer_memory_def == null:
		return 0.0
	var wave_progress: float = float(max(wave_index - offer_memory_def.start_wave, 0))
	var intensity: float = (
		wave_progress * offer_memory_def.per_wave_linear +
		wave_progress * wave_progress * offer_memory_def.per_wave_quadratic
	)
	if offer_memory_def.intensity_cap > 0.0:
		intensity = min(intensity, offer_memory_def.intensity_cap)
	return max(intensity, 0.0)

func _get_poi_type(poi: PoiInstance) -> int:
	if poi == null or poi.poi_def == null:
		return PoiDef.PoiType.OFFENSE
	return int(poi.poi_def.poi_type)

func _get_poi_type_label(poi_type: int) -> String:
	match poi_type:
		PoiDef.PoiType.DEFENSE:
			return "DEFENSE"
		PoiDef.PoiType.UTILITY:
			return "UTILITY"
	return "OFFENSE"
