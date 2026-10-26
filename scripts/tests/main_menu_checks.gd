extends Node

const MENU_SCENE: PackedScene = preload("res://scenes/main_menu/main_menu.tscn")
const WORLD_SCENE: PackedScene = preload("res://scenes/world/world.tscn")
const REAL_ROSTER: PilotRoster = preload("res://content/data/pilots/pilot_roster.tres")
const BASE_SHIP: ShipDef = preload("res://content/data/ships/starter_fighter.tres")
const BASE_WEAPON: WeaponDef = preload("res://content/data/weapons/pulse_mk1.tres")
const BUTTONS: String = "CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/"
const PREVIEW_PATH: NodePath = ^"HangarBackground/HangarViewport/HangarPreview"

var _menu: Control = null
var _roster: PilotRoster = null
var _pilot_a: PilotDef = null
var _pilot_b: PilotDef = null
var _locked_pilot: PilotDef = null
var _ship_a: ShipDef = null
var _ship_b: ShipDef = null
var _ship_c: ShipDef = null
var _weapon_a: WeaponDef = null
var _weapon_b: WeaponDef = null
var _weapon_c: WeaponDef = null
var _locked_weapon: WeaponDef = null
var _campaign_signals: int = 0
var _practice_signals: int = 0
var _selection_signals: int = 0
var _emitted_practice_run: RunDefinition = null
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Menu Validation":
		push_error("Main menu checks require the isolated Fluxbreak Menu Validation project.")
		get_tree().quit(2)
		return
	# Headless starts with a dummy window size; exercise the authored minimum
	# desktop size from the very first menu layout, before testing later resizes.
	get_tree().root.size = Vector2i(1280, 720)
	await _wait_frames(2)
	get_tree().node_added.connect(_mute_test_audio)
	_make_selection_fixture()
	_set_fixture_selection()
	_menu = _create_menu(_roster)
	await _wait_frames(3)
	await _check_navigation_and_focus()
	_check_selection_cascade()
	await _check_remembered_selection()
	await _check_preview_safety_and_latest_selection()
	await _check_settings_and_upgrades()
	_check_launch_signals_and_factions()
	await _check_responsive_controls()
	await _dispose_menu()
	_restore_real_selection()
	await _check_world_launch(false)
	await _check_world_launch(true)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("MAIN_MENU_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	call_deferred("_finish_checks")

func _make_selection_fixture() -> void:
	_weapon_a = _make_weapon("menu_fixture_pulse", "Fixture Pulse")
	_weapon_b = _make_weapon("menu_fixture_beam", "Fixture Beam")
	_weapon_c = _make_weapon("menu_fixture_cannon", "Fixture Cannon")
	_locked_weapon = _make_weapon("menu_fixture_locked_weapon", "Locked Weapon")
	_ship_a = _make_ship(&"menu_fixture_fighter", "Fixture Fighter")
	_ship_a.starter_weapon_options.assign([_weapon_option(_weapon_a, 0), _weapon_option(_weapon_b, 1), _weapon_option(_locked_weapon, 2, false)])
	_ship_b = _make_ship(&"menu_fixture_bruiser", "Fixture Bruiser")
	_ship_b.starter_weapon_options.assign([_weapon_option(_weapon_c, 0)])
	_ship_c = _make_ship(&"menu_fixture_carrier", "Fixture Carrier")
	_ship_c.starter_weapon_options.assign([_weapon_option(_weapon_a, 0)])
	var locked_ship: ShipDef = _make_ship(&"menu_fixture_locked_ship", "Locked Ship")
	locked_ship.starter_weapon_options.assign([_weapon_option(_weapon_a, 0)])
	_pilot_a = _make_pilot(&"menu_fixture_alpha", "Fixture Alpha", _ship_a, 0)
	_pilot_a.starter_ship_options.assign([_ship_option(_ship_a, 0), _ship_option(_ship_b, 1), _ship_option(locked_ship, 2, false)])
	_pilot_b = _make_pilot(&"menu_fixture_beta", "Fixture Beta", _ship_c, 1)
	_pilot_b.starter_ship_options.assign([_ship_option(_ship_c, 0)])
	_locked_pilot = _make_pilot(&"menu_fixture_locked_pilot", "Locked Pilot", _ship_a, 2)
	_locked_pilot.starts_unlocked = false
	_roster = PilotRoster.new()
	_roster.pilots.assign([_pilot_a, _pilot_b, _locked_pilot])

func _make_weapon(weapon_id: String, display_name: String) -> WeaponDef:
	var weapon: WeaponDef = BASE_WEAPON.duplicate() as WeaponDef
	weapon.weapon_id = weapon_id
	weapon.display_name = display_name
	return weapon

func _make_ship(ship_id: StringName, display_name: String) -> ShipDef:
	var ship: ShipDef = BASE_SHIP.duplicate() as ShipDef
	ship.id = ship_id
	ship.display_name = display_name
	ship.starter_weapon_options = []
	return ship

func _make_pilot(pilot_id: StringName, display_name: String, ship: ShipDef, order: int) -> PilotDef:
	var pilot: PilotDef = PilotDef.new()
	pilot.id = pilot_id
	pilot.display_name = display_name
	pilot.ship = ship
	pilot.sort_order = order
	return pilot

func _weapon_option(weapon: WeaponDef, order: int, unlocked: bool = true) -> ShipStarterWeaponOptionDef:
	var option: ShipStarterWeaponOptionDef = ShipStarterWeaponOptionDef.new()
	option.weapon = weapon
	option.sort_order = order
	option.starts_unlocked = unlocked
	return option

func _ship_option(ship: ShipDef, order: int, unlocked: bool = true) -> PilotStarterShipOptionDef:
	var option: PilotStarterShipOptionDef = PilotStarterShipOptionDef.new()
	option.ship = ship
	option.sort_order = order
	option.starts_unlocked = unlocked
	return option

func _set_fixture_selection() -> void:
	GameFlow._cached_roster = _roster
	GameFlow.set_selected_pilot(_pilot_a)
	GameFlow.set_selected_ship(_ship_a)
	GameFlow.set_selected_weapon(_weapon_a)

func _create_menu(roster: PilotRoster) -> Control:
	var menu: Control = MENU_SCENE.instantiate() as Control
	menu.set("pilot_roster", roster)
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu)
	menu.connect("practice_requested", _on_campaign_requested)
	menu.connect("merc_practice_requested", _on_practice_requested)
	menu.connect("selection_changed", _on_selection_changed)
	return menu

