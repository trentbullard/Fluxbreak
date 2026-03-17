extends Node
class_name BudgetBuyer

@export var enemy_catalog_path: NodePath
@export var target_catalog_path: NodePath
@export var recent_primary_memory: int = 3
@export_range(0.1, 1.0, 0.01) var secondary_share_fallback: float = 0.25
@export_range(0.1, 1.0, 0.01) var support_share_fallback: float = 0.15

var _ec: EnemyCatalog
var _tc: TargetCatalog
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _recent_primary_enemy_ids: Array[String] = []
var _last_wave_plan: Dictionary = {}

func _ready() -> void:
	_ec = get_node_or_null(enemy_catalog_path) as EnemyCatalog
	_tc = get_node_or_null(target_catalog_path) as TargetCatalog
	_rng.randomize()

func clear_history() -> void:
	_recent_primary_enemy_ids.clear()
	_last_wave_plan.clear()

func get_last_wave_plan() -> Dictionary:
	return _last_wave_plan.duplicate(true)

func buy_wave(enemy_points: int, target_points: int, card: WaveCard, max_enemy_tier: int) -> Array[SpawnRequest]:
	var reqs: Array[SpawnRequest] = []
	var safe_card: WaveCard = card if card != null else WaveCard.new()
	_last_wave_plan = {
		"card_id": String(safe_card.get_card_id()),
		"card_name": safe_card.get_display_name_or_default(),
		"enemy_points": max(enemy_points, 0),
		"target_points": max(target_points, 0),
		"primary_enemy_id": "",
		"packages": [],
		"targets": [],
	}

	if _ec != null and enemy_points > 0:
		_build_enemy_requests(reqs, max(enemy_points, 0), safe_card, max_enemy_tier)
	if _tc != null and target_points > 0:
		_build_target_requests(reqs, max(target_points, 0), safe_card)

	return reqs

