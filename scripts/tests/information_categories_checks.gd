extends Node

## Saved unlock fixtures and browsing checks use a unique user-data namespace.
const MENU_SCENE: PackedScene = preload("res://scenes/main_menu/main_menu.tscn")
const BASE_SHIP: ShipDef = preload("res://content/data/ships/starter_fighter.tres")
const BASE_WEAPON: WeaponDef = preload("res://content/data/weapons/pulse_mk1.tres")
const BUTTONS: String = "CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/"
const PANEL: String = "EnemyInformationPanel"
const GRID: String = "EnemyInformationPanel/Margin/Content/UnlockGrid"
const ENEMY_GRID: String = "EnemyInformationPanel/Margin/Content/EnemyGrid"
const CLOSE: String = "EnemyInformationPanel/Margin/Content/Header/Close"

var _menu: Control
var _grid: UnlockInformationGrid
var _panel: Control
var _close: Button
var _roster: PilotRoster
var _alpha: PilotDef
var _beta: PilotDef
var _ship_a: ShipDef
var _ship_b: ShipDef
var _weapon_a: WeaponDef
var _weapon_b: WeaponDef
var _weapon_c: WeaponDef
var _checks: int = 0
var _failures: int = 0
var _output: String = ""
var _panel_identity: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run_checks.call_deferred()

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Information Categories Validation":
		push_error("Information category checks require their isolated wrapper.")
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
	_make_fixture()
	_seed_kills(0)
	GameFlow._cached_roster = _roster
	GameFlow.set_selected_pilot(_alpha)
	GameFlow.set_selected_ship(_ship_a)
	GameFlow.set_selected_weapon(_weapon_a)
	_menu = MENU_SCENE.instantiate() as Control
	_menu.set("pilot_roster", _roster)
	_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_menu)
	await _frames(6)
	_grid = _menu.get_node(GRID) as UnlockInformationGrid
	_panel = _menu.get_node(PANEL) as Control
	_close = _menu.get_node(CLOSE) as Button
	_panel_identity = _panel.get_instance_id()
	_button("InformationContainer/Information").pressed.emit()
	await _frames(3)
	await _check_categories_and_navigation()
	await _check_saved_unlock_progress()
	await _check_empty_roster()
	_menu.queue_free()
	await _frames(5)
	GameFlow.abandon_run()
	print("INFORMATION_CATEGORIES_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _make_fixture() -> void:
	_weapon_a = _make_weapon("information_fixture_pulse", "Fixture Pulse")
	_weapon_b = _make_weapon("information_fixture_beam", "Fixture Beam")
	_weapon_c = _make_weapon("information_fixture_cannon", "Fixture Cannon")
	_ship_a = _make_ship(&"information_fixture_fighter", "Fixture Fighter")
	_ship_b = _make_ship(&"information_fixture_bruiser", "Fixture Bruiser")
	_ship_a.starter_weapon_options.assign([_weapon_option(_weapon_a), _weapon_option(_weapon_b, 5)])
	_ship_b.starter_weapon_options.assign([_weapon_option(_weapon_a), _weapon_option(_weapon_c)])
	_alpha = PilotDef.new()
	_alpha.id = &"information_fixture_alpha"
	_alpha.display_name = "Fixture Alpha"
	_alpha.ship = _ship_a
	_alpha.starter_ship_options.assign([_ship_option(_ship_a), _ship_option(_ship_b, 10)])
	_beta = PilotDef.new()
	_beta.id = &"information_fixture_beta"
	_beta.display_name = "Fixture Beta"
	_beta.ship = _ship_b
	_beta.starts_unlocked = false
	_beta.sort_order = 1
	var pilot_requirement: PilotUnlockRequirement = PilotUnlockRequirement.new()
	pilot_requirement.stat = UnlockRequirement.UnlockStat.KILLS
	pilot_requirement.minimum_value = 20
	_beta.unlock_requirements.assign([pilot_requirement])
	# An individually unlocked option on a locked pilot is not an available path.
	_beta.starter_ship_options.assign([_ship_option(_ship_b), _ship_option(_ship_a)])
	_roster = PilotRoster.new()
	_roster.pilots.assign([_alpha, _beta, _alpha])

func _make_weapon(id: String, name_text: String) -> WeaponDef:
	var result: WeaponDef = BASE_WEAPON.duplicate() as WeaponDef
	result.weapon_id = id
	result.display_name = name_text
	return result

func _make_ship(id: StringName, name_text: String) -> ShipDef:
	var result: ShipDef = BASE_SHIP.duplicate() as ShipDef
	result.id = id
	result.display_name = name_text
	result.starter_weapon_options = []
	return result

func _requirement(kills: int) -> UnlockRequirement:
	var result: UnlockRequirement = UnlockRequirement.new()
	result.stat = UnlockRequirement.UnlockStat.KILLS
	result.minimum_value = kills
	return result

func _weapon_option(weapon: WeaponDef, kills: int = 0) -> ShipStarterWeaponOptionDef:
	var result: ShipStarterWeaponOptionDef = ShipStarterWeaponOptionDef.new()
	result.weapon = weapon
	result.starts_unlocked = kills == 0
	if kills > 0:
		result.unlock_requirements.assign([_requirement(kills)])
	return result

func _ship_option(ship: ShipDef, kills: int = 0) -> PilotStarterShipOptionDef:
	var result: PilotStarterShipOptionDef = PilotStarterShipOptionDef.new()
	result.ship = ship
	result.starts_unlocked = kills == 0
	if kills > 0:
		result.unlock_requirements.assign([_requirement(kills)])
	return result

func _seed_kills(kills: int) -> void:
	var saved: ConfigFile = ConfigFile.new()
	if FileAccess.file_exists(GameFlow.SAVE_PATH):
		saved.load(GameFlow.SAVE_PATH)
	saved.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_SAVE_SCHEMA_VERSION, GameFlow.CURRENT_SAVE_SCHEMA_VERSION)
	saved.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_GAME_VERSION, ProjectSettings.get_setting("application/config/version", "dev"))
	saved.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "kills", kills)
	_expect(saved.save(GameFlow.SAVE_PATH) == OK, "Unlock fixture saves only isolated progression")
	GameFlow._load_user_data()

