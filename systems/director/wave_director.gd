extends Node
class_name WaveDirector

signal wave_started(index: int, enemy_budget: int, target_budget: int)
signal wave_cleared(index: int, time_sec: float)
signal wave_forced_next(index: int)
signal downtime_started(duration: float, next_wave_index: int)
signal downtime_ended(next_wave_index: int)
signal next_wave_eta(seconds: float)
signal boss_wave_started(boss_def: EnemyBossDef, wave_index: int)
signal boss_wave_ended(boss_def: EnemyBossDef, wave_index: int, player_won: bool)
signal gateway_ready(stage: StageDef, position: Vector3)

@export var spawner_path: NodePath
@export var downtime_sec: float = 30.0

@export var pressure_interval_sec: float = 10.0
@export var pressure_enemy_burst: int = 1
@export var pressure_target_burst: int = 0
@export var pressure_enemy_point_budget: int = 3
@export var pressure_target_point_budget: int = 0

@export var wave_burst_extra: int = 0

@export var batch_size_min: int = 2
@export var batch_size_max: int = 4
@export var inter_batch_delay: float = 0.7

@export var wave_clear_carryover_ok: int = 0
@export var wave_timeout_sec: float = 25.0
@export var victory_wave_index: int = 30

@export_group("Soft Density")
@export var soft_enemy_density_base: float = 6.0
@export var soft_enemy_density_per_wave: float = 1.4

@export var threat_director_path: NodePath
@export var wave_budgeter_path: NodePath
@export var budget_buyer_path: NodePath
@export var wave_intensity_director_path: NodePath
@export var enemy_combat_scaling_director_path: NodePath
@export var wave_cards: Array[WaveCard] = []

var _buyer: BudgetBuyer
var _threat_dir: ThreatDirector
var _wave_budgeter: WaveBudgeter
var _intensity_dir: WaveIntensityDirector
var _enemy_combat_scaling_dir: EnemyCombatScalingDirector
var _elapsed_sec: float = 0.0

var _spawner: Spawner
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _wave_index: int = 0
var _progression_wave_index: int = 0
var _wave_timer: float = 0.0
var _state: RunState.State = RunState.State.DOWNTIME
var _downtime_remaining: float = 0.0
var _wave_token: int = 0
var _pressure_token: int = 0
var _active_card: WaveCard = null
var _pending_card: WaveCard = null
var _recent_card_ids: Array[String] = []
var _last_debug_snapshot: Dictionary = {}
var _current_enemy_density_reference: float = 6.0
var _boss_wave_active: bool = false
var _active_boss_def: EnemyBossDef = null
var _active_boss_instance: Enemy = null
var _gateway_hold_active: bool = false

func get_state() -> RunState.State:
	return _state

func get_wave_index() -> int:
	return _wave_index

func get_progression_wave_index() -> int:
	return _progression_wave_index

func get_next_wave_index() -> int:
	if _state == RunState.State.DOWNTIME:
		return _wave_index + 1
	return max(_wave_index, 1)

func get_wave_time_remaining() -> float:
	return max(wave_timeout_sec - _wave_timer, 0.0)

func get_downtime_remaining() -> float:
	return max(_downtime_remaining, 0.0)

func get_debug_snapshot() -> Dictionary:
	return _last_debug_snapshot.duplicate(true)

func is_boss_wave_active() -> bool:
	return _boss_wave_active

func is_gateway_hold_active() -> bool:
	return _gateway_hold_active

func get_active_boss_def() -> EnemyBossDef:
	return _active_boss_def

func _ready() -> void:
	_threat_dir = get_node_or_null(threat_director_path) as ThreatDirector
	_wave_budgeter = get_node_or_null(wave_budgeter_path) as WaveBudgeter
	_spawner = get_node_or_null(spawner_path) as Spawner
	_buyer = get_node_or_null(budget_buyer_path) as BudgetBuyer
	_intensity_dir = get_node_or_null(wave_intensity_director_path) as WaveIntensityDirector
	_enemy_combat_scaling_dir = get_node_or_null(enemy_combat_scaling_director_path) as EnemyCombatScalingDirector
	if _intensity_dir == null:
		_intensity_dir = WaveIntensityDirector.new()
		_intensity_dir.name = "WaveIntensityDirectorRuntime"
		add_child(_intensity_dir)
	if _enemy_combat_scaling_dir == null:
		_enemy_combat_scaling_dir = EnemyCombatScalingDirector.new()
		_enemy_combat_scaling_dir.name = "EnemyCombatScalingDirectorRuntime"
		add_child(_enemy_combat_scaling_dir)
	if _spawner == null:
		push_error("WaveDirector: spawner_path not set.")
		return
	if not GameFlow.stage_changed.is_connected(_on_stage_changed):
		GameFlow.stage_changed.connect(_on_stage_changed)
	_rng.randomize()
	_reset_stage_runtime(true, true, true)
	_start_pressure_loop()

