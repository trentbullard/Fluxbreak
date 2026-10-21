extends Enemy
class_name MercEnemy

enum CorvetteState { APPROACH, BURST, RETREAT }

const SHIELD_RECIPIENT_COOLDOWN: StringName = &"merc_shield_pulse_ready_msec"
const SUPPORT_LINK_DURATION_SEC: float = 0.55

var _behavior: MercBehaviorDef = MercBehaviorDef.new()
var _controlled_turrets: Array[EnemyTurret] = []
var _corvette_state: CorvetteState = CorvetteState.APPROACH
var _attack_cooldown_left: float = 1.0
var _burst_shots_left: int = 0
var _burst_interval_left: float = 0.0
var _retreat_time_left: float = 0.0
var _shield_pulse_left: float = 1.5
var _escort_scan_left: float = 0.0
var _escort: Enemy = null
var _active_attack: EnemyAttackTelegraph = null
var _support_links: Array[Dictionary] = []
var _orbit_direction: float = 1.0

func configure_enemy(d: EnemyDef, spawn_context: EnemySpawnContext = null) -> void:
	super.configure_enemy(d, spawn_context)
	var merc_def: MercEnemyDef = d as MercEnemyDef
	if merc_def != null and merc_def.behavior != null:
		_behavior = merc_def.behavior
	else:
		_behavior = MercBehaviorDef.new()
	set_meta(&"merc_mode", _behavior.mode)
	_collect_controlled_turrets()

func _ready() -> void:
	super._ready()
	_collect_controlled_turrets()
	_attack_cooldown_left = randf_range(0.7, 1.4)
	_orbit_direction = -1.0 if get_instance_id() % 2 == 0 else 1.0
	about_to_die.connect(_on_merc_about_to_die)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_update_support_links(delta)
	if player_ship == null or not is_instance_valid(player_ship) or not player_ship.visible:
		_cancel_charge()
		return
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_face_target(player_ship.global_position)
	match _behavior.mode:
		MercBehaviorDef.Mode.CORVETTE:
			_tick_corvette(delta)
		MercBehaviorDef.Mode.FRIGATE:
			_tick_frigate(delta)
		MercBehaviorDef.Mode.DESTROYER:
			_tick_destroyer()

func get_tactical_state() -> String:
	match _behavior.mode:
		MercBehaviorDef.Mode.FRIGATE:
			return "Shield escort"
		MercBehaviorDef.Mode.DESTROYER:
			return "Cannon charging" if is_instance_valid(_active_attack) else "Cannon recovery"
		_:
			match _corvette_state:
				CorvetteState.BURST:
					return "Burst attack"
				CorvetteState.RETREAT:
					return "Repositioning"
				_:
					return "Closing in"

func _tick_corvette(delta: float) -> void:
	var target_position: Vector3 = player_ship.global_position
	match _corvette_state:
		CorvetteState.APPROACH:
			_steer_in_band(target_position, _behavior.approach_range * 0.7, _behavior.approach_range)
			if _attack_cooldown_left <= 0.0 and _is_within_distance(player_ship, _behavior.approach_range) and _has_target_in_weapon_range():
				_corvette_state = CorvetteState.BURST
				_burst_shots_left = maxi(_behavior.burst_shots, 1)
				_burst_interval_left = 0.0
		CorvetteState.BURST:
			_steer_in_band(target_position, _behavior.approach_range * 0.65, _behavior.retreat_range)
			_burst_interval_left -= delta
			if _burst_interval_left <= 0.0:
				_fire_controlled_shot()
				_burst_shots_left -= 1
				_burst_interval_left = maxf(_behavior.burst_interval_sec, 0.05)
				if _burst_shots_left <= 0:
					_corvette_state = CorvetteState.RETREAT
					_retreat_time_left = maxf(_behavior.retreat_duration_sec, 0.1)
					_attack_cooldown_left = maxf(_behavior.attack_cooldown_sec, 0.1)
		CorvetteState.RETREAT:
			_steer_in_band(target_position, _behavior.retreat_range, _behavior.retreat_range * 1.1)
			_retreat_time_left -= delta
			if _retreat_time_left <= 0.0:
				_corvette_state = CorvetteState.APPROACH

func _tick_frigate(delta: float) -> void:
	_escort_scan_left -= delta
	if _escort_scan_left <= 0.0:
		_escort_scan_left = 0.5
		_escort = _pick_escort()
	if _escort != null and is_instance_valid(_escort) and _escort.hull > 0.0:
		var away_from_player: Vector3 = (_escort.global_position - player_ship.global_position).normalized()
		var anchor: Vector3 = _escort.global_position + away_from_player * _behavior.escort_distance
		var to_anchor: Vector3 = anchor - global_position
		var desired_velocity: Vector3 = to_anchor.limit_length(maxf(_behavior.max_speed, 1.0))
		desired_velocity += _escort.linear_velocity * 0.35
		_steer_to_velocity(desired_velocity.limit_length(maxf(_behavior.max_speed, 1.0)))
	else:
		_steer_in_band(player_ship.global_position, _behavior.approach_range, _behavior.retreat_range)
	_shield_pulse_left -= delta
	if _shield_pulse_left <= 0.0:
		_shield_pulse_left = maxf(_behavior.shield_pulse_interval_sec, 0.5)
		_pulse_allied_shields()
	if _attack_cooldown_left <= 0.0 and _fire_controlled_shot():
		_attack_cooldown_left = maxf(_behavior.attack_cooldown_sec, 0.1)

