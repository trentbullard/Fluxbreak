extends EnemyAttackTelegraph
class_name GreyTether

## Emitted after an attached link breaks, or after its capture fails/cancels.
signal completed(attached: bool)

var _ship: Ship = null
var _duration_sec: float = 2.5
var _slow_multiplier: float = 0.75
var _break_distance: float = 360.0
var _attached: bool = false
var _ever_attached: bool = false
var _finished: bool = false

func start_tether(source: Enemy, target: Ship, windup_sec: float = 1.3, duration_sec: float = 2.5, slow_multiplier: float = 0.75, break_distance: float = 360.0, radius: float = 49.68, corridor_end: Vector3 = Vector3.INF, corridor_start: Vector3 = Vector3.INF) -> bool:
	if _active or _finished or not is_inside_tree() or not is_instance_valid(source) or source._dead or not is_instance_valid(target) or not target.is_alive() or target.is_tether_immune() or target.get_tether_time_remaining() > 0.0:
		return false
	_ship = target
	_duration_sec = clampf(duration_sec, 0.05, 3.0)
	_slow_multiplier = clampf(slow_multiplier, 0.65, 1.0)
	_break_distance = clampf(break_distance, 100.0, 600.0)
	if source.global_position.distance_squared_to(target.global_position) > _break_distance * _break_distance:
		return false
	set_warning_style("TETHER CAPTURE", Color(0.8, 0.46, 1.0, 0.9))
	var directional: bool = corridor_end.is_finite() and corridor_start.is_finite()
	if directional:
		set_warning_style("CAPTURE CORRIDOR", Color(0.8, 0.46, 1.0, 0.9))
		set_response_hint("TURN OUT OF THE LANE")
	start_attack(source, target, source, windup_sec, radius, directional, corridor_end, corridor_start)
	if _grey_field != null:
		_grey_field.set_capture_style()
	add_to_group("grey_tethers")
	return _active

func is_active() -> bool:
	return (_active or _attached) and not _finished

func is_attached() -> bool:
	return _attached and not _finished

func is_warning_for(target: Node3D) -> bool:
	return is_active() and _ship == target

func get_time_remaining() -> float:
	return _ship.get_tether_time_remaining() if _attached and is_instance_valid(_ship) else super.get_time_remaining()

func get_attack_label() -> String:
	return "TETHER LINK" if _attached else ("CAPTURE CORRIDOR" if _corridor else "TETHER CAPTURE")

func get_response_hint() -> String:
	return "MOVE AWAY TO BREAK" if _attached else super.get_response_hint()

func cancel() -> void:
	_finish()

func _capture_weapon(_host: Object) -> void:
	# This warning controls a movement status only; it never rolls damage.
	pass

func _resolve_attack() -> void:
	_active = false
	_has_resolved = true
	if is_instance_valid(_ship) and contains_position(_ship.global_position):
		_attached = _ship.try_apply_tether_slow(_source, _slow_multiplier, _duration_sec, _break_distance)
	_ever_attached = _attached
	resolved.emit(_attached)
	if not _attached:
		_finish()
	else:
		_update_link()

func _physics_process(delta: float) -> void:
	if _finished:
		return
	if not _attached:
		super._physics_process(delta)
		return
	if not is_instance_valid(_ship) or not is_instance_valid(_source) or _source._dead or _source.is_queued_for_deletion() or not _ship.is_alive() or not _ship.visible or _ship.get_tether_source() != _source or _ship.get_tether_time_remaining() <= 0.0:
		_finish()
		return
	if _source.global_position.distance_squared_to(_ship.global_position) > _break_distance * _break_distance:
		_finish()
		return
	_elapsed_sec += delta
	_update_link()

func _update_link() -> void:
	_grey_field.configure_link(_source.global_position, _ship.global_position)
	_grey_field.set_charge(1.0, _elapsed_sec)

func _finish() -> void:
	if _finished:
		return
	var owned_link: bool = _attached
	_finished = true
	_active = false
	_attached = false
	if owned_link and is_instance_valid(_ship) and is_instance_valid(_source):
		_ship.clear_tether_slow(_source)
	completed.emit(_ever_attached)
	queue_free()

func _exit_tree() -> void:
	if _attached and is_instance_valid(_ship) and is_instance_valid(_source):
		_ship.clear_tether_slow(_source)
	_attached = false
