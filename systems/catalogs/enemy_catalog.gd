# systems/catalogs/enemy_catalog.gd (godot 4.5)
extends Node
class_name EnemyCatalog

@export var enemies: Array[EnemyDef] = []

func get_pool(faction: FactionDef, role: EnemyRoleDef, max_tier: int) -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	for e in enemies:
		if e == null:
			continue
		if max_tier > 0 and e.tier > max_tier:
			continue
		if faction != null and not _matches_faction_ref(e.faction, faction):
			continue
		if role != null and not _matches_role_ref(e.role, role):
			continue
		out.append(e)
	return out

func get_pool_for_roles(faction: FactionDef, roles: Array[EnemyRoleDef], max_tier: int) -> Array[EnemyDef]:
	var cleaned_roles: Array[EnemyRoleDef] = []
	for role in roles:
		if role != null and not _contains_role_ref(cleaned_roles, role):
			cleaned_roles.append(role)
	if cleaned_roles.is_empty():
		return get_pool(faction, null, max_tier)

	var out: Array[EnemyDef] = []
	for e in enemies:
		if e == null:
			continue
		if max_tier > 0 and e.tier > max_tier:
			continue
		if faction != null and not _matches_faction_ref(e.faction, faction):
			continue
		if _contains_role_ref(cleaned_roles, e.role):
			out.append(e)
	return out

func get_affordable_pool(pool: Array[EnemyDef], max_cost: int) -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	for e in pool:
		if e != null and e.threat_cost <= max_cost:
			out.append(e)
	return out

func get_unique_roles(faction: FactionDef, max_tier: int) -> Array[EnemyRoleDef]:
	var roles: Array[EnemyRoleDef] = []
	for e in enemies:
		if e == null:
			continue
		if max_tier > 0 and e.tier > max_tier:
			continue
		if faction != null and not _matches_faction_ref(e.faction, faction):
			continue
		if e.role != null and not _contains_role_ref(roles, e.role):
			roles.append(e.role)
	return roles

func pick_by_cost(pool: Array[EnemyDef], max_cost: int) -> EnemyDef:
	var best: EnemyDef = null
	for e in pool:
		if e != null and e.threat_cost <= max_cost:
			if best == null or e.threat_cost > best.threat_cost:
				best = e
	return best

func _matches_faction_ref(left: FactionDef, right: FactionDef) -> bool:
	if left == right:
		return true
	if left == null or right == null:
		return false
	var left_id: StringName = left.get_faction_id()
	var right_id: StringName = right.get_faction_id()
	return left_id != &"" and left_id == right_id

func _matches_role_ref(left: EnemyRoleDef, right: EnemyRoleDef) -> bool:
	if left == right:
		return true
	if left == null or right == null:
		return false
	var left_id: StringName = left.get_role_id()
	var right_id: StringName = right.get_role_id()
	return left_id != &"" and left_id == right_id

func _contains_role_ref(source: Array[EnemyRoleDef], wanted: EnemyRoleDef) -> bool:
	for entry in source:
		if _matches_role_ref(entry, wanted):
			return true
	return false
