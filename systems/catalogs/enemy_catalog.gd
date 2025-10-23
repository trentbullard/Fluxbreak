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

func pick_by_cost(pool: Array[EnemyDef], max_cost: int) -> EnemyDef:
	var best: EnemyDef = null
	for e in pool:
		if e.threat_cost <= max_cost:
			if best == null or e.threat_cost > best.threat_cost:
				best = e
	return best
