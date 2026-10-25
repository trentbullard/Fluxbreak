extends Node

## Isolated data, lifecycle, layout, and optional Vulkan checks for target plates.
const PLATE: PackedScene = preload("res://scenes/hud/nameplate.tscn")
const TARGET: PackedScene = preload("res://scenes/targets/target_object.tscn")
const GATEWAY: PackedScene = preload("res://scenes/objectives/boss_gateway.tscn")
const DEFINITIONS: Array[String] = [
	"machine_drone_mk1", "merc_corvette_mk1", "bug_sporeling_mk1",
	"grey_probe_mk1", "merc_vanguard_flagship_mk1",
]

var _checks: int = 0
var _failures: int = 0
var _output: String = ""
var _space: Node3D
var _camera: Camera3D
var _ship: Node3D
var _manager: NameplateManager
var _docking: DockingManager
var _fixtures: Array[Node3D] = []
var _background: ColorRect
var _planet: Polygon2D
var _gallery_title: Label

func _ready() -> void:
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Nameplate Validation":
		push_error("Nameplate checks require the isolated validation wrapper.")
		get_tree().quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	if not _output.is_empty():
		if DisplayServer.get_name() == "headless":
			push_error("Rendered nameplate checks require a renderer.")
			get_tree().quit(2)
			return
		DirAccess.make_dir_recursive_absolute(_output)
	get_tree().root.size = Vector2i(1280, 720)
	GameFlow.abandon_run()
	_build_fixture()
	await _frames(3)
	await _check_view_contract()
	await _check_real_definitions()
	await _check_distance_scaling()
	await _check_pool_and_markers()
	await _check_projection_and_lifecycle()
	await _check_bounded_pool()
	await _check_dense_layout()
	if not _output.is_empty():
		await _render_gallery()
	_clear_fixtures()
	_manager.free()
	_space.free()
	_docking.free()
	if is_instance_valid(_background):
		_background.free()
	if is_instance_valid(_planet):
		_planet.free()
	if is_instance_valid(_gallery_title):
		_gallery_title.free()
	await _frames(3)
	print("NAMEPLATE_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _build_fixture() -> void:
	_space = Node3D.new()
	_space.name = "NameplateSpace"
	add_child(_space)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.far = 40000.0
	_space.add_child(_camera)
	_ship = Node3D.new()
	_space.add_child(_ship)
	_docking = DockingManager.new()
	_docking.name = "Docking"
	add_child(_docking)
	_manager = NameplateManager.new()
	_manager.nameplate_scene = PLATE
	_manager.docking_manager_path = NodePath("../Docking")
	add_child(_manager)
	_manager.init(_camera, _ship)
	_manager.set_process(false)

func _check_view_contract() -> void:
	var ui: TargetNameplate = PLATE.instantiate() as TargetNameplate
	add_child(ui)
	ui.show_combat("Greys", "Probe", "1.2km", 75.25, 100.0, 0.0, 200.0)
	await _frames(2)
	_check(_text(ui, "Combat/Header/Faction") == "GREYS" and _text(ui, "Combat/Identity/Name") == "Probe", "Combat identity separates authored faction and unit name")
	_check(_text(ui, "Combat/Header/Distance") == "1.2km", "The view preserves the manager's formatted distance")
	_check(_row(ui, "Shield").visible and is_zero_approx(ui.get("_shield_ratio")), "A depleted shield with positive capacity stays visible and empty")
	_check(_text(ui, "Combat/Shield/Caption") == "SHLD  0 / 200", "Depleted shield caption shows zero and its real capacity")
	_check(is_equal_approx(float(ui.get("_hull_ratio")), 0.7525), "Hull fill uses the unrounded current/capacity ratio")
	_check(_text(ui, "Combat/Hull/Caption") == "HULL  76 / 100", "Small positive fractional health remains visible in numeric captions")
	ui.show_combat("Bugs", "Sporeling", "300m", -8.0, 100.0, 0.0, 0.0)
	_check(not _row(ui, "Shield").visible and is_zero_approx(ui.get("_shield_ratio")), "Shieldless units hide the shield row without invalid division")
	_check(is_zero_approx(ui.get("_hull_ratio")) and _text(ui, "Combat/Hull/Caption") == "HULL  0 / 100", "Negative hull safely clamps to an empty bar and zero caption")
	ui.show_combat("Mercs", "Corvette", "500m", 300.0, 100.0, 400.0, 200.0)
	_check(is_equal_approx(float(ui.get("_hull_ratio")), 1.0) and is_equal_approx(float(ui.get("_shield_ratio")), 1.0), "Over-capacity resource fills cannot escape their tracks")
	ui.show_combat("Neutral", "Expired", "0m", 0.0, 0.0, INF, NAN)
	_check(is_zero_approx(ui.get("_hull_ratio")) and is_zero_approx(ui.get("_shield_ratio")) and not _row(ui, "Shield").visible, "Zero and nonfinite capacities/values remain finite and safe")
	ui.show_auxiliary("Factory [ATK]\n1200m", Color.GOLD)
	_check(not (ui.get_node("Combat") as Control).visible and (ui.get_node("HBox") as Control).visible, "Auxiliary POI mode completely hides combat rows")
	_check(_text(ui, "Combat/Header/Faction").is_empty() and _text(ui, "Combat/Identity/Name").is_empty() and _text(ui, "Combat/Hull/Caption").is_empty(), "Changing combat to auxiliary clears all former combat text")
	ui.reset_display()
	_check(_text(ui, "HBox/Label").is_empty() and not (ui.get_node("HBox/StateIndicator") as Control).visible and not (ui.get_node("Combat") as Control).visible, "Reset clears auxiliary text, indicators, and combat presentation")
	ui.scale = Vector2(0.2, 0.2)
	ui.reset_display()
	_check(ui.scale.is_equal_approx(Vector2.ONE), "Reset restores full size before a pooled control becomes a navigation marker")
	_check_mouse_ignored(ui)
	var child_count: int = ui.get_child_count()
	for index: int in range(100):
		ui.show_combat("Machines", "Drone", "900m", float(index), 100.0, 10.0, 10.0)
	_check(ui.get_child_count() == child_count, "Repeated health refreshes do not construct extra UI nodes")
	_check(TargetNameplate.SHIELD_COLOR.b > TargetNameplate.SHIELD_COLOR.r and TargetNameplate.HULL_COLOR.r > TargetNameplate.HULL_COLOR.b, "Shield and hull retain distinct blue and red bar colors")
	ui.free()

func _check_real_definitions() -> void:
	for identity: String in DEFINITIONS:
		var enemy: Enemy = _enemy(identity)
		_manager._sync_targets()
		var ui: TargetNameplate = _plate_for(enemy)
		_check(ui != null and ui.visible, "%s receives a visible combat plate" % identity)
		if ui == null:
			_clear_fixtures()
			continue
		_check(_text(ui, "Combat/Header/Faction") == enemy.get_faction_display_name().to_upper() and _text(ui, "Combat/Identity/Name") == enemy.display_name, "%s displays its real faction and authored name" % identity)
		_check(enemy.eff_max_hull > enemy.def.max_hull, "%s fixture has effective scaled hull distinct from base hull" % identity)
		_check(is_equal_approx(float(ui.get("_hull_ratio")), 1.0) and _text(ui, "Combat/Hull/Caption").ends_with("/ %d" % int(ceil(enemy.eff_max_hull))), "%s uses effective scaled maximum hull" % identity)
		_check(_row(ui, "Shield").visible == (enemy.eff_max_shield > 0.0), "%s only displays an authored positive shield capacity" % identity)
		enemy.apply_damage(enemy.eff_max_shield + enemy.eff_max_hull * 0.25)
		_manager._sync_targets()
		_check(is_equal_approx(float(ui.get("_hull_ratio")), 0.75), "%s damage updates the real hull ratio" % identity)
		if enemy.eff_max_shield > 0.0:
			_check(_row(ui, "Shield").visible and is_zero_approx(ui.get("_shield_ratio")), "%s depleted shields remain displayed" % identity)
			enemy._on_regen_tick()
			_manager._sync_targets()
			_check(is_equal_approx(float(ui.get("_shield_ratio")), enemy.shield / enemy.eff_max_shield), "%s actual regeneration updates its shield bar" % identity)
		_clear_fixtures()
	for identity: String in ["asteroid_small", "wreck_medium"]:
		var target: TargetObject = _target(identity)
		target.hull = target.max_hull * 0.4
		_manager._sync_targets()
		var ui: TargetNameplate = _plate_for(target)
		_check(_text(ui, "Combat/Header/Faction") == "NEUTRAL" and _text(ui, "Combat/Identity/Name") == target.def.display_name, "%s is explicitly Neutral with its authored name" % identity)
		_check(is_equal_approx(float(ui.get("_hull_ratio")), 0.4) and not _row(ui, "Shield").visible, "%s displays target hull and hides absent shields" % identity)
		_clear_fixtures()

func _check_distance_scaling() -> void:
	var enemy: Enemy = _enemy("grey_probe_mk1")
	enemy.hull = enemy.eff_max_hull * 0.6
	enemy.shield = enemy.eff_max_shield * 0.35
	var previous_scale: float = 1.0
	var initial: TargetNameplate
	for distance: float in [100.0, 400.0, 1000.0, 2000.0, 12000.0]:
		enemy.position = Vector3(0.0, 0.0, -distance)
		_manager._sync_targets()
		await _frames(2)
		_manager._sync_targets()
		var ui: TargetNameplate = _plate_for(enemy)
		if initial == null:
			initial = ui
		var expected_scale: float = clampf(400.0 / maxf(distance, 400.0), 0.2, 1.0)
		_check(ui == initial and ui.visible, "The same visible enemy plate is retained at %dm without distance-based culling" % int(distance))
		_check(ui.scale.is_equal_approx(Vector2.ONE * expected_scale), "Combat distance %dm yields %.2f display scale" % [int(distance), expected_scale])
		_check(ui.scale.x <= previous_scale and ui.scale.x >= 0.2, "Distance scaling shrinks monotonically to its floor at %dm" % int(distance))
		_check(ui.pivot_offset.is_zero_approx(), "Distance-scaled combat plates use a stable top-left pivot")
		_check(is_equal_approx(float(ui.get("_hull_ratio")), 0.6) and is_equal_approx(float(ui.get("_shield_ratio")), 0.35), "Distance scaling preserves independent live hull and shield ratios")
		var screen_pos: Vector2 = _camera.unproject_position(enemy.global_position)
		var rect: Rect2 = ui.get_global_rect()
		_check(is_equal_approx(rect.get_center().x, screen_pos.x) and is_equal_approx(rect.end.y, screen_pos.y - float(_manager.pixel_offset_up) * expected_scale), "Scaled bounds and attachment gap stay anchored above the target at %dm" % int(distance))
		previous_scale = ui.scale.x
	for distance: float in [1600.0, 1200.0, 800.0, 500.0, 300.0, 500.0, 800.0]:
		enemy.position.z = -distance
		_manager._sync_targets()
		var ui: TargetNameplate = _plate_for(enemy)
		_check(ui == initial and is_equal_approx(ui.scale.x, clampf(400.0 / maxf(distance, 400.0), 0.2, 1.0)), "An approaching or receding enemy updates scale continuously without reallocating its plate")
	_camera.position.z = 600.0
	enemy.position.z = -400.0
	_manager._sync_targets()
	_check(is_equal_approx(initial.scale.x, 0.4) and _text(initial, "Combat/Header/Distance") == "400m", "Perspective sizing uses camera distance while the displayed distance remains ship-relative")
	_camera.position = Vector3.ZERO
	_clear_fixtures()
	var target: TargetObject = _target("wreck_medium")
	for distance: float in [300.0, 1000.0, 6000.0]:
		target.position.z = -distance
		_manager._sync_targets()
		var ui: TargetNameplate = _plate_for(target)
		_check(is_equal_approx(ui.scale.x, clampf(400.0 / maxf(distance, 400.0), 0.2, 1.0)), "Stationary salvage uses the same perspective scale as enemies at %dm" % int(distance))
	_clear_fixtures()
	await _frames(2)

func _check_pool_and_markers() -> void:
	var enemy: Enemy = _enemy("grey_probe_mk1")
	enemy.position.z = -10000.0
	_manager._sync_targets()
	var initial: TargetNameplate = _plate_for(enemy)
	_check(initial.scale.is_equal_approx(Vector2.ONE * 0.2), "A distant enemy shrinks before its view is recycled")
	_clear_fixtures()
	var poi: PoiInstance = _poi()
	_manager._sync_targets()
	var ui: TargetNameplate = _plate_for(poi)
	_check(ui == initial, "A freed enemy's pooled plate is reused for a POI")
	_check(ui.scale.is_equal_approx(Vector2.ONE), "A POI reusing a distant combat plate retains full navigation size")
	_check(not (ui.get_node("Combat") as Control).visible and _text(ui, "Combat/Header/Faction").is_empty(), "Enemy-to-POI reuse leaks no title or health rows")
	var indicator: ColorRect = ui.get_node("HBox/StateIndicator") as ColorRect
	_check(indicator.visible and indicator.color.is_equal_approx(NameplateManager.POI_UNVISITED_COLOR) and _text(ui, "HBox/Label").contains("[ATK]"), "Unvisited POI retains its cyan state indicator and type tag")
	_docking._visited_pois.append(poi.get_instance_id())
	_manager._sync_targets()
	_check(indicator.color.is_equal_approx(NameplateManager.POI_VISITED_COLOR), "Visited POI changes to its established amber indicator")
	_clear_fixtures()
	var gateway: BossGateway = _gateway()
	_manager._sync_targets()
	ui = _plate_for(gateway)
	indicator = ui.get_node("HBox/StateIndicator") as ColorRect
	_check(ui == initial and indicator.visible and indicator.color.is_equal_approx(gateway.get_marker_color()), "POI-to-gateway reuse applies the current route's marker color")
	_check(ui.scale.is_equal_approx(Vector2.ONE), "Gateway markers retain full navigation size")
	_check(_text(ui, "HBox/Label").contains(gateway.get_display_name()) and _text(ui, "HBox/Label").contains("Dock to inspect"), "Gateway keeps its authored route name and docking instruction")
	_clear_fixtures()
	var target: TargetObject = _target("wreck_medium")
	_manager._sync_targets()
	ui = _plate_for(target)
	_check(ui == initial and not (ui.get_node("HBox") as Control).visible and not (ui.get_node("HBox/StateIndicator") as Control).visible, "Gateway-to-target reuse clears all auxiliary indicators")
	_check(_text(ui, "Combat/Identity/Name") == "Medium Wreck" and not _row(ui, "Shield").visible, "Pooled combat view fully refreshes identity and shield availability")
	_check(is_equal_approx(ui.scale.x, 0.4), "A reused navigation plate receives its salvage target's smaller distance scale")
	_clear_fixtures()
	await _frames(2)

func _check_projection_and_lifecycle() -> void:
	var enemy: Enemy = _enemy("machine_drone_mk1")
	_manager._sync_targets()
	var base_connections: int = enemy.get_signal_connection_list("tree_exited").size()
	for index: int in range(40):
		enemy.position = Vector3(0.0, 0.0, 1000.0)
		_manager._sync_targets()
		_check(not _manager._map.has(enemy), "Behind-camera targets release their visible plate")
		enemy.position = Vector3(0.0, 0.0, -1000.0)
		_manager._sync_targets()
	_check(enemy.get_signal_connection_list("tree_exited").size() <= base_connections, "Repeated offscreen/on-screen cycles do not accumulate target exit callbacks")
	enemy.position = Vector3(0.0, 0.0, -31000.0)
	_manager._sync_targets()
	_check(not _manager._map.has(enemy), "Targets beyond the unchanged nameplate range are hidden")
	for distance: float in [3000.0, 3001.0, 12000.0]:
		enemy.position = Vector3(0.0, 0.0, -distance)
		_manager._sync_targets()
		_check(_text(_plate_for(enemy), "Combat/Header/Distance") == HudDistanceFormatter.format_distance(distance), "Distance formatting remains consistent at %dm" % int(distance))
	for distance: float in [300.0, 1000.0, 12000.0]:
		for screen_point: Vector2 in [Vector2(1.0, 1.0), Vector2(1279.0, 1.0), Vector2(1.0, 719.0), Vector2(1279.0, 719.0)]:
			enemy.position = _camera.project_position(screen_point, distance)
			_manager._sync_targets()
			await _frames(2)
			_manager._sync_targets()
			var ui: TargetNameplate = _plate_for(enemy)
			_check(ui != null and Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)).encloses(ui.get_global_rect()), "Projected near, intermediate and distant edge plates remain inside the viewport using their scaled bounds")
	_clear_fixtures()
	_check(_manager._map.is_empty(), "Target removal releases its active mapping immediately")
	var live: Enemy = _enemy("grey_probe_mk1")
	_manager._sync_targets()
	var pooled: Array[TargetNameplate] = _manager._pool.duplicate()
	_manager.free()
	await _frames(2)
	_check(live.get_signal_connection_list("tree_exited").is_empty(), "Manager destruction disconnects callbacks from still-living targets")
	for ui: Control in pooled:
		_check(not is_instance_valid(ui), "Manager destruction frees detached pooled controls")
	_manager = NameplateManager.new()
	_manager.nameplate_scene = PLATE
	_manager.docking_manager_path = NodePath("../Docking")
	add_child(_manager)
	_manager.init(_camera, _ship)
	_manager.set_process(false)
	_clear_fixtures()

