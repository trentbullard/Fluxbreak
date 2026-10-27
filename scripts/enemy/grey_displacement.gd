extends Node3D
class_name GreyDisplacement

## Arrival itself is harmless; the owner schedules a separate attack afterward.
signal completed(moved: bool)

var _source: Enemy = null
var _destination: Vector3 = Vector3.ZERO
var _origin: Vector3 = Vector3.ZERO
var _remaining_sec: float = 0.0
var _active: bool = false
var _finished: bool = false
var _windup_sec: float = 1.2
var _origin_marker: EnemyAttackField = null
var _arrival_marker: EnemyAttackField = null

func start_displacement(source: Enemy, destination: Vector3, windup_sec: float = 1.2) -> bool:
	if _active or _finished or not is_inside_tree() or not is_instance_valid(source) or source._dead or not source.is_inside_tree() or not destination.is_finite():
		return false
	_source = source
	_origin = source.global_position
	_destination = destination
	_remaining_sec = maxf(windup_sec, 0.2)
	_windup_sec = _remaining_sec
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("grey_displacements")
	_source.about_to_die.connect(_on_source_died, CONNECT_ONE_SHOT)
	_source.tree_exiting.connect(cancel, CONNECT_ONE_SHOT)
	_build_markers()
	_active = true
	_update_markers()
	return true

func is_active() -> bool:
	return _active and not _finished

func cancel() -> void:
	_finish(false)

func _physics_process(delta: float) -> void:
	if not is_active():
		return
	if not is_instance_valid(_source) or _source._dead or _source.is_queued_for_deletion() or not _source.is_inside_tree():
		cancel()
		return
	_remaining_sec = maxf(_remaining_sec - delta, 0.0)
	_update_markers()
	if _remaining_sec <= 0.0:
		_source.global_position = _destination
		_source.linear_velocity = Vector3.ZERO
		_source.angular_velocity = Vector3.ZERO
		_finish(true)

func _finish(moved: bool) -> void:
	if _finished:
		return
	_active = false
	_finished = true
	completed.emit(moved)
	queue_free()

func _on_source_died(_enemy: Enemy) -> void:
	cancel()

func _build_markers() -> void:
	_origin_marker = EnemyAttackField.new()
	_origin_marker.name = "ShiftOrigin"
	add_child(_origin_marker)
	_origin_marker.configure_marker(22.0)
	_origin_marker.global_position = _origin
	_arrival_marker = EnemyAttackField.new()
	_arrival_marker.name = "ShiftArrival"
	add_child(_arrival_marker)
	_arrival_marker.configure_marker(30.0)
	_arrival_marker.global_position = _destination

func _update_markers() -> void:
	var elapsed: float = _windup_sec - _remaining_sec
	var progress: float = elapsed / _windup_sec
	_origin_marker.set_charge(progress, elapsed)
	_arrival_marker.set_charge(progress, elapsed)
