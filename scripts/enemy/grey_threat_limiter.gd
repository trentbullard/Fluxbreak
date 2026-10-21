extends RefCounted
class_name GreyThreatLimiter

const MAX_ACTIVE_VOLUMES: int = 2

## Controllers check and create their warning in the same call, without yielding.
## Resolved flashes and harmless displacement markers consume no danger slots.
static func can_start_pulse(source: Enemy) -> bool:
	return _source_is_active(source) and _count_threats(source).x < MAX_ACTIVE_VOLUMES

## A pending capture reserves the same unique tether slot as an attached link.
static func can_start_tether(source: Enemy) -> bool:
	if not _source_is_active(source):
		return false
	var counts: Vector2i = _count_threats(source)
	return counts.x < MAX_ACTIVE_VOLUMES and counts.y == 0

static func _source_is_active(source: Enemy) -> bool:
	return is_instance_valid(source) and source.is_inside_tree() and not source.is_queued_for_deletion() and not source._dead and source.get_faction_id() == &"greys"

static func _count_threats(source: Enemy) -> Vector2i:
	var counts: Vector2i = Vector2i.ZERO
	for node: Node in source.get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var warning: EnemyAttackTelegraph = node as EnemyAttackTelegraph
		if warning == null or not _source_is_active(warning._source):
			continue
		var tether: GreyTether = warning as GreyTether
		if tether != null:
			if tether.is_active():
				counts.x += 1
				counts.y += 1
		elif warning._active and not warning._has_resolved:
			counts.x += 1
	return counts
