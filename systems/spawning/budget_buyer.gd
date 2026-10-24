extends Node
class_name BudgetBuyer

## Catalog containing the ordinary enemies available for card purchases.
@export var enemy_catalog_path: NodePath
## Catalog containing passive target purchases.
@export var target_catalog_path: NodePath
## Recent anchor choices avoided while another affordable anchor is available.
@export var recent_primary_memory: int = 3

var _ec: EnemyCatalog
var _tc: TargetCatalog
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _recent_primary_enemy_ids: Array[String] = []
var _last_wave_plan: Dictionary = {}
var _seed_configured: bool = false

func _ready() -> void:
	_ec = get_node_or_null(enemy_catalog_path) as EnemyCatalog
	_tc = get_node_or_null(target_catalog_path) as TargetCatalog
	if not _seed_configured:
		_rng.randomize()

func set_seed(value: int) -> void:
	_seed_configured = true
	_rng.seed = value

func clear_history() -> void:
	_recent_primary_enemy_ids.clear()
	_last_wave_plan.clear()

func get_last_wave_plan() -> Dictionary:
	return _last_wave_plan.duplicate(true)

func buy_wave(
	enemy_points: int,
	target_points: int,
	card: WaveCard,
	max_enemy_tier: int,
	wave_index: int = 0,
	stage_index: int = 0,
	elapsed_sec: float = 0.0
) -> Array[SpawnRequest]:
	var reqs: Array[SpawnRequest] = []
	var safe_card: WaveCard = card if card != null else WaveCard.new()
	_last_wave_plan = {
		"card_id": String(safe_card.get_card_id()),
		"card_name": safe_card.get_display_name_or_default(),
		"faction_bias_id": _faction_debug_id(safe_card.faction_bias),
		"enemy_points": max(enemy_points, 0),
		"enemy_points_spent": 0,
		"enemy_points_remainder": max(enemy_points, 0),
		"remainder_reason": "no_enemy_budget" if enemy_points <= 0 else "enemy_catalog_unavailable",
		"requested_formation_count": 0,
		"formation_count": 0,
		"capital_points_spent": 0,
		"capital_point_allowance": 0,
		"planned_enemy_units": 0,
		"target_points": max(target_points, 0),
		"primary_enemy_id": "",
		"packages": [],
		"targets": [],
	}

	if _ec != null and enemy_points > 0:
		_build_enemy_requests(reqs, max(enemy_points, 0), safe_card, max_enemy_tier, wave_index, stage_index, elapsed_sec)
	if _tc != null and target_points > 0:
		_build_target_requests(reqs, max(target_points, 0), safe_card)

	return reqs