func _build_enemy_requests(reqs: Array[SpawnRequest], enemy_points: int, card: WaveCard, max_enemy_tier: int) -> void:
	var e_pool: Array[EnemyDef] = _ec.get_pool(card.faction_bias, "", max_enemy_tier)
	if e_pool.is_empty():
		return

	var role_biases: Array[String] = card.get_role_biases()
	if role_biases.is_empty():
		role_biases = _ec.get_unique_roles(card.faction_bias, max_enemy_tier)
	if role_biases.is_empty():
		role_biases.append("")

	var primary_role: String = role_biases[0]
	var secondary_role: String = role_biases[1] if role_biases.size() > 1 else ""
	var support_role: String = role_biases[2] if role_biases.size() > 2 else ""

	var primary_pool: Array[EnemyDef] = _resolve_role_pool(e_pool, primary_role)
	var primary_pick: EnemyDef = _pick_enemy_for_package(
		primary_pool,
		enemy_points,
		enemy_points,
		card,
		{},
		_recent_primary_enemy_ids,
		true
	)
	if primary_pick == null:
		primary_pick = _pick_enemy_for_package(e_pool, enemy_points, enemy_points, card, {}, [], true)
	if primary_pick == null:
		return

	_last_wave_plan["primary_enemy_id"] = primary_pick.id
	_remember_primary_enemy(primary_pick.id)

	var shares: Array[float] = card.get_budget_shares()
	var primary_budget: int = max(int(round(float(enemy_points) * shares[0])), primary_pick.threat_cost)
	var secondary_budget: int = int(round(float(enemy_points) * shares[1]))
	var support_budget: int = int(round(float(enemy_points) * shares[2]))

	if secondary_role == "":
		secondary_budget = int(round(float(enemy_points) * secondary_share_fallback))
	if support_role == "":
		support_budget = int(round(float(enemy_points) * support_share_fallback))

	if primary_pick.threat_cost >= max(card.anchor_support_cost_threshold, 1):
		support_budget = max(support_budget, min(primary_pick.threat_cost / 2, enemy_points))

	var reserved_budget: int = primary_budget + secondary_budget + support_budget
	var flex_budget: int = max(enemy_points - reserved_budget, 0)

	var desired_packages: int = clampi(
		2 + int(enemy_points / 12),
		max(card.package_count_min, 1),
		max(card.package_count_max, card.package_count_min)
	)

	var packages: Array[Dictionary] = []
	packages.append({"label": "primary", "role": primary_role, "budget": primary_budget, "leader": primary_pick})
	if secondary_budget > 0:
		packages.append({"label": "secondary", "role": secondary_role, "budget": secondary_budget})
	if support_budget > 0:
		packages.append({"label": "support", "role": support_role, "budget": support_budget})

	while packages.size() < desired_packages and flex_budget > 0:
		var role_index: int = packages.size() % max(role_biases.size(), 1)
		var flex_role: String = role_biases[role_index] if role_biases.size() > 0 else ""
		var remaining_slots: int = desired_packages - packages.size()
		var split_budget: int = max(int(round(float(flex_budget) / float(max(remaining_slots, 1)))), 1)
		packages.append({"label": "flex_%d" % packages.size(), "role": flex_role, "budget": split_budget})
		flex_budget = max(flex_budget - split_budget, 0)

	if flex_budget > 0:
		packages[0]["budget"] = int(packages[0].get("budget", 0)) + flex_budget

	var spent_by_id: Dictionary = {}
	for package in packages:
		var package_label: String = String(package.get("label", "package"))
		var package_role: String = String(package.get("role", ""))
		var package_budget: int = max(int(package.get("budget", 0)), 0)
		var leader: EnemyDef = package.get("leader", null) as EnemyDef
		if package_budget <= 0:
			continue

		var package_debug: Dictionary = {
			"label": package_label,
			"role": package_role,
			"budget": package_budget,
			"units": [],
		}
		var package_pool: Array[EnemyDef] = _resolve_role_pool(e_pool, package_role)
		var points_left: int = package_budget
		var max_picks: int = 1 if package_label == "support" else 2

		if leader != null:
			var leader_copies: int = _determine_copies_for_pick(
				leader,
				points_left,
				enemy_points,
				spent_by_id,
				card,
				package_label == "primary"
			)
			if leader_copies > 0:
				_append_enemy_request(reqs, leader, leader_copies, card)
				var leader_points: int = leader_copies * leader.threat_cost
				points_left = max(points_left - leader_points, 0)
				spent_by_id[leader.id] = int(spent_by_id.get(leader.id, 0)) + leader_points
				var units: Array = package_debug.get("units", [])
				units.append("%s x%d" % [_enemy_display_name(leader), leader_copies])
				package_debug["units"] = units
			max_picks -= 1

		var blocked_ids: Dictionary = {}
		if leader != null and not card.allow_swarm_primary:
			blocked_ids[leader.id] = true

		while points_left > 0 and max_picks > 0:
			var pick: EnemyDef = _pick_enemy_for_package(
				package_pool,
				points_left,
				enemy_points,
				card,
				spent_by_id,
				_dictionary_keys_to_array(blocked_ids),
				false
			)
			if pick == null:
				break
			var copies: int = _determine_copies_for_pick(
				pick,
				points_left,
				enemy_points,
				spent_by_id,
				card,
				package_label == "primary"
			)
			if copies <= 0:
				blocked_ids[pick.id] = true
				max_picks -= 1
				continue
			_append_enemy_request(reqs, pick, copies, card)
			var spent_points: int = copies * pick.threat_cost
			points_left = max(points_left - spent_points, 0)
			spent_by_id[pick.id] = int(spent_by_id.get(pick.id, 0)) + spent_points
			var package_units: Array = package_debug.get("units", [])
			package_units.append("%s x%d" % [_enemy_display_name(pick), copies])
			package_debug["units"] = package_units
			blocked_ids[pick.id] = true
			max_picks -= 1

		var debug_packages: Array = _last_wave_plan["packages"]
		debug_packages.append(package_debug)
		_last_wave_plan["packages"] = debug_packages