func _tick_destroyer() -> void:
	if is_instance_valid(_active_attack):
		_steer_to_velocity(Vector3.ZERO)
		return
	_steer_in_band(player_ship.global_position, _behavior.approach_range, _behavior.retreat_range)
	if _attack_cooldown_left > 0.0 or not _has_target_in_weapon_range():
		return
	var turret: EnemyTurret = _first_valid_turret()
	if turret == null:
		return
	var encounter_root: Node = get_tree().current_scene
	if encounter_root == null:
		return
	_active_attack = EnemyAttackTelegraph.new()
	encounter_root.add_child(_active_attack)
	_active_attack.resolved.connect(_on_charge_resolved)
	_active_attack.start_attack(self, player_ship, turret, maxf(_behavior.charge_windup_sec, 0.2), maxf(_behavior.charge_radius, 1.0), true)

func _steer_in_band(target_position: Vector3, inner_range: float, outer_range: float) -> void:
	var to_target: Vector3 = target_position - global_position
	var distance_squared: float = to_target.length_squared()
	var radial: Vector3 = to_target.normalized()
	var tangent: Vector3 = radial.cross(Vector3.UP).normalized() * _orbit_direction
	var desired_velocity: Vector3 = tangent * _behavior.max_speed * _behavior.orbit_strength
	var inner: float = maxf(inner_range, 1.0)
	var outer: float = maxf(outer_range, inner)
	if distance_squared > outer * outer:
		desired_velocity += radial * _behavior.max_speed
	elif distance_squared < inner * inner:
		desired_velocity -= radial * _behavior.max_speed
	_steer_to_velocity(desired_velocity.limit_length(maxf(_behavior.max_speed, 1.0)))

func _steer_to_velocity(desired_velocity: Vector3) -> void:
	var correction: Vector3 = (desired_velocity - linear_velocity) * maxf(_behavior.steering_response, 0.1)
	apply_central_force(correction.limit_length(maxf(eff_thrust, 0.0)))

func _collect_controlled_turrets() -> void:
	_controlled_turrets.clear()
	for path: NodePath in turret_paths:
		var turret: EnemyTurret = get_node_or_null(path) as EnemyTurret
		if turret != null and not _controlled_turrets.has(turret):
			_controlled_turrets.append(turret)
	if _controlled_turrets.is_empty():
		for child: Node in get_children():
			if child is EnemyTurret:
				_controlled_turrets.append(child as EnemyTurret)
	# Merc attacks own every firing window, including charge recovery.
	for turret: EnemyTurret in _controlled_turrets:
		turret.set_physics_process(false)

func _first_valid_turret() -> EnemyTurret:
	for turret: EnemyTurret in _controlled_turrets:
		if is_instance_valid(turret):
			return turret
	return null

func _has_target_in_weapon_range() -> bool:
	for turret: EnemyTurret in _controlled_turrets:
		if not is_instance_valid(turret):
			continue
		var weapon_range: float = maxf(turret.eff_base_range + turret.eff_range_bonus_add, 0.0)
		if turret.get_shot_origin().distance_squared_to(player_ship.global_position) <= weapon_range * weapon_range:
			return true
	return false

func _fire_controlled_shot() -> bool:
	if _dead or def == null or def.weapon == null:
		return false
	var fired: bool = false
	for turret: EnemyTurret in _controlled_turrets:
		if not is_instance_valid(turret):
			continue
		var weapon_range: float = maxf(turret.eff_base_range + turret.eff_range_bonus_add, 0.0)
		if turret.get_shot_origin().distance_squared_to(player_ship.global_position) > weapon_range * weapon_range:
			continue
		turret._fire_at_with_roll(player_ship)
		fired = true
	return fired

func _pick_escort() -> Enemy:
	var best: Enemy = null
	var best_capacity: float = -1.0
	var search_radius: float = maxf(_behavior.shield_radius * 2.0, _behavior.escort_distance)
	for ally: Enemy in _get_nearby_allies(search_radius):
		# Follow the heavier hull, so a Frigate does not lead its own battle line.
		if int(ally.get_meta(&"merc_mode", -1)) == MercBehaviorDef.Mode.FRIGATE:
			continue
		if ally.eff_max_hull > best_capacity:
			best_capacity = ally.eff_max_hull
			best = ally
	return best

func _get_nearby_allies(radius: float) -> Array[Enemy]:
	var allies: Array[Enemy] = []
	if faction_id == &"":
		return allies
	for node: Node in get_tree().get_nodes_in_group("faction_" + String(faction_id)):
		var ally: Enemy = node as Enemy
		if ally == null or ally == self or not is_instance_valid(ally) or ally.hull <= 0.0 or not ally.visible:
			continue
		if ally.get_faction_id() == faction_id and _is_within_distance(ally, radius):
			allies.append(ally)
	allies.sort_custom(_sort_allies_by_distance)
	return allies