func _process(delta: float) -> void:
	if _gateway_hold_active:
		next_wave_eta.emit(0.0)
		return
	_elapsed_sec += delta
	if _intensity_dir != null:
		_intensity_dir.tick(delta, _state == RunState.State.IN_WAVE)

	if _state == RunState.State.DOWNTIME:
		_downtime_remaining = max(_downtime_remaining - delta, 0.0)
		next_wave_eta.emit(_downtime_remaining)
		if _downtime_remaining <= 0.0:
			_state = RunState.State.IN_WAVE
			downtime_ended.emit(_wave_index + 1)
			_next_wave()
	else:
		_wave_timer += delta
		if _boss_wave_active:
			next_wave_eta.emit(0.0)
			return
		var wave_timeout_left: float = max(wave_timeout_sec - _wave_timer, 0.0)
		var eta: float = wave_timeout_left + downtime_sec
		next_wave_eta.emit(eta)

func _start_downtime(first: bool = false) -> void:
	_gateway_hold_active = false
	_state = RunState.State.DOWNTIME
	RunState.set_state(RunState.State.DOWNTIME)
	_active_card = null
	_downtime_remaining = 5.0 if first else downtime_sec
	_ensure_pending_card()
	downtime_started.emit(_downtime_remaining, _wave_index + 1)

func _get_wave_card_deck() -> Array[WaveCard]:
	var active_stage: StageDef = GameFlow.get_current_stage()
	if active_stage != null:
		var stage_cards: Array[WaveCard] = active_stage.get_wave_cards()
		if not stage_cards.is_empty():
			return stage_cards
	return wave_cards

func _choose_card() -> WaveCard:
	var deck: Array[WaveCard] = _get_wave_card_deck()
	if deck.is_empty():
		return WaveCard.new()

	var candidates: Array[WaveCard] = []
	for entry in deck:
		if entry == null:
			continue
		if not _is_card_on_cooldown(entry):
			candidates.append(entry)
	if candidates.is_empty():
		for entry in deck:
			if entry != null:
				candidates.append(entry)
	if candidates.is_empty():
		return WaveCard.new()

	var total_weight: float = 0.0
	var weights: Array[float] = []
	for entry in candidates:
		var weight: float = max(entry.weight, 0.05)
		weights.append(weight)
		total_weight += weight
	if total_weight <= 0.0:
		return candidates[0]

	var roll: float = _rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for index in candidates.size():
		cursor += weights[index]
		if roll <= cursor:
			return candidates[index]
	return candidates[candidates.size() - 1]

func _ensure_pending_card() -> void:
	if _pending_card == null:
		_pending_card = _choose_card()

func _consume_pending_card() -> WaveCard:
	_ensure_pending_card()
	var card: WaveCard = _pending_card
	_pending_card = null
	if card == null:
		card = WaveCard.new()
	return card

func _is_card_on_cooldown(card: WaveCard) -> bool:
	if card == null:
		return false
	var cooldown: int = max(card.card_repeat_cooldown, 0)
	if cooldown <= 0:
		return false
	var wanted_id: String = String(card.get_card_id())
	var checked: int = 0
	for index in range(_recent_card_ids.size() - 1, -1, -1):
		if checked >= cooldown:
			break
		if _recent_card_ids[index] == wanted_id:
			return true
		checked += 1
	return false

func _remember_card(card: WaveCard) -> void:
	if card == null:
		return
	_recent_card_ids.append(String(card.get_card_id()))
	while _recent_card_ids.size() > 8:
		_recent_card_ids.remove_at(0)