func _open(category: StringName) -> void:
	var name_text: String = String(category).capitalize()
	_button(name_text + "Container/" + name_text).pressed.emit()
	await _frames(4)
	_expect(_menu.call("get_current_page") == category, "Category button opens " + String(category))
	_expect(_panel.get_instance_id() == _panel_identity and _panel.is_visible_in_tree(), "Categories reuse the same visible panel")
	_expect(_grid.is_visible_in_tree() and not (_menu.get_node(ENEMY_GRID) as Control).visible, "Only the unlock grid is shown for " + String(category))
	_expect((_menu.get_node(PANEL + "/Margin/Content/Header/Title") as Label).text == String(category).to_upper(), "Shared header names the active category")
	for name: String in ["Enemies", "Weapons", "Ships", "Pilots"]:
		_expect(_button(name + "Container/" + name).is_visible_in_tree(), "Information action remains visible: " + name)

func _check_categories_and_navigation() -> void:
	var selected_pilot: PilotDef = GameFlow.selected_pilot
	var selected_ship: ShipDef = GameFlow.get_selected_ship()
	var selected_weapon: WeaponDef = GameFlow.get_selected_weapon()
	var saved_before: String = FileAccess.get_file_as_string(GameFlow.SAVE_PATH)
	for category: StringName in [&"weapons", &"ships", &"pilots"]:
		await _open(category)
		var buttons: Array[Button] = _grid.get_entry_buttons()
		_expect(buttons.size() == (3 if category == &"weapons" else 2), "Canonical IDs deduplicate shared unlock paths in " + String(category))
		var ids: Dictionary = {}
		for entry: Button in buttons:
			var id: StringName = StringName(entry.get_meta("entry_id", &""))
			_expect(id != &"" and not ids.has(id) and StringName(entry.get_meta("entry_type", &"")) == category, "Each icon has one typed canonical identity")
			ids[id] = true
			entry.pressed.emit()
			_expect(_menu.call("get_current_page") == category, "Placeholder activation opens no details")
		_expect(get_viewport().gui_get_focus_owner() == buttons[0], "Opening focuses the first visible icon")
		await _action(&"ui_left")
		var name: String = String(category).capitalize()
		_expect(get_viewport().gui_get_focus_owner() == _button(name + "Container/" + name), "Grid Left returns to the active category")
		await _action(&"ui_right")
		_expect(get_viewport().gui_get_focus_owner() == buttons[0], "Menu Right reenters its active grid")
		await _check_layout()
		await _capture(String(category) + "_placeholders_720p.png")
	_expect(GameFlow.selected_pilot == selected_pilot and GameFlow.get_selected_ship() == selected_ship and GameFlow.get_selected_weapon() == selected_weapon, "Browsing cannot change the selected pilot, ship, or starting weapon")
	_expect(FileAccess.get_file_as_string(GameFlow.SAVE_PATH) == saved_before, "Browsing and inert activation never write saved progression")
	await _open(&"weapons")
	_check_state(_weapon_a.get_weapon_id(), true)
	_check_state(_weapon_b.get_weapon_id(), false)
	_check_state(_weapon_c.get_weapon_id(), false)
	await _open(&"ships")
	_check_state(_ship_a.get_ship_id(), true)
	_check_state(_ship_b.get_ship_id(), false)
	await _open(&"pilots")
	_check_state(_alpha.get_pilot_id(), true)
	_check_state(_beta.get_pilot_id(), false)
	var source: Button = (_menu.get_node("UpgradesPanel") as UpgradesPanel).btn_close
	_expect(_close.flat == source.flat and _close.get_theme_font("font") == source.get_theme_font("font") and _close.get_theme_font_size("font_size") == source.get_theme_font_size("font_size"), "All categories retain the meta-upgrade close appearance")
	for category: StringName in [&"weapons", &"ships", &"pilots"]:
		await _open(category)
		if category == &"weapons":
			_close.pressed.emit()
		elif category == &"ships":
			_button("BackContainer/Back").pressed.emit()
		else:
			await _action(&"ui_cancel")
		await _frames(3)
		var name: String = String(category).capitalize()
		_expect(_menu.call("get_current_page") == &"information" and not _panel.visible, "Close, Back, and cancel close a category panel")
		_expect(get_viewport().gui_get_focus_owner() == _button(name + "Container/" + name), "Closing restores its matching category focus")
	_button("EnemiesContainer/Enemies").pressed.emit()
	await _frames(3)
	_expect(_panel.get_instance_id() == _panel_identity and (_menu.get_node(ENEMY_GRID) as Control).is_visible_in_tree() and not _grid.visible, "Enemies switches the same panel back to the kill grid")

