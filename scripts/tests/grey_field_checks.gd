extends Node3D

## Save-isolated behavior and resource checks for shared faction attack fields.
const SHIP_SCENE: PackedScene = preload("res://scenes/ship/ship.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const PROBE: GreyEnemyDef = preload("res://content/data/enemies/grey_probe_mk1.tres")
const CORVETTE: MercEnemyDef = preload("res://content/data/enemies/merc_corvette_mk1.tres")
const SPORELING: BugEnemyDef = preload("res://content/data/enemies/bug_sporeling_mk1.tres")
const FIELD_SOURCES: Array[EnemyDef] = [
	preload("res://content/data/enemies/merc_destroyer_mk1.tres"),
	preload("res://content/data/enemies/merc_cruiser_mk1.tres"),
	preload("res://content/data/enemies/merc_contract_enforcer_mk1.tres"),
	preload("res://content/data/enemies/merc_vanguard_flagship_mk1.tres"),
	SPORELING,
	preload("res://content/data/enemies/bug_carapace_mk1.tres"),
	preload("res://content/data/enemies/bug_broodmother_mk1.tres"),
	preload("res://content/data/enemies/bug_devourer_mk1.tres"),
	preload("res://content/data/enemies/bug_hive_queen_mk1.tres"),
	preload("res://content/data/enemies/bug_nestbreaker_matron_mk1.tres"),
	preload("res://content/data/enemies/bug_first_queen_mk1.tres"),
]

var _ship: Ship
var _spawner: Spawner
var _source: Enemy
var _enemies: Array[Enemy] = []
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Grey Validation":
		push_error("Grey field checks require the isolated Grey validation project.")
		get_tree().quit(2)
		return
	_ship = SHIP_SCENE.instantiate() as Ship
	_ship.name = "TestShip"
	_ship.freeze = true
	_ship.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_ship)
	_ship.hull = 100000.0
	_ship.shield = 0.0
	_ship.eff_evasion = 0.0
	_ship.eff_damage_taken_mult = 1.0
	_spawner = Spawner.new()
	_spawner.ship_path = NodePath("../TestShip")
	_spawner.enemy_scene = ENEMY_SCENE
	_spawner.directed_mode = true
	_spawner.min_distance_from_ship = 0.0
	add_child(_spawner)
	_source = _spawn(PROBE)
	_check_sphere_and_release()
	_check_corridor_geometry()
	await _check_pause()
	_check_tether()
	_check_displacement()
	_check_other_factions()
	_check_repeated_spore_pulses()
	await _check_cancellation()
	await _cleanup()
	print("GREY_FIELD_CHECKS: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _spawn(definition: EnemyDef) -> Enemy:
	var enemy: Enemy = _spawner.spawn_one_with_def_at_position(Spawner.SpawnKind.ENEMY, definition, Vector3(0.0, 0.0, 180.0)) as Enemy
	_expect(enemy != null, "%s spawns with its authored actor" % definition.id)
	if enemy == null:
		return null
	_enemies.append(enemy)
	enemy.freeze = true
	enemy.set_physics_process(false)
	enemy.explosion_scene = null
	enemy._stop_warp_in()
	if enemy._regen_timer != null:
		enemy._regen_timer.stop()
	for node: Node in enemy.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stream = null
	return enemy

func _host(source: Enemy) -> Object:
	var host: Object = null
	if source is EnemyBoss:
		var boss: EnemyBoss = source as EnemyBoss
		if not boss._weapon_sockets.is_empty():
			host = boss._weapon_sockets[0]
	else:
		host = source.call("_first_valid_turret") as EnemyTurret
	_expect(host != null, "Authored source exposes a real weapon host")
	if host != null:
		for field: StringName in [&"systems_bonus", &"eff_range_falloff", &"eff_crit_chance", &"eff_graze_on_hit"]:
			host.set(field, 0.0)
		host.set(&"eff_base_accuracy", 1.0)
		host.set(&"eff_damage_min", 10.0)
		host.set(&"eff_damage_max", 10.0)
	return host

func _warning(source: Enemy, windup: float, radius: float, corridor: bool = false, endpoint: Vector3 = Vector3.ZERO, origin: Vector3 = Vector3.ZERO) -> EnemyAttackTelegraph:
	var warning: EnemyAttackTelegraph = EnemyAttackTelegraph.new()
	add_child(warning)
	warning.set_warning_style("FIELD TEST", _tint(source.get_faction_id()))
	warning.start_attack(source, _ship, _host(source), windup, radius, corridor, endpoint, origin)
	warning.set_physics_process(false)
	return warning

func _state(warning: EnemyAttackTelegraph) -> Vector4:
	if warning._attack_field == null:
		return Vector4.ZERO
	return warning._attack_field.get_instance_shader_parameter("field_state") as Vector4

func _has_no_extra_visuals(node: Node) -> bool:
	return node.find_children("*", "Label3D", true, false).is_empty() and node.get_node_or_null("CountdownRing") == null

func _check_sphere_and_release() -> void:
	_ship.global_position = Vector3.ZERO
	var first: EnemyAttackTelegraph = _warning(_source, 1.0, 40.0)
	var second: EnemyAttackTelegraph = _warning(_source, 1.0, 80.0, false, Vector3.RIGHT * 600.0)
	_expect(first._attack_field != null and second._attack_field != null, "Grey attacks use their field presentation")
	if first._attack_field == null or second._attack_field == null:
		first.cancel()
		second.cancel()
		return
	_expect(_has_no_extra_visuals(first) and first.find_children("*", "MeshInstance3D", true, false).size() == 1, "A Grey attack uses one field without countdown meshes or floating text")
	_expect(first._attack_field.mesh == second._attack_field.mesh and first._attack_field.get_active_material(0) == second._attack_field.get_active_material(0), "Different sphere sizes reuse the same geometry and material")
	_expect(first.is_warning_for(_ship) and first.get_attack_label() == "FIELD TEST" and first.get_response_hint() == "MOVE CLEAR", "HUD warning metadata remains available")
	var hull_before: float = _ship.hull
	first._physics_process(0.5)
	_expect(is_equal_approx(_ship.hull, hull_before) and is_equal_approx(_state(first).x, 0.5) and is_zero_approx(_state(first).z), "Charge progresses halfway without early damage or burst")
	first._physics_process(0.5)
	_expect(is_equal_approx(hull_before - _ship.hull, 10.0) and _state(first).z > 0.0, "Damage and field burst begin on the same release tick")
	var burst: float = _state(first).z
	first._physics_process(EnemyAttackTelegraph.RELEASE_FLASH_SEC * 0.5)
	_expect(_state(first).z > 0.0 and _state(first).z < burst and is_equal_approx(hull_before - _ship.hull, 10.0), "Release fades without applying damage twice")
	first._physics_process(EnemyAttackTelegraph.RELEASE_FLASH_SEC)
	_expect(first.is_queued_for_deletion(), "A finished field retires after its brief release")
	second.cancel()

func _check_corridor_geometry() -> void:
	var start: Vector3 = Vector3.LEFT * 60.0
	var end: Vector3 = Vector3.RIGHT * 60.0
	var warning: EnemyAttackTelegraph = _warning(_source, 2.0, 20.0, true, end, start)
	_expect(warning.contains_position(Vector3.ZERO) and warning.contains_position(start) and warning.contains_position(end), "Corridor includes its interior and two flat ends")
	_expect(not warning.contains_position(Vector3.RIGHT * 61.0) and not warning.contains_position(Vector3.UP * 21.0), "Corridor excludes positions beyond its flat ends or radial boundary")
	_source.global_position = Vector3.BACK * 220.0
	_ship.global_position = Vector3.UP * 200.0
	_expect(warning._locked_origin.is_equal_approx(start) and warning._locked_position.is_equal_approx(end), "Movement never drags an already committed field")
	var hull_before: float = _ship.hull
	warning._physics_process(2.0)
	_expect(is_equal_approx(_ship.hull, hull_before), "Leaving the real cylinder avoids damage with the new presentation")
	warning.cancel()
	var collapsed: EnemyAttackTelegraph = _warning(_source, 2.0, 20.0, true, Vector3.ZERO, Vector3.ZERO)
	_expect(collapsed.contains_position(Vector3.UP * 19.0) and not collapsed.contains_position(Vector3.UP * 21.0), "A zero-length corridor retains the existing spherical hit fallback")
	_expect(collapsed._attack_field != null and collapsed._attack_field.global_transform.is_finite() and absf(collapsed._attack_field.global_basis.determinant()) > 0.0, "Zero-length field geometry has a finite nondegenerate transform")
	collapsed.cancel()
	_ship.global_position = Vector3.ZERO
	_source.global_position = Vector3.BACK * 180.0

func _check_pause() -> void:
	var warning: EnemyAttackTelegraph = _warning(_source, 10.0, 40.0)
	warning._physics_process(0.25)
	warning.set_physics_process(true)
	get_tree().paused = true
	var remaining: float = warning.get_time_remaining()
	var state_before: Vector4 = _state(warning)
	for frame: int in range(4):
		await get_tree().process_frame
	_expect(is_equal_approx(warning.get_time_remaining(), remaining) and _state(warning).is_equal_approx(state_before), "Pause freezes both gameplay windup and shader animation state")
	get_tree().paused = false
	for frame: int in range(2):
		await get_tree().physics_frame
	_expect(warning.get_time_remaining() < remaining and _state(warning).y > state_before.y, "Unpausing resumes the same windup and field animation")
	warning.set_physics_process(false)
	warning.cancel()

func _check_tether() -> void:
	_ship._tether_immunity_sec = 0.0
	_ship.global_position = Vector3.ZERO
	var tether: GreyTether = GreyTether.new()
	add_child(tether)
	_expect(tether.start_tether(_source, _ship, 1.0, 2.5, 0.75, 360.0, 60.0), "Capture starts using the field presentation")
	_expect(is_equal_approx(_state(tether).w, 2.0), "Charging capture has a distinct flowing-band style before attachment")
	tether.set_physics_process(false)
	var hull_before: float = _ship.hull
	tether._physics_process(0.5)
	_expect(not tether.is_attached() and is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Charging capture causes no early slow")
	tether._physics_process(0.5)
	_expect(tether.is_attached() and _has_no_extra_visuals(tether) and is_equal_approx(_ship.hull, hull_before), "Capture becomes a text-free link without damage")
	_ship.global_position = _source.global_position + Vector3.RIGHT * 400.0
	tether._physics_process(0.02)
	_expect(not tether.is_attached() and is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Breaking the link still clears its movement status immediately")
	_ship.global_position = Vector3.ZERO
	_ship._tether_immunity_sec = 0.0

func _check_displacement() -> void:
	var displacement: GreyDisplacement = GreyDisplacement.new()
	add_child(displacement)
	var origin: Vector3 = _source.global_position
	var destination: Vector3 = origin + Vector3.RIGHT * 100.0
	_expect(displacement.start_displacement(_source, destination, 1.0), "Harmless displacement starts normally")
	displacement.set_physics_process(false)
	_expect(displacement.find_children("*", "Label3D", true, false).is_empty() and displacement.find_children("*", "MeshInstance3D", true, false).size() >= 2, "Harmless relocation has distinct endpoint markers without floating text")
	var hull_before: float = _ship.hull
	displacement._physics_process(0.5)
	_expect(_source.global_position.is_equal_approx(origin), "Relocation preserves its full warning delay")
	displacement._physics_process(0.5)
	_expect(_source.global_position.is_equal_approx(destination) and is_equal_approx(_ship.hull, hull_before), "Relocation remains harmless and moves to its locked destination")

func _check_other_factions() -> void:
	var merc: Enemy = _spawn(CORVETTE)
	var warning: EnemyAttackTelegraph = _warning(merc, 2.0, 40.0)
	_expect(_has_no_extra_visuals(warning), "Merc attacks no longer create legacy countdown rings or floating attack text")
	warning.cancel()
	var reference: EnemyAttackTelegraph = _warning(_source, 1.0, 40.0)
	var reference_sphere: Mesh = reference._attack_field.mesh
	var reference_material: Material = reference._attack_field.get_active_material(0)
	var reference_corridor: EnemyAttackTelegraph = _warning(_source, 1.0, 20.0, true, Vector3.RIGHT * 100.0, Vector3.LEFT * 100.0)
	for definition: EnemyDef in FIELD_SOURCES:
		var source: Enemy = _spawn(definition)
		if source == null:
			continue
		for corridor: bool in [false, true]:
			_ship.global_position = Vector3.ZERO
			var field: EnemyAttackTelegraph = _warning(source, 1.0, 40.0, corridor, Vector3.RIGHT * 100.0 if corridor else Vector3.ZERO, Vector3.LEFT * 100.0)
			_expect(field._attack_field != null, "Every supported regular and boss source uses a shared field: " + definition.id)
			if field._attack_field == null:
				field.cancel()
				continue
			_expect(_has_no_extra_visuals(field) and field.find_children("*", "MeshInstance3D", true, false).size() == 1 and not field._attack_field.mesh is ImmediateMesh, "Each attack has one cached mesh and no per-frame warning geometry: " + definition.id)
			_expect(field._attack_field.mesh == (reference_corridor._attack_field.mesh if corridor else reference_sphere) and field._attack_field.get_active_material(0) == reference_material, "Sphere/corridor geometry and material are shared across faction and boss boundaries: " + definition.id)
			var tint: Vector4 = field._attack_field.get_instance_shader_parameter(&"field_tint") as Vector4
			var expected: Color = _tint(definition.get_faction_id())
			_expect(tint.is_equal_approx(Vector4(expected.r, expected.g, expected.b, 1.0)), "Faction color is an instance value rather than a separate material: " + definition.id)
			_expect(field.is_warning_for(_ship) and field.get_attack_label() == "FIELD TEST", "Removing volume overlays preserves existing HUD metadata: " + definition.id)
			var mesh_id: int = field._attack_field.mesh.get_instance_id()
			var hull_before: float = _ship.hull
			field._physics_process(0.5)
			_expect(is_equal_approx(_ship.hull, hull_before) and is_equal_approx(_state(field).x, 0.5), "The new field keeps the complete damage-free windup: " + definition.id)
			field._physics_process(0.5)
			_expect(is_equal_approx(hull_before - _ship.hull, 10.0) and _state(field).z > 0.0, "The field flashes on the unchanged damage frame: " + definition.id)
			field._physics_process(EnemyAttackTelegraph.RELEASE_FLASH_SEC * 0.5)
			_expect(field._attack_field.mesh.get_instance_id() == mesh_id and is_equal_approx(hull_before - _ship.hull, 10.0), "Charge and release reuse the same geometry without another hit: " + definition.id)
			field.cancel()
	_expect(reference._attack_field.get_instance_shader_parameter(&"field_tint") == null or (reference._attack_field.get_instance_shader_parameter(&"field_tint") as Vector4).is_zero_approx(), "Merc and Bug palette changes do not recolor existing Grey fields")
	reference.cancel()
	reference_corridor.cancel()

func _tint(faction_id: StringName) -> Color:
	if faction_id == &"mercs":
		return MercEnemy.CAPITAL_ATTACK_COLOR
	if faction_id == &"bugs":
		return BugEnemy.ATTACK_COLOR
	return Color(0.5, 0.8, 1.0)

func _check_repeated_spore_pulses() -> void:
	var source: Enemy = _spawn(SPORELING)
	var host: Object = _host(source)
	_ship.global_position = Vector3.ZERO
	var zone: BugSporeZone = BugSporeZone.new()
	add_child(zone)
	var events: Dictionary = {"resolved": 0, "finished": 0}
	zone.resolved.connect(func(_hit: bool) -> void: events["resolved"] = int(events["resolved"]) + 1)
	zone.finished.connect(func() -> void: events["finished"] = int(events["finished"]) + 1)
	_expect(zone.start_zone(source, _ship, host, 0.5, 60.0, 2), "A real Bug spore zone starts its two-pulse lifecycle")
	zone.set_physics_process(false)
	var field: EnemyAttackField = zone._attack_field
	var mesh_id: int = field.mesh.get_instance_id()
	var locked_position: Vector3 = zone._locked_position
	var hull_before: float = _ship.hull
	zone._physics_process(0.5)
	_expect(zone.get_pulses_resolved() == 1 and is_equal_approx(hull_before - _ship.hull, 10.0) and _state(zone).z > 0.0, "The first spore pulse releases exactly once with its field flash")
	zone._physics_process(EnemyAttackTelegraph.RELEASE_FLASH_SEC * 0.5)
	_expect(_state(zone).z > 0.0 and _state(zone).z < 1.0 and int(events["finished"]) == 0, "The first spore flash fades during the gap without finishing the zone")
	host.set(&"eff_damage_min", 999.0)
	host.set(&"eff_damage_max", 999.0)
	source.global_position += Vector3.RIGHT * 300.0
	_ship.global_position = Vector3.UP * 4.0
	zone._physics_process(EnemyAttackTelegraph.RELEASE_FLASH_SEC * 0.5 + 0.001)
	_expect(zone._attack_field == field and field.mesh.get_instance_id() == mesh_id and field.visible and is_zero_approx(_state(zone).x) and is_zero_approx(_state(zone).z), "The next pulse reuses and reveals the same field with a fresh charge")
	_expect(zone._locked_position.is_equal_approx(locked_position) and field.global_position.is_equal_approx(locked_position), "Moving ships never drag a committed spore zone between pulses")
	zone._physics_process(0.25)
	_expect(zone.get_pulses_resolved() == 1 and is_equal_approx(hull_before - _ship.hull, 10.0), "The second pulse retains its complete fresh windup")
	zone._physics_process(0.25)
	_expect(zone.get_pulses_resolved() == 2 and is_equal_approx(hull_before - _ship.hull, 20.0) and int(events["resolved"]) == 1 and int(events["finished"]) == 0, "The second pulse keeps the original weapon snapshot and inherited completion semantics")
	zone._physics_process(EnemyAttackTelegraph.RELEASE_FLASH_SEC + 0.001)
	_expect(zone.is_queued_for_deletion() and int(events["finished"]) == 1, "Spore completion occurs only after the final release flash")
	zone.cancel()
	_expect(int(events["finished"]) == 1 and is_equal_approx(hull_before - _ship.hull, 20.0), "Cancelling an already finished spore zone cannot add rewards or duplicate completion")
	_ship.global_position = Vector3.ZERO

func _check_cancellation() -> void:
	var primary: EnemyAttackTelegraph = _warning(_source, 1.0, 40.0)
	var companion: EnemyAttackTelegraph = _warning(_source, 2.0, 40.0, false, Vector3.RIGHT * 100.0)
	primary.add_companion(companion)
	primary._physics_process(1.0)
	primary._physics_process(EnemyAttackTelegraph.RELEASE_FLASH_SEC + 0.01)
	_expect(not primary.is_queued_for_deletion() and is_zero_approx(_state(primary).z) and companion.is_warning_for(_ship), "A primary burst fades while its independently timed companion remains active")
	primary.cancel()
	_expect(primary.is_queued_for_deletion() and companion.is_queued_for_deletion(), "Cancelling a multipart attack retires all its fields")
	var other: Enemy = _spawn(PROBE)
	var pending: EnemyAttackTelegraph = _warning(other, 10.0, 40.0)
	other.queue_free()
	await get_tree().process_frame
	_expect(not is_instance_valid(pending) or pending.is_queued_for_deletion(), "Source removal cannot leave an orphaned field or future attack")

func _cleanup() -> void:
	for enemy: Enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	for warning: Node in get_tree().get_nodes_in_group("enemy_attack_telegraphs"):
		if is_instance_valid(warning):
			warning.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_expect(int(_spawner.get_alive_counts().get("enemies", 0)) == 0, "Field checks leave Spawner accounting empty")
	_expect(is_equal_approx(_ship.get_movement_slow_multiplier(), 1.0), "Field checks leave no movement status behind")

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("GREY_FIELD_CHECKS: " + description)