func _next_wave() -> void:
	_wave_token += 1
	RunState.set_state(RunState.State.IN_WAVE)
	_state = RunState.State.IN_WAVE

	_wave_index += 1
	_progression_wave_index += 1
	_wave_timer = 0.0
	if _intensity_dir != null:
		_intensity_dir.begin_wave()
	if _should_start_boss_wave():
		_active_card = null
		RunState.set_wave_context(_wave_index, 0, 0, _progression_wave_index)
		_last_debug_snapshot = {
			"wave_index": _wave_index,
			"progression_wave_index": _progression_wave_index,
			"stage_index": max(GameFlow.get_active_stage_index(), 0),
			"state": "boss_wave",
		}
		emit_signal("wave_started", _wave_index, 0, 0)
		_start_boss_wave()
		return

	_active_card = _consume_pending_card()
	_remember_card(_active_card)

	var pps: float = CombatStats.get_pps()
	var incoming_damage: float = CombatStats.get_damage_taken_per_sec()
	var kill_rate: float = CombatStats.get_enemy_kill_rate()
	var stage_index: int = max(GameFlow.get_active_stage_index(), 0)
	var threat: float = 0.0
	if _threat_dir != null:
		threat = _threat_dir.compute_threat(_elapsed_sec, _wave_index, stage_index, pps, incoming_damage)

	var budgets: Dictionary = {"enemy_points": 0, "target_points": 0}
	if _wave_budgeter != null:
		budgets = _wave_budgeter.to_budgets(threat, _elapsed_sec, _wave_index, _active_card)
	_current_enemy_density_reference = max(
		soft_enemy_density_base + float(max(_wave_index - 1, 0)) * soft_enemy_density_per_wave,
		float(int(budgets.get("enemy_points", 0))) * 0.65
	)

	var opening_adjustment: Dictionary = {"enemy_points": int(budgets.get("enemy_points", 0)), "scale": 1.0}
	if _intensity_dir != null:
		opening_adjustment = _intensity_dir.get_opening_adjustment(
			int(budgets.get("enemy_points", 0)),
			kill_rate,
			incoming_damage
		)
	budgets["enemy_points"] = int(opening_adjustment.get("enemy_points", budgets.get("enemy_points", 0)))

	RunState.set_wave_context(
		_wave_index,
		int(budgets["enemy_points"]),
		int(budgets["target_points"]),
		_progression_wave_index
	)

	var max_tier: int = clamp(1 + _wave_index / 3 + stage_index, 1, 5)
	var reqs: Array[SpawnRequest] = []
	var combat_scaling: EnemyCombatScalingSnapshot = _build_enemy_combat_scaling_snapshot(_wave_index, _elapsed_sec)
	if _buyer != null:
		reqs = _buyer.buy_wave(
			int(budgets["enemy_points"]),
			int(budgets["target_points"]),
			_active_card,
			max_tier,
			_wave_index,
			stage_index,
			_elapsed_sec
		)
	reqs = _prioritize_requests(reqs, _active_card)
	var spawn_profile: Dictionary = _build_spawn_profile(reqs, int(budgets["enemy_points"]))
	var package_order: Array[String] = _get_enemy_package_order(reqs)
	var package_layouts: Dictionary = _build_enemy_package_layouts(package_order, spawn_profile)
	_apply_spawn_profile_anchor_radii(spawn_profile, package_order, package_layouts)
	_apply_enemy_combat_scaling(reqs, combat_scaling)

	_last_debug_snapshot = _build_wave_debug_snapshot(
		_active_card,
		stage_index,
		threat,
		budgets,
		opening_adjustment,
		combat_scaling,
		spawn_profile
	)

	emit_signal("wave_started", _wave_index, budgets["enemy_points"], budgets["target_points"])
	_run_requests_async(reqs, spawn_profile, package_layouts)

func _build_wave_debug_snapshot(
	card: WaveCard,
	stage_index: int,
	threat: float,
	budgets: Dictionary,
	opening_adjustment: Dictionary,
	combat_scaling: EnemyCombatScalingSnapshot,
	spawn_profile: Dictionary
) -> Dictionary:
	var snapshot: Dictionary = {
		"wave_index": _wave_index,
		"progression_wave_index": _progression_wave_index,
		"stage_index": stage_index,
		"state": "wave",
		"card_id": String(card.get_card_id()) if card != null else "",
		"card_name": card.get_display_name_or_default() if card != null else "Wave",
		"threat": threat,
		"enemy_points": int(budgets.get("enemy_points", 0)),
		"target_points": int(budgets.get("target_points", 0)),
		"soft_enemy_density_reference": _current_enemy_density_reference,
		"opening_enemy_scale": float(opening_adjustment.get("scale", 1.0)),
		"pressure_state": _intensity_dir.get_last_pressure_state() if _intensity_dir != null else "n/a",
		"combat_scaling_intensity": combat_scaling.intensity if combat_scaling != null else 0.0,
		"combat_scaling_active": combat_scaling.has_scaling() if combat_scaling != null else false,
		"enemy_nanobot_multiplier": combat_scaling.nanobot_multiplier if combat_scaling != null else 1.0,
	}
	snapshot["spawn_profile"] = spawn_profile.duplicate(true)
	snapshot["enemy_effective_context"] = EnemyStatResolver.build_wave_debug_summary(
		card,
		_wave_index,
		stage_index,
		_elapsed_sec,
		combat_scaling
	)
	if _buyer != null:
		snapshot["wave_plan"] = _buyer.get_last_wave_plan()
	return snapshot

func _start_pressure_loop() -> void:
	if pressure_interval_sec <= 0.0:
		return
	_pressure_token += 1
	_run_pressure_coroutine(_pressure_token)

