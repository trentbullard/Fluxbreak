# wave_director.gd (Godot 4.5)
extends Node
class_name WaveDirector

signal wave_started(index: int, enemy_budget: int, target_budget: int)
signal wave_cleared(index: int, time_sec: float)
signal wave_forced_next(index: int)
signal downtime_started(duration: float, next_wave_index: int)
#signal downtime_tick(remaining: float)
signal downtime_ended(next_wave_index: int)
signal next_wave_eta(seconds: float)

@export var spawner_path: NodePath
@export var downtime_sec: float = 30.0

@export var start_enemies_min: int = 2
@export var start_enemies_max: int = 3
@export var start_targets_min: int = 1
@export var start_targets_max: int = 2

@export var per_wave_enemy_add: int = 1
@export var per_wave_target_add: int = 1

@export var pressure_interval_sec: float = 10.0
@export var pressure_enemy_burst: int = 1
@export var pressure_target_burst: int = 0
@export var pressure_enemy_point_budget: int = 3
@export var pressure_target_point_budget: int = 0

@export var wave_burst_extra: int = 0 # optional extra burst on wave start to make waves more obvious

@export var batch_size_min: int = 2
@export var batch_size_max: int = 4
@export var inter_batch_delay: float = 0.7

@export var wave_clear_carryover_ok: int = 0
@export var wave_timeout_sec: float = 25.0

@export var max_alive_base: int = 8
@export var max_alive_per_wave: int = 1
@export var max_targets_alive: int = 3

# new threat/budget system
@export var threat_director_path: NodePath
@export var wave_budgeter_path: NodePath
@export var budget_buyer_path: NodePath
@export var wave_cards: Array[WaveCard] = []
var _buyer: BudgetBuyer
var _threat_dir: ThreatDirector
var _wave_budgeter: WaveBudgeter
var _elapsed_sec: float = 0.0

var _spawner: Spawner
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _wave_index: int = 0
var _wave_timer: float = 0.0
var _state: RunState.State = RunState.State.DOWNTIME
var _downtime_remaining: float = 0.0
var _wave_token: int = 0
var _pressure_token: int = 0

func _ready() -> void:
	_threat_dir = get_node_or_null(threat_director_path) as ThreatDirector
	_wave_budgeter = get_node_or_null(wave_budgeter_path) as WaveBudgeter
	_spawner = get_node_or_null(spawner_path) as Spawner
	_buyer = get_node_or_null(budget_buyer_path) as BudgetBuyer
	if _spawner == null:
		push_error("WaveDirector: spawner_path not set.")
		return
	_rng.randomize()
	_start_downtime(true)
	_start_pressure_loop()

func _process(delta: float) -> void:
	_elapsed_sec += delta

	if _state == RunState.State.DOWNTIME:
		_downtime_remaining = max(_downtime_remaining - delta, 0.0)
		next_wave_eta.emit(_downtime_remaining)
		if _downtime_remaining <= 0.0:
			_state = RunState.State.IN_WAVE
			downtime_ended.emit(_wave_index + 1)
			_next_wave()
	else:
		# IN_WAVE: advance wave timer smoothly here (not in the coroutine)
		_wave_timer += delta
		var wave_timeout_left: float = max(wave_timeout_sec - _wave_timer, 0.0)
		# Upper-bound ETA until the *latest* next-wave start
		var eta: float = wave_timeout_left + downtime_sec
		next_wave_eta.emit(eta)

func _start_downtime(first: bool = false) -> void:
	_state = RunState.State.DOWNTIME
	RunState.set_state(RunState.State.DOWNTIME)
	_downtime_remaining = 5.0 if first else downtime_sec
	downtime_started.emit(_downtime_remaining, _wave_index + 1)

func _choose_card() -> WaveCard:
	if wave_cards.size() == 0:
		return WaveCard.new()
	return wave_cards[ _rng.randi() % wave_cards.size() ]

func _next_wave() -> void:
	_wave_token += 1
	RunState.set_state(RunState.State.IN_WAVE)
	_state = RunState.State.IN_WAVE

	_wave_index += 1
	_wave_timer = 0.0
	
	var cap: int = max_alive_base + (_wave_index - 1) * max_alive_per_wave
	_spawner.set_max_alive(cap)
	_spawner.set_max_alive_total(cap + max_targets_alive)
	
	var pps: float = CombatStats.get_pps()
	var threat: float = _threat_dir.compute_threat(_elapsed_sec, pps)
	var budgets: Dictionary = _wave_budgeter.to_budgets(threat, _elapsed_sec)
	RunState.set_wave_context(_wave_index, int(budgets["enemy_points"]), int(budgets["target_points"]))
	
	var card: WaveCard = _choose_card()
	var max_tier: int = clamp(1 + _wave_index / 3, 1, 5)
	
	var reqs: Array[SpawnRequest] = _buyer.buy_wave(
		int(budgets["enemy_points"]),
		int(budgets["target_points"]),
		card,
		max_tier
	)
	
	emit_signal("wave_started", _wave_index, budgets["enemy_points"], budgets["target_points"])
	# Make the initial wave pop more obvious: allow an optional extra generic burst
	if wave_burst_extra > 0 and reqs.size() > 0:
		# try to spawn extra enemies (respecting spawner caps)
		_spawner.spawn_burst(Spawner.SpawnKind.ENEMY, wave_burst_extra)

	_run_requests_async(reqs, card)

