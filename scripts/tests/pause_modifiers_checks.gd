extends Node

## Save-isolated checks and optional rendered captures of current-run history.
const WORLD_SCENE: PackedScene = preload("res://scenes/world/world.tscn")
const BULKHEAD: Upgrade = preload("res://content/data/upgrades/upgrade_reinforced_bulkheads_1.tres")
const MAGNET: Upgrade = preload("res://content/data/upgrades/upgrade_salvage_magnet_2.tres")
const MENU_BUTTONS: String = "CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/"

var _checks: int = 0
var _failures: int = 0
var _output: String = ""
var _world: Node3D
var _ship: Ship
var _pause: PauseMenu
var _panel: RunModifiersPanel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Pause Modifiers Validation":
		push_error("Pause modifier checks require the isolated validation wrapper.")
		get_tree().quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	if not _output.is_empty():
		if DisplayServer.get_name() == "headless":
			push_error("Rendered pause checks require a renderer.")
			get_tree().quit(2)
			return
		DirAccess.make_dir_recursive_absolute(_output)
	get_tree().root.size = Vector2i(1280, 720)
	get_tree().node_added.connect(_mute_audio)
	GameFlow.abandon_run()
	_check_history_contract()
	_world = WORLD_SCENE.instantiate() as Node3D
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	await _wait_frames(5)
	_ship = _world.get_node("Ship") as Ship
	_pause = _world.get_node("PauseMenu") as PauseMenu
	_panel = _pause.get_node("ScreenRoot/RunModifiersPanel") as RunModifiersPanel
	_panel.refresh()
	_check(_all_text().has("No active map modifiers."), "Empty map state is honest")
	_check(_all_text().has("No active faction modifiers."), "Empty faction state is honest")
	_check(_all_text().has("No upgrades chosen this run."), "Empty upgrade state is honest")
	await _launch_campaign()
	await _check_real_purchase_path()
	await _check_pause_contents()
	await _check_navigation()
	await _check_camera_modal()
	await _check_sector_carry()
	await _check_new_run_reset()
	GameFlow.abandon_run()
	RunState.reset_upgrades_purchased()
	get_tree().paused = false
	PauseManager.is_paused = false
	_world.queue_free()
	get_tree().current_scene = self
	await _wait_frames(5)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("PAUSE_MODIFIERS_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _check_history_contract() -> void:
	RunState.start_run()
	var first: Upgrade = BULKHEAD.duplicate(true) as Upgrade
	RunState.record_upgrade_purchase("  REINFORCED_BULKHEADS_1  ", first)
	RunState.record_upgrade_purchase(MAGNET.id, MAGNET)
	RunState.record_upgrade_purchase(first.id, first)
	RunState.record_upgrade_purchase("  ", first)
	var entries: Array[Dictionary] = RunState.get_purchased_upgrade_entries()
	_check(entries.size() == 3, "Repeated purchases remain separate and empty IDs are rejected")
	_check(entries[0]["id"] == first.id and entries[1]["id"] == MAGNET.id and entries[2]["id"] == first.id, "History is newest first with normalized IDs")
	_check(entries[0]["name"] == first.display_name and entries[0]["description"] == first.descripton, "History captures the selected resource's name and stat description")
	first.display_name = "Changed after purchase"
	first.descripton = "Changed after purchase"
	entries[0]["name"] = "External mutation"
	entries.clear()
	var immutable: Array[Dictionary] = RunState.get_purchased_upgrade_entries()
	_check(immutable[0]["name"] == BULKHEAD.display_name and immutable[0]["description"] == BULKHEAD.descripton, "Resources and returned dictionaries cannot mutate prior purchase snapshots")
	RunState.record_upgrade_purchase("legacy_test_upgrade")
	_check(RunState.get_purchased_upgrade_entries()[0]["name"] == "Legacy Test Upgrade", "Legacy ID-only callers receive a readable fallback")
	RunState.start_run()
	_check(RunState.get_purchased_upgrade_entries().is_empty() and RunState.get_purchased_upgrade_ids().is_empty(), "Starting a run clears history and existing purchase memory together")

func _launch_campaign() -> void:
	var menu: Control = _world.get_node("MainMenuOverlay") as Control
	menu.call("show_page", &"play")
	menu.call("set_practice_faction_id", &"greys")
	(menu.get_node(MENU_BUTTONS + "PracticeContainer/Practice") as Button).pressed.emit()
	await _wait_frames(4)
	_check(not menu.visible and not get_tree().paused, "The actual Campaign button starts the run")
	_check(GameFlow.get_run_faction() != null and GameFlow.get_run_faction().get_faction_id() == &"greys", "The selected faction remains attached to the run")
	_ship.freeze = true
	_ship.set_physics_process(false)
	_ship.get_node("MouseFlightController").process_mode = Node.PROCESS_MODE_DISABLED
	_ship.get_node("ControllerFlightController").process_mode = Node.PROCESS_MODE_DISABLED
	_ship._regen_timer.stop()
	_world.get_node("StageRoot/WaveDirector").set_process(false)
	_world.get_node("StageRoot/WaveDirector").set_physics_process(false)

func _check_real_purchase_path() -> void:
	var menu: UpgradeMenu = _world.get_node("UpgradeMenu") as UpgradeMenu
	var original_upgrades: Array[Upgrade] = menu.available_upgrades.duplicate()
	var original_weapons: Array[WeaponDef] = menu.available_weapons.duplicate()
	for upgrade: Upgrade in [BULKHEAD, MAGNET, BULKHEAD]:
		menu.available_upgrades = [upgrade]
		menu.available_weapons = []
		_ship._nanobots = 100000
		RunState.nanobots_updated.emit(_ship.get_nanobots())
		menu.show_for_poi(null)
		await _wait_frames(2)
		var buttons: Array[Button] = menu.get("_buttons")
		_check(not buttons[0].disabled and buttons[0].text.contains(upgrade.display_name), "A real affordable upgrade offer is present")
		buttons[0].pressed.emit()
		await _wait_frames(2)
		var newest: Dictionary = RunState.get_purchased_upgrade_entries()[0]
		_check(not menu.visible and newest["name"] == upgrade.display_name and newest["description"] == upgrade.descripton, "A successful actual offer button records its exact selected text")
		_check(_ship.get_nanobots() < 100000, "Purchase history corresponds to a paid upgrade")
	var count: int = RunState.get_purchased_upgrade_entries().size()
	_ship._nanobots = 0
	RunState.nanobots_updated.emit(0)
	menu.show_for_poi(null)
	await _wait_frames(2)
	var buttons: Array[Button] = menu.get("_buttons")
	_check(buttons[0].disabled, "An unaffordable real offer is disabled")
	buttons[0].pressed.emit()
	_check(RunState.get_purchased_upgrade_entries().size() == count and menu.visible, "The affordability guard rejects even a direct button signal without recording a purchase")
	menu.btn_close.pressed.emit()
	await _wait_frames(2)
	_check(RunState.get_purchased_upgrade_entries().size() == count and not menu.visible, "Closing an offer without buying adds no history")
	menu.available_upgrades = original_upgrades
	menu.available_weapons = original_weapons

func _check_pause_contents() -> void:
	PauseManager.pause_requested.emit()
	await _wait_frames(4)
	_check(_pause.visible and _panel.is_visible_in_tree() and get_tree().paused, "Pausing exposes the right-hand modifier panel")
	var texts: Array[String] = _all_text()
	_check(texts.has("MAP MODIFIERS") and texts.has("FACTION MODIFIERS") and texts.has("RUN UPGRADES"), "Map, faction, and chosen upgrades have separate sections")
	_check(texts.has(GameFlow.get_run_faction().get_display_name_or_default()) and texts.has("No active faction modifiers."), "Faction context is shown without inventing faction modifier effects")
	for modifier: StageModifierDef in GameFlow.get_active_stage_modifiers():
		_check(texts.has(modifier.get_display_name_or_default()) and texts.has(modifier.description), "An active map modifier shows its authored name and exact stat effect")
	var rows: Array[Dictionary] = _upgrade_rows()
	_check(rows.size() == 3 and rows[0]["name"] == BULKHEAD.display_name and rows[1]["name"] == MAGNET.display_name and rows[2]["name"] == BULKHEAD.display_name, "Visible upgrade rows preserve purchase order and duplicate choices")
	_check(rows[0]["description"] == BULKHEAD.descripton and rows[1]["description"] == MAGNET.descripton, "Visible chosen upgrades use their stat descriptions")
	await _check_layout()
	await _capture("pause_modifiers_top_720p.png")
	var before_count: int = _panel.entries.get_child_count()
	PauseManager.resume_requested.emit()
	await _wait_frames(2)
	PauseManager.pause_requested.emit()
	await _wait_frames(3)
	_check(_panel.entries.get_child_count() == before_count and _upgrade_rows().size() == 3, "Repeated pause refreshes replace rows without duplicating them")
	for index: int in range(18):
		var item: Upgrade = MAGNET.duplicate(true) as Upgrade
		item.id = "history_scroll_%02d" % index
		item.display_name = "Salvage Magnet II / Extended field calibration %02d" % index
		RunState.record_upgrade_purchase(item.id, item)
	_panel.refresh()
	await _wait_frames(4)
	_check(_upgrade_rows().size() == 21, "Long runs retain every chosen upgrade")
	_check(_panel.get_v_scroll_bar().max_value > _panel.size.y, "Long history scrolls instead of growing outside the screen")
	await _check_layout()

func _check_navigation() -> void:
	_pause.btn_resume.grab_focus()
	await _send_key(KEY_RIGHT)
	_check(get_viewport().gui_get_focus_owner() == _panel, "Keyboard Right enters the new right panel")
	var initial: int = _panel.scroll_vertical
	await _send_key(KEY_DOWN)
	_check(_panel.scroll_vertical > initial and get_viewport().gui_get_focus_owner() == _panel, "Keyboard Down scrolls history without stealing focus")
	await _send_key(KEY_UP)
	_check(_panel.scroll_vertical == initial, "Keyboard Up scrolls back")
	await _send_key(KEY_LEFT)
	_check(get_viewport().gui_get_focus_owner() == _pause.btn_resume, "Keyboard Left returns from the right panel to central actions")
	await _send_joy(JOY_BUTTON_DPAD_RIGHT)
	_check(get_viewport().gui_get_focus_owner() == _panel, "Controller Right enters the new right panel")
	initial = _panel.scroll_vertical
	await _send_joy(JOY_BUTTON_DPAD_DOWN)
	_check(_panel.scroll_vertical > initial, "Controller Down scrolls the chosen upgrades")
	await _send_joy(JOY_BUTTON_DPAD_UP)
	_check(_panel.scroll_vertical == initial, "Controller Up scrolls back")
	_panel.scroll_vertical = int(_panel.get_v_scroll_bar().max_value)
	await _wait_frames(3)
	await _capture("pause_modifiers_bottom_720p.png")
	await _send_joy(JOY_BUTTON_DPAD_LEFT)
	_check(get_viewport().gui_get_focus_owner() == _pause.btn_resume, "Controller Left returns to central actions")
	await _send_key(KEY_LEFT)
	_check(get_viewport().gui_get_focus_owner() == _pause.stat_panel, "The existing left statistics panel remains keyboard reachable")
	initial = _pause.stat_panel.scroll_vertical
	await _send_key(KEY_DOWN)
	_check(_pause.stat_panel.scroll_vertical > initial, "Statistics scrolling remains usable")
	await _send_key(KEY_RIGHT)
	_check(get_viewport().gui_get_focus_owner() == _pause.btn_resume, "The left panel returns to central actions")

func _check_camera_modal() -> void:
	_pause.open_camera_settings()
	await _wait_frames(3)
	_check(_pause.camera_settings_panel.visible and get_tree().paused, "The existing camera settings still opens above both side panels")
	await _send_key(KEY_ESCAPE)
	_check(not _pause.camera_settings_panel.visible and _pause.visible and get_tree().paused, "Escape closes camera settings without resuming the run")
	_pause.open_camera_settings()
	await _wait_frames(2)
	await _send_joy(JOY_BUTTON_B)
	_check(not _pause.camera_settings_panel.visible and _pause.visible and get_tree().paused, "Controller B closes only camera settings")

func _check_sector_carry() -> void:
	var history: Array[Dictionary] = RunState.get_purchased_upgrade_entries()
	PauseManager.resume_requested.emit()
	await _wait_frames(2)
	var stage: StageDef = GameFlow.get_current_stage()
	var routes: Array[SectorRouteDef] = stage.get_gateway_routes()
	_check(not routes.is_empty(), "Campaign provides an actual authored sector route")
	if routes.is_empty():
		return
	_check(GameFlow.advance_to_next_stage(routes[0].get_destination_id()), "The gateway's stage-transfer hook enters its offered destination")
	await _wait_frames(4)
	_check(RunState.get_purchased_upgrade_entries() == history, "Sector transfer retains exact chosen upgrade history")
	PauseManager.pause_requested.emit()
	await _wait_frames(3)
	var texts: Array[String] = _all_text()
	for modifier: StageModifierDef in GameFlow.get_active_stage_modifiers():
		_check(texts.has(modifier.get_display_name_or_default()) and texts.has(modifier.description), "After transfer the panel displays the destination's current map effects")
	_check(_upgrade_rows().size() == history.size(), "Destination pause menu retains the run's full purchase history")
	_panel.scroll_vertical = 0
	await _wait_frames(3)
	await _capture("pause_modifiers_destination_720p.png")

func _check_new_run_reset() -> void:
	PauseManager.resume_requested.emit()
	await _wait_frames(2)
	GameFlow.start_new_run(GameFlow.get_active_run_definition())
	await _wait_frames(3)
	PauseManager.pause_requested.emit()
	await _wait_frames(3)
	_check(RunState.get_purchased_upgrade_entries().is_empty() and _upgrade_rows().is_empty(), "A new run removes old choices from state and visible rows")
	_check(_all_text().has("No upgrades chosen this run."), "A new run displays the honest empty history message")
	await _capture("pause_modifiers_empty_720p.png")

func _check_layout() -> void:
	await _wait_frames(3)
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var right: Rect2 = _panel.get_global_rect()
	var left: Rect2 = _pause.stat_panel.get_global_rect()
	var center: Rect2 = (_pause.get_node("ScreenRoot/CenterContainer/VBox") as Control).get_global_rect()
	_check(viewport.encloses(right) and viewport.encloses(left) and viewport.encloses(center), "Both panels and central actions fit the 1280x720 viewport")
	_check(not right.intersects(left) and not right.intersects(center) and not left.intersects(center), "Left statistics, central actions, and right history do not overlap")
	for node: Node in _panel.entries.find_children("*", "Label", true, false):
		var label: Label = node as Label
		_check(label.autowrap_mode != TextServer.AUTOWRAP_OFF and label.size.x <= right.size.x, "History names and descriptions wrap within the right panel")
	_check(_panel.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Long descriptions cannot create horizontal scrolling")

func _all_text() -> Array[String]:
	var texts: Array[String] = []
	for node: Node in _panel.entries.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	return texts

func _upgrade_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var in_upgrades: bool = false
	for node: Node in _panel.entries.get_children():
		if node is Label and (node as Label).text == "RUN UPGRADES":
			in_upgrades = true
		elif in_upgrades and node is VBoxContainer:
			var labels: Array[Label] = []
			for child: Node in node.get_children():
				if child is Label:
					labels.append(child as Label)
			if not labels.is_empty():
				rows.append({"name": labels[0].text, "description": labels[1].text if labels.size() > 1 else ""})
	return rows

func _capture(filename: String) -> void:
	if _output.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(not image.is_empty() and image.save_png(_output.path_join(filename)) == OK, "Rendered %s" % filename)

func _send_key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _wait_frames(2)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	Input.parse_input_event(event)
	await _wait_frames(2)

func _send_joy(button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await _wait_frames(2)
	event = InputEventJoypadButton.new()
	event.button_index = button
	Input.parse_input_event(event)
	await _wait_frames(2)

func _wait_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _mute_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("PAUSE_MODIFIERS_CHECKS: " + description)