func _create_pausable_timer(seconds: float) -> SceneTreeTimer:
	return get_tree().create_timer(seconds, false)

func _run_pressure_coroutine(token: int) -> void:
	while true:
		var t: SceneTreeTimer = _create_pausable_timer(pressure_interval_sec)
		await t.timeout
		if token != _pressure_token:
			return
		if _buyer == null or _spawner == null:
			continue

		if _state == RunState.State.DOWNTIME:
			_ensure_pending_card()
			var alive_now: Dictionary = _spawner.get_alive_counts()
			var downtime_target_budget: int = 0
			if _intensity_dir != null:
				downtime_target_budget = _intensity_dir.get_downtime_target_budget(
					_wave_index + 1,
					int(alive_now.get("targets", 0)),
					_pending_card
				)
			if downtime_target_budget <= 0:
				downtime_target_budget = pressure_target_point_budget
			if downtime_target_budget > 0 and _pending_card != null:
				var target_reqs: Array[SpawnRequest] = _buyer.buy_wave(
					0,
					downtime_target_budget,
					_pending_card,
					1,
					_wave_index + 1,
					max(GameFlow.get_active_stage_index(), 0),
					_elapsed_sec
				)
				for req in target_reqs:
					if req.kind == "Target" and req.target_def != null and req.count > 0:
						_spawner.spawn_target_burst(req.target_def, req.count)
			continue

		if _state != RunState.State.IN_WAVE:
			continue
		if _boss_wave_active:
			continue

		var active_card: WaveCard = _active_card if _active_card != null else WaveCard.new()
		var alive_counts: Dictionary = _spawner.get_alive_counts()
		var pressure_plan: Dictionary = {
			"state": "hold",
			"enemy_points": 0,
			"target_points": 0,
		}
		if _intensity_dir != null:
			pressure_plan = _intensity_dir.build_pressure_plan(
				_wave_index,
				int(alive_counts.get("enemies", 0)),
				max(_current_enemy_density_reference, 1.0),
				CombatStats.get_enemy_kill_rate(),
				CombatStats.get_damage_taken_per_sec(),
				active_card
			)
		var pressure_enemy_budget: int = int(pressure_plan.get("enemy_points", 0))
		var pressure_target_budget: int = int(pressure_plan.get("target_points", 0))
		if pressure_enemy_budget <= 0 and pressure_target_budget <= 0:
			continue

		var max_tier: int = clamp(1 + _wave_index / 3 + max(GameFlow.get_active_stage_index(), 0), 1, 5)
		var pressure_combat_scaling: EnemyCombatScalingSnapshot = _build_enemy_combat_scaling_snapshot(_wave_index, _elapsed_sec)
		var pressure_reqs: Array[SpawnRequest] = _buyer.buy_wave(
			pressure_enemy_budget,
			pressure_target_budget,
			active_card,
			max_tier,
			_wave_index,
			max(GameFlow.get_active_stage_index(), 0),
			_elapsed_sec
		)
		pressure_reqs = _prioritize_requests(pressure_reqs, active_card)
		var pressure_spawn_profile: Dictionary = _build_spawn_profile(pressure_reqs, pressure_enemy_budget)
		var pressure_package_order: Array[String] = _get_enemy_package_order(pressure_reqs)
		var pressure_package_layouts: Dictionary = _build_enemy_package_layouts(pressure_package_order, pressure_spawn_profile)
		_apply_spawn_profile_anchor_radii(
			pressure_spawn_profile,
			pressure_package_order,
			pressure_package_layouts
		)
		_apply_enemy_combat_scaling(pressure_reqs, pressure_combat_scaling)
		var pressure_spawned_portals: Dictionary = {}
		for index in pressure_reqs.size():
			var req: SpawnRequest = pressure_reqs[index]
			if req == null:
				continue
			if req.kind == "Enemy" and req.enemy_def != null and req.count > 0:
				_ensure_package_portal_spawned(
					req,
					index,
					pressure_package_layouts,
					pressure_spawned_portals
				)
				_spawn_enemy_request_batch(
					req,
					req.count,
					_get_package_layout_for_request(req, index, pressure_package_layouts)
				)
			elif req.kind == "Target" and req.target_def != null and req.count > 0:
				_spawner.spawn_target_burst(req.target_def, req.count)

		_last_debug_snapshot["pressure_state"] = pressure_plan.get("state", "hold")
		_last_debug_snapshot["pressure_enemy_points"] = pressure_enemy_budget
		_last_debug_snapshot["pressure_target_points"] = pressure_target_budget
		_last_debug_snapshot["pressure_spawn_profile"] = pressure_spawn_profile.duplicate(true)
		_last_debug_snapshot["combat_scaling_intensity"] = pressure_combat_scaling.intensity if pressure_combat_scaling != null else 0.0
		_last_debug_snapshot["enemy_nanobot_multiplier"] = pressure_combat_scaling.nanobot_multiplier if pressure_combat_scaling != null else 1.0

