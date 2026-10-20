extends Node3D
class_name EnemyAttackTelegraph

## Emitted once after the locked area has been tested and the shot resolved.
signal resolved(hit: bool)

const RING_SEGMENTS: int = 48
const RELEASE_FLASH_SEC: float = 0.18

# This object is the immutable weapon host used by the combat resolver. Damage,
# accuracy and effects are captured at the start, rather than read after windup.
var systems_bonus: float = 0.0
var eff_base_accuracy: float = 0.0
var eff_range_falloff: float = 0.0
var eff_crit_chance: float = 0.0
var eff_graze_on_hit: float = 0.0
var eff_graze_on_miss: float = 0.0
var eff_crit_mult: float = 1.0
var eff_graze_mult: float = 0.3
var eff_damage_min: float = 0.0
var eff_damage_max: float = 0.0
var eff_base_range: float = 0.0
var eff_range_bonus_add: float = 0.0
var eff_systems_bonus_add: float = 0.0

var _source: Enemy = null
var _target: Node3D = null
var _weapon_host: Object = null
var _effects: Array[StatusEffectDef] = []
var _context: CombatStatContext = null
var _locked_origin: Vector3 = Vector3.ZERO
var _locked_position: Vector3 = Vector3.ZERO
var _radius: float = 1.0
var _corridor: bool = false
var _windup_sec: float = 1.0
var _elapsed_sec: float = 0.0
var _active: bool = false
var _has_resolved: bool = false
var _flash_remaining_sec: float = 0.0
var _wire_mesh: ImmediateMesh = null
var _progress_mesh: ImmediateMesh = null
var _wire_material: StandardMaterial3D = null
var _progress_material: StandardMaterial3D = null
var _label: Label3D = null

func start_attack(source: Enemy, target: Node3D, weapon_host: Object, windup_sec: float, radius: float, corridor: bool = false) -> void:
	if _active or _has_resolved:
		return
	if not is_instance_valid(source) or not is_instance_valid(target) or not is_instance_valid(weapon_host):
		cancel()
		return
	_source = source
	_target = target
	_weapon_host = weapon_host
	_locked_origin = WeaponCombatResolver.get_shot_origin(weapon_host)
	_locked_position = target.global_position
	_radius = maxf(radius, 1.0)
	_corridor = corridor
	_windup_sec = maxf(windup_sec, 0.05)
	_context = source.build_combat_stat_context()
	_capture_weapon(weapon_host)
	global_position = _locked_position
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("enemy_attack_telegraphs")
	source.about_to_die.connect(_on_source_died, CONNECT_ONE_SHOT)
	source.tree_exiting.connect(cancel, CONNECT_ONE_SHOT)
	_build_visuals()
	_active = true
	_update_visuals(0.0)

func get_shot_origin() -> Vector3:
	return _locked_origin

func is_warning_for(target: Node3D) -> bool:
	return _active and not _has_resolved and _target == target

func get_time_remaining() -> float:
	return maxf(_windup_sec - _elapsed_sec, 0.0)

func get_attack_label() -> String:
	return "CORRIDOR" if _corridor else "SALVO"

func cancel() -> void:
	_active = false
	queue_free()

## Uses the same locked volume drawn by the warning. Ship evasion is still
## resolved normally, but leaving this volume always avoids the shot.
func contains_position(world_position: Vector3) -> bool:
	if not _corridor:
		return _locked_position.distance_squared_to(world_position) <= _radius * _radius
	var segment: Vector3 = _locked_position - _locked_origin
	var segment_length_sq: float = segment.length_squared()
	if segment_length_sq <= 0.0001:
		return _locked_position.distance_squared_to(world_position) <= _radius * _radius
	var fraction: float = (world_position - _locked_origin).dot(segment) / segment_length_sq
	# A closed cylinder, including its two flat ends, matches the warning rings.
	if fraction < 0.0 or fraction > 1.0:
		return false
	var closest: Vector3 = _locked_origin + segment * fraction
	return closest.distance_squared_to(world_position) <= _radius * _radius

func _physics_process(delta: float) -> void:
	if _has_resolved:
		_flash_remaining_sec -= delta
		if _flash_remaining_sec <= 0.0:
			queue_free()
		return
	if not _active:
		return
	if not is_instance_valid(_source) or _source._dead or not is_instance_valid(_target):
		cancel()
		return
	if not _target.visible or (_target.has_method("is_alive") and not bool(_target.call("is_alive"))):
		cancel()
		return
	_elapsed_sec += delta
	var progress: float = clampf(_elapsed_sec / _windup_sec, 0.0, 1.0)
	_update_visuals(progress)
	if progress >= 1.0:
		_resolve_attack()

func _capture_weapon(host: Object) -> void:
	for property_name in ["systems_bonus", "eff_base_accuracy", "eff_range_falloff", "eff_crit_chance", "eff_graze_on_hit", "eff_graze_on_miss", "eff_crit_mult", "eff_graze_mult", "eff_damage_min", "eff_damage_max", "eff_base_range", "eff_range_bonus_add", "eff_systems_bonus_add"]:
		var property_value: Variant = host.get(property_name)
		if property_value != null:
			set(property_name, float(property_value))
	var weapon: WeaponDef = null
	if host.has_method("get_weapon"):
		weapon = host.call("get_weapon") as WeaponDef
	elif _source.def != null:
		weapon = _source.def.weapon
	if weapon != null:
		for effect in weapon.status_effects:
			if effect != null:
				_effects.append(effect.duplicate(true) as StatusEffectDef)

