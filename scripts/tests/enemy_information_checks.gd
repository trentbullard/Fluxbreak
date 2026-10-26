extends Node

## A unique save namespace tests historical kills without touching player data.
const MENU_SCENE: PackedScene = preload("res://scenes/main_menu/main_menu.tscn")
const BUTTONS: String = "CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/"
const ENEMY_PANEL: String = "EnemyInformationPanel"
const ENEMY_GRID: String = "EnemyInformationPanel/Margin/Content/EnemyGrid"
const PANEL_CLOSE: String = "EnemyInformationPanel/Margin/Content/Header/Close"
const KNOWN_IDS: Array[String] = ["machine_drone_mk1", "bug_sporeling_mk1", "grey_witness_mk1"]
const DRONE: EnemyDef = preload("res://content/data/enemies/machine_drone_mk1.tres")
const PRACTICE_BOSS: EnemyBossDef = preload("res://content/data/enemies/grey_witness_practice.tres")

var _menu: Control = null
var _grid: EnemyInformationGrid = null
var _checks: int = 0
var _failures: int = 0
var _output: String = ""
var _source_materials: Array[BaseMaterial3D] = []
var _source_sss_flags: Array[bool] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run_checks.call_deferred()

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Enemy Information Validation":
		push_error("Enemy information checks require their isolated validation wrapper.")
		get_tree().quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
	get_tree().root.size = Vector2i(1280, 720)
	AudioServer.set_bus_mute(0, true)
	get_tree().node_added.connect(_silence)
	GameFlow.abandon_run()
	_seed_saved_history()
	_snapshot_source_materials()
	_menu = MENU_SCENE.instantiate() as Control
	_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_menu)
	await _frames(6)
	_grid = _menu.get_node(ENEMY_GRID) as EnemyInformationGrid
	_button("InformationContainer/Information").pressed.emit()
	await _frames(2)
	_button("EnemiesContainer/Enemies").pressed.emit()
	await _frames(4)
	_expect(_menu.call("get_current_page") == &"enemies" and _grid.is_visible_in_tree(), "Information > Enemies opens its grid")
	_expect(_button("EnemiesContainer/Enemies").is_visible_in_tree() and _button("WeaponsContainer/Weapons").is_visible_in_tree() and _button("ShipsContainer/Ships").is_visible_in_tree() and _button("PilotsContainer/Pilots").is_visible_in_tree(), "Opening the enemy panel preserves all Information menu actions")
	await _check_panel_layout()
	_check_first_header_visible("Opening Enemies keeps its first faction heading visible")
	_check_roster()
	_check_saved_markers()
	await _check_drone_model_preview()
	await _check_navigation_and_inert_icons()
	await _capture("enemies_saved_history_720p.png")
	await _check_new_kill_persistence()
	await _check_all_enemy_model_previews()
	await _check_empty_history()
	_menu.queue_free()
	await _frames(5)
	GameFlow.abandon_run()
	print("ENEMY_INFORMATION_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _seed_saved_history() -> void:
	var saved: ConfigFile = ConfigFile.new()
	saved.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_SAVE_SCHEMA_VERSION, GameFlow.CURRENT_SAVE_SCHEMA_VERSION)
	saved.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_GAME_VERSION, ProjectSettings.get_setting("application/config/version", "dev"))
	saved.set_value(GameFlow.SCORE_SECTION, GameFlow.SCORE_KEY_HIGH_SCORE, 1234)
	for enemy_id: String in KNOWN_IDS:
		saved.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "kills|enemy|" + enemy_id, 2)
	# Aggregate, faction, damage and encounter records cannot stand in for kills.
	saved.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "kills", 9000)
	saved.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "kills|faction|greys", 100)
	saved.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "damage_dealt|enemy|grey_probe_mk1", 5000)
	saved.set_value(GameFlow.BOSS_STATS_GLOBAL_SECTION_PREFIX + "grey_veiled_mind_mk1", "encounters", 12)
	saved.set_value(GameFlow.BOSS_STATS_GLOBAL_SECTION_PREFIX + "grey_veiled_mind_mk1", "kills", 0)
	_expect(saved.save(GameFlow.SAVE_PATH) == OK, "Historical fixture writes only the isolated stats file")
	GameFlow._load_user_data()