func _prioritize_requests(reqs: Array[SpawnRequest], card: WaveCard) -> Array[SpawnRequest]:
	if reqs.is_empty():
		return reqs
	var enemy_reqs: Array[SpawnRequest] = []
	var target_reqs: Array[SpawnRequest] = []
	for req in reqs:
		if req == null:
			continue
		if req.kind == "Enemy":
			enemy_reqs.append(req)
		else:
			target_reqs.append(req)

	var enemy_first: bool = true
	if card != null:
		enemy_first = _rng.randf() <= clampf(card.enemy_first_bias, 0.0, 1.0)

	var ordered: Array[SpawnRequest] = []
	if enemy_first:
		for req in enemy_reqs:
			ordered.append(req)
		for req in target_reqs:
			ordered.append(req)
	else:
		for req in target_reqs:
			ordered.append(req)
		for req in enemy_reqs:
			ordered.append(req)
	return ordered

func _build_enemy_combat_scaling_snapshot(wave_index: int, elapsed_sec: float) -> EnemyCombatScalingSnapshot:
	if _enemy_combat_scaling_dir == null:
		return EnemyCombatScalingSnapshot.new()
	return _enemy_combat_scaling_dir.build_snapshot(wave_index, elapsed_sec)

func _apply_enemy_combat_scaling(reqs: Array[SpawnRequest], combat_scaling: EnemyCombatScalingSnapshot) -> void:
	if reqs.is_empty():
		return
	for req in reqs:
		if req == null or req.kind != "Enemy":
			continue
		req.enemy_combat_scaling = combat_scaling

func _rand_batch() -> int:
	return _rng.randi_range(batch_size_min, batch_size_max)

func _run_requests_async(reqs: Array[SpawnRequest], spawn_profile: Dictionary, package_layouts: Dictionary) -> void:
	_run_requests_coroutine(reqs, spawn_profile, package_layouts, _wave_token)

func _alive_enemy_count() -> int:
	var alive_now: Dictionary = _spawner.get_alive_counts()
	return int(alive_now.get("enemies", 0))

func _any_remaining(rem: Array[int]) -> bool:
	for n in rem:
		if n > 0:
			return true
	return false

func _build_spawn_profile(reqs: Array[SpawnRequest], enemy_points: int) -> Dictionary:
	var package_count: int = _get_enemy_package_order(reqs).size()
	var total_enemy_units: int = 0
	for req in reqs:
		if req == null or req.kind != "Enemy":
			continue
		total_enemy_units += max(req.count, 0)
	var budget_scale: float = clampf(float(enemy_points) / 18.0, 0.0, 1.0)
	var composition_scale: float = clampf(float(max(package_count - 1, 0)) / 3.0, 0.0, 1.0)
	var kill_nudge: float = clampf(CombatStats.get_enemy_kill_pressure_rate() / 20.0, 0.0, 0.15)
	var spawn_pressure_scale: float = clampf(
		budget_scale * 0.75 + composition_scale * 0.25 + kill_nudge,
		0.0,
		1.0
	)
	var opening_unit_cap: int = 0
	if total_enemy_units > 0:
		opening_unit_cap = min(
			total_enemy_units,
			clampi(int(round(lerpf(4.0, 18.0, spawn_pressure_scale))), 4, 18)
		)
	return {
		"package_count": package_count,
		"total_enemy_units": total_enemy_units,
		"budget_scale": budget_scale,
		"composition_scale": composition_scale,
		"kill_nudge": kill_nudge,
		"spawn_pressure_scale": spawn_pressure_scale,
		"opening_unit_cap": opening_unit_cap,
		"anchor_radii": [],
	}

func _get_enemy_package_order(reqs: Array[SpawnRequest]) -> Array[String]:
	var package_order: Array[String] = []
	var seen: Dictionary = {}
	for index in reqs.size():
		var req: SpawnRequest = reqs[index]
		if req == null or req.kind != "Enemy":
			continue
		var package_id: String = _resolve_package_id(req, index)
		if seen.has(package_id):
			continue
		seen[package_id] = true
		package_order.append(package_id)
	return package_order

func _apply_spawn_profile_anchor_radii(
	spawn_profile: Dictionary,
	package_order: Array[String],
	package_layouts: Dictionary
) -> void:
	var anchor_radii: Array[float] = []
	for package_id in package_order:
		if not package_layouts.has(package_id):
			continue
		var layout: Dictionary = package_layouts[package_id]
		anchor_radii.append(float(layout.get("anchor_radius", 0.0)))
	spawn_profile["anchor_radii"] = anchor_radii

