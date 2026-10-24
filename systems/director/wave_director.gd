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
@export var pressure_target_point_budget: int = 0

@export var batch_size_min: int = 2
@export var batch_size_max: int = 4

@export_group("Formation Delivery")
## Minimum share of purchased enemies included in complete opening formations.
@export_range(0.0, 1.0) var opening_formation_unit_share: float = 0.6
## Launch at least this many formations immediately when available.
@export var minimum_opening_formations: int = 2
## Time between complete reinforcement formation launches.
@export var formation_launch_interval_sec: float = 2.0
## Compress reinforcement intervals so the final planned launch fits this window.
@export var formation_dispatch_window_sec: float = 8.0

@export_group("Delivery Diagnostics")
## Interval between alive/nearby enemy samples; no per-frame scene scan.
@export var delivery_sample_interval_sec: float = 0.5
## Radius used by the explicitly labelled nearby-enemy diagnostic.
@export var delivery_nearby_radius_m: float = 1000.0

@export_group("")

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
var _active_dispatches: Array[Dictionary] = []
var _delivery_history: Array[Dictionary] = []
var _main_delivery: Dictionary = {}
var _delivery_sample_remaining: float = 0.0
var _run_finished: bool = false

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
	return max(_get_wave_timeout_sec() - _wave_timer, 0.0)

func _get_wave_timeout_sec() -> float:
	var stage: StageDef = GameFlow.get_current_stage()
	if stage != null and stage.wave_timeout_override_sec > 0.0:
		return stage.wave_timeout_override_sec
	return wave_timeout_sec

func _get_downtime_sec() -> float:
	var stage: StageDef = GameFlow.get_current_stage()
	if stage != null and stage.downtime_override_sec >= 0.0:
		return stage.downtime_override_sec
	return downtime_sec

func _get_max_enemy_tier() -> int:
	return _get_max_enemy_tier_for_wave(_wave_index)

func _get_max_enemy_tier_for_wave(wave_index: int) -> int:
	var stage: StageDef = GameFlow.get_current_stage()
	var wave_offset: int = max(wave_index - 1, 0)
	if stage != null and wave_offset < stage.authored_tier_caps.size():
		return clampi(stage.authored_tier_caps[wave_offset], 1, 5)
	return clampi(1 + int(wave_index / 3) + max(GameFlow.get_active_stage_index(), 0), 1, 5)

func get_downtime_remaining() -> float:
	return max(_downtime_remaining, 0.0)

func get_debug_snapshot() -> Dictionary:
	return _last_debug_snapshot.duplicate(true)

func get_delivery_history() -> Array[Dictionary]:
	# Each record contains values only, so completed requests release their resources.
	return _delivery_history.duplicate(true)

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
	if not GameFlow.run_completed.is_connected(_on_run_completed):
		GameFlow.run_completed.connect(_on_run_completed)
	_rng.randomize()
	_reset_stage_runtime(true, true, true)
	_start_pressure_loop()

func _process(delta: float) -> void:
	_delivery_sample_remaining -= delta
	if _delivery_sample_remaining <= 0.0:
		_delivery_sample_remaining = maxf(delivery_sample_interval_sec, 0.1)
		_sample_delivery_density()
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
		var wave_timeout_left: float = max(_get_wave_timeout_sec() - _wave_timer, 0.0)
		var eta: float = wave_timeout_left + _get_downtime_sec()
		next_wave_eta.emit(eta)