func _build_enemy_requests(
	reqs: Array[SpawnRequest],
	enemy_points: int,
	card: WaveCard,
	max_enemy_tier: int,
	wave_index: int,
	stage_index: int,
	elapsed_sec: float
) -> void:
	var pool: Array[EnemyDef] = []
	for entry: EnemyDef in _ec.get_pool(card.faction_bias, null, max_enemy_tier):
		if entry != null and not entry is EnemyBossDef and entry.threat_cost > 0:
			pool.append(entry)
	var requested_count: int = clampi(
		2 + int(enemy_points / 12),
		maxi(card.package_count_min, 1),
		maxi(card.package_count_max, maxi(card.package_count_min, 1))
	)
	_last_wave_plan["requested_formation_count"] = requested_count
	if pool.is_empty():
		_last_wave_plan["remainder_reason"] = "no_eligible_enemies"
		return

	var roles: Array[EnemyRoleDef] = card.get_role_biases()
	if roles.is_empty():
		roles = _ec.get_unique_roles(card.faction_bias, max_enemy_tier)
	var primary_role: EnemyRoleDef = roles[0] if not roles.is_empty() else null
	var secondary_role: EnemyRoleDef = card.secondary_role_bias
	var support_role: EnemyRoleDef = card.support_role_bias
	var primary_pick: EnemyDef = _choose_primary(pool, primary_role, enemy_points, card)
	if primary_pick == null:
		_last_wave_plan["remainder_reason"] = "no_affordable_enemy"
		return
	_last_wave_plan["primary_enemy_id"] = primary_pick.id

	var shares: Array[float] = card.get_budget_shares()
	# One ledger owns the entire purchase. Role and formation slices are soft
	# allocation goals; their unspent points always return to this ledger.
	var ledger: Dictionary = {
		"remaining": enemy_points,
		"capital_spent": 0,
		"capital_allowance": int(floor(float(enemy_points) * shares[0])),
		"primary_count": 0,
		"chosen_primary_spent": 0,
		"chosen_primary_allowance": maxi(int(round(float(enemy_points) * card.max_primary_budget_share)), primary_pick.threat_cost),
		"spent_by_id": {},
		"units": 0,
	}
	var first_formation: Dictionary = _new_formation(0)
	_record_purchase(first_formation, primary_pick, _purchase_label(primary_pick, primary_role, secondary_role, support_role, card), ledger, primary_role, primary_pick, card)

	# Reserve a real affordable seed for each additional formation before
	# dividing the budget. A required expensive anchor cannot starve the others.
	var simulated_ledger: Dictionary = ledger.duplicate(true)
	var seeds: Array[EnemyDef] = []
	while seeds.size() + 1 < requested_count:
		var seed: EnemyDef = _cheapest_formation_seed(pool, roles, simulated_ledger, primary_role, primary_pick, card)
		if seed == null:
			break
		seeds.append(seed)
		_spend_points(seed, simulated_ledger, primary_role, primary_pick, card)
	var formations: Array[Dictionary] = [first_formation]
	for seed_index: int in seeds.size():
		var formation: Dictionary = _new_formation(seed_index + 1)
		var seed: EnemyDef = seeds[seed_index]
		_record_purchase(formation, seed, _purchase_label(seed, primary_role, secondary_role, support_role, card), ledger, primary_role, primary_pick, card)
		formations.append(formation)

	# Split the remaining allocation evenly after guaranteeing every group a
	# member. Each formation can contain all three authored purchasing roles.
	var flex_points: int = int(ledger["remaining"])
	var split: int = int(flex_points / formations.size())
	var extra: int = flex_points % formations.size()
	for formation_index: int in formations.size():
		var formation: Dictionary = formations[formation_index]
		formation["initial_budget"] = int(formation["spent_points"]) + split + (1 if formation_index < extra else 0)
		var formation_budget: int = int(formation["initial_budget"])
		_fill_role_budget(formation, pool, primary_role, "primary", int(round(float(formation_budget) * shares[0])), ledger, primary_role, primary_pick, card)
		_fill_role_budget(formation, pool, secondary_role, "secondary", int(round(float(formation_budget) * shares[1])), ledger, primary_role, primary_pick, card)
		_fill_role_budget(formation, pool, support_role, "support", int(round(float(formation_budget) * shares[2])), ledger, primary_role, primary_pick, card)

	# Recycle all role/formation leftovers. Prefer noncapital escorts in the
	# card's roles, then the faction's other escorts, before further capitals.
	var next_formation: int = 0
	while int(ledger["remaining"]) > 0:
		var recycle_pool: Array[EnemyDef] = _recycle_pool(pool, roles, ledger, primary_role, primary_pick, card)
		if recycle_pool.is_empty():
			break
		var pick: EnemyDef = _pick_weighted_enemy(recycle_pool, int(ledger["remaining"]), enemy_points, ledger["spent_by_id"], false)
		if pick == null:
			break
		var formation: Dictionary = formations[next_formation]
		_record_purchase(formation, pick, _purchase_label(pick, primary_role, secondary_role, support_role, card), ledger, primary_role, primary_pick, card)
		next_formation = (next_formation + 1) % formations.size()

	var debug_packages: Array = []
	for formation: Dictionary in formations:
		var purchased_units: Array = formation["purchases"]
		var debug_units: Array[String] = []
		for purchase: Dictionary in purchased_units:
			var pick: EnemyDef = purchase["enemy"] as EnemyDef
			var copies: int = int(purchase["count"])
			_append_enemy_request(reqs, pick, copies, card, wave_index, stage_index, elapsed_sec, String(formation["package_id"]), String(purchase["label"]), int(formation["spent_points"]))
			debug_units.append("%s x%d" % [_enemy_display_name(pick), copies])
		debug_packages.append({
			"package_id": formation["package_id"],
			"label": formation["label"],
			"role_id": _role_debug_id(primary_role),
			"budget": formation["spent_points"],
			"initial_budget": formation["initial_budget"],
			"spent_points": formation["spent_points"],
			"units": debug_units,
		})
	_last_wave_plan["packages"] = debug_packages
	_last_wave_plan["enemy_points_spent"] = enemy_points - int(ledger["remaining"])
	_last_wave_plan["enemy_points_remainder"] = int(ledger["remaining"])
	_last_wave_plan["remainder_reason"] = _remainder_reason(pool, ledger, primary_role, primary_pick, card)
	_last_wave_plan["formation_count"] = formations.size()
	_last_wave_plan["capital_points_spent"] = int(ledger["capital_spent"])
	_last_wave_plan["capital_point_allowance"] = int(ledger["capital_allowance"])
	_last_wave_plan["planned_enemy_units"] = int(ledger["units"])
	_remember_primary_enemy(primary_pick.id)