func _build_enemy_package_layouts(package_order: Array[String], spawn_profile: Dictionary) -> Dictionary:
	var layouts: Dictionary = {}
	if _spawner == null:
		return layouts
	var chosen_anchors: Array[Vector3] = []
	var spawn_pressure_scale: float = float(spawn_profile.get("spawn_pressure_scale", 0.0))
	for package_id in package_order:
		var layout: Dictionary = _spawner.build_enemy_pack_layout(spawn_pressure_scale, chosen_anchors)
		layouts[package_id] = layout
		var anchor: Vector3 = layout.get("anchor", Vector3.ZERO)
		chosen_anchors.append(anchor)
	return layouts

func _build_package_request_indices(reqs: Array[SpawnRequest]) -> Dictionary:
	var package_indices: Dictionary = {}
	for index in reqs.size():
		var req: SpawnRequest = reqs[index]
		if req == null or req.kind != "Enemy":
			continue
		var package_id: String = _resolve_package_id(req, index)
		if not package_indices.has(package_id):
			package_indices[package_id] = []
		var indices: Array = package_indices[package_id]
		indices.append(index)
		package_indices[package_id] = indices
	return package_indices

func _resolve_package_id(req: SpawnRequest, fallback_index: int) -> String:
	if req != null:
		var trimmed: String = req.package_id.strip_edges()
		if trimmed != "":
			return trimmed
	return "package_%d" % fallback_index

func _get_package_layout_for_request(req: SpawnRequest, req_index: int, package_layouts: Dictionary) -> Dictionary:
	var package_id: String = _resolve_package_id(req, req_index)
	if package_layouts.has(package_id):
		return package_layouts[package_id]
	return {}

func _ensure_package_portal_spawned(
	req: SpawnRequest,
	req_index: int,
	package_layouts: Dictionary,
	spawned_portals: Dictionary
) -> void:
	if req == null or req.kind != "Enemy" or _spawner == null:
		return
	var package_id: String = _resolve_package_id(req, req_index)
	if spawned_portals.has(package_id):
		return
	var package_layout: Dictionary = _get_package_layout_for_request(req, req_index, package_layouts)
	if package_layout.is_empty():
		return
	var anchor: Vector3 = package_layout.get("anchor", Vector3.ZERO)
	var member_radius: float = float(package_layout.get("member_radius", 0.0))
	var spawn_pressure_scale: float = float(package_layout.get("spawn_pressure_scale", 0.0))
	_spawner.spawn_enemy_pack_warp(anchor, member_radius, spawn_pressure_scale)
	spawned_portals[package_id] = true

func _spawn_enemy_request_batch(req: SpawnRequest, count: int, package_layout: Dictionary = {}) -> int:
	if req == null or req.enemy_def == null or count <= 0:
		return 0
	if _spawner == null:
		return 0
	if package_layout.is_empty():
		return _spawner.spawn_enemy_burst(req.enemy_def, count, req)
	var anchor: Vector3 = package_layout.get("anchor", Vector3.ZERO)
	var member_radius: float = float(package_layout.get("member_radius", 0.0))
	return _spawner.spawn_enemy_pack_burst(req.enemy_def, count, anchor, member_radius, req)