func _check_bounded_pool() -> void:
	for index: int in range(100):
		var enemy: Enemy = Enemy.new()
		enemy.display_name = "Stress %d" % index
		enemy.position = Vector3(float(index % 10 - 5) * 10.0, float(index / 10 - 5) * 10.0, -1000.0)
		enemy.freeze = true
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		_space.add_child(enemy)
		_fixtures.append(enemy)
	_manager._sync_targets()
	_check(_manager._map.size() == 100 and _manager.get_child_count() == 100, "A hundred simultaneous visible combatants create one plate each")
	for index: int in range(12):
		for enemy: Node3D in _fixtures:
			enemy.position.z = 1000.0
		_manager._sync_targets()
		for enemy: Node3D in _fixtures:
			enemy.position.z = -1000.0
		_manager._sync_targets()
	_check(_manager._map.size() == 100 and _manager._pool.is_empty() and _manager.get_child_count() == 100, "Mass visibility cycles reuse a bounded pool without extra active plates")
	_clear_fixtures()
	_check(_manager._map.is_empty() and _manager._pool.size() == 100, "Mass removal returns all plates exactly once to the pool")
	var ids: Dictionary[int, bool] = {}
	for ui: Control in _manager._pool:
		ids[ui.get_instance_id()] = true
	_check(ids.size() == 100, "The detached pool contains no duplicate controls")
	await _frames(2)