func _check_roster() -> void:
	var definitions: Array[EnemyDef] = EnemyInformationGrid.get_enemy_definitions()
	var buttons: Array[Button] = _grid.get_entry_buttons()
	_expect(definitions.size() == 27 and buttons.size() == 27, "All 27 ordinary and boss enemy identities have one icon")
	var ids: Dictionary = {}
	var factions: Dictionary = {}
	for definition: EnemyDef in definitions:
		_expect(not definition.id.is_empty() and not ids.has(definition.id), "Roster IDs are nonempty and unique: " + definition.id)
		ids[definition.id] = true
		factions[definition.get_faction_id()] = true
		_expect(not definition.resource_path.ends_with("_practice.tres"), "Practice tuning does not create a duplicate identity")
	_expect(factions.size() == 4, "Roster includes all four playable enemy factions")
	_expect(ids.has(PRACTICE_BOSS.id), "Practice boss canonical ID resolves to the normal boss entry")
	var button_ids: Dictionary = {}
	for button: Button in buttons:
		var enemy_id: String = String(button.get_meta("enemy_id", ""))
		_expect(ids.has(enemy_id) and not button_ids.has(enemy_id), "Each grid button identifies exactly one authored enemy")
		button_ids[enemy_id] = true

func _snapshot_source_materials() -> void:
	for definition: EnemyDef in EnemyInformationGrid.get_enemy_definitions():
		_remember_source_material(definition.material)
		if definition.model_scene == null:
			continue
		var source: Node = definition.model_scene.instantiate()
		_collect_source_materials(source)
		source.free()

func _collect_source_materials(node: Node) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		_remember_source_material(mesh.material_override as BaseMaterial3D)
		_remember_source_material(mesh.material_overlay as BaseMaterial3D)
		for surface: int in mesh.mesh.get_surface_count():
			_remember_source_material(mesh.get_active_material(surface) as BaseMaterial3D)
	for child: Node in node.get_children():
		_collect_source_materials(child)

func _remember_source_material(material: BaseMaterial3D) -> void:
	if material != null and not _source_materials.has(material):
		_source_materials.append(material)
		_source_sss_flags.append(material.subsurf_scatter_enabled)

func _check_saved_markers() -> void:
	for button: Button in _grid.get_entry_buttons():
		var enemy_id: String = String(button.get_meta("enemy_id", ""))
		var killed: bool = KNOWN_IDS.has(enemy_id)
		var expected_text: String = "" if killed else "?"
		_expect(button.text == expected_text and bool(button.get_meta("killed", false)) == killed, "Saved lifetime kill state controls icon " + enemy_id)
	_expect(_entry("grey_probe_mk1").text == "?", "Damage dealt and faction totals do not reveal a never-killed Probe")
	_expect(_entry("grey_veiled_mind_mk1").text == "?", "A boss encounter without a kill remains unknown")
	_expect(_entry(PRACTICE_BOSS.id).text.is_empty() and _entry(PRACTICE_BOSS.id).get_node_or_null("ModelPreview") != null, "Saved canonical boss kills reveal its shared Practice/Campaign 3D portrait")