func _start_downtime(first: bool = false) -> void:
	_cancel_active_deliveries("downtime_started")
	_gateway_hold_active = false
	_state = RunState.State.DOWNTIME
	RunState.set_state(RunState.State.DOWNTIME)
	_active_card = null
	_downtime_remaining = 5.0 if first else _get_downtime_sec()
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
	var stage: StageDef = GameFlow.get_current_stage()
	var run: RunDefinition = GameFlow.get_active_run_definition()
	var locked_faction: FactionDef = run.enemy_faction if run != null else null
	var next_index: int = _wave_index + 1 if _state == RunState.State.DOWNTIME else _wave_index
	if stage != null and stage.ordered_wave_cards and not deck.is_empty():
		var authored_card: WaveCard = deck[clampi(next_index - 1, 0, deck.size() - 1)]
		if locked_faction == null or authored_card.get_faction_bias_id() == locked_faction.get_faction_id():
			return authored_card
	var unlocked_tier: int = _get_max_enemy_tier_for_wave(next_index)
	var eligible: Array[WaveCard] = []
	for entry: WaveCard in deck:
		if entry == null or entry.min_enemy_tier > unlocked_tier or entry.weight <= 0.0:
			continue
		if locked_faction != null and entry.get_faction_bias_id() != locked_faction.get_faction_id():
			continue
		eligible.append(entry)

	var candidates: Array[WaveCard] = []
	for entry: WaveCard in eligible:
		if not _is_card_on_cooldown(entry):
			candidates.append(entry)
	if candidates.is_empty():
		candidates = eligible
	if candidates.is_empty():
		# Even a malformed deck must not fall back to another faction's enemies.
		var fallback: WaveCard = WaveCard.new()
		fallback.faction_bias = locked_faction if locked_faction != null else (stage.boss_faction if stage != null else null)
		return fallback

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
	_cancel_active_deliveries("wave_token_invalidated")
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
	var opening_adjustment: Dictionary = {"enemy_points": int(budgets.get("enemy_points", 0)), "scale": 1.0}
	if _intensity_dir != null:
		opening_adjustment = _intensity_dir.get_opening_adjustment(
			int(budgets.get("enemy_points", 0)),
			kill_rate,
			incoming_damage
		)
	budgets["enemy_points"] = int(opening_adjustment.get("enemy_points", budgets.get("enemy_points", 0)))
	var stage: StageDef = GameFlow.get_current_stage()
	var wave_offset: int = max(_wave_index - 1, 0)
	if stage != null and wave_offset < stage.authored_enemy_budgets.size():
		budgets["enemy_points"] = max(stage.authored_enemy_budgets[wave_offset], 0)
		opening_adjustment["enemy_points"] = budgets["enemy_points"]
		opening_adjustment["scale"] = 1.0
	_current_enemy_density_reference = max(
		soft_enemy_density_base + float(max(_wave_index - 1, 0)) * soft_enemy_density_per_wave,
		float(int(budgets.get("enemy_points", 0))) * 0.65
	)

	RunState.set_wave_context(
		_wave_index,
		int(budgets["enemy_points"]),
		int(budgets["target_points"]),
		_progression_wave_index
	)

	var max_tier: int = _get_max_enemy_tier()
	var reqs: Array[SpawnRequest] = []
	var combat_scaling: EnemyCombatScalingSnapshot = _build_enemy_combat_scaling_snapshot(_wave_index, _elapsed_sec)
	if _buyer != null:
		# Authored lessons may deliberately repeat a primary role. Procedural
		# anti-repetition must not replace that lesson with a different role.
		if stage != null and stage.ordered_wave_cards:
			_buyer.clear_history()
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

func _exit_tree() -> void:
	_cancel_active_deliveries("director_removed")
	_wave_token += 1
	_pressure_token += 1
	# Resume suspended requests through their cancellation guards before the
	# timers disappear, so their stage and enemy resources can be released.
	for child: Node in get_children():
		if child is Timer:
			(child as Timer).timeout.emit()

func _create_pausable_timer(seconds: float) -> Timer:
	# Owning these timers releases suspended wave requests when the encounter
	# exits, even if the menu pauses the tree before their timeout can run.
	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(seconds, 0.001)
	timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(timer)
	timer.timeout.connect(timer.queue_free, CONNECT_ONE_SHOT)
	timer.start()
	return timer

