extends Node
class_name WaveDirector

signal wave_started(index: int, enemy_budget: int, target_budget: int)
signal wave_cleared(index: int, time_sec: float)
signal wave_forced_next(index: int)
signal downtime_started(duration: float, next_wave_index: int)
signal downtime_ended(next_wave_index: int)
signal next_wave_eta(seconds: float)

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

func get_state() -> RunState.State:
	return _state

func get_wave_index() -> int:
	return _wave_index

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
	_start_downtime(true)
	_start_pressure_loop()

func _process(delta: float) -> void:
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
		var wave_timeout_left: float = max(wave_timeout_sec - _wave_timer, 0.0)
		var eta: float = wave_timeout_left + downtime_sec
		next_wave_eta.emit(eta)

func _start_downtime(first: bool = false) -> void:
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
	_wave_timer = 0.0
	_active_card = _consume_pending_card()
	_remember_card(_active_card)
	if _intensity_dir != null:
		_intensity_dir.begin_wave()

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

	RunState.set_wave_context(_wave_index, int(budgets["enemy_points"]), int(budgets["target_points"]))

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
	_apply_enemy_combat_scaling(reqs, combat_scaling)

	_last_debug_snapshot = _build_wave_debug_snapshot(
		_active_card,
		stage_index,
		threat,
		budgets,
		opening_adjustment,
		combat_scaling
	)

	emit_signal("wave_started", _wave_index, budgets["enemy_points"], budgets["target_points"])
	_run_requests_async(reqs, _active_card)

func _build_wave_debug_snapshot(
	card: WaveCard,
	stage_index: int,
	threat: float,
	budgets: Dictionary,
	opening_adjustment: Dictionary,
	combat_scaling: EnemyCombatScalingSnapshot
) -> Dictionary:
	var snapshot: Dictionary = {
		"wave_index": _wave_index,
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
		_apply_enemy_combat_scaling(pressure_reqs, pressure_combat_scaling)
		for req in pressure_reqs:
			if req.kind == "Enemy" and req.enemy_def != null and req.count > 0:
				_spawner.spawn_enemy_burst(req.enemy_def, req.count, req)
			elif req.kind == "Target" and req.target_def != null and req.count > 0:
				_spawner.spawn_target_burst(req.target_def, req.count)

		_last_debug_snapshot["pressure_state"] = pressure_plan.get("state", "hold")
		_last_debug_snapshot["pressure_enemy_points"] = pressure_enemy_budget
		_last_debug_snapshot["pressure_target_points"] = pressure_target_budget
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

func _run_requests_async(reqs: Array[SpawnRequest], card: WaveCard) -> void:
	_run_requests_coroutine(reqs, card, _wave_token)

func _alive_enemy_count() -> int:
	var alive_now: Dictionary = _spawner.get_alive_counts()
	return int(alive_now.get("enemies", 0))

func _any_remaining(rem: Array[int]) -> bool:
	for n in rem:
		if n > 0:
			return true
	return false

func _run_requests_coroutine(reqs: Array[SpawnRequest], card: WaveCard, token: int) -> void:
	var remaining: Array[int] = []
	for req in reqs:
		remaining.append(req.count)

	var req_index: int = 0
	if reqs.size() > 0:
		var first: SpawnRequest = reqs[0]
		var first_batch: int = _rand_batch()
		var n0: int = min(first_batch, remaining[0])
		if n0 > 0:
			var spawned0: int = 0
			if first.kind == "Enemy":
				spawned0 = _spawner.spawn_enemy_burst(first.enemy_def, n0, first)
			else:
				spawned0 = _spawner.spawn_target_burst(first.target_def, n0)
			remaining[0] = max(remaining[0] - spawned0, 0)
		var timer0: SceneTreeTimer = _create_pausable_timer(inter_batch_delay)
		await timer0.timeout
		if token != _wave_token:
			return

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
			spawned = _spawner.spawn_enemy_burst(req.enemy_def, batch_size, req)
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
			_start_downtime()
			return
		var t: SceneTreeTimer = _create_pausable_timer(0.5)
		await t.timeout

	emit_signal("wave_forced_next", _wave_index)
	_start_downtime()

func _on_stage_changed(_stage: StageDef, _stage_index: int) -> void:
	_pending_card = null
	_active_card = null
	_recent_card_ids.clear()
	if _buyer != null:
		_buyer.clear_history()