func _check_saved_unlock_progress() -> void:
	_seed_kills(6)
	await _open(&"weapons")
	_check_state(_weapon_b.get_weapon_id(), true)
	_check_state(_weapon_c.get_weapon_id(), false)
	await _open(&"ships")
	_check_state(_ship_b.get_ship_id(), false)
	_seed_kills(12)
	await _open(&"ships")
	_check_state(_ship_b.get_ship_id(), true)
	await _open(&"weapons")
	_check_state(_weapon_c.get_weapon_id(), true)
	await _open(&"pilots")
	_check_state(_beta.get_pilot_id(), false)
	_seed_kills(25)
	await _open(&"pilots")
	_check_state(_beta.get_pilot_id(), true)
	get_tree().root.size = Vector2i(1920, 1080)
	await _frames(6)
	await _check_layout()
	await _capture("pilots_placeholders_1080p.png")
	get_tree().root.size = Vector2i(1280, 720)
	await _frames(4)

func _check_empty_roster() -> void:
	_menu.set("pilot_roster", PilotRoster.new())
	for category: StringName in [&"weapons", &"ships", &"pilots"]:
		await _open(category)
		_expect(_grid.get_entry_buttons().is_empty(), "An empty roster does not invent category entries")
		_expect(get_viewport().gui_get_focus_owner() == _close and _close.is_visible_in_tree(), "An empty category retains a reachable Close action")
		_close.pressed.emit()
		await _frames(3)
		_expect(_menu.call("get_current_page") == &"information", "Empty categories can close normally")

func _check_state(id: StringName, expected: bool) -> void:
	var found: bool = false
	for button: Button in _grid.get_entry_buttons():
		if StringName(button.get_meta("entry_id", &"")) == id:
			found = true
			_expect(button.text == ("!" if expected else "?") and bool(button.get_meta("unlocked", false)) == expected, "Saved prerequisite path controls icon " + String(id))
	_expect(found, "Roster contains expected identity " + String(id))

func _check_layout() -> void:
	var panel_rect: Rect2 = _panel.get_global_rect()
	var left_rect: Rect2 = (_menu.get_node("CenterContainer/MainMenuContainer/ButtonPanel") as Control).get_global_rect()
	_expect(get_viewport().get_visible_rect().encloses(panel_rect) and not panel_rect.intersects(left_rect) and panel_rect.position.x >= left_rect.end.x, "Shared panel fits to the right of the menu")
	_expect(panel_rect.encloses(_grid.get_global_rect()) and panel_rect.encloses(_close.get_global_rect()), "Grid and Close remain inside the shared panel")
	for button: Button in _grid.get_entry_buttons():
		_expect(_grid.get_global_rect().encloses(button.get_global_rect()), "Small authored fixture icons remain visible inside the grid")

func _button(path: String) -> Button:
	return _menu.get_node(BUTTONS + path) as Button

func _action(name: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = name
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = InputEventAction.new()
	event.action = name
	Input.parse_input_event(event)
	await _frames(2)

func _frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _capture(filename: String) -> void:
	if _output.is_empty():
		return
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(_output.path_join(filename)) == OK, "Rendered " + filename)

func _silence(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("INFORMATION_CATEGORIES_CHECKS: " + description)