func _run_pressure_coroutine(token: int) -> void:
	while true:
		var t: Timer = _create_pausable_timer(pressure_interval_sec)
		await t.timeout
		if token != _pressure_token:
			return
		if _run_finished:
			return
		if _buyer == null or _spawner == null:
			continue
		var stage: StageDef = GameFlow.get_current_stage()
		if stage != null and not stage.pressure_reinforcements_enabled:
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
				_spawn_downtime_target_requests(target_reqs)
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

		var max_tier: int = _get_max_enemy_tier()
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
		_run_requests_coroutine(
			pressure_reqs,
			pressure_spawn_profile,
			pressure_package_layouts,
			_wave_token,
			"pressure",
			false
		)

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
		if req == null or req.kind != "Enemy" or req.count <= 0:
			continue
		req.enemy_combat_scaling = combat_scaling

func _rand_batch() -> int:
	return _rng.randi_range(batch_size_min, batch_size_max)

func _run_requests_async(reqs: Array[SpawnRequest], spawn_profile: Dictionary, package_layouts: Dictionary) -> void:
	_run_requests_coroutine(reqs, spawn_profile, package_layouts, _wave_token)

func _alive_enemy_count() -> int:
	var alive_now: Dictionary = _spawner.get_alive_counts()
	return int(alive_now.get("enemies", 0))

func _build_spawn_profile(reqs: Array[SpawnRequest], enemy_points: int) -> Dictionary:
	var package_order: Array[String] = _get_enemy_package_order(reqs)
	var package_count: int = package_order.size()
	var package_units: Dictionary = {}
	var total_enemy_units: int = 0
	for index in reqs.size():
		var req: SpawnRequest = reqs[index]
		if req == null or req.kind != "Enemy" or req.count <= 0:
			continue
		total_enemy_units += max(req.count, 0)
		var package_id: String = _resolve_package_id(req, index)
		package_units[package_id] = int(package_units.get(package_id, 0)) + max(req.count, 0)
	var budget_scale: float = clampf(float(enemy_points) / 18.0, 0.0, 1.0)
	var composition_scale: float = clampf(float(max(package_count - 1, 0)) / 3.0, 0.0, 1.0)
	var kill_nudge: float = clampf(CombatStats.get_enemy_kill_pressure_rate() / 20.0, 0.0, 0.15)
	var spawn_pressure_scale: float = clampf(
		budget_scale * 0.75 + composition_scale * 0.25 + kill_nudge,
		0.0,
		1.0
	)
	var opening_package_ids: Array[String] = []
	var opening_enemy_units: int = 0
	var minimum_opening: int = mini(package_count, maxi(minimum_opening_formations, 1))
	var desired_opening_units: int = int(ceil(float(total_enemy_units) * clampf(opening_formation_unit_share, 0.0, 1.0)))
	for package_id in package_order:
		if opening_enemy_units >= desired_opening_units and opening_package_ids.size() >= minimum_opening:
			break
		opening_package_ids.append(package_id)
		opening_enemy_units += int(package_units.get(package_id, 0))
	var remaining_package_count: int = package_count - opening_package_ids.size()
	var launch_interval: float = 0.0
	if remaining_package_count > 0:
		launch_interval = minf(maxf(formation_launch_interval_sec, 0.0), maxf(formation_dispatch_window_sec, 0.0) / float(remaining_package_count))
	var formation_schedule: Array[Dictionary] = []
	for index in package_order.size():
		var package_id: String = package_order[index]
		var delayed_index: int = maxi(index - opening_package_ids.size() + 1, 0)
		formation_schedule.append({
			"package_id": package_id,
			"units": int(package_units.get(package_id, 0)),
			"launch_at_sec": float(delayed_index) * launch_interval,
		})
	return {
		"package_count": package_count,
		"total_enemy_units": total_enemy_units,
		"budget_scale": budget_scale,
		"composition_scale": composition_scale,
		"kill_nudge": kill_nudge,
		"spawn_pressure_scale": spawn_pressure_scale,
		"opening_package_ids": opening_package_ids,
		"opening_enemy_units": opening_enemy_units,
		"formation_schedule": formation_schedule,
		"formation_launch_interval_sec": launch_interval,
		"planned_dispatch_duration_sec": float(remaining_package_count) * launch_interval,
		"anchor_radii": [],
	}