func _check_navigation_and_focus() -> void:
	_check(_menu.call("get_current_page") == &"home", "Fresh menus open on Home")
	_check(_button("PlayContainer/Play").is_visible_in_tree() and _button("HangarContainer/Hangar").is_visible_in_tree(), "Home exposes Play and Hangar")
	_check(not _picker("PilotContainer/Row/PilotPicker").is_visible_in_tree() and not _button("PracticeContainer/Practice").is_visible_in_tree(), "Home keeps loadout and launch controls on their dedicated pages")
	_check(get_viewport().gui_get_focus_owner() == _button("PlayContainer/Play"), "Home gives controller and keyboard users a visible default focus")
	_check(get_viewport().get_visible_rect().encloses(_button("PlayContainer/Play").get_global_rect()), "Initial Home layout keeps Play on screen before any window resize (button %s; center %s)" % [str(_button("PlayContainer/Play").get_global_rect()), str((_menu.get_node("CenterContainer") as Control).get_global_rect())])
	await _send_action(&"ui_down")
	_check(get_viewport().gui_get_focus_owner() == _button("HangarContainer/Hangar"), "Controller navigation moves between visible Home actions")
	_button("PlayContainer/Play").pressed.emit()
	await _wait_frames(2)
	_check(_menu.call("get_current_page") == &"play", "Play button opens run configuration")
	_check(_picker("FactionContainer/Row/FactionPicker").is_visible_in_tree(), "Play exposes the faction selector")
	_check(_button("PracticeContainer/Practice").is_visible_in_tree() and _button("MercPracticeContainer/MercPractice").is_visible_in_tree(), "Play exposes Campaign and Practice")
	_check(_button("PracticeContainer/Practice").get_global_rect().end.y <= _picker("FactionContainer/Row/FactionPicker").get_global_rect().position.y, "Campaign appears above the Practice-only faction selector")
	_check(not _picker("PilotContainer/Row/PilotPicker").is_visible_in_tree(), "Play keeps pilot editing in Hangar")
	_assert_focus_visible("Play focuses a visible enabled control")
	var faction_picker: OptionButton = _picker("FactionContainer/Row/FactionPicker")
	faction_picker.grab_focus()
	await _send_action(&"ui_accept")
	_check(faction_picker.get_popup().visible, "Controller accept opens the focused faction picker")
	await _send_action(&"ui_cancel")
	_check(not faction_picker.get_popup().visible and _menu.call("get_current_page") == &"play", "Cancel closes a picker popup before leaving the Play page")
	_button("ChangeLoadoutContainer/ChangeLoadout").pressed.emit()
	await _wait_frames(2)
	_check(_menu.call("get_current_page") == &"hangar", "Change Loadout opens Hangar")
	_check(_picker("PilotContainer/Row/PilotPicker").is_visible_in_tree() and _picker("ShipContainer/Row/ShipPicker").is_visible_in_tree() and _picker("WeaponContainer/Row/WeaponPicker").is_visible_in_tree(), "Hangar exposes all three loadout selectors")
	_check(not _picker("FactionContainer/Row/FactionPicker").is_visible_in_tree(), "Hangar leaves run faction configuration on Play")
	_button("ContinueContainer/ContinueToPlay").pressed.emit()
	await _wait_frames(2)
	_check(_menu.call("get_current_page") == &"play", "Hangar Continue returns to Play")
	await _send_action(&"ui_cancel")
	_check(_menu.call("get_current_page") == &"home", "Cancel returns from Play to Home")
	_button("HangarContainer/Hangar").pressed.emit()
	await _wait_frames(2)
	_check(_menu.call("get_current_page") == &"hangar", "Home Hangar button opens loadout selection")
	_button("BackContainer/Back").pressed.emit()
	await _wait_frames(2)
	_check(_menu.call("get_current_page") == &"home", "Back returns a subpage to Home")
	await _send_action(&"ui_cancel")
	_check(_menu.call("get_current_page") == &"home" and _menu.visible, "Cancel at Home leaves the menu open")
	get_viewport().gui_release_focus()
	var controller_event: InputEventJoypadButton = InputEventJoypadButton.new()
	controller_event.button_index = JOY_BUTTON_DPAD_DOWN
	controller_event.pressed = true
	Input.parse_input_event(controller_event)
	await _wait_frames(3)
	_assert_focus_visible("A controller event restores missing focus to a visible Home control")
	for page: StringName in [&"home", &"play", &"hangar", &"settings"]:
		_menu.call("show_page", page)
		await _wait_frames(2)
		_assert_focus_visible("Page %s always focuses a visible enabled control" % page)