func _check_dense_layout() -> void:
	_populate_dense_combatants(false)
	_manager._sync_targets()
	await _frames(3)
	_manager._sync_targets()
	var baseline_area: float = _total_plate_area()
	_check(_manager._map.size() == 120, "The dense encounter retains all 120 near combatant nameplates")
	_set_dense_distances(true)
	_manager._sync_targets()
	await _frames(3)
	_manager._sync_targets()
	var actual_area: float = _total_plate_area()
	var scale_counts: Dictionary[int, int] = {100: 0, 40: 0, 20: 0}
	for ui: TargetNameplate in _manager._map.values():
		var percent: int = roundi(ui.scale.x * 100.0)
		scale_counts[percent] = int(scale_counts.get(percent, 0)) + 1
	_check(_manager._map.size() == 120 and _manager.get_child_count() == 120, "Distance shrinking keeps all 120 labels without adding a visibility cap")
	_check(scale_counts[100] == 40 and scale_counts[40] == 40 and scale_counts[20] == 40, "A mixed-distance encounter has forty full, forty 40-percent and forty 20-percent plates")
	_check(baseline_area > 0.0 and actual_area / baseline_area < 0.41, "Mixed-distance nameplates use at most 41 percent of the former fixed-size rectangle area")
	print("NAMEPLATE_DENSITY: 120 labels at 300/1000/2000m, baseline rectangle area %.0fpx2, scaled %.0fpx2 (%.1f%%)" % [baseline_area, actual_area, 100.0 * actual_area / maxf(baseline_area, 1.0)])
	_clear_fixtures()
	await _frames(2)