func _get_enemy_package_order(reqs: Array[SpawnRequest]) -> Array[String]:
	var package_order: Array[String] = []
	var seen: Dictionary = {}
	for index in reqs.size():
		var req: SpawnRequest = reqs[index]
		if req == null or req.kind != "Enemy" or req.count <= 0:
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
		if req == null or req.kind != "Enemy" or req.count <= 0:
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
	token: int,
	source: String = "wave",
	owns_wave_completion: bool = true
) -> void:
	var dispatch: Dictionary = _begin_delivery(reqs, token, source)
	var package_indices: Dictionary = _build_package_request_indices(reqs)
	var spawned_package_portals: Dictionary = {}
	# Targets retain their authored batch cadence and do not wait behind ships.
	_run_target_delivery(reqs, dispatch)
	var schedule: Array = spawn_profile.get("formation_schedule", [])
	for formation_variant in schedule:
		var formation: Dictionary = formation_variant as Dictionary
		var stop_reason: String = _delivery_stop_reason(dispatch)
		if stop_reason != "":
			_cancel_delivery(dispatch, stop_reason)
			break
		var due_time: float = float(dispatch["started_wave_sec"]) + float(formation.get("launch_at_sec", 0.0))
		var wait_sec: float = minf(due_time - _wave_timer, _get_wave_timeout_sec() - _wave_timer)
		if wait_sec > 0.0:
			var launch_timer: Timer = _create_pausable_timer(wait_sec)
			await launch_timer.timeout
		stop_reason = _delivery_stop_reason(dispatch)
		if stop_reason != "":
			_cancel_delivery(dispatch, stop_reason)
			break
		var package_id: String = String(formation.get("package_id", ""))
		var indices: Array = package_indices.get(package_id, [])
		# A complete formation shares a launch; the spawner retains warp staggering.
		for index_variant in indices:
			stop_reason = _delivery_stop_reason(dispatch)
			if stop_reason != "":
				_cancel_delivery(dispatch, stop_reason)
				break
			var req_index: int = int(index_variant)
			var req: SpawnRequest = reqs[req_index]
			var remaining: Array = dispatch["remaining"]
			var count: int = int(remaining[req_index])
			if count <= 0:
				continue
			if req.enemy_def == null:
				_cancel_request_units(dispatch, req_index, count, "invalid_enemy_definition")
				continue
			_ensure_package_portal_spawned(req, req_index, package_layouts, spawned_package_portals)
			var spawned: int = _spawn_enemy_request_batch(req, count, _get_package_layout_for_request(req, req_index, package_layouts))
			_record_spawned_units(dispatch, req_index, mini(spawned, count))
			if spawned < count:
				_cancel_request_units(dispatch, req_index, count - maxi(spawned, 0), "spawn_unavailable")
	_finish_delivery_if_complete(dispatch)
	if owns_wave_completion:
		await _clear_or_timeout_then_downtime(token)

