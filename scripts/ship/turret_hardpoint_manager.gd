# scripts/ship/turret_hardpoint_manager.gd (godot 4.5)
extends Node3D
class_name TurretHardpointManager

@export var assembly_scene: PackedScene
@export var policy: MountLayoutPolicy
@export var anchors_root_path: NodePath = NodePath("")
@export var stow_anchor_name: String = "StowParking"
@export var max_assemblies: int = 8

const DEFAULT_TEAM_ID: int = 1

var _anchor_cache: Dictionary = {}
var _pool: Array[TurretAssembly] = []
var _mount_stack: Array[MountLoadoutDef] = []

func _ready() -> void:
	_build_anchor_cache()
	ensure_pool_size(max_assemblies)
	
	EventBus.add_gun_requested.connect(push_weapon)
	EventBus.rem_gun_requested.connect(pop_weapon)

func get_weapons() -> Array[WeaponDef]:
	var out: Array[WeaponDef] = []
	for mount in _mount_stack:
		if mount != null and mount.weapon != null:
			out.append(mount.weapon)
	return out

func get_weapon_count() -> int:
	return _mount_stack.size()

func get_turret_assemblies() -> Array[TurretAssembly]:
	return _pool.duplicate()

func apply_loadout(loadout: ShipLoadoutDef, take: int) -> void:
	_mount_stack.clear()
	if loadout != null and not loadout.mounts.is_empty():
		var want: int = clamp(take, 0, loadout.mounts.size())
		for i in range(want):
			var ml: MountLoadoutDef = loadout.mounts[i]
			var copy: MountLoadoutDef = _clone_mount_loadout(ml)
			if copy != null and copy.weapon != null:
				_mount_stack.append(copy)
	_realign_and_apply_current()
	_notify_changed()

func set_weapons(weapons_ordered: Array[WeaponDef]) -> void:
	_mount_stack.clear()
	for weapon in weapons_ordered:
		if weapon == null:
			continue
		_mount_stack.append(_make_mount_loadout("", weapon, _default_team_for_new_mount()))
	_realign_and_apply_current()
	_notify_changed()

func push_weapon(w: WeaponDef) -> void:
	if _mount_stack.size() >= max_assemblies:
		return

	var team_for_new: int = _default_team_for_new_mount()
	if w == null:
		if _mount_stack.is_empty():
			return
		var first_weapon: WeaponDef = _mount_stack[0].weapon
		if first_weapon == null:
			return
		w = first_weapon.duplicate(true) as WeaponDef
		team_for_new = _mount_stack[0].team_id
	if w == null:
		return

	_mount_stack.append(_make_mount_loadout("", w, team_for_new))
	_realign_and_apply_current()
	_notify_changed()

func pop_weapon(idx: int = -1, w: WeaponDef = null) -> void:
	if _mount_stack.size() <= 1:
		return

	var target_index: int = idx

	if w != null:
		# find the first matching weapon by weapon_id
		for i in range(_mount_stack.size()):
			var mount: MountLoadoutDef = _mount_stack[i]
			var weap: WeaponDef = mount.weapon if mount != null else null
			if weap != null and weap.weapon_id == w.weapon_id:
				target_index = i
				break
	else:
		# if no specific weapon, default to last if idx not given
		if target_index < 0 or target_index >= _mount_stack.size():
			target_index = _mount_stack.size() - 1

	# safety check before removing
	if target_index < 0 or target_index >= _mount_stack.size():
		return

	_mount_stack.remove_at(target_index)
	_realign_and_apply_current()
	_notify_changed()

func swap_weapon_at(index: int, w: WeaponDef) -> void:
	if index < 0 or index >= _mount_stack.size():
		return
	var mount: MountLoadoutDef = _mount_stack[index]
	if mount == null:
		mount = _make_mount_loadout("", w, _default_team_for_new_mount())
		_mount_stack[index] = mount
	else:
		mount.weapon = w
	_realign_and_apply_current()
	_notify_changed()

func _notify_changed() -> void:
	EventBus.weapons_changed.emit(get_weapons())

func _realign_and_apply_current() -> void:
	var count: int = _mount_stack.size()
	
	# 1) ensure pool big enough
	ensure_pool_size(count)
	
	# 2) deterministic order
	_pool.sort_custom(func(a: TurretAssembly, b: TurretAssembly) -> bool:
		return a.mount_index < b.mount_index
	)
	
	# 3) apply weapons to first K assemblies
	var k: int = min(count, _pool.size())
	for i in range(k):
		var mount: MountLoadoutDef = _mount_stack[i]
		var weapon: WeaponDef = mount.weapon if mount != null else null
		var team_id: int = mount.team_id if mount != null else DEFAULT_TEAM_ID
		_pool[i].team_id = team_id
		_pool[i].swap_weapon(weapon, true)
	
	# 4) clear the rest
	for j in range(k, _pool.size()):
		_pool[j].clear_weapon(true)
	
	# 5) place by explicit mount_id anchors, or fallback to policy.
	var anchors: Array[Node3D] = _resolve_anchor_nodes_for_active_stack(k)
	var limit: int = min(k, anchors.size())
	for i in range(limit):
		_snap(_pool[i], anchors[i])
	
	# 6) stow leftovers
	if _pool.size() > limit:
		var stow: Node3D = _anchor_cache.get(stow_anchor_name, null)
		if stow != null:
			for j in range(limit, _pool.size()):
				_snap(_pool[j], stow)

func _default_team_for_new_mount() -> int:
	if not _mount_stack.is_empty() and _mount_stack[0] != null:
		return _mount_stack[0].team_id
	return DEFAULT_TEAM_ID

func _make_mount_loadout(mount_id: String, weapon: WeaponDef, team_id: int) -> MountLoadoutDef:
	var mount: MountLoadoutDef = MountLoadoutDef.new()
	mount.mount_id = mount_id
	mount.weapon = weapon
	mount.team_id = team_id
	return mount

func _clone_mount_loadout(source: MountLoadoutDef) -> MountLoadoutDef:
	if source == null:
		return null
	return _make_mount_loadout(source.mount_id, source.weapon, source.team_id)

func _build_anchor_cache() -> void:
	_anchor_cache.clear()
	var root: Node = get_node_or_null(anchors_root_path)
	if root == null: return
	for c in root.get_children():
		if c is Node3D:
			_anchor_cache[String(c.name)] = c

func rebuild_anchor_cache() -> void:
	_build_anchor_cache()
	_realign_and_apply_current()

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

func _resolve_anchor_nodes_for_active_stack(count: int) -> Array[Node3D]:
	var explicit: Array[Node3D] = _resolve_explicit_anchor_nodes(count)
	if explicit.size() == count:
		return explicit
	return _resolve_anchor_nodes(count)

func _resolve_explicit_anchor_nodes(count: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if count <= 0:
		return out
	for i in range(count):
		var mount: MountLoadoutDef = _mount_stack[i]
		if mount == null:
			return []
		var anchor_name: String = mount.mount_id.strip_edges()
		if anchor_name == "":
			return []
		var anchor: Node3D = _anchor_cache.get(anchor_name, null)
		if anchor == null:
			return []
		out.append(anchor)
	return out

func _resolve_anchor_nodes(count: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if policy == null or count <= 0:
		return out
	var names: PackedStringArray = policy.get_anchor_names_for(count)
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
