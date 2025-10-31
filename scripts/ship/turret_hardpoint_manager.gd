# scripts/ship/turret_hardpoint_manager.gd (godot 4.5)
extends Node3D
class_name TurretHardpointManager

@export var assembly_scene: PackedScene
@export var policy: MountLayoutPolicy
@export var anchors_root_path: NodePath = NodePath("Anchors")
@export var stow_anchor_name: String = "StowParking"
@export var max_assemblies: int = 8

var _anchor_cache: Dictionary = {}
var _pool: Array[TurretAssembly] = []
var _weapons: Array[WeaponDef] = []

func _ready() -> void:
	_build_anchor_cache()
	ensure_pool_size(8)
	
	EventBus.add_gun_requested.connect(push_weapon)
	EventBus.rem_gun_requested.connect(pop_weapon)

func get_weapons() -> Array[WeaponDef]:
	return _weapons.duplicate()

func get_weapon_count() -> int:
	return _weapons.size()

func apply_loadout(loadout: ShipLoadoutDef, take: int) -> void:
	_weapons.clear()
	if loadout != null and not loadout.mounts.is_empty():
		var want: int = clamp(take, 0, loadout.mounts.size())
		for i in range(want):
			var ml: MountLoadoutDef = loadout.mounts[i]
			if ml != null and ml.weapon != null:
				_weapons.append(ml.weapon)
	_realign_and_apply_current()
	_notify_changed()

func set_weapons(weapons_ordered: Array[WeaponDef]) -> void:
	_weapons = weapons_ordered.duplicate()
	_realign_and_apply_current()
	_notify_changed()

func push_weapon(w: WeaponDef) -> void:
	if _weapons.size() >= max_assemblies: return
	if w == null:
		w = get_weapons()[0].duplicate(true)
	_weapons.append(w)
	_realign_and_apply_current()
	_notify_changed()

func pop_weapon(idx: int = -1, w: WeaponDef = null) -> void:
	if _weapons.size() <= 1:
		return

	var target_index: int = idx

	if w != null:
		# find the first matching weapon by weapon_id
		for i in range(_weapons.size()):
			var weap: WeaponDef = _weapons[i]
			if weap.weapon_id == w.weapon_id:
				target_index = i
				break
	else:
		# if no specific weapon, default to last if idx not given
		if target_index < 0 or target_index >= _weapons.size():
			target_index = _weapons.size() - 1

	# safety check before removing
	if target_index < 0 or target_index >= _weapons.size():
		return

	_weapons.remove_at(target_index)
	_realign_and_apply_current()
	_notify_changed()

func swap_weapon_at(index: int, w: WeaponDef) -> void:
	if index < 0 or index >= _weapons.size(): return
	_weapons[index] = w
	_realign_and_apply_current()
	_notify_changed()

func _notify_changed() -> void:
	EventBus.weapons_changed.emit(_weapons)

func _realign_and_apply_current() -> void:
	var count: int = _weapons.size()
	
	# 1) ensure pool big enough
	ensure_pool_size(count)
	
	# 2) deterministic order
	_pool.sort_custom(func(a: TurretAssembly, b: TurretAssembly) -> bool:
		return a.mount_index < b.mount_index
	)
	
	# 3) apply weapons to first K assemblies
	var k: int = min(count, _pool.size())
	for i in range(k):
		_pool[i].swap_weapon(_weapons[i], true)
	
	# 4) clear the rest
	for j in range(k, _pool.size()):
		_pool[j].clear_weapon(true)
	
	# 5) place by policy
	var anchors: Array[Node3D] = _resolve_anchor_nodes(k)
	var limit: int = min(k, anchors.size())
	for i in range(limit):
		_snap(_pool[i], anchors[i])
	
	# 6) stow leftovers
	if _pool.size() > limit:
		var stow: Node3D = _anchor_cache.get(stow_anchor_name, null)
		if stow != null:
			for j in range(limit, _pool.size()):
				_snap(_pool[j], stow)

func _build_anchor_cache() -> void:
	_anchor_cache.clear()
	var root: Node = get_node_or_null(anchors_root_path)
	if root == null: return
	for c in root.get_children():
		if c is Node3D:
			_anchor_cache[String(c.name)] = c

func ensure_pool_size(n: int) -> void:
	var target: int = clamp(n, 0, max_assemblies)
	while _pool.size() < target and assembly_scene != null:
		var a: TurretAssembly = assembly_scene.instantiate() as TurretAssembly
		if a != null:
			a.mount_index = _pool.size()
			a.controller_path = get_parent().get_path()
			add_child(a)
			_pool.append(a)
	while _pool.size() > target:
		var last: TurretAssembly = _pool.pop_back()
		if last != null:
			last.queue_free()

func _resolve_anchor_nodes(count: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if policy == null or count <= 0:
		return out
	var names: PackedStringArray = policy.get_anchor_names_for(count - 1)
	for n in names:
		if _anchor_cache.has(n):
			out.append(_anchor_cache[n])
	return out

func _snap(a: TurretAssembly, anchor: Node3D) -> void:
	if a == null or anchor == null:
		return
	
	a.set_as_top_level(false)

	if a.get_parent() != anchor:
		a.reparent(anchor, true)
	
	a.transform = Transform3D.IDENTITY