func _begin_delivery(reqs: Array[SpawnRequest], token: int, source: String, allow_downtime: bool = false) -> Dictionary:
	var remaining: Array[int] = []
	var enemy_units: int = 0
	var target_units: int = 0
	var formations: Dictionary = {}
	for index in reqs.size():
		var req: SpawnRequest = reqs[index]
		var count: int = maxi(req.count, 0) if req != null else 0
		remaining.append(count)
		if req == null:
			continue
		if req.kind == "Enemy":
			enemy_units += count
			var package_id: String = _resolve_package_id(req, index)
			if not formations.has(package_id):
				formations[package_id] = {"planned_units": 0, "spawned_units": 0, "cancelled_units": 0, "composition": []}
			var formation: Dictionary = formations[package_id]
			formation["planned_units"] = int(formation["planned_units"]) + count
			var composition: Array = formation["composition"]
			composition.append({"enemy_id": String(req.enemy_def.id) if req.enemy_def != null else "", "count": count})
		else:
			target_units += count
	var ledger: Dictionary = {
		"source": source,
		"wave_token": token,
		"wave_index": _wave_index,
		"planned_units": enemy_units,
		"spawned_units": 0,
		"pending_units": enemy_units,
		"cancelled_units": 0,
		"cancel_reasons": {},
		"dispatch_duration_sec": 0.0,
		"peak_alive_enemies": 0,
		"peak_nearby_enemies": 0,
		"nearby_radius_m": delivery_nearby_radius_m,
		"nearby_sample_interval_sec": delivery_sample_interval_sec,
		"formations": formations,
		"target_delivery": {"planned_units": target_units, "spawned_units": 0, "pending_units": target_units, "cancelled_units": 0, "cancel_reasons": {}},
	}
	var dispatch: Dictionary = {
		"ledger": ledger,
		"requests": reqs,
		"remaining": remaining,
		"token": token,
		"started_wave_sec": _wave_timer,
		"cancelled": false,
		"complete": false,
		"allow_downtime": allow_downtime,
	}
	_active_dispatches.append(dispatch)
	_delivery_history.append(ledger)
	while _delivery_history.size() > 32:
		_delivery_history.remove_at(0)
	if source == "wave":
		_main_delivery = ledger
		_last_debug_snapshot["delivery"] = ledger
	elif source == "pressure":
		var pressure_deliveries: Array = _last_debug_snapshot.get("pressure_deliveries", [])
		pressure_deliveries.append(ledger)
		_last_debug_snapshot["pressure_deliveries"] = pressure_deliveries
	return dispatch

func _delivery_stop_reason(dispatch: Dictionary) -> String:
	if bool(dispatch.get("cancelled", false)):
		return "dispatch_cancelled"
	if not is_inside_tree():
		return "director_removed"
	if int(dispatch.get("token", -1)) != _wave_token:
		return "wave_token_invalidated"
	if _run_finished:
		return "run_completed"
	if _gateway_hold_active:
		return "gateway_hold"
	if _boss_wave_active:
		return "boss_wave_started"
	if bool(dispatch.get("allow_downtime", false)):
		return "" if _state == RunState.State.DOWNTIME else "downtime_ended"
	if _state != RunState.State.IN_WAVE:
		return "wave_ended"
	if _wave_timer >= _get_wave_timeout_sec():
		return "wave_timeout"
	var tree: SceneTree = get_tree()
	var player: Node = tree.get_first_node_in_group("player") if tree != null else null
	if player != null and player.has_method("is_alive") and not bool(player.call("is_alive")):
		return "player_dead"
	return ""

func _record_spawned_units(dispatch: Dictionary, req_index: int, count: int) -> void:
	if count <= 0:
		return
	var remaining: Array = dispatch["remaining"]
	count = mini(count, int(remaining[req_index]))
	remaining[req_index] = int(remaining[req_index]) - count
	var reqs: Array = dispatch["requests"]
	var req: SpawnRequest = reqs[req_index] as SpawnRequest
	var ledger: Dictionary = dispatch["ledger"]
	var counters: Dictionary = ledger if req.kind == "Enemy" else ledger["target_delivery"]
	counters["spawned_units"] = int(counters["spawned_units"]) + count
	counters["pending_units"] = int(counters["pending_units"]) - count
	if req.kind == "Enemy":
		ledger["dispatch_duration_sec"] = maxf(_wave_timer - float(dispatch["started_wave_sec"]), 0.0)
		var formations: Dictionary = ledger["formations"]
		var formation: Dictionary = formations[_resolve_package_id(req, req_index)]
		formation["spawned_units"] = int(formation["spawned_units"]) + count
		# Cheap purchased-unit peak capture also covers battles shorter than a sample.
		var alive: int = _alive_enemy_count() if _spawner != null else 0
		ledger["peak_alive_enemies"] = maxi(int(ledger["peak_alive_enemies"]), alive)
		if int(_main_delivery.get("wave_token", -1)) == int(dispatch["token"]):
			_main_delivery["peak_alive_enemies"] = maxi(int(_main_delivery.get("peak_alive_enemies", 0)), alive)

