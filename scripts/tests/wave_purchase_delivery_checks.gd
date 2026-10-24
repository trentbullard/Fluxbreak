extends Node3D

## Budget and dispatch invariants use synthetic actors, not player save data.
const CORVETTE: EnemyDef = preload("res://content/data/enemies/merc_corvette_mk1.tres")
const BUDGETS: Array[int] = [0, 1, 3, 7, 18, 40, 100, 240]
var _checks: int = 0
var _failures: int = 0
var _buyer: BudgetBuyer = null
var _catalog: EnemyCatalog = null
var _clock_before: float = 1.0

class RecordingSpawner extends Spawner:
	var records: Array[Dictionary] = []
	var clock: WaveDirector = null
	var blocked: bool = false
	var alive_count: int = 0

	func _ready() -> void:
		pass

	func get_alive_counts() -> Dictionary:
		return {"enemies": alive_count, "targets": 0, "total": alive_count}

	func spawn_enemy_burst(definition: EnemyDef, count: int, request: SpawnRequest = null) -> int:
		return _record(definition, count, request)

	func spawn_enemy_pack_burst(definition: EnemyDef, count: int, _anchor: Vector3, _radius: float, request: SpawnRequest = null) -> int:
		return _record(definition, count, request)

	func _record(definition: EnemyDef, count: int, request: SpawnRequest) -> int:
		if blocked or definition == null:
			return 0
		records.append({"package_id": request.package_id if request != null else "", "count": count, "time": clock._wave_timer})
		alive_count += count
		return count