func _new_formation(index: int) -> Dictionary:
	return {
		"package_id": "pkg_%d_formation" % index,
		"label": "formation_%d" % (index + 1),
		"spent_points": 0,
		"role_spent": {},
		"purchases": [],
	}

func _choose_primary(pool: Array[EnemyDef], role: EnemyRoleDef, budget: int, card: WaveCard) -> EnemyDef:
	var qualified: Array[EnemyDef] = []
	for entry: EnemyDef in pool:
		if entry.tier >= card.min_primary_enemy_tier and entry.threat_cost <= budget:
			qualified.append(entry)
	var candidates: Array[EnemyDef] = _resolve_role_pool(qualified, role)
	if candidates.is_empty():
		# An adaptive allocation may not yet afford its unlocked anchor. Prefer
		# the same role at lower tier, then a legal faction screen.
		candidates = _resolve_role_pool(_ec.get_affordable_pool(pool, budget), role)
	var fresh: Array[EnemyDef] = []
	for entry: EnemyDef in candidates:
		if not _recent_primary_enemy_ids.has(entry.id):
			fresh.append(entry)
	if not fresh.is_empty():
		candidates = fresh
	return _pick_weighted_enemy(candidates, budget, budget, {}, true)

func _fill_role_budget(
	formation: Dictionary,
	pool: Array[EnemyDef],
	role: EnemyRoleDef,
	label: String,
	role_budget: int,
	ledger: Dictionary,
	primary_role: EnemyRoleDef,
	primary_pick: EnemyDef,
	card: WaveCard
) -> void:
	if role_budget <= 0 or role == null:
		return
	while true:
		var spent_by_role: Dictionary = formation["role_spent"]
		var available: int = mini(role_budget - int(spent_by_role.get(label, 0)), int(formation["initial_budget"]) - int(formation["spent_points"]))
		available = mini(available, int(ledger["remaining"]))
		if available <= 0:
			return
		var candidates: Array[EnemyDef] = []
		for entry: EnemyDef in pool:
			if not _matches_role_ref(entry, role):
				continue
			if label == "primary" and not _is_primary_enemy(entry, primary_role, card):
				continue
			if entry.threat_cost <= available and _can_buy_enemy(entry, ledger, primary_role, primary_pick, card):
				candidates.append(entry)
		var pick: EnemyDef = _pick_weighted_enemy(candidates, available, int(_last_wave_plan["enemy_points"]), ledger["spent_by_id"], false)
		if pick == null:
			return
		_record_purchase(formation, pick, label, ledger, primary_role, primary_pick, card)

func _cheapest_formation_seed(pool: Array[EnemyDef], roles: Array[EnemyRoleDef], ledger: Dictionary, primary_role: EnemyRoleDef, primary_pick: EnemyDef, card: WaveCard) -> EnemyDef:
	var cheapest_escort: EnemyDef = null
	var cheapest_capital: EnemyDef = null
	for entry: EnemyDef in pool:
		if not _can_buy_enemy(entry, ledger, primary_role, primary_pick, card):
			continue
		if _is_capital(entry, card):
			if cheapest_capital == null or entry.threat_cost < cheapest_capital.threat_cost:
				cheapest_capital = entry
		elif cheapest_escort == null or entry.threat_cost < cheapest_escort.threat_cost:
			cheapest_escort = entry
		elif entry.threat_cost == cheapest_escort.threat_cost:
			for role: EnemyRoleDef in roles:
				if _matches_role_ref(entry, role) and not _matches_role_ref(cheapest_escort, role):
					cheapest_escort = entry
					break
	return cheapest_escort if cheapest_escort != null else cheapest_capital

