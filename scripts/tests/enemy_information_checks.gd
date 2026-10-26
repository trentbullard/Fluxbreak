extends Node

## A unique save namespace tests historical kills without touching player data.
const MENU_SCENE: PackedScene = preload("res://scenes/main_menu/main_menu.tscn")
const BUTTONS: String = "CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/"
const ENEMY_PANEL: String = "EnemyInformationPanel"
const ENEMY_GRID: String = "EnemyInformationPanel/Margin/Content/EnemyGrid"
const PANEL_CLOSE: String = "EnemyInformationPanel/Margin/Content/Header/Close"
const KNOWN_IDS: Array[String] = ["machine_drone_mk1", "bug_sporeling_mk1", "grey_witness_mk1"]
const PRACTICE_BOSS: EnemyBossDef = preload("res://content/data/enemies/grey_witness_practice.tres")

var _menu: Control = null
var _grid: EnemyInformationGrid = null
var _checks: int = 0
var _failures: int = 0
var _output: String = ""

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
	await _check_navigation_and_inert_icons()
	await _capture("enemies_saved_history_720p.png")
	await _check_new_kill_persistence()
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

func _check_saved_markers() -> void:
	for button: Button in _grid.get_entry_buttons():
		var enemy_id: String = String(button.get_meta("enemy_id", ""))
		var killed: bool = KNOWN_IDS.has(enemy_id)
		_expect(button.text == ("!" if killed else "?") and bool(button.get_meta("killed", false)) == killed, "Saved lifetime kill state controls icon " + enemy_id)
	_expect(_entry("grey_probe_mk1").text == "?", "Damage dealt and faction totals do not reveal a never-killed Probe")
	_expect(_entry("grey_veiled_mind_mk1").text == "?", "A boss encounter without a kill remains unknown")
	_expect(_entry(PRACTICE_BOSS.id).text == "!", "Saved canonical boss kills reveal its shared Practice/Campaign entry")

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
	_expect(_entry("grey_probe_mk1").text == "!" and bool(_entry("grey_probe_mk1").get_meta("killed", false)), "Reloaded kill records reveal that enemy on refresh")
	_expect(_entry("grey_veiled_mind_mk1").text == "?", "Revealing one enemy does not reveal another in its faction")
	_button("BackContainer/Back").pressed.emit()
	await _frames(2)
	_button("EnemiesContainer/Enemies").pressed.emit()
	await _frames(3)
	_expect(_entry("grey_probe_mk1").text == "!", "Reopening Enemies retains the loaded saved progress")
	await _capture("enemies_updated_history_720p.png")
	GameFlow.abandon_run()

func _check_empty_history() -> void:
	var empty: ConfigFile = ConfigFile.new()
	empty.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_SAVE_SCHEMA_VERSION, GameFlow.CURRENT_SAVE_SCHEMA_VERSION)
	_expect(empty.save(GameFlow.SAVE_PATH) == OK, "Missing enemy stats fixture writes successfully")
	GameFlow._load_user_data()
	_grid.refresh()
	for button: Button in _grid.get_entry_buttons():
		_expect(button.text == "?" and not bool(button.get_meta("killed", true)), "Absent saved kill record safely remains unknown")
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
