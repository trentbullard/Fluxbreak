# systems/catalogs/target_catalog.gd (godot 4.5)
extends Node
class_name TargetCatalog

@export var targets: Array[TargetDef] = []

func get_pool(size_band_max: int) -> Array[TargetDef]:
	var out: Array[TargetDef] = []
	for t in targets:
		if size_band_max > 0 and t.size_band > size_band_max:
			continue
		out.append(t)
	return out

func pick_by_cost(pool: Array[TargetDef], max_cost: int) -> TargetDef:
	var best: TargetDef = null
	for t in pool:
		if t.threat_cost <= max_cost:
			if best == null or t.threat_cost > best.threat_cost:
				best = t
	return best
