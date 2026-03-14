# scripts/ship/turret_controller.gd (godot 4.5)
extends Node3D
class_name TurretController

@export var detector: Area3D
@export var detector_shape: CollisionShape3D
@export var detection_radius: float = 200.0
@export var target_groups: Array[String] = ["targets"]

# How we distribute fire:
enum AssignMode { FOCUS_ONE, FOCUS_PER_TEAM, FOCUS_PER_TURRET }
@export var assign_mode: AssignMode = AssignMode.FOCUS_ONE
enum TargetPriorityMode { CLOSEST, WEAKEST_TOTAL_HP }

# Optional: how often to recompute assignments (sec). 0 = every physics frame.
@export var assign_interval: float = 0.10

const Stat = StatTypes.Stat

var eff_detection_radius: float
var _stats: StatAggregator

var _targets: Array[WeakRef] = []
var _by_team: Dictionary = {}              # team_id:int -> Array[PlayerTurret] turrets
var _turret_to_target: Dictionary = {}     # turret:PlayerTurret -> target:Node3D (or null)
var _team_to_target: Dictionary = {}       # team_id:int -> target:Node3D (or null)
var _elapsed: float = 0.0
var _rr_global: int = 0                    # for FOCUS_PER_TURRET
var _rr_team_start: Dictionary = {}        # team_id:int -> cursor into live targets

func _ready() -> void:
	var sphere: SphereShape3D = detector_shape.shape as SphereShape3D
	if sphere != null:
		sphere.radius = detection_radius

	_stats = get_stat_aggregator()
	_refresh_detection_radius()
	if _stats != null and not _stats.stats_changed.is_connected(_on_stats_changed):
		_stats.stats_changed.connect(_on_stats_changed)

	if not detector.body_entered.is_connected(_on_body_entered):
		detector.body_entered.connect(_on_body_entered)
	if not detector.body_exited.is_connected(_on_body_exited):
		detector.body_exited.connect(_on_body_exited)

func register_turret(turret: PlayerTurret, team_id: int) -> void:
	if not _by_team.has(team_id):
		_by_team[team_id] = []
	var arr: Array = _by_team[team_id]
	if not arr.has(turret):
		arr.append(turret)
	_turret_to_target[turret] = null

func unregister_turret(turret: PlayerTurret, team_id: int) -> void:
	if _by_team.has(team_id):
		var arr: Array = _by_team[team_id]
		arr.erase(turret)
	_turret_to_target.erase(turret)

func get_assigned_target(turret: PlayerTurret, team_id: int) -> Node3D:
	if assign_mode == AssignMode.FOCUS_PER_TEAM and _team_to_target.has(team_id):
		var team_wr: WeakRef = _team_to_target[team_id] as WeakRef
		var t: Node3D = team_wr.get_ref() as Node3D if team_wr != null else null
		if t != null:
			return t
		_team_to_target.erase(team_id)

	if _turret_to_target.has(turret):
		var t2_wr := _turret_to_target[turret] as WeakRef
		var t2 := t2_wr.get_ref() as Node3D if t2_wr != null else null
		if t2 == null:
			_turret_to_target.erase(turret)
			return null
		return t2
	return null

func get_live_targets(origin: Node3D = null, base_range: float = -1.0, range_bonus: float = 0.0, enemy_only: bool = false) -> Array[Node3D]:
	var live: Array[Node3D] = []
	var query_origin: Node3D = origin if origin != null else self
	var use_range_filter: bool = base_range > 0.0
	var eff_base: float = max(base_range, 0.0)
	var eff_bonus: float = max(range_bonus, 0.0)
	var eff_max: float = eff_base + eff_bonus
	if use_range_filter and eff_max < eff_base:
		eff_max = eff_base
	var eff_max_sq: float = eff_max * eff_max

	for i in range(_targets.size() - 1, -1, -1):
		var wr: WeakRef = _targets[i] as WeakRef
		var target: Node3D = wr.get_ref() as Node3D if wr != null else null
		if target == null:
			_targets.remove_at(i)
			continue
		if enemy_only and not _is_enemy_target(target):
			continue

		if use_range_filter:
			var d_sq: float = query_origin.global_position.distance_squared_to(target.global_position)
			if d_sq > eff_max_sq:
				continue
		live.append(target)

	if query_origin != null:
		live.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return query_origin.global_position.distance_squared_to(a.global_position) < query_origin.global_position.distance_squared_to(b.global_position)
		)

	return live

