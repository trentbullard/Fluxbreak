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

func start_tether(source: Enemy, target: Ship, windup_sec: float = 1.3, duration_sec: float = 2.5, slow_multiplier: float = 0.75, break_distance: float = 360.0, radius: float = 36.0) -> bool:
	if _active or _finished or not is_inside_tree() or not is_instance_valid(source) or source._dead or not is_instance_valid(target) or not target.is_alive() or target.is_tether_immune() or target.get_tether_time_remaining() > 0.0:
		return false
	_ship = target
	_duration_sec = clampf(duration_sec, 0.05, 3.0)
	_slow_multiplier = clampf(slow_multiplier, 0.65, 1.0)
	_break_distance = clampf(break_distance, 100.0, 600.0)
	if source.global_position.distance_squared_to(target.global_position) > _break_distance * _break_distance:
		return false
	set_warning_style("TETHER CAPTURE", Color(0.8, 0.46, 1.0, 0.9))
	start_attack(source, target, source, windup_sec, radius)
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
	return "TETHER LINK" if _attached else "TETHER CAPTURE"

func get_response_hint() -> String:
	return "MOVE AWAY TO BREAK" if _attached else "MOVE CLEAR"

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
		_progress_mesh.clear_surfaces()
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
	_update_link()

func _update_link() -> void:
	_wire_mesh.clear_surfaces()
	_wire_material.albedo_color = Color(0.5, 0.85, 1.0, 0.95)
	_wire_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _wire_material)
	var origin: Vector3 = _source.global_position - global_position
	var endpoint: Vector3 = _ship.global_position - global_position
	_wire_mesh.surface_add_vertex(origin)
	_wire_mesh.surface_add_vertex(endpoint)
	_wire_mesh.surface_end()
	_label.position = (origin + endpoint) * 0.5 + Vector3.UP * 52.0
	_label.modulate = Color(0.6, 0.85, 1.0)
	_label.text = "TETHER  %.1fs" % _ship.get_tether_time_remaining()

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