func _cancel_request_units(dispatch: Dictionary, req_index: int, count: int, reason: String) -> void:
	var remaining: Array = dispatch["remaining"]
	count = mini(maxi(count, 0), int(remaining[req_index]))
	if count <= 0:
		return
	remaining[req_index] = int(remaining[req_index]) - count
	var reqs: Array = dispatch["requests"]
	var req: SpawnRequest = reqs[req_index] as SpawnRequest
	var ledger: Dictionary = dispatch["ledger"]
	var counters: Dictionary = ledger if req.kind == "Enemy" else ledger["target_delivery"]
	counters["pending_units"] = int(counters["pending_units"]) - count
	counters["cancelled_units"] = int(counters["cancelled_units"]) + count
	var reasons: Dictionary = counters["cancel_reasons"]
	reasons[reason] = int(reasons.get(reason, 0)) + count
	if req.kind == "Enemy":
		ledger["dispatch_duration_sec"] = maxf(_wave_timer - float(dispatch["started_wave_sec"]), 0.0)
		var formations: Dictionary = ledger["formations"]
		var formation: Dictionary = formations[_resolve_package_id(req, req_index)]
		formation["cancelled_units"] = int(formation["cancelled_units"]) + count

func _cancel_delivery(dispatch: Dictionary, reason: String) -> void:
	if bool(dispatch.get("complete", false)):
		return
	dispatch["cancelled"] = true
	var remaining: Array = dispatch["remaining"]
	for index in remaining.size():
		_cancel_request_units(dispatch, index, int(remaining[index]), reason)
	_finish_delivery_if_complete(dispatch)

func _cancel_active_deliveries(reason: String) -> void:
	for dispatch: Dictionary in _active_dispatches.duplicate():
		_cancel_delivery(dispatch, reason)

func _finish_delivery_if_complete(dispatch: Dictionary) -> void:
	var ledger: Dictionary = dispatch["ledger"]
	var targets: Dictionary = ledger["target_delivery"]
	if int(ledger["pending_units"]) > 0 or int(targets["pending_units"]) > 0:
		return
	dispatch["complete"] = true
	_active_dispatches.erase(dispatch)

func _run_target_delivery(reqs: Array[SpawnRequest], dispatch: Dictionary) -> void:
	# Each pass serves every target request once rather than draining one first.
	while true:
		var pending: bool = false
		var delay: float = 0.0
		for index in reqs.size():
			var req: SpawnRequest = reqs[index]
			if req == null or req.kind != "Target":
				continue
			var remaining: Array = dispatch["remaining"]
			var count: int = int(remaining[index])
			if count <= 0:
				continue
			var stop_reason: String = _delivery_stop_reason(dispatch)
			if stop_reason != "":
				_cancel_delivery(dispatch, stop_reason)
				return
			if req.target_def == null:
				_cancel_request_units(dispatch, index, count, "invalid_target_definition")
				continue
			var batch_size: int = mini(count, clampi(_rand_batch(), maxi(req.batch_size_min, 1), maxi(req.batch_size_max, req.batch_size_min)))
			var spawned: int = _spawner.spawn_target_burst(req.target_def, batch_size) if _spawner != null else 0
			_record_spawned_units(dispatch, index, mini(spawned, batch_size))
			if spawned < batch_size:
				_cancel_request_units(dispatch, index, int(remaining[index]), "spawn_unavailable")
			if int(remaining[index]) > 0:
				pending = true
				delay = maxf(delay, req.inter_batch_sec)
		if not pending:
			_finish_delivery_if_complete(dispatch)
			return
		var wait: Timer = _create_pausable_timer(maxf(delay, 0.001))
		await wait.timeout

func _spawn_downtime_target_requests(reqs: Array[SpawnRequest]) -> void:
	var dispatch: Dictionary = _begin_delivery(reqs, _wave_token, "downtime_targets", true)
	for index in reqs.size():
		var req: SpawnRequest = reqs[index]
		if req == null or req.kind != "Target" or req.count <= 0:
			continue
		var reason: String = _delivery_stop_reason(dispatch)
		if reason != "":
			_cancel_delivery(dispatch, reason)
			return
		var spawned: int = _spawner.spawn_target_burst(req.target_def, req.count) if req.target_def != null else 0
		_record_spawned_units(dispatch, index, mini(spawned, req.count))
		if spawned < req.count:
			_cancel_request_units(dispatch, index, req.count - maxi(spawned, 0), "spawn_unavailable")
	_finish_delivery_if_complete(dispatch)

