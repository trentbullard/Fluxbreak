# scripts/enemy/enemy.gd  (Godot 4.5)
extends RigidBody3D
class_name Enemy

signal about_to_die(target: Enemy)

const NanobotSwarmScene: PackedScene = preload("res://scenes/drops/nanobot_swarm.tscn")

@export_group("Paths")
@export var turret_paths: Array[NodePath] = []

# ---------- Designer test defaults (used if no def is injected) ----------
@export_group("Defaults")
@export var max_hull: float = 20.0
@export var max_shield: float = 0.0
@export var shield_regen: float = 0.0
@export var evasion: float = 0.10
@export var thrust: float = 40.0
@export var score_on_kill: int = 10
@export var explosion_scene: PackedScene

@export var player_ship: Ship
@export var label_height: float = 1.5
@export var label_update_hz: float = 10.0

@export_group("Behavior")
@export var min_distance: float = 250.0
@export var max_distance: float = 400.0
@export var model_root_path: NodePath = ^"ModelRoot"

@export_group("Warp In")
@export var warp_fade_duration_sec: float = 0.35
@export var warp_start_scale: float = 0.72
@export_range(0.0, 1.0, 0.01) var warp_start_alpha: float = 0.18
@export var warp_emission_boost: float = 2.6

# designer test entry point
@export var editor_preview_def: EnemyDef

# ---------- Runtime / identity (not exported) ----------
var def: EnemyDef = null
var enemy_id: String = ""
var display_name: String = ""
var faction: FactionDef = null
var role: EnemyRoleDef = null
var faction_id: StringName = &""
var role_id: StringName = &""
var tier: int = 1
var eff_max_hull: float = 20.0
var eff_max_shield: float = 0.0
var eff_shield_regen: float = 0.0
var eff_evasion: float = 0.10
var eff_thrust: float = 40.0

# ---------- Internals ----------
var _dead: bool = false
var _last_xform: Transform3D = Transform3D()
var hull: float
var shield: float
var _regen_timer: Timer
var _tangent_axis: Vector3 = Vector3.UP
var _axis_timer: float = 0.0
var _spawn_context: EnemySpawnContext = null
var _stat_snapshot: EnemyStatSnapshot = null
var _warp_tween: Tween = null
var _warp_material_entries: Array[Dictionary] = []
var _warp_model_root: Node3D = null
var _warp_original_model_scale: Vector3 = Vector3.ONE

func configure_enemy(d: EnemyDef, spawn_context: EnemySpawnContext = null) -> void:
	if d == null: return
	def = d
	_spawn_context = spawn_context if spawn_context != null else EnemySpawnContext.from_enemy_def(d)
	
	# Identity (runtime only)
	enemy_id = d.id
	display_name = d.display_name
	faction = d.faction
	role = d.role
	faction_id = d.get_faction_id()
	role_id = d.get_role_id()
	tier = d.tier
	
	# Make this discoverable by AI/UX without tight coupling
	set_meta("faction_id", faction_id)
	set_meta("role_id", role_id)
	set_meta("kind", "enemy")
	if faction_id != &"":
		add_to_group("faction_" + String(faction_id))
	if role_id != &"":
		add_to_group("role_" + String(role_id))
	
	# Stats (these override prefab defaults)
	max_hull = d.max_hull
	max_shield = d.max_shield
	shield_regen = d.shield_regen
	evasion = d.evasion
	thrust = d.thrust
	score_on_kill = d.score_on_kill
	_refresh_effective_stats()
	
	# Visuals
	var model_root: Node3D = get_node_or_null(model_root_path) as Node3D
	if d.model_scene != null:
		if model_root != null: model_root.free()
		var new_root: Node3D = d.model_scene.instantiate() as Node3D
		new_root.name = "ModelRoot"
		add_child(new_root)
		model_root_path = ^"ModelRoot"
		model_root = new_root
		call_deferred("_snap_to_socket", ^"Turret/Muzzle", ^"ModelRoot/MuzzleSocket", false, false)
	
	var weapon_snapshot: WeaponStatSnapshot = null
	if _stat_snapshot != null:
		weapon_snapshot = _stat_snapshot.weapon_stats
	_apply_weapon_to_turrets(d.weapon, d.team_id, weapon_snapshot)

