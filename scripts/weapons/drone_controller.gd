extends Node3D
class_name DroneController

const STATE_DOCKED: int = 0
const STATE_ACTIVE: int = 1
const STATE_ATTACKING: int = 2
const STATE_RETURNING: int = 3

signal state_reported(origin_bay_id: int, slot_index: int, next_state: int)

var origin_bay_id: int = -1
var slot_index: int = -1
var _target_ref: WeakRef = weakref(null)

func configure_drone(origin_bay_id_value: int, slot_index_value: int) -> void:
	origin_bay_id = origin_bay_id_value
	slot_index = slot_index_value

func command_launch(target: Node3D) -> void:
	command_set_target(target)
	_report_state(STATE_ACTIVE)

func command_attack(target: Node3D) -> void:
	command_set_target(target)
	if target == null:
		_report_state(STATE_ACTIVE)
		return
	_report_state(STATE_ATTACKING)

func command_idle() -> void:
	command_set_target(null)
	_report_state(STATE_ACTIVE)

func command_set_target(target: Node3D) -> void:
	_target_ref = weakref(target) if target != null else weakref(null)

func command_begin_return() -> void:
	command_set_target(null)
	_report_state(STATE_RETURNING)

func command_dock() -> void:
	command_set_target(null)
	_report_state(STATE_DOCKED)
	if is_inside_tree():
		call_deferred("queue_free")
	else:
		queue_free()

func get_target() -> Node3D:
	return _target_ref.get_ref() as Node3D if _target_ref != null else null

func _report_state(next_state: int) -> void:
	state_reported.emit(origin_bay_id, slot_index, next_state)