func _recycle_pool(pool: Array[EnemyDef], roles: Array[EnemyRoleDef], ledger: Dictionary, primary_role: EnemyRoleDef, primary_pick: EnemyDef, card: WaveCard) -> Array[EnemyDef]:
	var preferred_escorts: Array[EnemyDef] = []
	var faction_escorts: Array[EnemyDef] = []
	var preferred_capitals: Array[EnemyDef] = []
	var faction_capitals: Array[EnemyDef] = []
	for entry: EnemyDef in pool:
		if not _can_buy_enemy(entry, ledger, primary_role, primary_pick, card):
			continue
		var preferred: bool = roles.is_empty()
		for role: EnemyRoleDef in roles:
			if _matches_role_ref(entry, role):
				preferred = true
				break
		if _is_capital(entry, card):
			faction_capitals.append(entry)
			if preferred:
				preferred_capitals.append(entry)
		else:
			faction_escorts.append(entry)
			if preferred:
				preferred_escorts.append(entry)
	if not preferred_escorts.is_empty():
		return preferred_escorts
	if not faction_escorts.is_empty():
		return faction_escorts
	if not preferred_capitals.is_empty():
		return preferred_capitals
	return faction_capitals

func _can_buy_enemy(entry: EnemyDef, ledger: Dictionary, primary_role: EnemyRoleDef, primary_pick: EnemyDef, card: WaveCard) -> bool:
	if entry == null or entry.threat_cost <= 0 or entry.threat_cost > int(ledger["remaining"]):
		return false
	if _is_primary_enemy(entry, primary_role, card) and card.primary_count_max > 0 and int(ledger["primary_count"]) >= card.primary_count_max:
		return false
	if _is_capital(entry, card) and int(ledger["capital_spent"]) + entry.threat_cost > int(ledger["capital_allowance"]):
		return false
	if entry.id == primary_pick.id and not card.allow_swarm_primary and int(ledger["chosen_primary_spent"]) + entry.threat_cost > int(ledger["chosen_primary_allowance"]):
		return false
	return true

func _is_capital(entry: EnemyDef, card: WaveCard) -> bool:
	return entry.tier >= 4 or entry.threat_cost >= maxi(card.anchor_support_cost_threshold, 1)

func _is_primary_enemy(entry: EnemyDef, primary_role: EnemyRoleDef, card: WaveCard) -> bool:
	return entry.tier >= card.min_primary_enemy_tier and (primary_role == null or _matches_role_ref(entry, primary_role))

func _purchase_label(entry: EnemyDef, primary_role: EnemyRoleDef, secondary_role: EnemyRoleDef, support_role: EnemyRoleDef, card: WaveCard) -> String:
	if _is_primary_enemy(entry, primary_role, card):
		return "primary"
	if secondary_role != null and _matches_role_ref(entry, secondary_role):
		return "secondary"
	if support_role != null and _matches_role_ref(entry, support_role):
		return "support"
	return "escort"

func _record_purchase(formation: Dictionary, entry: EnemyDef, label: String, ledger: Dictionary, primary_role: EnemyRoleDef, primary_pick: EnemyDef, card: WaveCard) -> void:
	_spend_points(entry, ledger, primary_role, primary_pick, card)
	formation["spent_points"] = int(formation["spent_points"]) + entry.threat_cost
	var role_spent: Dictionary = formation["role_spent"]
	role_spent[label] = int(role_spent.get(label, 0)) + entry.threat_cost
	var purchases: Array = formation["purchases"]
	for purchase: Dictionary in purchases:
		var existing: EnemyDef = purchase["enemy"] as EnemyDef
		if existing.id == entry.id and String(purchase["label"]) == label:
			purchase["count"] = int(purchase["count"]) + 1
			return
	purchases.append({"enemy": entry, "label": label, "count": 1})

func _spend_points(entry: EnemyDef, ledger: Dictionary, primary_role: EnemyRoleDef, primary_pick: EnemyDef, card: WaveCard) -> void:
	ledger["remaining"] = int(ledger["remaining"]) - entry.threat_cost
	ledger["units"] = int(ledger["units"]) + 1
	if _is_capital(entry, card):
		ledger["capital_spent"] = int(ledger["capital_spent"]) + entry.threat_cost
	if _is_primary_enemy(entry, primary_role, card):
		ledger["primary_count"] = int(ledger["primary_count"]) + 1
	if entry.id == primary_pick.id:
		ledger["chosen_primary_spent"] = int(ledger["chosen_primary_spent"]) + entry.threat_cost
	var spent_by_id: Dictionary = ledger["spent_by_id"]
	spent_by_id[entry.id] = int(spent_by_id.get(entry.id, 0)) + entry.threat_cost