func get_prioritized_live_targets(origin: Node3D = null, base_range: float = -1.0, range_bonus: float = 0.0, priority_mode: int = TargetPriorityMode.CLOSEST, enemy_only: bool = false) -> Array[Node3D]:
	var live: Array[Node3D] = get_live_targets(origin, base_range, range_bonus, enemy_only)
	if live.is_empty():
		return live

	var query_origin: Node3D = origin if origin != null else self
	match priority_mode:
		TargetPriorityMode.WEAKEST_TOTAL_HP:
			live.sort_custom(func(a: Node3D, b: Node3D) -> bool:
				var ha: float = _estimate_total_health(a)
				var hb: float = _estimate_total_health(b)
				if not is_equal_approx(ha, hb):
					return ha < hb
				return query_origin.global_position.distance_squared_to(a.global_position) < query_origin.global_position.distance_squared_to(b.global_position)
			)
		_:
			# CLOSEST is already handled by get_live_targets sorting when origin is set.
			pass

	return live

func _is_enemy_target(target: Node3D) -> bool:
	if target == null:
		return false
	if target.has_meta("kind"):
		var kind: String = String(target.get_meta("kind"))
		if kind == "enemy":
			return true
	if target.is_in_group("enemy"):
		return true
	if target.has_method("get_evasion") and target.has_method("apply_damage"):
		return true
	return false

func _estimate_total_health(target: Object) -> float:
	var hull: float = _read_float_property(target, "hull")
	var shield: float = _read_float_property(target, "shield")
	return max(0.0, hull) + max(0.0, shield)

func _read_float_property(target: Object, property_name: String) -> float:
	if target == null:
		return 0.0
	var raw: Variant = target.get(property_name)
	var t: int = typeof(raw)
	if t == TYPE_FLOAT or t == TYPE_INT:
		return float(raw)
	return 0.0

func _on_body_entered(body: Node) -> void:
	if not (body is Node3D):
		return
	for g in target_groups:
		if body.is_in_group(g):
			var wr := weakref(body) as WeakRef
			_targets.append(wr)
			if body.has_signal("about_to_die"):
				body.about_to_die.connect(func(_t): _purge_target(wr), CONNECT_ONE_SHOT)
			body.tree_exiting.connect(func(): _purge_target(wr), CONNECT_ONE_SHOT)
			break

func _on_body_exited(body: Node) -> void:
	# Remove any weakrefs that point to this body
	for i in range(_targets.size() - 1, -1, -1):
		var wr := _targets[i] as WeakRef
		if wr == null or wr.get_ref() == body:
			_targets.remove_at(i)

	# Also clear assignments that were pointing to this body
	for k in _turret_to_target.keys():
		var w := _turret_to_target[k] as WeakRef
		if w != null and w.get_ref() == body:
			_turret_to_target[k] = null

	for team_id in _team_to_target.keys():
		var w2 := _team_to_target[team_id] as WeakRef
		if w2 != null and w2.get_ref() == body:
			_team_to_target.erase(team_id)

func _physics_process(delta: float) -> void:
	# Clean dead targets (resolve weakref)
	for i in range(_targets.size() - 1, -1, -1):
		var wr := _targets[i] as WeakRef
		if wr == null or wr.get_ref() == null:
			_targets.remove_at(i)

	if assign_interval <= 0.0:
		_compute_assignments()
	else:
		_elapsed += delta
		if _elapsed >= assign_interval:
			_elapsed = 0.0
			_compute_assignments()