func _check_drone_model_preview() -> void:
	var button: Button = _entry(DRONE.id)
	var preview: EnemyIconPreview = button.get_node_or_null("ModelPreview") as EnemyIconPreview
	_expect(preview != null and button.text.is_empty(), "A saved Drone kill replaces its marker with a 3D preview")
	if preview == null:
		return
	var viewport: SubViewport = preview.get_viewport_3d()
	var model: Node3D = preview.get_model_root()
	_expect(viewport != null and model != null, "Drone preview owns a real 3D viewport and model")
	if viewport == null or model == null:
		return
	_expect(viewport.own_world_3d and viewport.find_world_3d() != get_viewport().find_world_3d(), "Portrait rendering uses an isolated 3D world")
	_expect(viewport.size.x > 0 and viewport.size.y > 0 and viewport.size.x <= 256 and viewport.size.y <= 256, "Portrait rendering keeps a bounded thumbnail resolution")
	_expect(preview.texture != null and preview.mouse_filter == Control.MOUSE_FILTER_IGNORE and preview.focus_mode == Control.FOCUS_NONE, "The rendered portrait leaves mouse and keyboard activation with its existing icon button")
	var source_meshes: Array[Mesh] = []
	var source_state: SceneState = DRONE.model_scene.get_state()
	for node_index: int in source_state.get_node_count():
		for property_index: int in source_state.get_node_property_count(node_index):
			if source_state.get_node_property_name(node_index, property_index) == &"mesh":
				var mesh: Mesh = source_state.get_node_property_value(node_index, property_index) as Mesh
				if mesh != null:
					source_meshes.append(mesh)
	var visual_nodes: Array[Node] = [model]
	visual_nodes.append_array(model.find_children("*", "", true, false))
	var copied_meshes: int = 0
	var safe_visuals: bool = true
	var actual_meshes: bool = true
	var compatible_materials: bool = true
	var material_count: int = 0
	for node: Node in visual_nodes:
		if node.get_script() != null or node is CollisionObject3D or node is EnemyTurret or node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is Timer or node is AnimationPlayer or node is GPUParticles3D or node is CPUParticles3D:
			safe_visuals = false
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node != null:
			copied_meshes += 1
			actual_meshes = actual_meshes and source_meshes.has(mesh_node.mesh)
			for surface: int in mesh_node.mesh.get_surface_count():
				var material: BaseMaterial3D = mesh_node.get_active_material(surface) as BaseMaterial3D
				if material != null:
					material_count += 1
					compatible_materials = compatible_materials and not material.subsurf_scatter_enabled
			var overlay: BaseMaterial3D = mesh_node.material_overlay as BaseMaterial3D
			if overlay != null:
				compatible_materials = compatible_materials and not overlay.subsurf_scatter_enabled
	_expect(copied_meshes == source_meshes.size() and copied_meshes > 0 and actual_meshes, "Portrait shows the actual authored Machine Drone meshes")
	_expect(safe_visuals, "Portrait model contains no gameplay scripts, actors, physics, audio, timers or effects")
	_expect(material_count > 0 and compatible_materials, "Portrait materials disable SSS unsupported by transparent thumbnail viewports")
	var originals_unchanged: bool = not _source_materials.is_empty()
	for index: int in _source_materials.size():
		originals_unchanged = originals_unchanged and _source_materials[index].subsurf_scatter_enabled == _source_sss_flags[index]
	_expect(originals_unchanged, "Preview material adaptation leaves all authored source SSS flags unchanged")
	await _frames(12)
	_expect(preview.is_active(), "The visible unlocked portrait is active")
	var initial_basis: Basis = model.global_basis
	await _frames(20)
	_expect(not initial_basis.is_equal_approx(model.global_basis), "The visible 3D portrait rotates over time")
	await _capture("machine_drone_rotating_720p.png")
	get_tree().paused = true
	initial_basis = model.global_basis
	await _frames(20)
	_expect(preview.is_active() and not initial_basis.is_equal_approx(model.global_basis), "Menu portrait animation continues while the game tree is paused")
	get_tree().paused = false
	var preview_id: int = preview.get_instance_id()
	var model_id: int = model.get_instance_id()
	for repeat: int in range(3):
		_grid.refresh()
	await _frames(4)
	_expect(button.get_node("ModelPreview").get_instance_id() == preview_id and preview.get_model_root().get_instance_id() == model_id, "Refreshing known kill state reuses its existing preview and model")
	_expect(button.find_children("ModelPreview", "", true, false).size() == 1 and preview.find_children("*", "SubViewport", true, false).size() == 1, "Repeated refresh cannot duplicate portrait controls or viewports")
	_grid.get_entry_buttons().back().grab_focus()
	await _frames(12)
	_expect(not preview.is_active() and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Scrolling the portrait out of view stops its viewport rendering")
	initial_basis = model.global_basis
	await _frames(12)
	_expect(initial_basis.is_equal_approx(model.global_basis), "Offscreen portraits perform no rotation work")
	_grid.scroll_vertical = 0
	button.grab_focus()
	await _frames(12)
	_expect(preview.is_active(), "Scrolling the portrait back into view resumes it")
	_menu.call("show_page", &"weapons")
	await _frames(8)
	_expect(not preview.is_active() and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Switching reference categories stops the enemy portrait")
	_menu.call("show_page", &"enemies")
	await _frames(8)
	_expect(preview.is_active(), "Returning to Enemies resumes the same portrait")
	_menu.hide()
	await _frames(8)
	_expect(not preview.is_active() and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hiding the main menu stops portrait rendering")
	initial_basis = model.global_basis
	await _frames(12)
	_expect(initial_basis.is_equal_approx(model.global_basis), "Hidden menus perform no portrait rotation work")
	_menu.show()
	await _frames(8)
	_expect(preview.is_active(), "Showing the menu resumes the visible portrait")
	_menu.call("show_page", &"information")
	await _frames(8)
	_expect(not preview.is_active() and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Closing the information panel disables its portrait viewport")
	_menu.call("show_page", &"enemies")
	await _frames(8)

func _check_navigation_and_inert_icons() -> void:
	var buttons: Array[Button] = _grid.get_entry_buttons()
	_expect(get_viewport().gui_get_focus_owner() == buttons[0], "Enemies focuses the first grid icon")
	await _action(&"ui_left")
	_expect(get_viewport().gui_get_focus_owner() == _button("EnemiesContainer/Enemies"), "Left from the first grid column returns to the Information menu")
	await _action(&"ui_right")
	_expect(get_viewport().gui_get_focus_owner() == buttons[0], "Right from Enemies enters its open grid")
	await _action(&"ui_right")
	_expect(get_viewport().gui_get_focus_owner() == buttons[1], "Right navigation moves across a grid row")
	await _action(&"ui_down")
	_expect(get_viewport().gui_get_focus_owner() == buttons[5], "Down navigation follows four-column grid geometry")
	await _action(&"ui_up")
	_expect(get_viewport().gui_get_focus_owner() == buttons[1], "Up navigation returns to the corresponding column")
	var stats_before: Dictionary = GameFlow._meta_stats_global.duplicate(true)
	var saved_before: String = FileAccess.get_file_as_string(GameFlow.SAVE_PATH)
	for button: Button in buttons:
		button.pressed.emit()
		_expect(_menu.call("get_current_page") == &"enemies", "Icon activation opens no detail page")
	_expect(GameFlow._meta_stats_global == stats_before and FileAccess.get_file_as_string(GameFlow.SAVE_PATH) == saved_before, "Browsing and activating icons never writes progression")
	buttons[-1].grab_focus()
	await _frames(4)
	_expect(_grid.get_global_rect().encloses(buttons[-1].get_global_rect()), "Focusing a late entry scrolls its icon into view")
	_expect(_grid.scroll_vertical > 0 and _grid.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Enemy roster scrolls vertically without horizontal scrolling")
	_button("BackContainer/Back").pressed.emit()
	await _frames(3)
	_expect(_menu.call("get_current_page") == &"information" and not (_menu.get_node(ENEMY_PANEL) as Control).visible, "Enemies Back closes the panel while remaining in Information")
	_expect(get_viewport().gui_get_focus_owner() == _button("EnemiesContainer/Enemies"), "Closing with Back restores focus to Enemies")
	_button("EnemiesContainer/Enemies").pressed.emit()
	await _frames(3)
	var close: Button = _menu.get_node(PANEL_CLOSE) as Button
	close.grab_focus()
	await _frames(2)
	_expect(get_viewport().gui_get_focus_owner() == close, "The panel Close button is keyboard and controller focusable")
	await _action(&"ui_accept")
	_expect(_menu.call("get_current_page") == &"information" and not (_menu.get_node(ENEMY_PANEL) as Control).visible, "Activating panel Close leaves Information visible")
	_expect(get_viewport().gui_get_focus_owner() == _button("EnemiesContainer/Enemies"), "Panel Close restores focus to Enemies")
	_button("EnemiesContainer/Enemies").pressed.emit()
	await _frames(3)
	await _action(&"ui_cancel")
	_expect(_menu.call("get_current_page") == &"information" and not (_menu.get_node(ENEMY_PANEL) as Control).visible, "Controller cancel/Escape closes the enemy panel before leaving Information")
	_expect(get_viewport().gui_get_focus_owner() == _button("EnemiesContainer/Enemies"), "Cancel restores focus to Enemies")
	_button("BackContainer/Back").pressed.emit()
	await _frames(3)
	_expect(_menu.call("get_current_page") == &"home", "Back leaves Information after its panel is closed")
	_button("InformationContainer/Information").pressed.emit()
	await _frames(3)
	_button("EnemiesContainer/Enemies").pressed.emit()
	await _frames(3)
	_check_first_header_visible("Reopening a previously scrolled roster restores its first faction heading")

func _check_panel_layout() -> void:
	var original_size: Vector2i = get_tree().root.size
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		await _frames(6)
		var viewport: Rect2 = get_viewport().get_visible_rect()
		var panel: Rect2 = (_menu.get_node(ENEMY_PANEL) as Control).get_global_rect()
		var left: Rect2 = (_menu.get_node("CenterContainer/MainMenuContainer/ButtonPanel") as Control).get_global_rect()
		_expect(viewport.encloses(panel) and viewport.encloses(left), "Enemy side panel and Information menu fit %s" % resolution)
		_expect(panel.position.x >= left.end.x and not panel.intersects(left), "Enemy panel stays to the right of the visible menu at %s" % resolution)
		_expect(panel.encloses(_grid.get_global_rect()), "Enemy grid remains inside its side panel at %s" % resolution)
		_expect((_menu.get_node(PANEL_CLOSE) as Button).is_visible_in_tree() and panel.encloses((_menu.get_node(PANEL_CLOSE) as Button).get_global_rect()), "Enemy panel Close remains visible at %s" % resolution)
		if resolution == Vector2i(1920, 1080):
			await _capture("enemies_side_panel_1080p.png")
	get_tree().root.size = original_size
	await _frames(6)

func _check_new_kill_persistence() -> void:
	GameFlow.start_new_run()
	var context: CombatStatContext = CombatStatContext.new()
	context.enemy_id = &"grey_probe_mk1"
	context.faction_id = &"greys"
	GameFlow.record_enemy_kill(context)
	_grid.refresh()
	_expect(_entry("grey_probe_mk1").text == "?", "Uncommitted current-run kills do not invent saved lifetime progress")
	GameFlow._finalize_run_stats(false)
	var saved: ConfigFile = ConfigFile.new()
	_expect(saved.load(GameFlow.SAVE_PATH) == OK and int(saved.get_value(GameFlow.META_STATS_GLOBAL_SECTION, "kills|enemy|grey_probe_mk1", 0)) == 1, "Normal run finalization persists an exact per-enemy kill")
	GameFlow._load_user_data()
	_grid.refresh()
	_expect(_entry("grey_probe_mk1").text.is_empty() and _entry("grey_probe_mk1").get_node_or_null("ModelPreview") != null and bool(_entry("grey_probe_mk1").get_meta("killed", false)), "Reloaded kill records reveal that enemy's model on refresh")
	_expect(_entry("grey_veiled_mind_mk1").text == "?", "Revealing one enemy does not reveal another in its faction")
	_button("BackContainer/Back").pressed.emit()
	await _frames(2)
	_button("EnemiesContainer/Enemies").pressed.emit()
	await _frames(3)
	_expect(_entry("grey_probe_mk1").text.is_empty() and _entry("grey_probe_mk1").get_node_or_null("ModelPreview") != null, "Reopening Enemies retains the loaded saved portrait progress")
	await _capture("enemies_updated_history_720p.png")
	GameFlow.abandon_run()

func _check_all_enemy_model_previews() -> void:
	var saved: ConfigFile = ConfigFile.new()
	_expect(saved.load(GameFlow.SAVE_PATH) == OK, "All-model fixture loads its isolated saved history")
	var definitions: Array[EnemyDef] = EnemyInformationGrid.get_enemy_definitions()
	for definition: EnemyDef in definitions:
		saved.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "kills|enemy|" + definition.id, 1)
	_expect(saved.save(GameFlow.SAVE_PATH) == OK, "All 27 saved identities are unlocked only in the isolated fixture")
	GameFlow._load_user_data()
	_menu.call("show_page", &"enemies")
	await _frames(8)
	var preview_ids: Dictionary = {}
	var visible_count: int = 0
	var sleeping_count: int = 0
	var initial_bases: Dictionary = {}
	for definition: EnemyDef in definitions:
		var button: Button = _entry(definition.id)
		var preview: EnemyIconPreview = button.get_node_or_null("ModelPreview") as EnemyIconPreview
		_expect(preview != null and button.text.is_empty(), "Known enemy has a real portrait: " + definition.id)
		if preview == null:
			continue
		preview_ids[definition.id] = preview.get_instance_id()
		_expect(button.find_children("ModelPreview", "", true, false).size() == 1 and preview.find_children("*", "SubViewport", true, false).size() == 1, "Each known enemy has exactly one portrait and viewport: " + definition.id)
		_check_authored_model(definition, preview)
		_check_model_framing(definition, preview)
		if preview.is_active():
			visible_count += 1
			initial_bases[definition.id] = preview.get_model_root().global_basis
		else:
			sleeping_count += 1
			_expect(preview.get_viewport_3d().render_target_update_mode == SubViewport.UPDATE_DISABLED, "Clipped portraits keep rendering disabled: " + definition.id)
	_expect(visible_count > 1 and sleeping_count > 0, "Multiple visible portraits animate while clipped roster entries sleep")
	await _frames(20)
	for enemy_id: String in initial_bases:
		var preview: EnemyIconPreview = _entry(enemy_id).get_node("ModelPreview") as EnemyIconPreview
		_expect(not (initial_bases[enemy_id] as Basis).is_equal_approx(preview.get_model_root().global_basis), "Each visible enemy rotates through the shared preview component: " + enemy_id)
	for repeat: int in range(3):
		_grid.refresh()
	await _frames(4)
	for definition: EnemyDef in definitions:
		var preview: EnemyIconPreview = _entry(definition.id).get_node("ModelPreview") as EnemyIconPreview
		_expect(preview.get_instance_id() == int(preview_ids[definition.id]), "Refresh reuses each existing enemy portrait: " + definition.id)
	var sources_unchanged: bool = not _source_materials.is_empty()
	for index: int in _source_materials.size():
		sources_unchanged = sources_unchanged and _source_materials[index].subsurf_scatter_enabled == _source_sss_flags[index]
	_expect(sources_unchanged, "All-faction preview adaptation preserves authored material flags")
	await _capture_all_factions(definitions)
	var stats_before: Dictionary = GameFlow._meta_stats_global.duplicate(true)
	var file_before: String = FileAccess.get_file_as_string(GameFlow.SAVE_PATH)
	for button: Button in _grid.get_entry_buttons():
		button.pressed.emit()
	_expect(_menu.call("get_current_page") == &"enemies" and GameFlow._meta_stats_global == stats_before and FileAccess.get_file_as_string(GameFlow.SAVE_PATH) == file_before, "Activating every 3D portrait keeps details inactive and never writes progression")
	_menu.call("show_page", &"ships")
	await _frames(5)
	_check_all_portraits_sleep("Changing categories")
	_menu.call("show_page", &"enemies")
	await _frames(5)
	_menu.hide()
	await _frames(5)
	_check_all_portraits_sleep("Hiding the main menu")
	_menu.show()
	await _frames(5)
	_menu.call("show_page", &"information")
	await _frames(5)
	_check_all_portraits_sleep("Closing the information panel")
	_menu.call("show_page", &"enemies")
	await _frames(5)

func _collect_source_meshes(node: Node, meshes: Array[Mesh], inherited_visible: bool = true) -> void:
	var shown: bool = inherited_visible
	if node is Node3D:
		shown = shown and (node as Node3D).visible
	var visual: MeshInstance3D = node as MeshInstance3D
	if shown and visual != null and visual.mesh != null:
		meshes.append(visual.mesh)
	for child: Node in node.get_children():
		_collect_source_meshes(child, meshes, shown)

func _check_authored_model(definition: EnemyDef, preview: EnemyIconPreview) -> void:
	var source_meshes: Array[Mesh] = []
	if definition.model_scene != null:
		var source: Node = definition.model_scene.instantiate()
		_collect_source_meshes(source, source_meshes)
		source.free()
	var copied: int = 0
	var actual: bool = true
	var safe: bool = true
	var compatible: bool = true
	var model: Node3D = preview.get_model_root()
	var nodes: Array[Node] = [model]
	nodes.append_array(model.find_children("*", "", true, false))
	for node: Node in nodes:
		if node.get_script() != null or node is CollisionObject3D or node is EnemyTurret or node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is Timer or node is AnimationPlayer or node is GPUParticles3D or node is CPUParticles3D:
			safe = false
		var visual: MeshInstance3D = node as MeshInstance3D
		if visual == null or visual.mesh == null:
			continue
		copied += 1
		actual = actual and source_meshes.has(visual.mesh)
		for surface: int in visual.mesh.get_surface_count():
			var material: BaseMaterial3D = visual.get_active_material(surface) as BaseMaterial3D
			if material != null:
				compatible = compatible and not material.subsurf_scatter_enabled
	_expect(copied > 0 and copied == source_meshes.size() and actual, "Portrait copies the actual authored meshes: " + definition.id)
	_expect(safe and compatible, "Portrait contains only safe, transparent-compatible visual nodes: " + definition.id)

func _check_model_framing(definition: EnemyDef, preview: EnemyIconPreview) -> void:
	var bounds: AABB = preview.get_model_bounds()
	var model: Node3D = preview.get_model_root()
	var camera: Camera3D = preview.get_camera_3d()
	_expect(bounds.size.is_finite() and bounds.has_volume() and bounds.get_center().is_equal_approx(Vector3.ZERO), "Portrait bounds are finite and centered: " + definition.id)
	var original_basis: Basis = model.basis
	var pixels: Vector2 = Vector2(preview.get_viewport_3d().size)
	var frame: Rect2 = Rect2(Vector2.ONE * 2.0, pixels - Vector2.ONE * 4.0)
	var framed: bool = true
	for angle: float in [0.0, PI * 0.25, PI * 0.5, PI * 0.75]:
		model.basis = Basis(Vector3.UP, angle)
		for corner: int in range(8):
			var world_position: Vector3 = model.global_transform * bounds.get_endpoint(corner)
			var screen_position: Vector2 = camera.unproject_position(world_position)
			framed = framed and screen_position.is_finite() and not camera.is_position_behind(world_position) and frame.has_point(screen_position)
	model.basis = original_basis
	_expect(framed, "Shared framing preserves the entire rotating portrait at multiple yaw angles: " + definition.id)

func _check_all_portraits_sleep(reason: String) -> void:
	for button: Button in _grid.get_entry_buttons():
		var preview: EnemyIconPreview = button.get_node_or_null("ModelPreview") as EnemyIconPreview
		_expect(preview == null or (not preview.is_active() and preview.get_viewport_3d().render_target_update_mode == SubViewport.UPDATE_DISABLED), reason + " stops every portrait: " + String(button.get_meta("enemy_id", "")))

func _capture_all_factions(definitions: Array[EnemyDef]) -> void:
	if _output.is_empty():
		return
	var captured: Dictionary = {}
	for definition: EnemyDef in definitions:
		var faction: String = String(definition.get_faction_id())
		if captured.has(faction):
			continue
		captured[faction] = true
		_entry(definition.id).grab_focus()
		await _frames(8)
		await _capture("enemy_models_%s_720p.png" % faction)
	for definition: EnemyDef in definitions:
		if not definition is EnemyBossDef:
			continue
		_entry(definition.id).grab_focus()
		await _frames(8)
		await _capture("enemy_boss_%s_720p.png" % definition.id)
	_grid.scroll_vertical = 0
	_entry(DRONE.id).grab_focus()
	await _frames(6)

func _check_empty_history() -> void:
	var empty: ConfigFile = ConfigFile.new()
	empty.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_SAVE_SCHEMA_VERSION, GameFlow.CURRENT_SAVE_SCHEMA_VERSION)
	_expect(empty.save(GameFlow.SAVE_PATH) == OK, "Missing enemy stats fixture writes successfully")
	GameFlow._load_user_data()
	_grid.refresh()
	await _frames(8)
	for button: Button in _grid.get_entry_buttons():
		_expect(button.text == "?" and not bool(button.get_meta("killed", true)), "Absent saved kill record safely remains unknown")
	for button: Button in _grid.get_entry_buttons():
		var preview: EnemyIconPreview = button.get_node_or_null("ModelPreview") as EnemyIconPreview
		_expect(preview == null or (not preview.visible and not preview.is_active() and preview.get_viewport_3d().render_target_update_mode == SubViewport.UPDATE_DISABLED), "A missing saved kill never exposes or renders its retained model: " + String(button.get_meta("enemy_id", "")))
	await _capture("enemies_empty_history_720p.png")

func _entry(enemy_id: String) -> Button:
	for button: Button in _grid.get_entry_buttons():
		if String(button.get_meta("enemy_id", "")) == enemy_id:
			return button
	return null

func _check_first_header_visible(description: String) -> void:
	var header: Control = _grid.entries.get_child(0) as Control
	_expect(header != null and _grid.get_global_rect().encloses(header.get_global_rect()), description)

func _button(path: String) -> Button:
	return _menu.get_node(BUTTONS + path) as Button

func _action(action_name: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action_name
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = InputEventAction.new()
	event.action = action_name
	Input.parse_input_event(event)
	await _frames(2)

func _capture(filename: String) -> void:
	if _output.is_empty():
		return
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(_output.path_join(filename)) == OK, "Rendered " + filename)

func _frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _silence(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("ENEMY_INFORMATION_CHECKS: " + description)