func _populate_dense_combatants(mixed_distances: bool) -> void:
	var identities: Array[String] = ["machine_drone_mk1", "merc_corvette_mk1", "bug_sporeling_mk1", "grey_probe_mk1"]
	for index: int in range(120):
		var enemy: Enemy = _enemy(identities[index % identities.size()])
		enemy.hull = enemy.eff_max_hull * 0.68
		enemy.shield = enemy.eff_max_shield * 0.55
	_set_dense_distances(mixed_distances)

func _set_dense_distances(mixed_distances: bool) -> void:
	var distances: Array[float] = [300.0, 1000.0, 2000.0]
	for index: int in range(_fixtures.size()):
		var screen_point: Vector2 = Vector2(100.0 + float(index % 12) * 98.0, 160.0 + float(index / 12) * 57.0)
		var direction: Vector3 = (_camera.project_position(screen_point, 1.0) - _camera.global_position).normalized()
		var distance: float = distances[index % distances.size()] if mixed_distances else 300.0
		_fixtures[index].global_position = _camera.global_position + direction * distance

func _total_plate_area() -> float:
	var area: float = 0.0
	for ui: TargetNameplate in _manager._map.values():
		area += ui.get_global_rect().get_area()
	return area

func _render_gallery() -> void:
	_background = ColorRect.new()
	_background.color = Color(0.015, 0.025, 0.055)
	_background.size = Vector2(1280.0, 720.0)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	move_child(_background, 0)
	_planet = Polygon2D.new()
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(80):
		points.append(Vector2(1020.0, 440.0) + Vector2.from_angle(TAU * float(index) / 80.0) * 490.0)
	_planet.polygon = points
	_planet.color = Color(0.12, 0.2, 0.32)
	add_child(_planet)
	move_child(_planet, 1)
	_gallery_title = Label.new()
	_gallery_title.position = Vector2(30.0, 20.0)
	_gallery_title.add_theme_font_size_override("font_size", 24)
	_gallery_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_gallery_title.add_theme_constant_override("outline_size", 6)
	_gallery_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gallery_title)
	_gallery_title.text = "Combat nameplates shrink with distance; navigation markers retain their size"
	var all_nodes: Array[Node3D] = []
	for identity: String in DEFINITIONS:
		var enemy: Enemy = _enemy(identity)
		enemy.hull = enemy.eff_max_hull * 0.68
		enemy.shield = enemy.eff_max_shield * (0.0 if identity == "grey_probe_mk1" else 0.55)
		all_nodes.append(enemy)
	for identity: String in ["asteroid_small", "wreck_medium"]:
		var target: TargetObject = _target(identity)
		target.hull = target.max_hull * 0.4
		all_nodes.append(target)
	all_nodes.append(_poi())
	all_nodes.append(_gateway())
	for index: int in range(all_nodes.size()):
		all_nodes[index].position = _camera.project_position(Vector2(220.0 + float(index % 3) * 420.0, 235.0 + float(index / 3) * 215.0), 1500.0)
	_manager._sync_targets()
	await _frames(4)
	_manager._sync_targets()
	for ui: Control in _manager._map.values():
		_check(ui.get_global_rect().size.x <= 380.0 and Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)).encloses(ui.get_global_rect()), "Rendered gallery remains compact and within the 720p viewport")
	await _capture("nameplates_dark_720p.png")
	_background.color = Color(0.68, 0.78, 0.86)
	_planet.color = Color(0.97, 0.79, 0.43)
	await _capture("nameplates_bright_planet_720p.png")
	_clear_fixtures()
	_populate_dense_combatants(false)
	_background.color = Color(0.015, 0.025, 0.055)
	_planet.color = Color(0.12, 0.2, 0.32)
	_gallery_title.text = "120 combatants | Former fixed-size equivalent | All nameplates at 100%"
	_manager._sync_targets()
	await _capture("nameplates_dense_constant_baseline_dark_720p.png")
	_set_dense_distances(true)
	_manager._sync_targets()
	_gallery_title.text = "120 combatants | 300 / 1,000 / 2,000 metres | All nameplates retained"
	await _capture("nameplates_dense_distance_dark_720p.png")
	_background.color = Color(0.68, 0.78, 0.86)
	_planet.color = Color(0.97, 0.79, 0.43)
	await _capture("nameplates_dense_distance_bright_planet_720p.png")