func _build_target_requests(reqs: Array[SpawnRequest], target_points: int, card: WaveCard) -> void:
	var t_pool: Array[TargetDef] = _tc.get_pool(max(card.target_size_band_max, 0))
	if t_pool.is_empty():
		t_pool = _tc.get_pool(0)
	if t_pool.is_empty():
		return

	var points_left: int = target_points
	var picks: int = 0
	while points_left > 0 and picks < 2:
		var pick: TargetDef = _pick_target_for_budget(t_pool, points_left)
		if pick == null:
			break
		var copies: int = max(1, points_left / max(pick.threat_cost, 1))
		if pick.size_band > 1:
			copies = 1
		var req: SpawnRequest = SpawnRequest.new()
		req.kind = "Target"
		req.target_def = pick
		req.count = copies
		req.batch_size_min = card.batch_size_min
		req.batch_size_max = card.batch_size_max
		req.inter_batch_sec = card.inter_batch_sec
		reqs.append(req)

		points_left = max(points_left - copies * pick.threat_cost, 0)
		var target_debug: Array = _last_wave_plan["targets"]
		target_debug.append("%s x%d" % [_target_display_name(pick), copies])
		_last_wave_plan["targets"] = target_debug
		picks += 1

func _resolve_role_pool(pool: Array[EnemyDef], role: String) -> Array[EnemyDef]:
	var trimmed_role: String = role.strip_edges()
	if trimmed_role == "":
		return pool.duplicate()
	var out: Array[EnemyDef] = []
	for entry in pool:
		if entry != null and entry.role == trimmed_role:
			out.append(entry)
	if out.is_empty():
		return pool.duplicate()
	return out

func _pick_enemy_for_package(
	pool: Array[EnemyDef],
	package_budget: int,
	total_enemy_points: int,
	card: WaveCard,
	spent_by_id: Dictionary,
	blocked_ids: Array[String],
	prefer_anchor: bool
) -> EnemyDef:
	var affordable: Array[EnemyDef] = _ec.get_affordable_pool(pool, max(package_budget, 1))
	if affordable.is_empty():
		return null

	var candidates: Array[EnemyDef] = []
	for entry in affordable:
		if entry == null:
			continue
		if blocked_ids.has(entry.id):
			continue
		if not _can_spend_more_on_enemy(entry, total_enemy_points, spent_by_id, card):
			continue
		candidates.append(entry)

	if candidates.is_empty():
		for entry in affordable:
			if entry != null and not blocked_ids.has(entry.id):
				candidates.append(entry)
	if candidates.is_empty():
		return null

	var total_weight: float = 0.0
	var candidate_weights: Array[float] = []
	for entry in candidates:
		var fit_ratio: float = float(entry.threat_cost) / float(max(package_budget, 1))
		var fit_score: float = max(1.0 - abs(1.0 - fit_ratio), 0.0)
		var weight: float = 0.25 + fit_score * 0.85 + float(entry.tier) * 0.06
		if prefer_anchor and entry.threat_cost >= 4:
			weight += 0.20
		if _recent_primary_enemy_ids.has(entry.id):
			weight *= 0.45
		var spent_share: float = float(int(spent_by_id.get(entry.id, 0))) / float(max(total_enemy_points, 1))
		weight *= clamp(1.0 - spent_share, 0.30, 1.0)
		candidate_weights.append(weight)
		total_weight += weight

	if total_weight <= 0.0:
		return candidates[0]

	var roll: float = _rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for index in candidates.size():
		cursor += candidate_weights[index]
		if roll <= cursor:
			return candidates[index]
	return candidates[candidates.size() - 1]

