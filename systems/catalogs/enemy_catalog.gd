# systems/catalogs/enemy_catalog.gd (godot 4.5)
extends Node
class_name EnemyCatalog

@export var enemies: Array[EnemyDef] = []

func get_pool(faction: String, role: String, max_tier: int) -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	for e in enemies:
		if max_tier > 0 and e.tier > max_tier:
			continue
		if faction != "" and e.faction != faction:
			continue
		if role != "" and e.role != role:
			continue
		out.append(e)
	return out

func get_pool_for_roles(faction: String, roles: Array[String], max_tier: int) -> Array[EnemyDef]:
	var cleaned_roles: Array[String] = []
	for role in roles:
		var trimmed: String = role.strip_edges()
		if trimmed != "" and not cleaned_roles.has(trimmed):
			cleaned_roles.append(trimmed)
	if cleaned_roles.is_empty():
		return get_pool(faction, "", max_tier)

	var out: Array[EnemyDef] = []
	for e in enemies:
		if max_tier > 0 and e.tier > max_tier:
			continue
		if faction != "" and e.faction != faction:
			continue
		if cleaned_roles.has(e.role):
			out.append(e)
	return out

func get_affordable_pool(pool: Array[EnemyDef], max_cost: int) -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	for e in pool:
		if e != null and e.threat_cost <= max_cost:
			out.append(e)
	return out

func get_unique_roles(faction: String, max_tier: int) -> Array[String]:
	var roles: Array[String] = []
	for e in enemies:
		if e == null:
			continue
		if max_tier > 0 and e.tier > max_tier:
			continue
		if faction != "" and e.faction != faction:
			continue
		if e.role != "" and not roles.has(e.role):
			roles.append(e.role)
	return roles

func pick_by_cost(pool: Array[EnemyDef], max_cost: int) -> EnemyDef:
	var best: EnemyDef = null
	for e in pool:
		if e.threat_cost <= max_cost:
			if best == null or e.threat_cost > best.threat_cost:
				best = e
	return best
