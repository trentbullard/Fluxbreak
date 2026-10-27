extends EnemyAttackTelegraph
class_name BugSporeZone

## Emitted after the last pulse's release flash, or immediately on cancellation.
signal finished()

const HARD_GLOBAL_CAP: int = 8
const SPORE_TINT: Color = Color(0.50, 1.0, 0.20, 0.9)

var _pulse_limit: int = 1
var _pulses_resolved: int = 0
var _pending_next_pulse: bool = false
var _finished_emitted: bool = false
var _base_label: String = "SPORE ZONE"

## Count live zones without keeping static references across encounters.
static func can_spawn(source: Enemy, global_cap: int = HARD_GLOBAL_CAP, owner_cap: int = 1) -> bool:
	if not is_instance_valid(source) or source._dead or not source.is_inside_tree() or source.is_queued_for_deletion():
		return false
	var living: int = 0
	var owned: int = 0
	for node: Node in source.get_tree().get_nodes_in_group("bug_spore_zones"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		living += 1
		if int(node.get_meta("spore_owner_id", 0)) == source.get_instance_id():
			owned += 1
	return living < clampi(global_cap, 1, HARD_GLOBAL_CAP) and owned < clampi(owner_cap, 1, 2)

## The first target position and weapon snapshot remain fixed for every pulse.
## Add the zone to the encounter tree before calling this method.
func start_zone(source: Enemy, target: Node3D, weapon_host: Object, windup_sec: float, radius: float, pulse_count: int = 1, warning_label: String = "SPORE ZONE", global_cap: int = HARD_GLOBAL_CAP, owner_cap: int = 1) -> bool:
	if not is_inside_tree() or not can_spawn(source, global_cap, owner_cap):
		cancel()
		return false
	_pulse_limit = clampi(pulse_count, 1, 2)
	_base_label = warning_label.strip_edges()
	set_meta("spore_owner_id", source.get_instance_id())
	add_to_group("bug_spore_zones")
	set_warning_style(_pulse_label(), SPORE_TINT)
	start_attack(source, target, weapon_host, maxf(windup_sec, 0.5), maxf(radius, 1.0))
	return _active and not is_queued_for_deletion()

func get_pulses_resolved() -> int:
	return _pulses_resolved

func _physics_process(delta: float) -> void:
	if _pending_next_pulse:
		if not is_instance_valid(_source) or _source._dead or not is_instance_valid(_target) or not _target.visible or (_target.has_method("is_alive") and not bool(_target.call("is_alive"))):
			cancel()
			return
		_flash_remaining_sec -= delta
		if _attack_field != null:
			_attack_field.set_release(maxf(_flash_remaining_sec, 0.0) / RELEASE_FLASH_SEC)
		if _flash_remaining_sec <= 0.0:
			_pending_next_pulse = false
			_has_resolved = false
			_active = true
			_elapsed_sec = 0.0
			_warning_label = _pulse_label()
			_update_visuals(0.0)
		return
	if _has_resolved and _flash_remaining_sec <= delta:
		_emit_finished()
	super._physics_process(delta)

func _resolve_attack() -> void:
	super._resolve_attack()
	_pulses_resolved += 1
	_pending_next_pulse = _pulses_resolved < _pulse_limit

func cancel() -> void:
	_pending_next_pulse = false
	_emit_finished()
	super.cancel()

func _emit_finished() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	finished.emit()

func _pulse_label() -> String:
	return "%s %d/%d" % [_base_label, _pulses_resolved + 1, _pulse_limit]