func _resolve_attack() -> void:
	_active = false
	_has_resolved = true
	_flash_remaining_sec = RELEASE_FLASH_SEC
	var did_hit: bool = false
	if contains_position(_target.global_position):
		var accuracy: float = WeaponCombatResolver.compute_effective_accuracy_vs_target(self, _target)
		var outcome: int = WeaponCombatResolver.resolve_shot_for_turret(self, accuracy)
		var damage: float = randf_range(minf(eff_damage_min, eff_damage_max), maxf(eff_damage_min, eff_damage_max))
		var applied: float = WeaponCombatResolver.apply_shot_to_target(
			_source, _target, outcome, damage, eff_graze_mult, eff_crit_mult, _effects, false, _context
		)
		did_hit = applied > 0.0
	else:
		EffectsBus.show_float(_locked_position, "EVADED", Color(0.35, 0.95, 1.0))
	if is_instance_valid(_weapon_host) and _weapon_host.has_method("play_shot_sound"):
		_weapon_host.call("play_shot_sound")
	elif _weapon_host is EnemyTurret:
		var turret: EnemyTurret = _weapon_host as EnemyTurret
		if is_instance_valid(turret.shot_sound):
			turret.shot_sound.pitch_scale = randf_range(0.9, 1.1)
			turret.shot_sound.play()
	_wire_material.albedo_color = Color(1.0, 0.85, 0.4, 1.0)
	_label.text = "FIRE" if did_hit else "CLEAR"
	resolved.emit(did_hit)

func _on_source_died(_enemy: Enemy) -> void:
	cancel()

func _build_visuals() -> void:
	_wire_material = _make_material(Color(1.0, 0.62, 0.12, 0.85))
	_progress_material = _make_material(Color(1.0, 0.2, 0.1, 1.0))
	_wire_mesh = ImmediateMesh.new()
	_progress_mesh = ImmediateMesh.new()
	var warning: MeshInstance3D = MeshInstance3D.new()
	warning.name = "LockedVolume"
	warning.mesh = _wire_mesh
	warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(warning)
	var progress: MeshInstance3D = MeshInstance3D.new()
	progress.name = "CountdownRing"
	progress.mesh = _progress_mesh
	progress.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(progress)
	_wire_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _wire_material)
	if _corridor:
		_add_corridor()
	else:
		_add_ring(_wire_mesh, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, _radius)
		_add_ring(_wire_mesh, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, _radius)
		_add_ring(_wire_mesh, Vector3.ZERO, Vector3.UP, Vector3.BACK, _radius)
	_wire_mesh.surface_end()
	_label = Label3D.new()
	_label.name = "AttackCountdown"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 28
	_label.outline_size = 6
	_label.pixel_size = 0.28
	_label.position = Vector3.UP * (_radius + 14.0)
	_label.modulate = Color(1.0, 0.75, 0.3)
	add_child(_label)

func _make_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = color
	return material

func _add_corridor() -> void:
	var start: Vector3 = _locked_origin - _locked_position
	var direction: Vector3 = (_locked_position - _locked_origin).normalized()
	if direction.length_squared() <= 0.0001:
		direction = Vector3.FORWARD
	var reference_axis: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right: Vector3 = direction.cross(reference_axis).normalized()
	var up: Vector3 = direction.cross(right).normalized()
	_add_ring(_wire_mesh, start, right, up, _radius)
	_add_ring(_wire_mesh, Vector3.ZERO, right, up, _radius)
	for rail in range(8):
		var angle: float = TAU * float(rail) / 8.0
		var offset: Vector3 = (right * cos(angle) + up * sin(angle)) * _radius
		_wire_mesh.surface_add_vertex(start + offset)
		_wire_mesh.surface_add_vertex(offset)

func _add_ring(mesh: ImmediateMesh, center: Vector3, axis_a: Vector3, axis_b: Vector3, radius: float, fraction: float = 1.0) -> void:
	var segments: int = maxi(1, int(ceil(float(RING_SEGMENTS) * fraction)))
	for segment in range(segments):
		var angle_a: float = TAU * fraction * float(segment) / float(segments)
		var angle_b: float = TAU * fraction * float(segment + 1) / float(segments)
		mesh.surface_add_vertex(center + (axis_a * cos(angle_a) + axis_b * sin(angle_a)) * radius)
		mesh.surface_add_vertex(center + (axis_a * cos(angle_b) + axis_b * sin(angle_b)) * radius)

func _update_visuals(progress: float) -> void:
	_wire_material.albedo_color = Color(1.0, lerpf(0.65, 0.12, progress), 0.1, 0.85)
	_label.text = "%s  %.1f" % ["CORRIDOR" if _corridor else "SALVO", maxf(_windup_sec - _elapsed_sec, 0.0)]
	_progress_mesh.clear_surfaces()
	if progress <= 0.0:
		return
	_progress_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _progress_material)
	_add_ring(_progress_mesh, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, _radius * 1.08, progress)
	_progress_mesh.surface_end()