func apply_damage(amount: float, combat_stat_context: CombatStatContext = null) -> void:
	if _dead:
		return
	var incoming: float = max(0.0, amount)
	if incoming <= 0.0:
		return
	var remaining: float = incoming
	var shield_damage: float = 0.0
	if shield > 0.0:
		var absorbed: float = min(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
		shield_damage = absorbed
	var hull_damage: float = 0.0
	if remaining > 0.0:
		hull_damage = min(hull, remaining)
		hull -= remaining
	var total_damage_applied: float = shield_damage + hull_damage
	var dealt_killing_blow: bool = hull_damage > 0.0 and hull <= 0.0
	if total_damage_applied > 0.0 and combat_stat_context != null:
		var effective_context: CombatStatContext = combat_stat_context.duplicate_context()
		effective_context.set_enemy_identity_from_source(self)
		GameFlow.record_damage_dealt(total_damage_applied, effective_context)
		if dealt_killing_blow:
			GameFlow.record_enemy_kill(effective_context)
	if hull <= 0.0:
		_die()

func set_ship(ship: Ship):
	player_ship = ship

func get_evasion() -> float:
	return clamp(eff_evasion, 0.0, 1.0)

func get_faction_id() -> StringName:
	return faction_id

func get_role_id() -> StringName:
	return role_id

func get_enemy_id() -> StringName:
	return StringName(enemy_id)

func get_faction_display_name() -> String:
	if faction == null:
		return ""
	return faction.get_display_name_or_default()

func get_role_display_name() -> String:
	if role == null:
		return ""
	return role.get_display_name_or_default()

func get_effective_stat_snapshot() -> EnemyStatSnapshot:
	return _stat_snapshot

func build_combat_stat_context() -> CombatStatContext:
	var context: CombatStatContext = CombatStatContext.new()
	context.set_enemy_identity_from_source(self)
	return context

func play_warp_in(delay_sec: float = 0.0) -> void:
	var model_root: Node3D = get_node_or_null(model_root_path) as Node3D
	if model_root == null:
		return

	_stop_warp_in()
	_warp_model_root = model_root
	_warp_original_model_scale = model_root.scale

	var tween: Tween = create_tween()
	_warp_tween = tween
	if delay_sec > 0.0:
		tween.tween_interval(delay_sec)
	tween.tween_callback(Callable(self, "_begin_warp_in"))
	tween.tween_method(
		Callable(self, "_set_warp_in_progress"),
		0.0,
		1.0,
		max(warp_fade_duration_sec, 0.01)
	)
	tween.tween_callback(Callable(self, "_finish_warp_in"))

func refresh_effective_stats(reinitialize_current_values: bool = false) -> void:
	_refresh_effective_stats()
	if reinitialize_current_values:
		hull = eff_max_hull
		shield = eff_max_shield

func _enter_tree() -> void:
	# In-editor preview convenience: if a def is set on the prefab
	# and nobody configured us yet, hydrate from it.
	if Engine.is_editor_hint() and def == null and editor_preview_def != null:
		configure_enemy(editor_preview_def)

func _ready() -> void:
	add_to_group("targets")
	_last_xform = global_transform

	hull = eff_max_hull
	shield = eff_max_shield
	
	# --- shield regen timer ---
	_regen_timer = Timer.new()
	_regen_timer.wait_time = 1.0
	_regen_timer.autostart = true
	_regen_timer.timeout.connect(_on_regen_tick)
	add_child(_regen_timer)

func _physics_process(delta: float) -> void:
	_axis_timer -= delta
	if _axis_timer <= 0.0:
		_pick_new_axis()
	
	if player_ship != null:
		_face_target(player_ship.global_position)
		_orbit_target(player_ship.global_position)

func _process(_delta: float) -> void:
	if is_inside_tree():
		_last_xform = global_transform

func _on_regen_tick() -> void:
	if _dead:
		return
	if shield < eff_max_shield and eff_shield_regen > 0.0:
		shield = min(shield + eff_shield_regen, eff_max_shield)

func _die() -> void:
	if _dead:
		return
	_dead = true
	
	about_to_die.emit(self)
	if def != null:
		CombatStats.report_enemy_kill(def.threat_cost)

	# spawn a visual nanobot swarm at the enemy location to represent dropped resources
	if NanobotSwarmScene != null:
		var swarm_node: NanobotSwarm = NanobotSwarmScene.instantiate() as NanobotSwarm
		if swarm_node != null:
			swarm_node.global_transform = global_transform
			# add to the same parent as the enemy so it sits in the world
			var parent_node := (get_parent() if get_parent() != null else get_tree().root)
			parent_node.add_child(swarm_node)
			var combat_scaling: EnemyCombatScalingSnapshot = _spawn_context.enemy_combat_scaling if _spawn_context != null else null
			swarm_node.value = RunState.calc_enemy_nanobots(def, combat_scaling)
	
	remove_from_group("targets")
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = true
	collision_layer = 0
	collision_mask  = 0
	set_physics_process(false)
	
	var mult: float = player_ship.get_effective_score_gain_mult()
	RunState.add_score(int(round(score_on_kill * mult)), "enemy")
	if explosion_scene != null:
		var fx := explosion_scene.instantiate() as Node3D
		fx.global_transform = global_transform
		(get_parent() if get_parent() != null else get_tree().root).add_child(fx)
	
	hide()
	call_deferred("_finalize_death")

func _face_target(target: Vector3) -> void:
	var desired: Vector3 = (target - global_position).normalized()
	var forward: Vector3 = -global_transform.basis.z
	var axis: Vector3 = forward.cross(desired)
	var dot: float = clamp(forward.dot(desired), -1.0, 1.0)
	var angle: float = acos(dot)
	
	if axis.length_squared() > 0.0001 and angle > 0.001:
		var torque: Vector3 = axis.normalized() * angle * 6.0
		apply_torque(torque)
	
	var new_transform: Transform3D = global_transform.looking_at(target, Vector3.UP)
	new_transform.origin = global_position
	global_transform = new_transform

func _orbit_target(target: Vector3) -> void:
	var to_target: Vector3 = target - global_position
	var dist2: float = to_target.length_squared()
	var min2: float = min_distance * min_distance
	var max2: float = max_distance * max_distance
	
	var radial_dir_out: Vector3 = -to_target.normalized()
	if dist2 < min2:
		apply_central_force(radial_dir_out * eff_thrust)
	if dist2 > max2:
		apply_central_force(-radial_dir_out * eff_thrust)
	
	var tangent: Vector3 = radial_dir_out.cross(_tangent_axis).normalized()
	apply_central_force(tangent * eff_thrust * 0.3)

func _refresh_effective_stats() -> void:
	if def == null:
		eff_max_hull = max_hull
		eff_max_shield = max_shield
		eff_shield_regen = shield_regen
		eff_evasion = clamp(evasion, 0.0, 1.0)
		eff_thrust = max(thrust, 0.0)
		return
	var snapshot: EnemyStatSnapshot = EnemyStatResolver.resolve(def, _spawn_context)
	_stat_snapshot = snapshot
	if snapshot == null:
		eff_max_hull = max_hull
		eff_max_shield = max_shield
		eff_shield_regen = shield_regen
		eff_evasion = clamp(evasion, 0.0, 1.0)
		eff_thrust = max(thrust, 0.0)
		return

	eff_max_hull = snapshot.max_hull
	eff_max_shield = snapshot.max_shield
	eff_shield_regen = snapshot.shield_regen
	eff_evasion = clamp(snapshot.evasion, 0.0, 1.0)
	eff_thrust = max(snapshot.thrust, 0.0)

func _is_offscreen(cam: Camera3D, world_pos: Vector3) -> bool:
	# Behind camera?
	if cam.is_position_behind(world_pos):
		return true

	# Outside viewport rect?
	var screen_pos: Vector2 = cam.unproject_position(world_pos)
	var rect: Rect2i = get_viewport().get_visible_rect()
	return not rect.has_point(screen_pos)

func _pick_new_axis() -> void:
	var choices: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT]
	_tangent_axis = choices.pick_random()
	_axis_timer = randf_range(1.0, 4.0)