func _check_selection_cascade() -> void:
	_menu.call("show_page", &"hangar")
	var pilots: OptionButton = _picker("PilotContainer/Row/PilotPicker")
	var ships: OptionButton = _picker("ShipContainer/Row/ShipPicker")
	var weapons: OptionButton = _picker("WeaponContainer/Row/WeaponPicker")
	_check(pilots.item_count == 3 and pilots.is_item_disabled(2), "Locked pilots remain visible and disabled")
	_check(ships.item_count == 3 and ships.is_item_disabled(2), "Locked ships remain visible and disabled")
	_check(weapons.item_count == 3 and weapons.is_item_disabled(2), "Locked weapons remain visible and disabled")
	_select_picker(weapons, 1)
	_check(GameFlow.get_selected_weapon() == _weapon_b, "Weapon selection updates the launch loadout")
	_select_picker(ships, 1)
	_check(GameFlow.get_selected_ship() == _ship_b and GameFlow.get_selected_weapon() == _weapon_c, "Changing hull chooses a compatible weapon")
	_check(weapons.item_count == 1 and weapons.get_selected() == 0, "Changing hull refreshes its compatible weapon choices")
	_select_picker(pilots, 1)
	_check(GameFlow.selected_pilot == _pilot_b and GameFlow.get_selected_ship() == _ship_c, "Changing pilot selects that pilot's valid hull")
	_select_picker(pilots, 0)
	_check(GameFlow.get_selected_ship() == _ship_b, "Returning to a pilot restores that pilot's remembered hull")
	_select_picker(ships, 0)
	_check(GameFlow.get_selected_weapon() == _weapon_b, "Returning to a hull restores its remembered weapon")
	_select_picker(weapons, 2)
	_check(GameFlow.get_selected_weapon() != _locked_weapon and GameFlow.get_selected_weapon() != null and not weapons.is_item_disabled(weapons.get_selected()), "A programmatic locked weapon selection recovers to an unlocked choice")
	_select_picker(ships, 2)
	_check(GameFlow.get_selected_ship() == _ship_a and not ships.is_item_disabled(ships.get_selected()), "A locked hull cannot enter the selected loadout")
	_select_picker(pilots, 2)
	_check(GameFlow.selected_pilot == _pilot_a and not pilots.is_item_disabled(pilots.get_selected()), "A locked pilot cannot enter the selected loadout")
	_check(_selection_signals >= 6, "Loadout edits notify the existing selection signal")
	_select_picker(weapons, 1)
	_menu.call("set_practice_faction_id", &"greys")