func _sort_allies_by_distance(a: Enemy, b: Enemy) -> bool:
	return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position)

func _is_within_distance(target: Node3D, radius: float) -> bool:
	var safe_radius: float = maxf(radius, 0.0)
	return global_position.distance_squared_to(target.global_position) <= safe_radius * safe_radius

func _pulse_allied_shields() -> void:
	var recipients: int = 0
	var now_msec: int = Time.get_ticks_msec()
	for ally: Enemy in _get_nearby_allies(_behavior.shield_radius):
		if recipients >= clampi(_behavior.shield_max_targets, 1, 4):
			break
		if int(ally.get_meta(SHIELD_RECIPIENT_COOLDOWN, 0)) > now_msec:
			continue
		var support_cap: float = ally.eff_max_shield * clampf(_behavior.shield_restore_fraction, 0.0, 1.0)
		var restored: float = minf(maxf(_behavior.shield_restore_amount, 0.0), maxf(support_cap - ally.shield, 0.0))
		if restored <= 0.0:
			continue
		ally.shield += restored
		ally.set_meta(SHIELD_RECIPIENT_COOLDOWN, now_msec + int(maxf(_behavior.shield_pulse_interval_sec, 0.5) * 1000.0))
		_show_support_link(ally, restored)
		recipients += 1

func _show_support_link(ally: Enemy, restored: float) -> void:
	var link: MeshInstance3D = MeshInstance3D.new()
	link.name = "ShieldPulseLink"
	link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.albedo_color = Color(0.15, 0.85, 1.0, 0.9)
	material.emission_enabled = true
	material.emission = Color(0.15, 0.85, 1.0)
	material.emission_energy_multiplier = 1.5
	link.material_override = material
	link.mesh = ImmediateMesh.new()
	add_child(link)
	link.top_level = true
	link.global_transform = Transform3D.IDENTITY
	_support_links.append({"node": link, "target": ally, "remaining": SUPPORT_LINK_DURATION_SEC})
	EffectsBus.show_float(ally.global_position, "SHIELD +" + str(int(round(restored))), Color(0.15, 0.85, 1.0))

func _update_support_links(delta: float) -> void:
	for index: int in range(_support_links.size() - 1, -1, -1):
		var entry: Dictionary = _support_links[index]
		var target_value: Variant = entry.get("target")
		var link_value: Variant = entry.get("node")
		var target: Enemy = target_value as Enemy if is_instance_valid(target_value) else null
		var link: MeshInstance3D = link_value as MeshInstance3D if is_instance_valid(link_value) else null
		var remaining: float = float(entry.get("remaining", 0.0)) - delta
		if remaining <= 0.0 or not is_instance_valid(target) or target.hull <= 0.0 or not is_instance_valid(link):
			if is_instance_valid(link):
				link.queue_free()
			_support_links.remove_at(index)
			continue
		entry["remaining"] = remaining
		var mesh: ImmediateMesh = link.mesh as ImmediateMesh
		mesh.clear_surfaces()
		var origin: Vector3 = global_position
		var endpoint: Vector3 = target.global_position
		var direction: Vector3 = (endpoint - origin).normalized()
		var side: Vector3 = direction.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.001:
			side = direction.cross(Vector3.RIGHT).normalized()
		var up: Vector3 = direction.cross(side).normalized()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_link_ribbon(mesh, origin, endpoint, side * 1.3)
		_add_link_ribbon(mesh, origin, endpoint, up * 1.3)
		mesh.surface_end()
		var material: StandardMaterial3D = link.material_override as StandardMaterial3D
		material.albedo_color.a = 0.9 * remaining / SUPPORT_LINK_DURATION_SEC

func _add_link_ribbon(mesh: ImmediateMesh, origin: Vector3, endpoint: Vector3, side: Vector3) -> void:
	mesh.surface_add_vertex(origin - side)
	mesh.surface_add_vertex(origin + side)
	mesh.surface_add_vertex(endpoint + side)
	mesh.surface_add_vertex(origin - side)
	mesh.surface_add_vertex(endpoint + side)
	mesh.surface_add_vertex(endpoint - side)

func _on_charge_resolved(_hit: bool) -> void:
	_active_attack = null
	_attack_cooldown_left = maxf(_behavior.attack_cooldown_sec, 0.1)

func _cancel_charge() -> void:
	if is_instance_valid(_active_attack):
		_active_attack.cancel()
	_active_attack = null

func _on_merc_about_to_die(_enemy: Enemy) -> void:
	_cancel_charge()
	_clear_support_links()

func _clear_support_links() -> void:
	for entry: Dictionary in _support_links:
		var link_value: Variant = entry.get("node")
		var link: MeshInstance3D = link_value as MeshInstance3D if is_instance_valid(link_value) else null
		if is_instance_valid(link):
			link.queue_free()
	_support_links.clear()

func _exit_tree() -> void:
	_cancel_charge()
	_clear_support_links()