func _begin_warp_in() -> void:
	if _dead:
		return
	if _warp_model_root == null or not is_instance_valid(_warp_model_root):
		return
	_prepare_warp_materials()
	_set_warp_in_progress(0.0)

func _set_warp_in_progress(progress_variant: Variant) -> void:
	var progress: float = clampf(float(progress_variant), 0.0, 1.0)
	if _warp_model_root != null and is_instance_valid(_warp_model_root):
		var visual_scale: float = lerpf(max(warp_start_scale, 0.01), 1.0, progress)
		_warp_model_root.scale = _warp_original_model_scale * visual_scale

	var alpha: float = lerpf(warp_start_alpha, 1.0, progress)
	var emission_scale: float = lerpf(warp_emission_boost, 1.0, progress)
	for entry in _warp_material_entries:
		var runtime_material: BaseMaterial3D = entry.get("runtime_material", null) as BaseMaterial3D
		if runtime_material == null:
			continue
		var base_color: Color = entry.get("base_color", Color.WHITE)
		var base_emission_color: Color = entry.get("base_emission_color", base_color)
		var base_emission_energy: float = float(entry.get("base_emission_energy", 1.0))
		runtime_material.albedo_color = Color(
			base_color.r,
			base_color.g,
			base_color.b,
			base_color.a * alpha
		)
		runtime_material.emission = base_emission_color
		runtime_material.emission_energy_multiplier = base_emission_energy * emission_scale