func _start_pressure_loop() -> void:
	# Start a background pressure loop which spawns small bursts periodically.
	# This runs continuously (during downtime and waves) so the world feels active.
	if pressure_interval_sec <= 0.0:
		return
	_pressure_token += 1
	_run_pressure_coroutine(_pressure_token)

func _run_pressure_coroutine(token: int) -> void:
	while true:
		var t: SceneTreeTimer = get_tree().create_timer(pressure_interval_sec)
		await t.timeout
		if token != _pressure_token:
			return
		# spawn a light background burst; prefer using catalog-ed defs via BudgetBuyer
		# Fallback to generic spawn_burst if buyer isn't available or budgets are zero
		var did_spawn: bool = false
		if _buyer != null:
			# Enemy pressure by buying a very small "wave" and spawning those defs
			if pressure_enemy_point_budget > 0:
				var ecard: WaveCard = WaveCard.new()
				var max_tier: int = clamp(1 + _wave_index / 3, 1, 5)
				var ereqs: Array[SpawnRequest] = _buyer.buy_wave(pressure_enemy_point_budget, 0, ecard, max_tier)
				for r in ereqs:
					if r.kind == "Enemy" and r.enemy_def != null and r.count > 0:
						_spawner.spawn_enemy_burst(r.enemy_def, r.count)
						did_spawn = true
			# Target pressure
			if pressure_target_point_budget > 0:
				var tcard: WaveCard = WaveCard.new()
				var treqs: Array[SpawnRequest] = _buyer.buy_wave(0, pressure_target_point_budget, tcard, 1)
				for r2 in treqs:
					if r2.kind == "Target" and r2.target_def != null and r2.count > 0:
						_spawner.spawn_target_burst(r2.target_def, r2.count)
						did_spawn = true
		# If the buyer didn't run (null) or produced nothing, fall back to simple generic bursts
		#if not did_spawn:
			#if pressure_enemy_burst > 0:
				#_spawner.spawn_burst(Spawner.SpawnKind.ENEMY, pressure_enemy_burst)
			#if pressure_target_burst > 0:
				#_spawner.spawn_burst(Spawner.SpawnKind.TARGET, pressure_target_burst)

func _rand_batch() -> int:
	return _rng.randi_range(batch_size_min, batch_size_max)

func _rand_pick_enemy_first() -> bool:
	# slight bias for enemies early; purely aesthetic
	return _rng.randf() < 0.65

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

func _request_kind(req: SpawnRequest) -> int:
	return Spawner.SpawnKind.ENEMY if req.kind == "Enemy" else Spawner.SpawnKind.TARGET

@warning_ignore("unused_parameter")
func _run_requests_coroutine(reqs: Array[SpawnRequest], card: WaveCard, token: int) -> void:
	# remaining counts per request
	var remaining: Array[int] = []
	for r in reqs:
		remaining.append(r.count)
	
	var req_index: int = 0
	#var pressure_clock: float = 0.0
	
	# initial pop to sell "wave started"
	if reqs.size() > 0:
		var first: SpawnRequest = reqs[0]
		var first_batch: int = _rand_batch()
		var n0: int = min(first_batch, remaining[0])
		if n0 > 0:
			var spawned0: int
			if first.kind == "Enemy":
				spawned0 = _spawner.spawn_enemy_burst(first.enemy_def, n0)
			else:
				spawned0 = _spawner.spawn_target_burst(first.target_def, n0)
			remaining[0] = max(remaining[0] - spawned0, 0)
		var timer0: SceneTreeTimer = get_tree().create_timer(inter_batch_delay)
		await timer0.timeout
		if token != _wave_token:
			return
	
	while _any_remaining(remaining):
		# pick next request that still has work
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
			spawned = _spawner.spawn_enemy_burst(req.enemy_def, batch_size)
		else:
			spawned = _spawner.spawn_target_burst(req.target_def, batch_size)
		
		if spawned == 0:
			# cap is full; wait a short while for space, then try again
			var wait_cap: SceneTreeTimer = get_tree().create_timer(0.35)
			await wait_cap.timeout
			if token != _wave_token:
				return
		else:
			remaining[req_index] = max(remaining[req_index] - spawned, 0)
			# per-request inter-batch delay
			var wait: SceneTreeTimer = get_tree().create_timer(req.inter_batch_sec)
			await wait.timeout
			if token != _wave_token:
				return
		
		# hard timeout while still spawning
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
		var t: SceneTreeTimer = get_tree().create_timer(0.5)
		await t.timeout
	
	emit_signal("wave_forced_next", _wave_index)
	_start_downtime()