func _run_requests_coroutine(
	reqs: Array[SpawnRequest],
	spawn_profile: Dictionary,
	package_layouts: Dictionary,
	token: int
) -> void:
	var remaining: Array[int] = []
	for req in reqs:
		remaining.append(req.count)

	var package_order: Array[String] = _get_enemy_package_order(reqs)
	var package_indices: Dictionary = _build_package_request_indices(reqs)
	var spawned_package_portals: Dictionary = {}
	var opening_remaining: int = int(spawn_profile.get("opening_unit_cap", 0))
	if opening_remaining > 0:
		for package_id in package_order:
			if opening_remaining <= 0:
				break
			if not package_indices.has(package_id):
				continue
			var indices: Array = package_indices[package_id]
			var package_layout: Dictionary = package_layouts.get(package_id, {})
			var package_spawned_any: bool = false
			var package_stalled: bool = false
			for index_variant in indices:
				if opening_remaining <= 0:
					break
				var req_index: int = int(index_variant)
				if req_index < 0 or req_index >= reqs.size():
					continue
				var req: SpawnRequest = reqs[req_index]
				if req == null or req.kind != "Enemy" or req.enemy_def == null:
					continue
				var spawn_now: int = min(remaining[req_index], opening_remaining)
				if spawn_now <= 0:
					continue
				_ensure_package_portal_spawned(
					req,
					req_index,
					package_layouts,
					spawned_package_portals
				)
				var opening_spawned: int = _spawn_enemy_request_batch(req, spawn_now, package_layout)
				if opening_spawned <= 0:
					package_stalled = true
					break
				remaining[req_index] = max(remaining[req_index] - opening_spawned, 0)
				opening_remaining = max(opening_remaining - opening_spawned, 0)
				package_spawned_any = true
			if package_stalled:
				var opening_retry: SceneTreeTimer = _create_pausable_timer(0.35)
				await opening_retry.timeout
				if token != _wave_token:
					return
			elif package_spawned_any:
				await get_tree().process_frame
				if token != _wave_token:
					return

	var req_index: int = 0
	while _any_remaining(remaining):
		var found: bool = false
		for step in reqs.size():
			var idx: int = (req_index + step) % reqs.size()
			if remaining[idx] > 0:
				req_index = idx
				found = true
				break
		if not found:
			break

		var req: SpawnRequest = reqs[req_index]
		var batch_size: int = clampi(_rand_batch(), req.batch_size_min, req.batch_size_max)
		batch_size = min(batch_size, remaining[req_index])

		var spawned: int = 0
		if req.kind == "Enemy":
			_ensure_package_portal_spawned(
				req,
				req_index,
				package_layouts,
				spawned_package_portals
			)
			spawned = _spawn_enemy_request_batch(
				req,
				batch_size,
				_get_package_layout_for_request(req, req_index, package_layouts)
			)
		else:
			spawned = _spawner.spawn_target_burst(req.target_def, batch_size)

		if spawned == 0:
			var wait_cap: SceneTreeTimer = _create_pausable_timer(0.35)
			await wait_cap.timeout
			if token != _wave_token:
				return
		else:
			remaining[req_index] = max(remaining[req_index] - spawned, 0)
			var wait: SceneTreeTimer = _create_pausable_timer(req.inter_batch_sec)
			await wait.timeout
			if token != _wave_token:
				return

		if _wave_timer >= wave_timeout_sec:
			emit_signal("wave_forced_next", _wave_index)
			if _should_trigger_victory():
				GameFlow.player_won()
				return
			_start_downtime()
			return

	await _clear_or_timeout_then_downtime(token)

func _clear_or_timeout_then_downtime(token: int) -> void:
	var end_deadline: float = _wave_timer + wave_timeout_sec
	while _wave_timer < end_deadline:
		if token != _wave_token:
			return
		var enemies_alive: int = _alive_enemy_count()
		if enemies_alive <= wave_clear_carryover_ok:
			emit_signal("wave_cleared", _wave_index, _wave_timer)
			if _should_trigger_victory():
				GameFlow.player_won()
				return
			_start_downtime()
			return
		var t: SceneTreeTimer = _create_pausable_timer(0.5)
		await t.timeout

	emit_signal("wave_forced_next", _wave_index)
	if _should_trigger_victory():
		GameFlow.player_won()
		return
	_start_downtime()

func _on_stage_changed(_stage: StageDef, _stage_index: int) -> void:
	_pending_card = null
	_active_card = null
	_recent_card_ids.clear()
	_clear_active_boss_state()
	_gateway_hold_active = false
	if _buyer != null:
		_buyer.clear_history()

func _should_trigger_victory() -> bool:
	var current_stage: StageDef = GameFlow.get_current_stage()
	if current_stage != null and current_stage.should_spawn_boss_wave():
		return false
	return victory_wave_index > 0 and _wave_index >= victory_wave_index

func _should_start_boss_wave() -> bool:
	var current_stage: StageDef = GameFlow.get_current_stage()
	if current_stage == null:
		return false
	if _gateway_hold_active:
		return false
	if not current_stage.should_spawn_boss_wave():
		return false
	return _wave_index == current_stage.boss_wave_index

func _start_boss_wave() -> void:
	if _spawner == null:
		push_error("WaveDirector: unable to start boss wave without spawner.")
		return
	var current_stage: StageDef = GameFlow.get_current_stage()
	if current_stage == null:
		push_error("WaveDirector: unable to resolve active stage for boss wave.")
		return
	var boss_def: EnemyBossDef = _choose_boss_for_stage(current_stage)
	if boss_def == null:
		push_error("WaveDirector: active stage has no valid boss definition for its configured faction.")
		return

	_clear_non_boss_hostiles()
	var boss_request: SpawnRequest = SpawnRequest.new()
	boss_request.kind = "Enemy"
	boss_request.enemy_def = boss_def
	boss_request.count = 1
	boss_request.wave_index = _wave_index
	boss_request.stage_index = max(GameFlow.get_active_stage_index(), 0)
	boss_request.elapsed_sec = _elapsed_sec
	boss_request.enemy_combat_scaling = _build_enemy_combat_scaling_snapshot(_wave_index, _elapsed_sec)

	var spawned_node: Node3D = _spawner.spawn_one_with_def(Spawner.SpawnKind.ENEMY, boss_def, boss_request)
	var boss_enemy: Enemy = spawned_node as Enemy
	if boss_enemy == null:
		push_error("WaveDirector: failed to spawn boss actor for `%s`." % boss_def.id)
		return

	_clear_active_boss_state()
	_boss_wave_active = true
	_active_boss_def = boss_def
	_active_boss_instance = boss_enemy
	if not boss_enemy.about_to_die.is_connected(_on_active_boss_about_to_die):
		boss_enemy.about_to_die.connect(_on_active_boss_about_to_die)
	GameFlow.begin_boss_encounter(boss_def, _wave_index)
	boss_wave_started.emit(boss_def, _wave_index)