func _check_remembered_selection() -> void:
	await _dispose_menu()
	_menu = _create_menu(_roster)
	await _wait_frames(3)
	_check(_menu.call("get_current_page") == &"home", "A recreated menu starts at Home")
	_check(GameFlow.selected_pilot == _pilot_a and GameFlow.get_selected_ship() == _ship_a and GameFlow.get_selected_weapon() == _weapon_b, "Reopening the menu retains the chosen pilot, hull, and weapon")
	_check(_picker("WeaponContainer/Row/WeaponPicker").get_selected() == 1, "Reopened selectors reflect the remembered weapon")
	_check(_menu.call("get_practice_faction_id") == &"greys", "Reopening the menu retains the selected faction")

func _check_preview_safety_and_latest_selection() -> void:
	_menu.call("show_page", &"hangar")
	var preview: Node = _menu.get_node(PREVIEW_PATH)
	_check(preview != null and preview.has_method("set_selection"), "Hangar owns its passive preview")
	_assert_passive_tree(preview)
	var mesh_count: int = preview.find_children("*", "MeshInstance3D", true, false).size()
	_check(mesh_count > 0 and BASE_SHIP.visuals != null and BASE_SHIP.visuals.model_scene != null, "Hangar can display the real starter ship model without a live Ship actor")
	preview.call("set_motion_enabled", true)
	preview.call("set_selection", _pilot_a, _ship_a, true)
	preview.call("set_selection", _pilot_a, _ship_b)
	preview.call("set_selection", _pilot_b, _ship_c)
	preview.call("set_selection", _pilot_a, _ship_a)
	for frame: int in range(240):
		if not bool(preview.call("is_transitioning")):
			break
		await get_tree().process_frame
	_check(preview.call("get_selected_bay_id") == &"menu_fixture_alpha:menu_fixture_fighter", "Rapid selection changes settle at the latest selected bay")
	_check(not bool(preview.call("is_transitioning")), "Interrupted preview pans finish instead of keeping stale tweens")
	preview.call("set_selection", _pilot_a, _ship_b)
	preview.call("set_motion_enabled", false)
	_check(preview.call("get_selected_bay_id") == &"menu_fixture_alpha:menu_fixture_bruiser" and not bool(preview.call("is_transitioning")), "Reduced motion immediately settles on the latest selected hull")
	var empty_ship: ShipDef = ShipDef.new()
	empty_ship.id = &"menu_fixture_empty"
	preview.call("set_selection", _pilot_a, empty_ship, true)
	_check(preview.call("get_selected_bay_id") == &"menu_fixture_alpha:menu_fixture_empty", "A hull without visual data gets a safe display cradle")
	_assert_passive_tree(preview)
	preview.call("set_selection", _pilot_a, _ship_a, true)
	_check(not GameFlow._run_active, "Preview navigation cannot start combat")