class DispatchHarness extends WaveDirector:
	var finished: bool = false
	var finish_time: float = 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_PAUSABLE
		_state = RunState.State.IN_WAVE
		_wave_token = 77
		victory_wave_index = 0

	func _process(delta: float) -> void:
		if _state == RunState.State.IN_WAVE:
			_wave_timer += delta

	func _start_downtime(_first: bool = false) -> void:
		finished = true
		finish_time = _wave_timer
		_state = RunState.State.DOWNTIME

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Wave Purchase Validation":
		push_error("Run wave purchase checks through the isolated validation wrapper.")
		get_tree().quit(2)
		return
	_clock_before = Engine.time_scale
	GameFlow.abandon_run()
	_prepare_buyer()
	_check_faction_matrix()
	_check_carrier_regression()
	_check_singleton_roles()
	_check_primary_history()
	_check_capital_allowance()
	_check_unaffordable_remainder()
	await _check_whole_formation_delivery()
	await _check_pause_and_invalidation()
	await _check_timeout_from_wave_start()
	await _check_blocked_spawner_cancellation()
	await _check_pressure_cancellation()
	Engine.time_scale = _clock_before
	get_tree().paused = false
	_buyer.queue_free()
	_catalog.queue_free()
	await get_tree().process_frame
	print("WAVE_PURCHASE_DELIVERY_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _prepare_buyer() -> void:
	# Read the production roster without starting the world or its run machinery.
	var world_scene: PackedScene = load("res://scenes/world/world.tscn") as PackedScene
	var world: Node = world_scene.instantiate()
	var source_catalog: EnemyCatalog = world.get_node("StageRoot/EnemyCatalog") as EnemyCatalog
	_catalog = EnemyCatalog.new()
	_catalog.name = "ValidationCatalog"
	_catalog.enemies = source_catalog.enemies.duplicate()
	add_child(_catalog)
	world.free()
	_buyer = BudgetBuyer.new()
	_buyer.name = "ValidationBuyer"
	_buyer.enemy_catalog_path = ^"../ValidationCatalog"
	add_child(_buyer)

func _check_faction_matrix() -> void:
	var factions: Array[PracticeFactionDef] = PracticeRunFactory.get_factions()
	_check(factions.size() == 4, "The purchasing matrix must cover all four factions.")
	for faction: PracticeFactionDef in factions:
		for card: WaveCard in faction.wave_cards:
			for points: int in BUDGETS:
				for seed_value in range(3):
					_buyer.clear_history()
					_buyer.set_seed(471200 + seed_value)
					var tier_limit: int = card.min_enemy_tier
					var requests: Array[SpawnRequest] = _buyer.buy_wave(points, 0, card, tier_limit, 19, 0, 1140.0)
					var plan: Dictionary = _buyer.get_last_wave_plan()
					_validate_purchase(requests, plan, points, card, tier_limit)
					var first_signature: String = _purchase_signature(requests)
					_buyer.clear_history()
					_buyer.set_seed(471200 + seed_value)
					var repeated: Array[SpawnRequest] = _buyer.buy_wave(points, 0, card, tier_limit, 19, 0, 1140.0)
					_check(first_signature == _purchase_signature(repeated), "%s budget %d must be reproducible with the same seed." % [card.card_id, points])
		var representative: WaveCard = faction.wave_cards.back()
		_buyer.clear_history()
		_buyer.set_seed(471211)
		var high_requests: Array[SpawnRequest] = _buyer.buy_wave(100, 0, representative, faction.max_enemy_tier)
		var high_plan: Dictionary = _buyer.get_last_wave_plan()
		print("PURCHASE_SAMPLE %s card=%s allocated=100 spent=%d remainder=%d formations=%d units=%d" % [faction.faction.get_faction_id(), representative.card_id, int(high_plan.get("enemy_points_spent", -1)), int(high_plan.get("enemy_points_remainder", -1)), int(high_plan.get("formation_count", -1)), _enemy_units(high_requests)])

func _validate_purchase(requests: Array[SpawnRequest], plan: Dictionary, allocated: int, card: WaveCard, max_tier: int) -> void:
	var label: String = "%s/%d" % [card.card_id, allocated]
	var spent: int = 0
	var units: int = 0
	var primary_units: int = 0
	var capital_spent: int = 0
	var anchor_cost: int = 0
	var species_spending: Dictionary = {}
	var package_spending: Dictionary = {}
	for request: SpawnRequest in requests:
		_check(request != null and request.kind == "Enemy" and request.enemy_def != null, "%s must return only valid enemy purchases." % label)
		if request == null or request.enemy_def == null:
			continue
		_check(request.count > 0, "%s must not emit empty requests." % label)
		_check(request.enemy_def.get_faction_id() == card.get_faction_bias_id(), "%s crossed faction boundaries." % label)
		_check(request.enemy_def.tier <= max_tier, "%s exceeded its authored tier cap." % label)
		_check(not request.package_id.is_empty(), "%s needs a spatial formation ID." % label)
		var cost: int = maxi(request.enemy_def.threat_cost, 1) * request.count
		spent += cost
		species_spending[request.enemy_def.id] = int(species_spending.get(request.enemy_def.id, 0)) + cost
		if request.enemy_def.id == str(plan.get("primary_enemy_id", "")):
			anchor_cost = request.enemy_def.threat_cost
		units += request.count
		package_spending[request.package_id] = int(package_spending.get(request.package_id, 0)) + cost
		if request.package_label == "primary":
			primary_units += request.count
		if request.enemy_def.tier >= 4 or request.enemy_def.threat_cost >= maxi(card.anchor_support_cost_threshold, 1):
			capital_spent += cost
	_check(spent <= allocated, "%s overspent its allocation." % label)
	_check(int(plan.get("enemy_points_spent", -1)) == spent, "%s ledger disagrees with purchased costs." % label)
	var remainder: int = int(plan.get("enemy_points_remainder", -1))
	_check(spent + remainder == allocated, "%s must conserve allocated points." % label)
	_check(int(plan.get("planned_enemy_units", -1)) == units, "%s unit ledger disagrees with requests." % label)
	_check(int(plan.get("formation_count", -1)) == package_spending.size(), "%s formation ledger disagrees with requests." % label)
	_check(int(plan.get("capital_points_spent", -1)) == capital_spent, "%s capital ledger disagrees with purchased costs." % label)
	var allowance: int = int(plan.get("capital_point_allowance", -1))
	_check(capital_spent <= maxi(allowance, anchor_cost), "%s capital allocation exceeded the single required-anchor exception." % label)
	if remainder > 0:
		_check(not str(plan.get("remainder_reason", "")).is_empty(), "%s remainder must explain its purchasing constraint." % label)
	if card.primary_count_max > 0:
		_check(primary_units <= card.primary_count_max, "%s exceeded its purchase-wide primary-count restriction." % label)
		var qualified_primary_units: int = 0
		for request: SpawnRequest in requests:
			if request.enemy_def != null and card.primary_role_bias != null and request.enemy_def.get_role_id() == card.primary_role_bias.get_role_id() and request.enemy_def.tier >= card.min_primary_enemy_tier:
				qualified_primary_units += request.count
		_check(qualified_primary_units <= card.primary_count_max, "%s role-labelled fallback purchases bypassed its primary-count restriction." % label)
	if remainder > 0:
		for candidate: EnemyDef in _catalog.get_pool(card.faction_bias, null, max_tier):
			if candidate is EnemyBossDef or candidate.threat_cost <= 0 or candidate.threat_cost > remainder:
				continue
			if candidate.tier >= 4 or candidate.threat_cost >= maxi(card.anchor_support_cost_threshold, 1):
				continue
			if card.primary_role_bias != null and candidate.get_role_id() == card.primary_role_bias.get_role_id() and candidate.tier >= card.min_primary_enemy_tier and card.primary_count_max > 0 and primary_units >= card.primary_count_max:
				continue
			var species_limit: int = maxi(int(round(float(allocated) * card.max_primary_budget_share)), anchor_cost)
			if not card.allow_swarm_primary and candidate.id == str(plan.get("primary_enemy_id", "")) and int(species_spending.get(candidate.id, 0)) + candidate.threat_cost > species_limit:
				continue
			_check(false, "%s stranded %d points despite an affordable legal noncapital escort %s." % [label, remainder, candidate.id])
	var packages: Array = plan.get("packages", [])
	var seen_ids: Dictionary = {}
	for entry: Dictionary in packages:
		var package_id: String = str(entry.get("package_id", ""))
		_check(not package_id.is_empty() and not seen_ids.has(package_id), "%s debug packages need distinct IDs." % label)
		seen_ids[package_id] = true
		_check(int(entry.get("spent_points", -1)) == int(package_spending.get(package_id, 0)), "%s formation expenditure must agree with requests." % label)
	_check(seen_ids.size() == package_spending.size(), "%s must report every purchased formation." % label)

func _check_carrier_regression() -> void:
	var card: WaveCard = load("res://content/data/cards/merc_carrier_group.tres") as WaveCard
	_buyer.clear_history()
	_buyer.set_seed(471211)
	var requests: Array[SpawnRequest] = _buyer.buy_wave(100, 0, card, 5)
	var plan: Dictionary = _buyer.get_last_wave_plan()
	_validate_purchase(requests, plan, 100, card, 5)
	_check(int(plan.get("enemy_points_spent", 0)) == 100, "Carrier Group's former 48/100 purchase must now use its full legal budget.")
	_check(int(plan.get("formation_count", 0)) == 3, "Carrier Group must fund all three authored spatial formations.")
	_check(_enemy_units(requests) > 7, "Carrier Group must purchase more than its former seven ships at 100 points.")
	print("CARRIER_REGRESSION before=48/100points,7units after=%d/100points,%dunits,%dformations" % [int(plan.get("enemy_points_spent", 0)), _enemy_units(requests), int(plan.get("formation_count", 0))])

func _fixture_enemy(identity: String, faction: FactionDef, role: EnemyRoleDef, cost: int, tier: int = 1) -> EnemyDef:
	var definition: EnemyDef = EnemyDef.new()
	definition.id = identity
	definition.faction = faction
	definition.role = role
	definition.threat_cost = cost
	definition.tier = tier
	return definition

func _check_singleton_roles() -> void:
	var original: Array[EnemyDef] = _catalog.enemies
	var faction: FactionDef = FactionDef.new()
	faction.faction_id = &"singleton_test"
	var primary_role: EnemyRoleDef = EnemyRoleDef.new()
	primary_role.role_id = &"anchor"
	var secondary_role: EnemyRoleDef = EnemyRoleDef.new()
	secondary_role.role_id = &"escort"
	var support_role: EnemyRoleDef = EnemyRoleDef.new()
	support_role.role_id = &"support"
	_catalog.enemies = [_fixture_enemy("anchor", faction, primary_role, 1), _fixture_enemy("escort", faction, secondary_role, 1), _fixture_enemy("support", faction, support_role, 1)]
	var card: WaveCard = WaveCard.new()
	card.card_id = "singleton_roles"
	card.faction_bias = faction
	card.primary_role_bias = primary_role
	card.secondary_role_bias = secondary_role
	card.support_role_bias = support_role
	card.primary_count_max = 2
	card.package_count_min = 3
	card.package_count_max = 3
	_buyer.clear_history()
	_buyer.set_seed(37)
	var requests: Array[SpawnRequest] = _buyer.buy_wave(30, 0, card, 1)
	var plan: Dictionary = _buyer.get_last_wave_plan()
	_validate_purchase(requests, plan, 30, card, 1)
	_check(int(plan.get("enemy_points_spent", 0)) == 30, "Singleton role pools must reuse affordable escorts instead of stranding points.")
	_check(int(plan.get("formation_count", 0)) == 3, "Affordable authored formations must all receive ships.")
	var role_counts: Dictionary = {}
	var formation_roles: Dictionary = {}
	for request: SpawnRequest in requests:
		var role_id: StringName = request.enemy_def.get_role_id()
		role_counts[role_id] = int(role_counts.get(role_id, 0)) + request.count
		var roles: Dictionary = formation_roles.get(request.package_id, {})
		roles[role_id] = true
		formation_roles[request.package_id] = roles
	_check(int(role_counts.get(&"anchor", 0)) <= 2, "Recycled purchases must not bypass the global primary-count limit.")
	_check(int(role_counts.get(&"escort", 0)) > 2 or int(role_counts.get(&"support", 0)) > 2, "Singleton escort/support pools must allow more than two copies.")
	var mixed: bool = false
	for roles: Dictionary in formation_roles.values():
		mixed = mixed or roles.size() > 1
	_check(mixed, "Role allocations must create mixed spatial formations rather than separate role-only anchors.")
	_catalog.enemies = original

func _check_capital_allowance() -> void:
	var original: Array[EnemyDef] = _catalog.enemies
	var faction: FactionDef = FactionDef.new()
	faction.faction_id = &"capital_test"
	var capital_role: EnemyRoleDef = EnemyRoleDef.new()
	capital_role.role_id = &"capital"
	var escort_role: EnemyRoleDef = EnemyRoleDef.new()
	escort_role.role_id = &"escort"
	_catalog.enemies = [_fixture_enemy("capital", faction, capital_role, 10, 5), _fixture_enemy("escort", faction, escort_role, 1)]
	var card: WaveCard = WaveCard.new()
	card.card_id = "capital_allowance"
	card.faction_bias = faction
	card.primary_role_bias = capital_role
	card.secondary_role_bias = escort_role
	card.primary_budget_share = 0.3
	card.secondary_budget_share = 0.7
	card.support_budget_share = 0.0
	card.min_primary_enemy_tier = 5
	for budget: int in [25, 100]:
		_buyer.clear_history()
		_buyer.set_seed(41)
		var requests: Array[SpawnRequest] = _buyer.buy_wave(budget, 0, card, 5)
		var plan: Dictionary = _buyer.get_last_wave_plan()
		_validate_purchase(requests, plan, budget, card, 5)
		var allowance: int = int(plan.get("capital_point_allowance", -1))
		var capital_spent: int = int(plan.get("capital_points_spent", -1))
		_check(allowance >= 0, "Capital purchases must expose their allowance.")
		_check(capital_spent <= maxi(allowance, 10), "Capital purchases may exceed allowance only for one required anchor.")
		_check(capital_spent >= 10, "Affordable authored capital identity must survive escort recycling.")
		if budget == 25:
			_check(capital_spent == 10, "The required-anchor exception must not fund several over-quota capitals.")
	_catalog.enemies = original

func _check_primary_history() -> void:
	var original: Array[EnemyDef] = _catalog.enemies
	var faction: FactionDef = FactionDef.new()
	faction.faction_id = &"history_test"
	var role: EnemyRoleDef = EnemyRoleDef.new()
	role.role_id = &"screen"
	_catalog.enemies = [_fixture_enemy("screen_a", faction, role, 1), _fixture_enemy("screen_b", faction, role, 1)]
	var card: WaveCard = WaveCard.new()
	card.card_id = "primary_history"
	card.faction_bias = faction
	card.primary_role_bias = role
	card.allow_swarm_primary = true
	_buyer.clear_history()
	_buyer.set_seed(51)
	_buyer.buy_wave(10, 0, card, 1)
	var first_primary: String = str(_buyer.get_last_wave_plan().get("primary_enemy_id", ""))
	_buyer.buy_wave(10, 0, card, 1)
	var second_primary: String = str(_buyer.get_last_wave_plan().get("primary_enemy_id", ""))
	_check(not first_primary.is_empty() and not second_primary.is_empty() and first_primary != second_primary, "Successive purchases must avoid a recent anchor when another affordable anchor exists.")
	_catalog.enemies = original

func _check_unaffordable_remainder() -> void:
	var original: Array[EnemyDef] = _catalog.enemies
	var faction: FactionDef = FactionDef.new()
	faction.faction_id = &"unaffordable_test"
	_catalog.enemies = [_fixture_enemy("cost_seven", faction, null, 7)]
	var card: WaveCard = WaveCard.new()
	card.card_id = "unaffordable"
	card.faction_bias = faction
	var requests: Array[SpawnRequest] = _buyer.buy_wave(6, 0, card, 1)
	var plan: Dictionary = _buyer.get_last_wave_plan()
	_validate_purchase(requests, plan, 6, card, 1)
	_check(requests.is_empty() and int(plan.get("enemy_points_remainder", -1)) == 6, "An unaffordable catalog must retain all points as an explained remainder.")
	_catalog.enemies = original

func _purchase_signature(requests: Array[SpawnRequest]) -> String:
	var entries: PackedStringArray = PackedStringArray()
	for request: SpawnRequest in requests:
		entries.append("%s:%s:%s:%d" % [request.package_id, request.package_label, request.enemy_def.id if request.enemy_def != null else "target", request.count])
	return "|".join(entries)

func _enemy_units(requests: Array[SpawnRequest]) -> int:
	var count: int = 0
	for request: SpawnRequest in requests:
		if request.kind == "Enemy":
			count += request.count
	return count

func _delivery_requests(group_count: int, count_per_group: int) -> Array[SpawnRequest]:
	var requests: Array[SpawnRequest] = []
	for group_index in group_count:
		# Two role requests share each formation: both must be delivered together.
		for role_index in 2:
			var request: SpawnRequest = SpawnRequest.new()
			request.enemy_def = CORVETTE
			request.count = count_per_group / 2
			request.package_id = "formation_%d" % group_index
			request.package_label = "primary" if role_index == 0 else "escort"
			requests.append(request)
	return requests

func _delivery_fixture(timeout_sec: float = 30.0) -> DispatchHarness:
	var director: DispatchHarness = DispatchHarness.new()
	director.wave_timeout_sec = timeout_sec
	add_child(director)
	var spawner: RecordingSpawner = RecordingSpawner.new()
	spawner.clock = director
	director.add_child(spawner)
	director._spawner = spawner
	return director

func _check_whole_formation_delivery() -> void:
	Engine.time_scale = 8.0
	var director: DispatchHarness = _delivery_fixture()
	var spawner: RecordingSpawner = director._spawner as RecordingSpawner
	var requests: Array[SpawnRequest] = _delivery_requests(12, 10)
	var profile: Dictionary = director._build_spawn_profile(requests, 120)
	var opening_ids: Array = profile.get("opening_package_ids", [])
	_check(opening_ids.size() >= 2, "The opening must include at least two available formations.")
	_check(int(profile.get("opening_enemy_units", 0)) >= 72, "The opening must cover at least 60% of units without an 18-unit ceiling.")
	director._run_requests_coroutine(requests, profile, {}, director._wave_token)
	await _wait_until_clock(director, 1.5)
	var opening_count: int = 0
	for record: Dictionary in spawner.records:
		opening_count += int(record["count"])
	_check(opening_count > 18, "A large wave must actually dispatch more than 18 opening units.")
	for package_id: String in opening_ids:
		var members: int = 0
		for record: Dictionary in spawner.records:
			if str(record["package_id"]) == package_id:
				members += int(record["count"])
		_check(members == 10, "Opening formation %s must not be cut in half by a unit ceiling." % package_id)
	await _wait_until_clock(director, 8.5)
	var delivery: Dictionary = director.get_debug_snapshot().get("delivery", {})
	_check(int(delivery.get("planned_units", -1)) == 120, "Dispatch accounting must record every planned enemy.")
	_check(int(delivery.get("spawned_units", -1)) == 120, "Every valid purchased enemy must be dispatched.")
	_check(int(delivery.get("pending_units", -1)) == 0 and int(delivery.get("cancelled_units", -1)) == 0, "Successful delivery must leave no pending or cancelled enemies.")
	_check(float(delivery.get("dispatch_duration_sec", 99.0)) <= 8.25, "The final formation launch must complete within eight seconds plus a frame allowance.")
	_check(int(delivery.get("nearby_radius_m", -1)) == 1000, "Nearby diagnostics must label their 1,000-metre measurement radius.")
	_check(delivery.has("peak_alive_enemies") and delivery.has("peak_nearby_enemies"), "Delivery diagnostics must include alive and nearby peaks.")
	print("DELIVERY_SAMPLE planned=%d spawned=%d opening=%d groups=%d duration=%.3fs" % [int(delivery.get("planned_units", -1)), int(delivery.get("spawned_units", -1)), opening_count, opening_ids.size(), float(delivery.get("dispatch_duration_sec", -1.0))])
	director._wave_token += 1
	await _wait_frames(6)
	director.queue_free()
	await _wait_frames(2)

func _check_pause_and_invalidation() -> void:
	Engine.time_scale = 1.0
	var director: DispatchHarness = _delivery_fixture()
	var spawner: RecordingSpawner = director._spawner as RecordingSpawner
	var requests: Array[SpawnRequest] = _delivery_requests(5, 8)
	var profile: Dictionary = director._build_spawn_profile(requests, 40)
	director._run_requests_coroutine(requests, profile, {}, director._wave_token)
	await _wait_frames(8)
	var count_before: int = spawner.alive_count
	var clock_before: float = director._wave_timer
	get_tree().paused = true
	await get_tree().create_timer(0.15, true, false, true).timeout
	_check(spawner.alive_count == count_before, "Paused delivery must not launch pending formations.")
	_check(is_equal_approx(director._wave_timer, clock_before), "The wave timeout must pause with delivery.")
	director._wave_token += 1
	get_tree().paused = false
	Engine.time_scale = 8.0
	await _wait_until_clock(director, 3.0)
	var delivery: Dictionary = director.get_debug_snapshot().get("delivery", {})
	_check(spawner.alive_count == count_before, "An invalidated wave token must prevent late spawns.")
	_check(int(delivery.get("pending_units", -1)) == 0, "Invalidated delivery must clear its pending ledger.")
	_check(int(delivery.get("cancelled_units", 0)) == 40 - count_before, "Invalidated delivery must account for every unspawned enemy.")
	var reasons: Dictionary = delivery.get("cancel_reasons", {})
	_check(not reasons.is_empty(), "Cancelled purchases must expose their cancellation reason.")
	_check(int(delivery.get("planned_units", -1)) == int(delivery.get("spawned_units", 0)) + int(delivery.get("cancelled_units", 0)), "Cancelled delivery must conserve planned units.")
	director.queue_free()
	await _wait_frames(2)

func _check_timeout_from_wave_start() -> void:
	Engine.time_scale = 8.0
	var director: DispatchHarness = _delivery_fixture(4.0)
	var requests: Array[SpawnRequest] = _delivery_requests(5, 8)
	var profile: Dictionary = director._build_spawn_profile(requests, 40)
	director._run_requests_coroutine(requests, profile, {}, director._wave_token)
	for frame_index in range(100):
		if director.finished:
			break
		await get_tree().process_frame
	_check(director.finished, "The wave must finish at its configured timeout even with surviving enemies.")
	_check(director.finish_time >= 4.0 and director.finish_time <= 4.75, "Delivery must not add its duration to the wave timeout (actual %.3fs)." % director.finish_time)
	director.queue_free()
	await _wait_frames(2)

func _check_blocked_spawner_cancellation() -> void:
	Engine.time_scale = 8.0
	var director: DispatchHarness = _delivery_fixture(1.0)
	var spawner: RecordingSpawner = director._spawner as RecordingSpawner
	spawner.blocked = true
	var requests: Array[SpawnRequest] = _delivery_requests(5, 8)
	var profile: Dictionary = director._build_spawn_profile(requests, 40)
	director._run_requests_coroutine(requests, profile, {}, director._wave_token)
	for frame_index in range(100):
		if director.finished:
			break
		await get_tree().process_frame
	var delivery: Dictionary = director.get_debug_snapshot().get("delivery", {})
	_check(director.finished and director.finish_time <= 1.75, "A blocked spawner must not indefinitely extend the wave.")
	_check(int(delivery.get("spawned_units", -1)) == 0 and int(delivery.get("pending_units", -1)) == 0, "Blocked delivery must not leave units silently pending.")
	_check(int(delivery.get("cancelled_units", -1)) == 40, "Blocked and timed-out purchases must all be accounted as cancelled.")
	var reasons: Dictionary = delivery.get("cancel_reasons", {})
	_check(not reasons.is_empty(), "Blocked delivery must expose a cancellation reason.")
	director.queue_free()
	await _wait_frames(2)

func _check_pressure_cancellation() -> void:
	for stop_state: String in ["gateway", "boss", "completed"]:
		Engine.time_scale = 8.0
		var director: DispatchHarness = _delivery_fixture()
		var spawner: RecordingSpawner = director._spawner as RecordingSpawner
		var requests: Array[SpawnRequest] = _delivery_requests(5, 8)
		var profile: Dictionary = director._build_spawn_profile(requests, 40)
		director._run_requests_coroutine(requests, profile, {}, director._wave_token, "pressure", false)
		await _wait_frames(2)
		var before: int = spawner.alive_count
		if stop_state == "gateway":
			director._gateway_hold_active = true
		elif stop_state == "boss":
			director._boss_wave_active = true
		else:
			director._on_run_completed()
		await _wait_until_clock(director, 3.0)
		var history: Array[Dictionary] = director.get_delivery_history()
		var delivery: Dictionary = history.back() if not history.is_empty() else {}
		_check(spawner.alive_count == before, "Pending pressure formations must not spawn during %s state." % stop_state)
		_check(int(delivery.get("pending_units", -1)) == 0 and int(delivery.get("cancelled_units", -1)) == 40 - before, "Pressure delivery must account for cancellation during %s state." % stop_state)
		_check(not director.finished, "Pressure dispatch must not own the main wave-completion lifecycle.")
		director.queue_free()
		await _wait_frames(2)

func _wait_until_clock(director: DispatchHarness, target_time: float) -> void:
	for frame_index in range(300):
		if director._wave_timer >= target_time or director.finished:
			return
		await get_tree().process_frame
	_check(false, "The synthetic dispatch clock failed to advance.")

func _wait_frames(count: int) -> void:
	for frame_index in range(count):
		await get_tree().process_frame