func _compute_assignments() -> void:
	_team_to_target.clear()
	for t in _turret_to_target.keys():
		_turret_to_target[t] = null

	var live: Array[Node3D] = []
	for wr in _targets:
		var n: Node3D = (wr as WeakRef).get_ref() as Node3D
		if n != null:
			live.append(n)
	_targets = _targets.filter(func(w): return (w.get_ref() != null))
	
	if live.is_empty():
		return

	# We prefer per-turret selection that respects each turret's base and max assignment ranges.
	# Sort the live list by distance to controller (ship) for deterministic ordering.
	live.sort_custom(_sort_by_distance_to_self)

	match assign_mode:
		AssignMode.FOCUS_ONE:
			# Pick the single target that maximizes (base_hits, total_hits) across ALL turrets
			var all_turrets: Array = []
			for team_id in _by_team.keys():
				all_turrets.append_array(_by_team[team_id])
			var best: Node3D = _choose_best_shared_target(live, all_turrets)
			for team_id in _by_team.keys():
				var arr: Array = _by_team[team_id]
				for turret in arr:
					_turret_to_target[turret] = weakref(best) if best != null else null

		AssignMode.FOCUS_PER_TEAM:
			# For each team: pick a team's best (max coverage), try to vary per team via RR start
			var used_indices: Dictionary = {} # target: bool (optional – not hard constraint)
			for team_id in _by_team.keys():
				var team_arr: Array[PlayerTurret] = _by_team[team_id]
				if not _rr_team_start.has(team_id):
					_rr_team_start[team_id] = 0
				var start_idx: int = int(_rr_team_start[team_id])
				
				var pick: Dictionary = _choose_best_shared_target_rr(live, team_arr, start_idx)
				_rr_team_start[team_id] = pick["cursor"]
				
				var tgt: Node3D = pick["target"]
				_team_to_target[team_id] = weakref(tgt) if tgt != null else null
				if tgt != null:
					used_indices[tgt] = true
				
				for turret in team_arr:
					_turret_to_target[turret] = weakref(tgt) if tgt != null else null

		AssignMode.FOCUS_PER_TURRET:
			# Give each turret a (preferably unique) target it can actually hit, using global RR
			var flat: Array = []
			for team_id in _by_team.keys():
				flat.append_array(_by_team[team_id])
			
			var used: Dictionary = {}
			var cursor: int = _rr_global
			for turret in flat:
				var pick2: Dictionary = _choose_target_for_turret_rr(turret, live, cursor, used)
				cursor = pick2["cursor"]
				var tgt2: Node3D = pick2["target"]
				if tgt2 != null:
					used[tgt2] = true
				_turret_to_target[turret] = weakref(tgt2) if tgt2 != null else null
			_rr_global = cursor

func _choose_target_for_turret_rr(turret: PlayerTurret, live: Array[Node3D], start_idx: int, used: Dictionary) -> Dictionary:
	var r: Dictionary = _get_squared_ranges_for_turret(turret)
	var base_r_sq: float = r["base"]
	var max_r_sq: float = r["max"]
	if max_r_sq <= 0.0 or live.is_empty():
		return {"target": null, "cursor": start_idx}
	
	var n: int = live.size()
	var chosen: Node3D = null
	
	# Pass 1: prefer not-yet-used targets within base range
	for k in n:
		var i: int = (start_idx + k) % n
		var tgt: Node3D = live[i]
		if used.has(tgt):
			continue
		var d_sq: float = turret.global_position.distance_squared_to(tgt.global_position)
		if d_sq <= base_r_sq:
			chosen = tgt
			break
	
	# Pass 2: not-yet-used targets within extended range
	if chosen == null:
		for k in n:
			var i2: int = (start_idx + k) % n
			var tgt2: Node3D = live[i2]
			if used.has(tgt2):
				continue
			var d2_sq: float = turret.global_position.distance_squared_to(tgt2.global_position)
			if d2_sq <= max_r_sq:
				chosen = tgt2
				break
	
	# Pass 3: allow reusing targets within base range
	if chosen == null:
		for k in n:
			var i3: int = (start_idx + k) % n
			var tgt3: Node3D = live[i3]
			var d3_sq: float = turret.global_position.distance_squared_to(tgt3.global_position)
			if d3_sq <= base_r_sq:
				chosen = tgt3
				break
	
	# Pass 4: allow reusing targets within extended range
	if chosen == null:
		for k in n:
			var i4: int = (start_idx + k) % n
			var tgt4: Node3D = live[i4]
			var d4_sq: float = turret.global_position.distance_squared_to(tgt4.global_position)
			if d4_sq <= max_r_sq:
				chosen = tgt4
				break
	
	var next_cursor: int = (start_idx + 1) % n
	return {"target": chosen, "cursor": next_cursor}