func _pick_target_for_budget(pool: Array[TargetDef], budget: int) -> TargetDef:
	var affordable: Array[TargetDef] = _tc.get_affordable_pool(pool, max(budget, 1))
	if affordable.is_empty():
		return null
	var total_weight: float = 0.0
	var weights: Array[float] = []
	for entry in affordable:
		var fit_ratio: float = float(entry.threat_cost) / float(max(budget, 1))
		var fit_score: float = max(1.0 - abs(1.0 - fit_ratio), 0.0)
		var weight: float = 0.25 + fit_score + float(entry.size_band) * 0.15
		weights.append(weight)
		total_weight += weight
	if total_weight <= 0.0:
		return affordable[0]

	var roll: float = _rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for index in affordable.size():
		cursor += weights[index]
		if roll <= cursor:
			return affordable[index]
	return affordable[affordable.size() - 1]

func _determine_copies_for_pick(
	pick: EnemyDef,
	budget: int,
	total_enemy_points: int,
	spent_by_id: Dictionary,
	card: WaveCard,
	primary_package: bool
) -> int:
	if pick == null:
		return 0
	var max_copies_from_budget: int = max(1, budget / max(pick.threat_cost, 1))
	var share_cap_points: int = total_enemy_points
	if not card.allow_swarm_primary:
		share_cap_points = max(int(round(float(total_enemy_points) * card.max_primary_budget_share)), pick.threat_cost)
	elif not primary_package:
		share_cap_points = max(int(round(float(total_enemy_points) * 0.65)), pick.threat_cost)

	var used_points: int = int(spent_by_id.get(pick.id, 0))
	var remaining_share_points: int = max(share_cap_points - used_points, 0)
	var max_copies_from_share: int = max(remaining_share_points / max(pick.threat_cost, 1), 0)
	if used_points == 0 and max_copies_from_share <= 0:
		max_copies_from_share = 1

	var copies: int = min(max_copies_from_budget, max(max_copies_from_share, 1))
	if not primary_package:
		copies = min(copies, 2)
	elif not card.allow_swarm_primary:
		copies = min(copies, max(1, int(ceil(float(max_copies_from_budget) * 0.6))))
	return max(copies, 0)

func _can_spend_more_on_enemy(entry: EnemyDef, total_enemy_points: int, spent_by_id: Dictionary, card: WaveCard) -> bool:
	if entry == null:
		return false
	if card.allow_swarm_primary:
		return true
	var limit_points: int = max(int(round(float(total_enemy_points) * card.max_primary_budget_share)), entry.threat_cost)
	var used_points: int = int(spent_by_id.get(entry.id, 0))
	return used_points + entry.threat_cost <= limit_points or used_points == 0

func _append_enemy_request(reqs: Array[SpawnRequest], pick: EnemyDef, copies: int, card: WaveCard) -> void:
	if pick == null or copies <= 0:
		return
	var req: SpawnRequest = SpawnRequest.new()
	req.kind = "Enemy"
	req.enemy_def = pick
	req.count = copies
	req.batch_size_min = card.batch_size_min
	req.batch_size_max = card.batch_size_max
	req.inter_batch_sec = card.inter_batch_sec
	reqs.append(req)

func _remember_primary_enemy(enemy_id: String) -> void:
	var trimmed: String = enemy_id.strip_edges()
	if trimmed == "":
		return
	_recent_primary_enemy_ids.append(trimmed)
	while _recent_primary_enemy_ids.size() > max(recent_primary_memory, 1):
		_recent_primary_enemy_ids.remove_at(0)

func _dictionary_keys_to_array(source: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in source.keys():
		out.append(String(key))
	return out

func _enemy_display_name(entry: EnemyDef) -> String:
	if entry == null:
		return "Enemy"
	var trimmed: String = entry.display_name.strip_edges()
	if trimmed != "":
		return trimmed
	return entry.id

func _target_display_name(entry: TargetDef) -> String:
	if entry == null:
		return "Target"
	var trimmed: String = entry.display_name.strip_edges()
	if trimmed != "":
		return trimmed
	return entry.id