func _enemy(identity: String) -> Enemy:
	var definition: EnemyDef = load("res://content/data/enemies/%s.tres" % identity) as EnemyDef
	var scaling: EnemyCombatScalingSnapshot = EnemyCombatScalingSnapshot.new()
	scaling.intensity = 3.0
	scaling.hull_multiplier = 2.5
	scaling.shield_multiplier = 3.0
	scaling.shield_regen_multiplier = 2.0
	var context: EnemySpawnContext = EnemySpawnContext.from_enemy_def(definition)
	context.enemy_combat_scaling = scaling
	var enemy: Enemy = Enemy.new()
	enemy.name = identity
	enemy.freeze = true
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.configure_enemy(definition, context)
	enemy.position = Vector3(0.0, 0.0, -1000.0)
	_space.add_child(enemy)
	enemy._regen_timer.stop()
	_fixtures.append(enemy)
	return enemy

func _target(identity: String) -> TargetObject:
	var target: TargetObject = TARGET.instantiate() as TargetObject
	target.freeze = true
	target.process_mode = Node.PROCESS_MODE_DISABLED
	target.configure_target(load("res://content/data/targets/%s.tres" % identity) as TargetDef)
	target.position = Vector3(0.0, 0.0, -1000.0)
	_space.add_child(target)
	_fixtures.append(target)
	return target