func _check_settings_and_upgrades() -> void:
	_menu.call("show_page", &"home")
	_button("SettingsContainer/Settings").pressed.emit()
	await _wait_frames(2)
	_check(_menu.call("get_current_page") == &"settings", "Settings button opens its page")
	var motion: CheckButton = _menu.get_node(BUTTONS + "SettingsControls/Motion") as CheckButton
	var volume: HSlider = _menu.get_node(BUTTONS + "SettingsControls/MasterVolume") as HSlider
	var original_volume: float = volume.value
	var original_motion: bool = motion.button_pressed
	var test_volume: float = 37.0 if not is_equal_approx(original_volume, 37.0) else 42.0
	_check(motion.is_visible_in_tree(), "Settings exposes the hangar motion preference")
	volume.value = test_volume
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(0), test_volume / 100.0), "Master volume immediately updates the actual audio bus")
	motion.button_pressed = false
	motion.toggled.emit(false)
	_menu.call("show_page", &"hangar")
	var preview: Node = _menu.get_node(PREVIEW_PATH)
	_select_picker(_picker("ShipContainer/Row/ShipPicker"), 1)
	_check(not bool(preview.call("is_transitioning")), "Disabling hangar animation applies to subsequent hull selections")
	_select_picker(_picker("ShipContainer/Row/ShipPicker"), 0)
	await _dispose_menu()
	_menu = _create_menu(_roster)
	await _wait_frames(3)
	volume = _menu.get_node(BUTTONS + "SettingsControls/MasterVolume") as HSlider
	motion = _menu.get_node(BUTTONS + "SettingsControls/Motion") as CheckButton
	_check(is_equal_approx(volume.value, test_volume), "Master volume preference survives menu recreation")
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(0), test_volume / 100.0), "Reopened menus apply the saved volume to the audio bus")
	_check(not motion.button_pressed, "Reduced motion preference survives menu recreation")
	_menu.call("show_page", &"hangar")
	preview = _menu.get_node(PREVIEW_PATH)
	_select_picker(_picker("ShipContainer/Row/ShipPicker"), 1)
	_check(not bool(preview.call("is_transitioning")), "Reopened menus apply saved reduced motion to new hull selections")
	_select_picker(_picker("ShipContainer/Row/ShipPicker"), 0)
	volume.value = original_volume
	motion.button_pressed = original_motion
	_menu.call("show_page", &"home")
	_button("UpgradesContainer/Upgrades").pressed.emit()
	await _wait_frames(2)
	var upgrades: UpgradesPanel = _menu.get_node("UpgradesPanel") as UpgradesPanel
	_check(upgrades.visible and _menu.call("get_current_page") == &"home", "Upgrades opens over the originating page")
	upgrades.btn_close.pressed.emit()
	await _wait_frames(2)
	_check(not upgrades.visible and _menu.call("get_current_page") == &"home", "Closing upgrades restores its originating page")
	_check(get_viewport().gui_get_focus_owner() == _button("UpgradesContainer/Upgrades"), "Closing upgrades restores focus to the invoking action")
	_menu.call("show_page", &"hangar")
	_menu.call("_on_upgrades_pressed")
	upgrades.btn_close.pressed.emit()
	await _wait_frames(2)
	_check(_menu.call("get_current_page") == &"hangar", "A programmatic upgrades overlay retains its non-Home origin")
	_assert_focus_visible("Closing upgrades from Hangar never focuses a hidden Home action")

