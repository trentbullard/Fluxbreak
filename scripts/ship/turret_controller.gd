# turret_controller.gd
extends Node3D
class_name TurretController

@export var detector: Area3D
@export var detector_shape: CollisionShape3D
@export var detection_radius: float = 200.0
@export var target_groups: Array[String] = ["targets"]

# How we distribute fire:
enum AssignMode { FOCUS_ONE, FOCUS_PER_TEAM, SPREAD_PER_TEAM, SPREAD_EACH_TURRET }
@export var assign_mode: AssignMode = AssignMode.FOCUS_ONE

# Optional: how often to recompute assignments (sec). 0 = every physics frame.
@export var assign_interval: float = 0.10

var _targets: Array[WeakRef] = []
var _by_team: Dictionary = {}              # team_id:int -> Array[Node3D] turrets (we store turret nodes)
var _turret_to_target: Dictionary = {}     # turret:Node3D -> target:Node3D (or null)
var _team_to_target: Dictionary = {}       # team_id:int -> target:Node3D (or null)
var _elapsed: float = 0.0

func _ready() -> void:
	var sphere: SphereShape3D = detector_shape.shape as SphereShape3D
	if sphere != null:
		sphere.radius = detection_radius

	if not detector.body_entered.is_connected(_on_body_entered):
		detector.body_entered.connect(_on_body_entered)
	if not detector.body_exited.is_connected(_on_body_exited):
		detector.body_exited.connect(_on_body_exited)

func register_turret(turret: Node3D, team_id: int) -> void:
	if not _by_team.has(team_id):
		_by_team[team_id] = []
	var arr: Array = _by_team[team_id]
	if not arr.has(turret):
		arr.append(turret)
	_turret_to_target[turret] = null

func unregister_turret(turret: Node3D, team_id: int) -> void:
	if _by_team.has(team_id):
		var arr: Array = _by_team[team_id]
		arr.erase(turret)
	_turret_to_target.erase(turret)

func get_assigned_target(turret: Node3D, team_id: int) -> Node3D:
	if assign_mode == AssignMode.FOCUS_PER_TEAM and _team_to_target.has(team_id):
		var t := (_team_to_target[team_id] as WeakRef).get_ref() as Node3D
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
	# Clear previous
	_team_to_target.clear()
	for t in _turret_to_target.keys():
		_turret_to_target[t] = null

	var live: Array[Node3D] = []
	for wr in _targets:
		var n := wr.get_ref() as Node3D
		if n != null:
			live.append(n)
	_targets = _targets.filter(func(w): return (w.get_ref() != null))
	
	if live.is_empty():
		return
	live.sort_custom(_sort_by_distance_to_self)

	match assign_mode:
		AssignMode.FOCUS_ONE:
			var primary: Node3D = live[0]
			# Everyone shoots the same
			for team_id in _by_team.keys():
				var arr: Array = _by_team[team_id]
				for turret in arr:
					_turret_to_target[turret] = weakref(primary)

		AssignMode.FOCUS_PER_TEAM:
			# First N targets go to teams 0..(N-1). Teams share within the team.
			var team_ids: Array = _by_team.keys()
			team_ids.sort() # stable ordering by team id
			for i in range(team_ids.size()):
				var team_id: int = team_ids[i]
				var tgt: Node3D = live[min(i, live.size() - 1)]
				_team_to_target[team_id] = weakref(tgt)
				var arr: Array = _by_team[team_id]
				for turret in arr:
					_turret_to_target[turret] = weakref(tgt)

		AssignMode.SPREAD_PER_TEAM:
			# Within each team, walk down the sorted list round-robin so teammates cover different targets
			for team_id in _by_team.keys():
				var arr: Array = _by_team[team_id]
				if arr.is_empty():
					continue
				for i in range(arr.size()):
					var idx: int = i % live.size()
					_turret_to_target[arr[i]] = weakref(live[idx])

		AssignMode.SPREAD_EACH_TURRET:
			# Ignore teams: spread all turrets across targets
			var flat: Array = []
			for team_id in _by_team.keys():
				flat.append_array(_by_team[team_id])
			for i in range(flat.size()):
				var turret := flat[i] as Node3D
				var idx: int = i % live.size()
				_turret_to_target[turret] = weakref(live[idx])

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