func _poi() -> PoiInstance:
	var poi: PoiInstance = PoiInstance.new()
	poi.configure(load("res://content/data/pois/offense_station.tres") as PoiDef, 1, 0)
	poi.position = Vector3(0.0, 0.0, -1000.0)
	_space.add_child(poi)
	_fixtures.append(poi)
	return poi

func _gateway() -> BossGateway:
	var route: SectorRouteDef = SectorRouteDef.new()
	route.route_id = &"nameplate_assault"
	route.display_name = "Assault Route"
	route.marker_kind = SectorRouteDef.MarkerKind.ASSAULT
	route.marker_color = Color(1.0, 0.31, 0.15)
	var gateway: BossGateway = GATEWAY.instantiate() as BossGateway
	gateway.configure_route(route)
	gateway.position = Vector3(0.0, 0.0, -1000.0)
	gateway.process_mode = Node.PROCESS_MODE_DISABLED
	_space.add_child(gateway)
	_fixtures.append(gateway)
	return gateway

func _plate_for(target: Node3D) -> TargetNameplate:
	return _manager._map.get(target) as TargetNameplate

func _clear_fixtures() -> void:
	for fixture: Node3D in _fixtures:
		if is_instance_valid(fixture):
			fixture.free()
	_fixtures.clear()
	_manager._sync_targets()

func _text(ui: Control, path: String) -> String:
	return (ui.get_node(path) as Label).text

func _row(ui: Control, resource_name: String) -> Control:
	return ui.get_node("Combat/" + resource_name) as Control

func _check_mouse_ignored(node: Node) -> void:
	if node is Control:
		_check((node as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "Nameplate overlay child %s ignores mouse input" % node.name)
	for child: Node in node.get_children():
		_check_mouse_ignored(child)

func _capture(filename: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var result: Error = image.save_png(_output.path_join(filename))
	_check(result == OK and image.get_width() == 1280 and image.get_height() == 720, "Rendered %s at 1280 x 720" % filename)

func _frames(count: int) -> void:
	for index: int in range(count):
		await get_tree().process_frame

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("Nameplate check failed: " + description)