func _check_launch_signals_and_factions() -> void:
	_menu.call("show_page", &"play")
	_menu.call("set_practice_faction_id", &"bugs")
	var campaign_before: int = _campaign_signals
	var practice_before: int = _practice_signals
	_button("PracticeContainer/Practice").pressed.emit()
	_check(_campaign_signals == campaign_before + 1 and _practice_signals == practice_before, "Campaign retains its existing launch signal")
	var campaign: RunDefinition = _menu.call("build_practice_run", false) as RunDefinition
	_check(campaign != null and campaign.run_mode == RunDefinition.RunMode.STORY and campaign.get_stage_count() == 2, "Campaign creates the full two-stage run")
	_button("MercPracticeContainer/MercPractice").pressed.emit()
	_check(_practice_signals == practice_before + 1 and _campaign_signals == campaign_before + 1, "Practice retains its existing typed run signal")
	_check(_emitted_practice_run != null and _emitted_practice_run.run_mode == RunDefinition.RunMode.PRACTICE and _emitted_practice_run.get_stage_count() == 1, "Practice emits the shorter run definition")
	_check(_emitted_practice_run != null and _emitted_practice_run.enemy_faction.get_faction_id() == &"bugs", "Only Practice uses the selected faction")
	_check(_menu.call("get_practice_faction_id") == &"bugs", "Campaign randomization preserves the Practice preference")
	for run: RunDefinition in [campaign, _emitted_practice_run]:
		if run != null:
			_check(run.enemy_faction != null, "Launch resolves one faction before play begins")
			for stage: StageDef in run.get_stages():
				for card: WaveCard in stage.get_wave_cards():
					_check(card.get_faction_bias_id() == run.enemy_faction.get_faction_id(), "Launch decks keep one faction across every stage")
	_menu.call("set_practice_faction_id", &"random")
	var random_run: RunDefinition = _menu.call("build_practice_run", false) as RunDefinition
	_check(random_run != null and random_run.enemy_faction != null, "Random resolves its faction before launch")
	_check(_menu.call("get_practice_faction_id") == &"random", "A random roll does not replace the player's Random preference")
	_menu.call("show_page", &"hangar")
	_menu.call("show_page", &"play")
	_check(_menu.call("get_practice_faction_id") == &"random", "Page changes cannot reroll or reset the faction preference")

func _check_responsive_controls() -> void:
	var old_size: Vector2i = get_tree().root.size
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1280, 900), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		for page: StringName in [&"home", &"play", &"hangar", &"settings"]:
			_menu.call("show_page", page)
			await _wait_frames(3)
			var viewport_rect: Rect2 = get_viewport().get_visible_rect()
			for node: Node in _menu.find_children("*", "Control", true, false):
				var control: Control = node as Control
				if control.is_visible_in_tree() and (control is BaseButton or control is HSlider) and control.get_parent() is not Popup:
					var rect: Rect2 = control.get_global_rect()
					_check(viewport_rect.encloses(rect), "%s keeps %s reachable at %dx%d (control %s; viewport %s)" % [page, control.name, resolution.x, resolution.y, str(rect), str(viewport_rect)])
	get_tree().root.size = old_size
	await _wait_frames(2)

func _restore_real_selection() -> void:
	GameFlow._cached_roster = REAL_ROSTER
	var pilot: PilotDef = REAL_ROSTER.get_pilots()[0]
	GameFlow.set_selected_pilot(pilot)
	GameFlow.set_selected_ship(pilot.ship)
	var weapons: Array[ShipStarterWeaponOptionDef] = GameFlow.get_starter_weapon_options(pilot.ship)
	for option: ShipStarterWeaponOptionDef in weapons:
		if GameFlow.is_weapon_option_unlocked(option):
			GameFlow.set_selected_weapon(option.weapon)
			break

