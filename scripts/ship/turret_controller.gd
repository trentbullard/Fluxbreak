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

var _targets: Array[Node3D] = []
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
	# Returns the controller's assignment for a turret; may be null.
	if assign_mode == AssignMode.FOCUS_PER_TEAM:
		if _team_to_target.has(team_id):
			return _team_to_target[team_id]
	if _turret_to_target.has(turret):
		return _turret_to_target[turret]
	return null

func _on_body_entered(body: Node) -> void:
	if not (body is Node3D) or _targets.has(body):
		return
	for g: String in target_groups:
		if body.is_in_group(g):
			_targets.append(body)
			break

func _on_body_exited(body: Node) -> void:
	_targets.erase(body)

func _physics_process(delta: float) -> void:
	# Clean dead targets
	for i in range(_targets.size() - 1, -1, -1):
		if _targets[i] == null or not is_instance_valid(_targets[i]):
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

	# Early out
	if _targets.is_empty():
		return

	# Sort targets by distance to controller (simple, fast, decent)
	var sorted: Array[Node3D] = _targets.duplicate() as Array[Node3D]
	sorted.sort_custom(_sort_by_distance_to_self)

	match assign_mode:
		AssignMode.FOCUS_ONE:
			var primary: Node3D = sorted[0]
			# Everyone shoots the same
			for team_id in _by_team.keys():
				var arr: Array = _by_team[team_id]
				for turret in arr:
					_turret_to_target[turret] = primary

		AssignMode.FOCUS_PER_TEAM:
			# First N targets go to teams 0..(N-1). Teams share within the team.
			var team_ids: Array = _by_team.keys()
			team_ids.sort() # stable ordering by team id
			for i in range(team_ids.size()):
				var team_id: int = team_ids[i]
				var tgt: Node3D = sorted[min(i, sorted.size() - 1)]
				_team_to_target[team_id] = tgt
				var arr: Array = _by_team[team_id]
				for turret in arr:
					_turret_to_target[turret] = tgt

		AssignMode.SPREAD_PER_TEAM:
			# Within each team, walk down the sorted list round-robin so teammates cover different targets
			for team_id in _by_team.keys():
				var arr: Array = _by_team[team_id]
				if arr.is_empty():
					continue
				for i in range(arr.size()):
					var tgt_index: int = i % sorted.size()
					_turret_to_target[arr[i]] = sorted[tgt_index]

		AssignMode.SPREAD_EACH_TURRET:
			# Ignore teams: spread all turrets across targets
			var flat: Array = []
			for team_id in _by_team.keys():
				flat.append_array(_by_team[team_id])
			for i in range(flat.size()):
				var turret: Node3D = flat[i]
				var idx: int = i % sorted.size()
				_turret_to_target[turret] = sorted[idx]

func _sort_by_distance_to_self(a: Node3D, b: Node3D) -> bool:
	var d2_a: float = global_position.distance_squared_to(a.global_position)
	var d2_b: float = global_position.distance_squared_to(b.global_position)
	return d2_a < d2_b