func _remainder_reason(pool: Array[EnemyDef], ledger: Dictionary, primary_role: EnemyRoleDef, primary_pick: EnemyDef, card: WaveCard) -> String:
	if int(ledger["remaining"]) <= 0:
		return "budget_fully_spent"
	var constraints: Array[String] = []
	for entry: EnemyDef in pool:
		if entry.threat_cost > int(ledger["remaining"]):
			continue
		if _is_primary_enemy(entry, primary_role, card) and card.primary_count_max > 0 and int(ledger["primary_count"]) >= card.primary_count_max and not constraints.has("primary_count_max"):
			constraints.append("primary_count_max")
		if _is_capital(entry, card) and int(ledger["capital_spent"]) + entry.threat_cost > int(ledger["capital_allowance"]) and not constraints.has("capital_budget_share"):
			constraints.append("capital_budget_share")
		if entry.id == primary_pick.id and not card.allow_swarm_primary and int(ledger["chosen_primary_spent"]) + entry.threat_cost > int(ledger["chosen_primary_allowance"]) and not constraints.has("primary_species_share"):
			constraints.append("primary_species_share")
	return "no_affordable_enemy" if constraints.is_empty() else ", ".join(constraints)

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

func _resolve_role_pool(pool: Array[EnemyDef], role: EnemyRoleDef) -> Array[EnemyDef]:
	if role == null:
		return pool.duplicate()
	var out: Array[EnemyDef] = []
	for entry in pool:
		if _matches_role_ref(entry, role):
			out.append(entry)
	if out.is_empty():
		return pool.duplicate()
	return out

func _pick_weighted_enemy(
	pool: Array[EnemyDef],
	budget: int,
	total_enemy_points: int,
	spent_by_id: Dictionary,
	prefer_anchor: bool
) -> EnemyDef:
	if pool.is_empty():
		return null
	var total_weight: float = 0.0
	var candidate_weights: Array[float] = []
	for entry: EnemyDef in pool:
		var fit_ratio: float = float(entry.threat_cost) / float(maxi(budget, 1))
		var fit_score: float = maxf(1.0 - absf(1.0 - fit_ratio), 0.0)
		var weight: float = 0.25 + fit_score * 0.85 + float(entry.tier) * 0.06
		if prefer_anchor and entry.threat_cost >= 4:
			weight += 0.20
		if prefer_anchor and _recent_primary_enemy_ids.has(entry.id):
			weight *= 0.45
		var spent_share: float = float(int(spent_by_id.get(entry.id, 0))) / float(maxi(total_enemy_points, 1))
		weight *= clampf(1.0 - spent_share, 0.30, 1.0)
		candidate_weights.append(weight)
		total_weight += weight
	if total_weight <= 0.0:
		return pool[0]
	var roll: float = _rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for index: int in pool.size():
		cursor += candidate_weights[index]
		if roll <= cursor:
			return pool[index]
	return pool[pool.size() - 1]

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

func _append_enemy_request(
	reqs: Array[SpawnRequest],
	pick: EnemyDef,
	copies: int,
	card: WaveCard,
	wave_index: int,
	stage_index: int,
	elapsed_sec: float,
	package_id: String,
	package_label: String,
	package_budget_points: int
) -> void:
	if pick == null or copies <= 0:
		return
	var req: SpawnRequest = SpawnRequest.new()
	req.kind = "Enemy"
	req.enemy_def = pick
	req.count = copies
	req.batch_size_min = card.batch_size_min
	req.batch_size_max = card.batch_size_max
	req.inter_batch_sec = card.inter_batch_sec
	req.package_id = package_id
	req.package_label = package_label
	req.package_budget_points = package_budget_points
	req.wave_card = card
	req.wave_index = wave_index
	req.stage_index = stage_index
	req.elapsed_sec = elapsed_sec
	reqs.append(req)

func _remember_primary_enemy(enemy_id: String) -> void:
	var trimmed: String = enemy_id.strip_edges()
	if trimmed == "":
		return
	_recent_primary_enemy_ids.append(trimmed)
	while _recent_primary_enemy_ids.size() > max(recent_primary_memory, 1):
		_recent_primary_enemy_ids.remove_at(0)

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

func _matches_role_ref(entry: EnemyDef, wanted: EnemyRoleDef) -> bool:
	if entry == null or wanted == null or entry.role == null:
		return false
	if entry.role == wanted:
		return true
	var entry_role_id: StringName = entry.get_role_id()
	var wanted_role_id: StringName = wanted.get_role_id()
	return entry_role_id != &"" and entry_role_id == wanted_role_id

func _role_debug_id(role: EnemyRoleDef) -> String:
	if role == null:
		return ""
	return String(role.get_role_id())

func _faction_debug_id(faction: FactionDef) -> String:
	if faction == null:
		return ""
	return String(faction.get_faction_id())