func _choose_boss_for_stage(stage: StageDef) -> EnemyBossDef:
	if stage == null:
		return null
	var pool: Array[EnemyBossDef] = stage.get_boss_pool()
	if pool.is_empty():
		return null
	if pool.size() == 1:
		return pool[0]
	var index: int = _rng.randi_range(0, pool.size() - 1)
	return pool[index]

func _on_active_boss_about_to_die(target: Enemy) -> void:
	if target == null or target != _active_boss_instance:
		return
	var boss_def: EnemyBossDef = _active_boss_def
	var resolved_wave_index: int = _wave_index
	var current_stage: StageDef = GameFlow.get_current_stage()
	var gateway_position: Vector3 = target.global_position
	var carryover_snapshot: EnemyCombatScalingSnapshot = _build_enemy_combat_scaling_snapshot(_wave_index, _elapsed_sec)
	_clear_active_boss_state()
	if boss_def != null:
		GameFlow.complete_boss_encounter(true, false)
		boss_wave_ended.emit(boss_def, resolved_wave_index, true)
	emit_signal("wave_cleared", resolved_wave_index, _wave_timer)
	if (
		current_stage != null
		and current_stage.should_open_gateway_on_boss_defeat()
		and GameFlow.has_next_stage()
	):
		if _enemy_combat_scaling_dir != null:
			_enemy_combat_scaling_dir.set_carried_baseline_from_snapshot(carryover_snapshot)
		_enter_gateway_hold(current_stage, gateway_position)
		return
	GameFlow.player_won()

func begin_stage_after_gateway_transfer() -> void:
	_reset_stage_runtime(false, false, true)

func _clear_active_boss_state() -> void:
	if _active_boss_instance != null and is_instance_valid(_active_boss_instance):
		if _active_boss_instance.about_to_die.is_connected(_on_active_boss_about_to_die):
			_active_boss_instance.about_to_die.disconnect(_on_active_boss_about_to_die)
	_active_boss_instance = null
	_active_boss_def = null
	_boss_wave_active = false

func _clear_non_boss_hostiles() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var targets: Array[Node] = tree.get_nodes_in_group("targets")
	for entry in targets:
		if entry == null or not is_instance_valid(entry):
			continue
		if entry is Enemy:
			var enemy: Enemy = entry as Enemy
			if enemy is EnemyBoss:
				continue
			enemy.queue_free()
			continue
		if entry is TargetObject:
			(entry as TargetObject).queue_free()

func _enter_gateway_hold(stage: StageDef, position: Vector3) -> void:
	_gateway_hold_active = true
	_state = RunState.State.GATEWAY_HOLD
	RunState.set_state(RunState.State.GATEWAY_HOLD)
	_active_card = null
	_pending_card = null
	_wave_token += 1
	RunState.set_wave_context(_wave_index, 0, 0, _progression_wave_index)
	_last_debug_snapshot = {
		"wave_index": _wave_index,
		"progression_wave_index": _progression_wave_index,
		"stage_index": max(GameFlow.get_active_stage_index(), 0),
		"state": "gateway_hold",
	}
	gateway_ready.emit(stage, position)

func _reset_stage_runtime(clear_progression: bool, clear_scaling_baseline: bool, first_downtime: bool) -> void:
	_wave_token += 1
	_wave_index = 0
	_wave_timer = 0.0
	_elapsed_sec = 0.0
	_downtime_remaining = 0.0
	_pending_card = null
	_active_card = null
	_recent_card_ids.clear()
	_last_debug_snapshot = {}
	_gateway_hold_active = false
	_clear_active_boss_state()
	if clear_progression:
		_progression_wave_index = 0
		RunState.reset_wave_progression()
	else:
		RunState.set_wave_context(0, 0, 0, _progression_wave_index)
	if clear_scaling_baseline and _enemy_combat_scaling_dir != null:
		_enemy_combat_scaling_dir.clear_carried_baseline()
	if _buyer != null:
		_buyer.clear_history()
	_start_downtime(first_downtime)