func _finish_warp_in() -> void:
	if _warp_model_root != null and is_instance_valid(_warp_model_root):
		_warp_model_root.scale = _warp_original_model_scale
	_restore_warp_materials()
	_warp_tween = null

func _stop_warp_in() -> void:
	if _warp_tween != null:
		_warp_tween.kill()
		_warp_tween = null
	if _warp_model_root != null and is_instance_valid(_warp_model_root):
		_warp_model_root.scale = _warp_original_model_scale
	_restore_warp_materials()

func _prepare_warp_materials() -> void:
	_restore_warp_materials()
	if _warp_model_root == null or not is_instance_valid(_warp_model_root):
		return

	var mesh_nodes: Array[Node] = _warp_model_root.find_children("*", "MeshInstance3D", true, false)
	for node in mesh_nodes:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance == null:
			continue
		if mesh_instance.material_override is BaseMaterial3D:
			var runtime_override: BaseMaterial3D = _duplicate_warp_material(mesh_instance.material_override)
			if runtime_override != null:
				var original_override: Material = mesh_instance.material_override
				mesh_instance.material_override = runtime_override
				_warp_material_entries.append({
					"mesh": mesh_instance,
					"surface_index": -1,
					"original_override": original_override,
					"runtime_material": runtime_override,
					"base_color": runtime_override.albedo_color,
					"base_emission_color": runtime_override.emission,
					"base_emission_energy": runtime_override.emission_energy_multiplier,
				})
			continue
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var original_surface_override: Material = mesh_instance.get_surface_override_material(surface_index)
			var source_material: Material = original_surface_override
			if source_material == null:
				source_material = mesh_instance.mesh.surface_get_material(surface_index)
			var runtime_material: BaseMaterial3D = _duplicate_warp_material(source_material)
			if runtime_material == null:
				continue
			mesh_instance.set_surface_override_material(surface_index, runtime_material)
			_warp_material_entries.append({
				"mesh": mesh_instance,
				"surface_index": surface_index,
				"original_override": original_surface_override,
				"runtime_material": runtime_material,
				"base_color": runtime_material.albedo_color,
				"base_emission_color": runtime_material.emission,
				"base_emission_energy": runtime_material.emission_energy_multiplier,
			})

func _duplicate_warp_material(source_material: Material) -> BaseMaterial3D:
	if not source_material is BaseMaterial3D:
		return null
	var runtime_material: BaseMaterial3D = source_material.duplicate(true) as BaseMaterial3D
	runtime_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	runtime_material.emission_enabled = true
	return runtime_material

func _restore_warp_materials() -> void:
	for entry in _warp_material_entries:
		var mesh_instance: MeshInstance3D = entry.get("mesh", null) as MeshInstance3D
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		var surface_index: int = int(entry.get("surface_index", -1))
		var original_override: Material = entry.get("original_override", null) as Material
		if surface_index < 0:
			mesh_instance.material_override = original_override
		else:
			mesh_instance.set_surface_override_material(surface_index, original_override)
	_warp_material_entries.clear()

func _finalize_death() -> void:
	_stop_warp_in()
	queue_free()

func _snap_to_socket(local_node_path: NodePath, socket_rel_path: NodePath, copy_rot := true, copy_scale := false) -> void:
	var node := get_node_or_null(local_node_path) as Node3D
	var model_root := get_node_or_null(model_root_path) as Node3D
	if node == null or model_root == null:
		return
	var socket := model_root.get_node_or_null(socket_rel_path) as Node3D
	if socket == null:
		return

	var parent := node.get_parent() as Node3D
	var xf := socket.global_transform

	# strip socket scale unless you explicitly want it
	if not copy_scale:
		xf.basis = xf.basis.orthonormalized()

	if copy_rot:
		# place node at socket (pos + rot)
		if parent:
			node.transform = parent.global_transform.affine_inverse() * xf
		else:
			node.global_transform = xf
	else:
		# position only; keep your current rotation/scale
		node.global_position = xf.origin

func _apply_weapon_to_turrets(weapon: WeaponDef, team_id_val: int, snapshot: WeaponStatSnapshot = null) -> void:
	if weapon == null: return
	
	var turrets: Array[Node] = []
	for p in turret_paths:
		var n: Node = get_node_or_null(p)
		if n != null:
			turrets.append(n)
	
	if turrets.is_empty():
		for child in get_children():
			if child is EnemyTurret:
				turrets.append(child)
	
	for t in turrets:
		if t is EnemyTurret:
			var detector: Area3D = $Detector
			(t as EnemyTurret).apply_weapon(weapon, team_id_val, detector, snapshot)