func _check_world_launch(short_practice: bool) -> void:
	var world: Node3D = WORLD_SCENE.instantiate() as Node3D
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await _wait_frames(3)
	var menu: Control = world.get_node("MainMenuOverlay") as Control
	_check(menu.call("get_current_page") == &"home" and get_tree().paused, "Actual world starts paused at Home")
	menu.call("show_page", &"play")
	menu.call("set_practice_faction_id", &"greys")
	var launch_button: Button = menu.get_node(BUTTONS + ("MercPracticeContainer/MercPractice" if short_practice else "PracticeContainer/Practice")) as Button
	launch_button.pressed.emit()
	var run: RunDefinition = GameFlow.get_active_run_definition()
	_check(run != null and run.get_stage_count() == (1 if short_practice else 2), "Actual %s button launches the correct run length" % ("Practice" if short_practice else "Campaign"))
	_check(run != null and run.enemy_faction != null and (not short_practice or run.enemy_faction.get_faction_id() == &"greys"), "Actual Campaign resolves a random faction while Practice uses the selected Greys")
	_check(menu.call("get_practice_faction_id") == &"greys", "Actual launch preserves the Practice selector preference")
	_check(not menu.visible and not get_tree().paused and (world.get_node("Ship") as Ship).visible, "Actual launch hides the menu and enables the playing ship")
	_check((world.get_node("HUD") as CanvasLayer).visible, "Actual launch enables the gameplay HUD")
	_check(not menu.get_node(PREVIEW_PATH).is_processing(), "Launching a run stops the hidden hangar preview")
	_check((menu.get_node("HangarBackground/HangarViewport") as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED, "Launching a run stops hidden hangar rendering")
	GameFlow._run_active = false
	GameFlow._clear_run_progression()
	get_tree().paused = false
	world.queue_free()
	get_tree().current_scene = self
	await _wait_frames(4)

func _assert_passive_tree(root: Node) -> void:
	var pending: Array[Node] = [root]
	var unsafe_nodes: Array[String] = []
	var hazard_groups: Array[String] = []
	while not pending.is_empty():
		var node: Node = pending.pop_back() as Node
		if node is Ship or node is Enemy or node is PlayerTurret or node is EnemyTurret or node is CollisionObject3D or node is Spawner:
			unsafe_nodes.append(String(node.get_path()))
		for group: StringName in node.get_groups():
			if String(group) in ["player", "targets", "enemies", "enemy_attack_telegraphs", "bug_brood", "bug_spore_zones", "grey_tethers", "grey_displacements", "merc_escorts"]:
				hazard_groups.append(String(group))
		for child: Node in node.get_children():
			pending.append(child)
	_check(unsafe_nodes.is_empty(), "Hangar preview contains no combat actors, weapons, spawners, or collision objects: %s" % str(unsafe_nodes))
	_check(hazard_groups.is_empty(), "Hangar preview never joins live combat or hazard groups")

func _assert_focus_visible(description: String) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	_check(focus != null and focus.is_visible_in_tree() and focus.focus_mode == Control.FOCUS_ALL and (not focus is BaseButton or not (focus as BaseButton).disabled), description)

func _send_action(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _wait_frames(2)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await _wait_frames(2)

func _select_picker(picker: OptionButton, index: int) -> void:
	picker.select(index)
	picker.item_selected.emit(index)

func _picker(path: String) -> OptionButton:
	return _menu.get_node(BUTTONS + path) as OptionButton

func _button(path: String) -> Button:
	return _menu.get_node(BUTTONS + path) as Button

func _on_campaign_requested() -> void:
	_campaign_signals += 1

func _on_practice_requested(run: RunDefinition) -> void:
	_practice_signals += 1
	_emitted_practice_run = run

func _on_selection_changed() -> void:
	_selection_signals += 1

func _mute_test_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _dispose_menu() -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null
	await _wait_frames(3)

func _wait_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("MAIN_MENU_CHECKS: " + description)

func _finish_checks() -> void:
	get_tree().quit(0 if _failures == 0 else 1)