func _sample_delivery_density() -> void:
	if _main_delivery.is_empty() or _spawner == null or not is_inside_tree():
		return
	if int(_main_delivery.get("wave_token", -1)) != _wave_token or _state != RunState.State.IN_WAVE or _boss_wave_active or _gateway_hold_active:
		return
	var tree: SceneTree = get_tree()
	var player: Node3D = tree.get_first_node_in_group("player") as Node3D
	var nearby: int = 0
	var alive: int = 0
	var radius_sq: float = delivery_nearby_radius_m * delivery_nearby_radius_m
	for node: Node in tree.get_nodes_in_group("targets"):
		if node is Enemy and not node.is_queued_for_deletion():
			alive += 1
			var enemy: Enemy = node as Enemy
			if player != null and enemy.global_position.distance_squared_to(player.global_position) <= radius_sq:
				nearby += 1
	_main_delivery["peak_alive_enemies"] = maxi(int(_main_delivery.get("peak_alive_enemies", 0)), alive)
	_main_delivery["peak_nearby_enemies"] = maxi(int(_main_delivery.get("peak_nearby_enemies", 0)), nearby)
	for dispatch: Dictionary in _active_dispatches:
		var ledger: Dictionary = dispatch["ledger"]
		ledger["peak_alive_enemies"] = maxi(int(ledger.get("peak_alive_enemies", 0)), alive)
		ledger["peak_nearby_enemies"] = maxi(int(ledger.get("peak_nearby_enemies", 0)), nearby)

func _on_run_completed() -> void:
	_run_finished = true
	_cancel_active_deliveries("run_completed")

func _clear_or_timeout_then_downtime(token: int) -> void:
	# _wave_timer already began before dispatch; delivery never extends the wave.
	var end_deadline: float = _get_wave_timeout_sec()
	while _wave_timer < end_deadline:
		if token != _wave_token or _state != RunState.State.IN_WAVE or _boss_wave_active or _gateway_hold_active or _run_finished or not is_inside_tree():
			return
		var enemies_alive: int = _alive_enemy_count()
		if enemies_alive <= wave_clear_carryover_ok:
			emit_signal("wave_cleared", _wave_index, _wave_timer)
			if _should_trigger_victory():
				GameFlow.player_won()
				return
			_start_downtime()
			return
		var t: Timer = _create_pausable_timer(minf(0.5, end_deadline - _wave_timer))
		await t.timeout
		if token != _wave_token or _state != RunState.State.IN_WAVE or _boss_wave_active or _gateway_hold_active or _run_finished or not is_inside_tree():
			return
	if token != _wave_token or _state != RunState.State.IN_WAVE or _boss_wave_active or _gateway_hold_active or _run_finished or not is_inside_tree():
		return

	emit_signal("wave_forced_next", _wave_index)
	if _should_trigger_victory():
		GameFlow.player_won()
		return
	_start_downtime()

func _on_stage_changed(_stage: StageDef, _stage_index: int) -> void:
	_cancel_active_deliveries("stage_changed")
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

	_cancel_active_deliveries("boss_wave_started")
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
		GameFlow.record_stage_completed(current_stage)
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
	_cancel_active_deliveries("gateway_hold")
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
	_cancel_active_deliveries("stage_reset")
	_wave_token += 1
	_wave_index = 0
	_wave_timer = 0.0
	_elapsed_sec = 0.0
	_downtime_remaining = 0.0
	_pending_card = null
	_active_card = null
	_recent_card_ids.clear()
	_last_debug_snapshot = {}
	_main_delivery = {}
	_delivery_sample_remaining = 0.0
	_run_finished = false
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