func _choose_best_shared_target_rr(live: Array[Node3D], turrets: Array[PlayerTurret], start_idx: int) -> Dictionary:
	if live.is_empty():
		return {"target": null, "cursor": start_idx}
	var n: int = live.size()
	var best: Node3D = null
	var best_key_base: int = -1
	var best_key_total: int = -1
	var best_key_dist: float = INF
	for k in n:
		var i: int = (start_idx + k) % n
		var tgt: Node3D = live[i]
		var sc: Dictionary = _score_target_for_turrets(tgt, turrets)
		if sc["total_hits"] == 0:
			continue
		var dist2: float = global_position.distance_squared_to(tgt.global_position)
		var better: bool = false
		if sc["base_hits"] > best_key_base:
			better = true
		elif sc["base_hits"] == best_key_base:
			if sc["total_hits"] > best_key_total:
				better = true
			elif sc["total_hits"] == best_key_total and dist2 < best_key_dist:
				better = true
		if better:
			best = tgt
			best_key_base = sc["base_hits"]
			best_key_total = sc["total_hits"]
			best_key_dist = dist2
	# Advance cursor even if nothing hit (keeps fairness over time)
	var next_cursor: int = (start_idx + 1) % n
	return {"target": best, "cursor": next_cursor}

# Pick best target by (base_hits desc, total_hits desc, distance asc from controller)
func _choose_best_shared_target(live: Array[Node3D], turrets: Array[PlayerTurret]) -> Node3D:
	var best: Node3D = null
	var best_key_base: int = -1
	var best_key_total: int = -1
	var best_key_dist: float = INF
	for i in live.size():
		var tgt: Node3D = live[i]
		var sc: Dictionary = _score_target_for_turrets(tgt, turrets)
		if sc["total_hits"] == 0:
			continue
		var dist2: float = global_position.distance_squared_to(tgt.global_position)
		var better: bool = false
		if sc["base_hits"] > best_key_base:
			better = true
		elif sc["base_hits"] == best_key_base:
			if sc["total_hits"] > best_key_total:
				better = true
			elif sc["total_hits"] == best_key_total and dist2 < best_key_dist:
				better = true
		if better:
			best = tgt
			best_key_base = sc["base_hits"]
			best_key_total = sc["total_hits"]
			best_key_dist = dist2
	return best

# Score a target for a given set of turrets:
# returns {base_hits:int, total_hits:int}
func _score_target_for_turrets(target: Node3D, turrets: Array[PlayerTurret]) -> Dictionary:
	var base_hits: int = 0
	var total_hits: int = 0
	for t in turrets:
		if t == null:
			continue
		var r: Dictionary = _get_squared_ranges_for_turret(t)
		if r["max"] <= 0.0:
			continue
		var d_sq: float = (t as PlayerTurret).global_position.distance_squared_to(target.global_position)
		if d_sq <= r["max"]:
			total_hits += 1
			if d_sq <= r["base"]:
				base_hits += 1
	return {"base_hits": base_hits, "total_hits": total_hits}

func _get_squared_ranges_for_turret(turret: PlayerTurret) -> Dictionary:
	var base_r: float = 0.0
	var max_r: float = 0.0
	if turret != null:
		var turret_base_range: float = turret.get_base_range()
		base_r = turret_base_range * turret_base_range
		var turret_max_range: float = turret.get_max_assign_range()
		max_r = turret_max_range * turret_max_range
	return {"base": base_r, "max": max_r}

func _sort_by_distance_to_self(a: Node3D, b: Node3D) -> bool:
	var d2_a: float = global_position.distance_squared_to(a.global_position)
	var d2_b: float = global_position.distance_squared_to(b.global_position)
	return d2_a < d2_b

func _purge_target(wr: WeakRef) -> void:
	for i in range(_targets.size() - 1, -1, -1):
		if _targets[i] == wr:
			_targets.remove_at(i)
	for k in _turret_to_target.keys():
		var w := _turret_to_target[k] as WeakRef
		if w != null and w == wr:
			_turret_to_target[k] = null
	for team_id in _team_to_target.keys():
		var w2 := _team_to_target[team_id] as WeakRef
		if w2 != null and w2 == wr:
			_team_to_target.erase(team_id)

func get_stat_aggregator() -> StatAggregator:
	# Ship is expected to be parent.
	var ship: Node = get_parent()
	if ship != null and ship.has_node("StatAggregator"):
		return ship.get_node("StatAggregator") as StatAggregator
	return null

func _refresh_detection_radius() -> void:
	if _stats == null:
		eff_detection_radius = detection_radius
	else:
		eff_detection_radius = _stats.compute_for_context(Stat.SCANNER_RANGE, detection_radius, StatAggregator.Context.PLAYER)
	var sphere: SphereShape3D = detector_shape.shape as SphereShape3D
	if sphere != null:
		sphere.radius = eff_detection_radius

func _on_stats_changed(_affected: Array[Stat]) -> void:
	_refresh_detection_radius()
