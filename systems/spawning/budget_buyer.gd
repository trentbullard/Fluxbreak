# system/spawning/budget_buyer.gd (godot 4.5)
extends Node
class_name BudgetBuyer

@export var enemy_catalog_path: NodePath
@export var target_catalog_path: NodePath

var _ec: EnemyCatalog
var _tc: TargetCatalog

func _ready() -> void:
	_ec = get_node_or_null(enemy_catalog_path) as EnemyCatalog
	_tc = get_node_or_null(target_catalog_path) as TargetCatalog

func buy_wave(enemy_points: int, target_points: int, card: WaveCard, max_enemy_tier: int) -> Array[SpawnRequest]:
	var reqs: Array[SpawnRequest] = []
	
	var e_pool: Array[EnemyDef] = _ec.get_pool(card.faction_bias, card.role_bias, max_enemy_tier)
	var e_pts: int = max(enemy_points, 0)
	while e_pts > 0 and e_pool.size() > 0:
		var pick: EnemyDef = _ec.pick_by_cost(e_pool, e_pts)
		if pick == null:
			break
		var copies: int = max(1, e_pts / max(pick.threat_cost, 1))
		var req: SpawnRequest = SpawnRequest.new()
		req.kind = "Enemy"
		req.enemy_def = pick
		req.count = copies
		req.batch_size_min = card.batch_size_min
		req.batch_size_max = card.batch_size_max
		req.inter_batch_sec = card.inter_batch_sec
		reqs.append(req)
		e_pts -= copies * pick.threat_cost
	
	var t_pool: Array[TargetDef] = _tc.get_pool(0)
	var t_pts: int = max(target_points, 0)
	while t_pts > 0 and t_pool.size() > 0:
		var tpick: TargetDef = _tc.pick_by_cost(t_pool, t_pts)
		if tpick == null:
			break
		var tcopies: int = max(1, t_pts / max(tpick.threat_cost, 1))
		var treq: SpawnRequest = SpawnRequest.new()
		treq.kind = "Target"
		treq.target_def = tpick
		treq.count = tcopies
		treq.batch_size_min = card.batch_size_min
		treq.batch_size_max = card.batch_size_max
		treq.inter_batch_sec = card.inter_batch_sec
		reqs.append(treq)
		t_pts -= tcopies * tpick.threat_cost
	
	return reqs
