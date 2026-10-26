# main_menu.gd (Godot 4.7.2)
extends Control

signal practice_requested
signal merc_practice_requested(run_definition: RunDefinition)
signal selection_changed

@export var pilot_roster: PilotRoster
@export var default_pilot_index: int = 0
## Deprecated fallback for older scenes; new practice runs use the faction selector.
@export var merc_practice_run: RunDefinition

@onready var btn_practice: Button = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/PracticeContainer/Practice
@onready var btn_merc_practice: Button = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/MercPracticeContainer/MercPractice
@onready var btn_upgrades: Button = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/UpgradesContainer/Upgrades
@onready var btn_settings: Button = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/SettingsContainer/Settings
@onready var btn_exit: Button = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/ExitContainer/Exit
@onready var pilot_picker: OptionButton = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/PilotContainer/Row/PilotPicker
@onready var ship_picker: OptionButton = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/ShipContainer/Row/ShipPicker
@onready var weapon_picker: OptionButton = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/WeaponContainer/Row/WeaponPicker
@onready var faction_picker: OptionButton = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/FactionContainer/Row/FactionPicker
@onready var faction_summary: Label = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/FactionSummary
@onready var version_label: Label = $VersionContainer/VersionLabel
@onready var music: AudioStreamPlayer = $MenuMusic
@onready var _upgrades_panel: UpgradesPanel = $UpgradesPanel
@onready var _center_container: CenterContainer = $CenterContainer
@onready var _high_score_container: Control = $HighScoreContainer
@onready var _flux_anchors_container: Control = $FluxAnchorsContainer
@onready var _roadmap_panel: PanelContainer = $RoadmapPanel
@onready var _version_container: PanelContainer = $VersionContainer
@onready var _buttons: VBoxContainer = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer
@onready var _play_button: Button = _buttons.get_node("PlayContainer/Play")
@onready var _hangar_button: Button = _buttons.get_node("HangarContainer/Hangar")
@onready var _information_button: Button = _buttons.get_node("InformationContainer/Information")
@onready var _enemies_button: Button = _buttons.get_node("EnemiesContainer/Enemies")
@onready var _weapons_button: Button = _buttons.get_node("WeaponsContainer/Weapons")
@onready var _ships_button: Button = _buttons.get_node("ShipsContainer/Ships")
@onready var _pilots_button: Button = _buttons.get_node("PilotsContainer/Pilots")
@onready var _information_panel: PanelContainer = $EnemyInformationPanel
@onready var _enemy_grid: EnemyInformationGrid = $EnemyInformationPanel/Margin/Content/EnemyGrid
@onready var _unlock_grid: UnlockInformationGrid = $EnemyInformationPanel/Margin/Content/UnlockGrid
@onready var _information_panel_close: Button = $EnemyInformationPanel/Margin/Content/Header/Close
@onready var _information_title: Label = $EnemyInformationPanel/Margin/Content/Header/Title
@onready var _information_legend: Label = $EnemyInformationPanel/Margin/Content/Legend
@onready var _information_details: InformationDetailsView = $EnemyInformationPanel/Margin/Content/Details
@onready var _information_details_back: Button = $EnemyInformationPanel/Margin/Content/Header/Back
@onready var _change_loadout: Button = _buttons.get_node("ChangeLoadoutContainer/ChangeLoadout")
@onready var _continue_button: Button = _buttons.get_node("ContinueContainer/ContinueToPlay")
@onready var _back_button: Button = _buttons.get_node("BackContainer/Back")
@onready var _section_title: Label = $CenterContainer/MainMenuContainer/SectionTitle
@onready var _section_description: Label = $CenterContainer/MainMenuContainer/SectionDescription
@onready var _loadout_summary: Label = _buttons.get_node("LoadoutSummary")
@onready var _hangar_details: Label = _buttons.get_node("HangarDetails")
@onready var _preview_caption: PanelContainer = $PreviewCaption
@onready var _preview_ship_name: Label = $PreviewCaption/Margin/Names/ShipName
@onready var _preview_pilot_name: Label = $PreviewCaption/Margin/Names/PilotName
@onready var _navigation_hint: Label = $NavigationHint
@onready var _hangar_viewport: SubViewport = $HangarBackground/HangarViewport
@onready var _hangar_preview: Node3D = $HangarBackground/HangarViewport/HangarPreview
@onready var _master_volume: HSlider = _buttons.get_node("SettingsControls/MasterVolume")
@onready var _volume_value: Label = _buttons.get_node("SettingsControls/VolumeLabel")
@onready var _fullscreen: CheckButton = _buttons.get_node("SettingsControls/Fullscreen")
@onready var _motion: CheckButton = _buttons.get_node("SettingsControls/Motion")
@onready var _camera_settings_button: Button = _buttons.get_node("SettingsControls/CameraSettings")
@onready var _camera_settings_panel: CameraSettingsPanel = $CameraSettingsPanel

const MENU_SETTINGS_PATH: String = "user://menu_settings.cfg"
const REFERENCE_PAGES: Array[StringName] = [&"enemies", &"weapons", &"ships", &"pilots"]
const INFORMATION_ROWS: Array[String] = ["EnemiesContainer", "WeaponsContainer", "ShipsContainer", "PilotsContainer", "BackContainer"]
const PAGE_ROWS: Dictionary = {
	&"home": ["PlayContainer", "HangarContainer", "UpgradesContainer", "InformationContainer", "SettingsContainer", "ExitContainer"],
	&"information": INFORMATION_ROWS,
	&"enemies": INFORMATION_ROWS,
	&"weapons": INFORMATION_ROWS,
	&"ships": INFORMATION_ROWS,
	&"pilots": INFORMATION_ROWS,
	&"play": ["LoadoutSummary", "ChangeLoadoutContainer", "FactionContainer", "FactionSummary", "PracticeContainer", "MercPracticeContainer", "BackContainer"],
	&"hangar": ["PilotContainer", "ShipContainer", "WeaponContainer", "HangarDetails", "ContinueContainer", "BackContainer"],
	&"settings": ["SettingsControls", "ControlsHelp", "BackContainer"],
}

var _available_pilots: Array[PilotDef] = []
var _available_ship_options: Array[PilotStarterShipOptionDef] = []
var _available_weapon_options: Array[ShipStarterWeaponOptionDef] = []
var _music_tween: Tween
var _suppress_picker_callbacks: bool = false
var _current_page: StringName = &"home"
var _menu_initialized: bool = false
var _details_source_button: Button = null
var _details_grid_scroll: int = 0
static var _remembered_practice_faction_id: StringName = &"random"

func _ready() -> void:
	_play_button.pressed.connect(show_page.bind(&"play"))
	_hangar_button.pressed.connect(show_page.bind(&"hangar"))
	_information_button.pressed.connect(show_page.bind(&"information"))
	_enemies_button.pressed.connect(show_page.bind(&"enemies"))
	_weapons_button.pressed.connect(show_page.bind(&"weapons"))
	_ships_button.pressed.connect(show_page.bind(&"ships"))
	_pilots_button.pressed.connect(show_page.bind(&"pilots"))
	_information_panel_close.pressed.connect(_close_information_panel)
	_information_details_back.pressed.connect(_return_to_information_grid)
	_enemy_grid.entry_selected.connect(_show_enemy_details)
	_unlock_grid.entry_selected.connect(_show_loadout_details)
	_change_loadout.pressed.connect(show_page.bind(&"hangar"))
	_continue_button.pressed.connect(show_page.bind(&"play"))
	_back_button.pressed.connect(_go_back)
	selection_changed.connect(_refresh_loadout_view)
	resized.connect(_update_responsive_layout)
	_center_container.minimum_size_changed.connect(_queue_responsive_layout)
	_load_menu_settings()
	_master_volume.value_changed.connect(_on_master_volume_changed)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_motion.toggled.connect(_on_motion_toggled)
	_camera_settings_button.pressed.connect(open_camera_settings)
	_camera_settings_panel.closed.connect(_on_camera_settings_closed)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()
	btn_practice.pressed.connect(_on_practice_pressed)
	btn_merc_practice.pressed.connect(_on_merc_practice_pressed)
	btn_upgrades.pressed.connect(_on_upgrades_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_exit.pressed.connect(_on_exit_pressed)
	pilot_picker.item_selected.connect(_on_pilot_selected)
	ship_picker.item_selected.connect(_on_ship_selected)
	weapon_picker.item_selected.connect(_on_weapon_selected)
	faction_picker.item_selected.connect(_on_faction_selected)
	_set_version_label()
	_style_information_panel_close()
	_set_focus_modes()
	_refresh_practice_faction_picker()
	_refresh_pilot_picker()
	_apply_current_pilot_selection(false)
	_menu_initialized = true
	_refresh_loadout_view(true)
	show_page(&"home")
	if visible and _has_connected_controller():
		call_deferred("_focus_default_control")
	_upgrades_panel.closed.connect(_on_upgrades_panel_closed)

func _style_information_panel_close() -> void:
	var reference: Button = _upgrades_panel.btn_close
	_information_panel_close.flat = reference.flat
	_information_panel_close.custom_minimum_size = reference.size
	_information_panel_close.add_theme_font_override("font", reference.get_theme_font("font"))
	_information_panel_close.add_theme_font_size_override("font_size", reference.get_theme_font_size("font_size"))
	# Use the meta panel's resolved appearance, including hover and focus states.
	for style_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		_information_panel_close.add_theme_stylebox_override(style_name, reference.get_theme_stylebox(style_name))
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_outline_color"]:
		_information_panel_close.add_theme_color_override(color_name, reference.get_theme_color(color_name))

func _set_version_label() -> void:
	var configured_version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if not configured_version.is_empty():
		version_label.text = configured_version

func _fade_in_music() -> void:
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(music, "volume_db", 0.0, 5.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_visibility_changed() -> void:
	if is_instance_valid(_hangar_preview):
		_hangar_preview.call("set_active", visible)
	if is_instance_valid(_hangar_viewport):
		_hangar_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	if visible:
		_start_music()
		if _has_connected_controller():
			call_deferred("_focus_default_control")
	else:
		_stop_music()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _upgrades_panel.visible or _camera_settings_panel.visible:
		return
	if _current_page == &"settings" and _handle_settings_key(event):
		get_viewport().set_input_as_handled()
		return
	if not _is_controller_event(event):
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	call_deferred("_focus_default_control")

func _handle_settings_key(event: InputEvent) -> bool:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed:
		return false
	var key: Key = key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
	var focused: Control = get_viewport().gui_get_focus_owner()
	if key == KEY_UP or key == KEY_DOWN or key == KEY_TAB:
		var controls: Array[Control] = _get_page_controls()
		var index: int = controls.find(focused)
		var backwards: bool = key == KEY_UP or (key == KEY_TAB and key_event.shift_pressed)
		index = posmod(index + (-1 if backwards else 1), controls.size())
		controls[index].grab_focus()
		return true
	if key == KEY_LEFT or key == KEY_RIGHT:
		var slider: HSlider = focused as HSlider
		if slider != null:
			slider.value += slider.step * (-1.0 if key == KEY_LEFT else 1.0)
		return true
	if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
		var button: Button = focused as Button
		if button != null and not key_event.echo:
			if button.toggle_mode:
				button.button_pressed = not button.button_pressed
			button.pressed.emit()
		return true
	if key == KEY_ESCAPE and not key_event.echo:
		show_page(&"home")
		return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _upgrades_panel.visible or _camera_settings_panel.visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and _current_page != &"home":
		_go_back()
		get_viewport().set_input_as_handled()

func _go_back() -> void:
	if _information_details.visible:
		_return_to_information_grid()
		return
	var previous_page: StringName = _current_page
	if REFERENCE_PAGES.has(previous_page):
		show_page(&"information")
		_focus_information_button.call_deferred(previous_page)
	else:
		show_page(&"home")

func _close_information_panel() -> void:
	var previous_page: StringName = _current_page
	show_page(&"information")
	_focus_information_button.call_deferred(previous_page)

func _show_enemy_details(definition: EnemyDef) -> void:
	if _current_page != &"enemies" or not _enemy_grid.is_visible_in_tree():
		return
	var key: String = "kills|enemy|" + definition.id
	if GameFlow.get_meta_stat_value(GameFlow.META_STAT_KILLS, &"", key) <= 0:
		return
	var entry: Dictionary = EnemyInformationDetails.for_enemy(definition)
	if entry.is_empty():
		return
	for button: Button in _enemy_grid.get_entry_buttons():
		if String(button.get_meta(&"enemy_id", "")) == definition.id:
			_show_information_details(entry, button, "ENEMY DETAILS")
			return

func _show_loadout_details(category: StringName, record: Dictionary, source: Button) -> void:
	if category != _current_page or not _unlock_grid.is_visible_in_tree():
		return
	var entry: Dictionary = {}
	var unlocked: bool = bool(record.get("unlocked", false))
	var unlock_text: String = String(record.get("unlock_text", ""))
	if category == &"weapons":
		entry = LoadoutInformationDetails.for_weapon(record.get("definition") as WeaponDef, unlocked, unlock_text)
	elif category == &"ships":
		entry = LoadoutInformationDetails.for_ship(record.get("definition") as ShipDef, unlocked, unlock_text)
	if not entry.is_empty():
		_show_information_details(entry, source, "WEAPON DETAILS" if category == &"weapons" else "SHIP DETAILS")

func _show_information_details(entry: Dictionary, source: Button, title: String) -> void:
	_details_source_button = source
	_details_grid_scroll = _get_information_grid().scroll_vertical
	_information_details.show_entry(entry)
	_get_information_grid().hide()
	_information_legend.hide()
	_information_title.text = title
	_information_details_back.show()
	_information_details.show()
	_wire_page_focus()
	_information_details_back.grab_focus()

func _return_to_information_grid() -> void:
	if not _information_details.visible:
		return
	_information_details.hide()
	_information_details_back.hide()
	_information_legend.show()
	_information_title.text = String(_current_page).to_upper()
	_get_information_grid().show()
	_wire_page_focus()
	_restore_details_source_focus.call_deferred()

func _restore_details_source_focus() -> void:
	if not _information_panel.is_visible_in_tree() or _information_details.visible:
		return
	_get_information_grid().scroll_vertical = _details_grid_scroll
	if is_instance_valid(_details_source_button) and _details_source_button.is_visible_in_tree():
		_details_source_button.grab_focus()

func _get_information_button(page: StringName) -> Button:
	match page:
		&"weapons":
			return _weapons_button
		&"ships":
			return _ships_button
		&"pilots":
			return _pilots_button
	return _enemies_button

func _focus_information_button(page: StringName) -> void:
	if visible and _current_page == &"information":
		_get_information_button(page).grab_focus()

func _get_information_grid() -> InformationIconGrid:
	return _enemy_grid if _current_page == &"enemies" else _unlock_grid

func get_current_page() -> StringName:
	return _current_page

func show_page(page: StringName) -> void:
	if not PAGE_ROWS.has(page):
		return
	_current_page = page
	if not is_node_ready():
		return
	_information_details.hide()
	_information_details_back.hide()
	_information_legend.show()
	_details_source_button = null
	var rows: Array = PAGE_ROWS[page]
	for child: Node in _buttons.get_children():
		var control: Control = child as Control
		if control != null:
			control.visible = rows.has(String(control.name))
	match page:
		&"play":
			_section_title.text = "DEPLOY"
			_section_description.text = "Two-stage Campaign or a short Practice encounter."
		&"hangar":
			_section_title.text = "HANGAR / LOADOUT"
			_section_description.text = "Choose a pilot, hull and starting weapon. Build the rest out there."
		&"settings":
			_section_title.text = "SETTINGS"
			_section_description.text = "Display, audio, flight camera and hangar motion."
		&"information", &"enemies", &"weapons", &"ships", &"pilots":
			_section_title.text = "INFORMATION"
			_section_description.text = "Enemies, weapons, ships and pilots."
		_:
			_section_title.text = "READY FOR DEPARTURE"
			_section_description.text = "Choose your loadout. Find your edge. Break through."
	var reference_open: bool = REFERENCE_PAGES.has(page)
	_information_panel.visible = reference_open
	_preview_caption.visible = not reference_open
	_enemy_grid.visible = page == &"enemies"
	_unlock_grid.visible = reference_open and page != &"enemies"
	if reference_open:
		_information_title.text = String(page).to_upper()
		_information_panel_close.tooltip_text = "Close %s information" % String(page)
		if page == &"enemies":
			_information_legend.text = "? Not yet killed     ! Killed"
			_enemy_grid.refresh()
		else:
			_information_legend.text = "? Locked     ! Unlocked"
			_unlock_grid.refresh(page, pilot_roster)
	_refresh_loadout_view()
	_wire_page_focus()
	_queue_responsive_layout()
	call_deferred("_focus_default_control")

func _refresh_loadout_view(immediate: bool = false) -> void:
	if not _menu_initialized:
		return
	var pilot: PilotDef = GameFlow.selected_pilot
	var ship: ShipDef = GameFlow.get_selected_ship()
	var weapon: WeaponDef = GameFlow.get_selected_weapon()
	if _available_pilots.is_empty() or pilot == null or not GameFlow.is_pilot_unlocked(pilot):
		pilot = null
		ship = null
		weapon = null
	var pilot_name: String = pilot.get_display_name_or_default() if pilot != null else "No pilot selected"
	var ship_name: String = ship.get_display_name_or_default() if ship != null else "No ship selected"
	var weapon_name: String = weapon.get_display_name_or_default() if weapon != null else "No weapon selected"
	_loadout_summary.text = "%s  /  %s\n%s" % [pilot_name, ship_name, weapon_name]
	_preview_ship_name.text = ship_name.to_upper()
	_preview_pilot_name.text = "%s  /  %s" % [pilot_name, weapon_name]
	var details: String = pilot.description.strip_edges() if pilot != null else "Unlock a pilot to prepare a loadout."
	if ship != null:
		details += "\n\nBASE HULL  %d    SHIELD  %d    SPEED  %d" % [int(ship.max_hull), int(ship.max_shield), int(ship.max_speed_forward)]
	_hangar_details.text = details
	_continue_button.disabled = btn_practice.disabled
	_hangar_preview.call("set_selection", pilot, ship, immediate)

func _queue_responsive_layout() -> void:
	# Container minimums settle after rows are shown or hidden, including the
	# first frame before the player has ever resized the window.
	call_deferred("_update_responsive_layout")

func _update_responsive_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var panel_width: float = clampf(viewport_size.x * 0.36, 390.0, 510.0)
	var margin: float = clampf(viewport_size.x * 0.04, 24.0, 72.0)
	var column: Control = _center_container.get_node("MainMenuContainer") as Control
	column.custom_minimum_size.x = panel_width
	var top_margin: float = clampf(viewport_size.y - 70.0 - column.get_combined_minimum_size().y, 50.0, 75.0)
	_center_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_center_container.position = Vector2(margin, top_margin)
	_center_container.size = Vector2(panel_width, maxf(viewport_size.y - top_margin - 70.0, 480.0))
	var logo: Sprite2D = column.get_node("TitleContainer/Logo") as Sprite2D
	logo.position = Vector2(panel_width * 0.5 - 118.0, 37.0)
	var right_start: float = margin + maxf(panel_width, column.get_combined_minimum_size().x) + 24.0
	_information_panel.position = Vector2(right_start, top_margin)
	_information_panel.size = Vector2(maxf(viewport_size.x - margin - right_start, 0.0), maxf(viewport_size.y - top_margin - 70.0, 0.0))

func _get_page_controls() -> Array[Control]:
	match _current_page:
		&"play":
			return [_change_loadout, faction_picker, btn_practice, btn_merc_practice, _back_button]
		&"hangar":
			return [pilot_picker, ship_picker, weapon_picker, _continue_button, _back_button]
		&"settings":
			return [_master_volume, _fullscreen, _motion, _camera_settings_button, _back_button]
		&"information":
			return [_enemies_button, _weapons_button, _ships_button, _pilots_button, _back_button]
		&"enemies", &"weapons", &"ships", &"pilots":
			var controls: Array[Control] = []
			if _information_details.visible:
				controls.assign([_information_details_back, _information_details])
			else:
				controls.assign(_get_information_grid().get_entry_buttons())
			controls.append_array([_information_panel_close, _enemies_button, _weapons_button, _ships_button, _pilots_button, _back_button])
			return controls
	return [_play_button, _hangar_button, btn_upgrades, _information_button, btn_settings, btn_exit]

func _wire_page_focus() -> void:
	var controls: Array[Control] = []
	var page_controls: Array[Control] = _get_page_controls()
	if REFERENCE_PAGES.has(_current_page):
		page_controls = [_enemies_button, _weapons_button, _ships_button, _pilots_button, _back_button]
	for control: Control in page_controls:
		var button: BaseButton = control as BaseButton
		if control.is_visible_in_tree() and (button == null or not button.disabled):
			controls.append(control)
	for index: int in controls.size():
		var control: Control = controls[index]
		var previous: Control = controls[(index - 1 + controls.size()) % controls.size()]
		var next: Control = controls[(index + 1) % controls.size()]
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_previous = control.get_path_to(previous)
		control.focus_neighbor_bottom = control.get_path_to(next)
		control.focus_next = control.get_path_to(next)
		control.focus_neighbor_left = NodePath("")
		control.focus_neighbor_right = NodePath("")
	if REFERENCE_PAGES.has(_current_page):
		var category_button: Button = _get_information_button(_current_page)
		if _information_details.visible:
			_information_details.wire_focus(_information_details_back, _information_panel_close, category_button)
			for control: Control in controls:
				control.focus_neighbor_right = control.get_path_to(_information_details_back)
			return
		for property_name: StringName in [&"focus_neighbor_top", &"focus_neighbor_bottom", &"focus_neighbor_left", &"focus_previous", &"focus_next"]:
			_information_panel_close.set(property_name, _information_panel_close.get_path_to(category_button))
		_information_panel_close.focus_neighbor_right = _information_panel_close.get_path_to(_information_panel_close)
		var grid: InformationIconGrid = _get_information_grid()
		grid.wire_focus(_information_panel_close, category_button)
		var entries: Array[Button] = grid.get_entry_buttons()
		var first: Button = entries.front() if not entries.is_empty() else _information_panel_close
		for control: Control in controls:
			control.focus_neighbor_right = control.get_path_to(first)

func _load_menu_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(MENU_SETTINGS_PATH)
	var volume: float = clampf(float(config.get_value("audio", "master_volume", AudioServer.get_bus_volume_linear(0))), 0.0, 1.0)
	_master_volume.set_value_no_signal(volume * 100.0)
	_volume_value.text = "MASTER VOLUME   %d%%" % int(roundf(volume * 100.0))
	AudioServer.set_bus_volume_linear(0, volume)
	var fullscreen: bool = bool(config.get_value("display", "fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN))
	_fullscreen.set_pressed_no_signal(fullscreen)
	if DisplayServer.get_name() != "headless" and config.has_section_key("display", "fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	var animate: bool = bool(config.get_value("display", "hangar_motion", true))
	_motion.set_pressed_no_signal(animate)
	_hangar_preview.call("set_motion_enabled", animate)

func _save_menu_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "master_volume", _master_volume.value / 100.0)
	config.set_value("display", "fullscreen", _fullscreen.button_pressed)
	config.set_value("display", "hangar_motion", _motion.button_pressed)
	config.save(MENU_SETTINGS_PATH)

func _on_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_linear(0, value / 100.0)
	_volume_value.text = "MASTER VOLUME   %d%%" % int(roundf(value))
	_save_menu_settings()

func _on_fullscreen_toggled(enabled: bool) -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	_save_menu_settings()

func _on_motion_toggled(enabled: bool) -> void:
	_hangar_preview.call("set_motion_enabled", enabled)
	_save_menu_settings()

func _start_music() -> void:
	music.volume_db = -80.0
	if not music.playing:
		music.play()
	_fade_in_music()

func _stop_music() -> void:
	if _music_tween != null:
		_music_tween.kill()
		_music_tween = null
	if music.playing:
		music.stop()

func _on_practice_pressed() -> void:
	_apply_current_pilot_selection(false)
	if GameFlow.selected_pilot == null or not GameFlow.is_pilot_unlocked(GameFlow.selected_pilot):
		return
	if GameFlow.get_selected_ship() == null or GameFlow.get_selected_weapon() == null:
		return
	practice_requested.emit()

func _on_merc_practice_pressed() -> void:
	_apply_current_pilot_selection(false)
	if btn_practice.disabled:
		return
	var run_definition: RunDefinition = build_practice_run(true)
	if run_definition == null:
		return
	merc_practice_requested.emit(run_definition)

func set_practice_faction_id(faction_id: StringName) -> void:
	var selected_id: StringName = &"random"
	for definition: PracticeFactionDef in PracticeRunFactory.get_factions():
		if definition != null and definition.faction != null and definition.faction.get_faction_id() == faction_id:
			selected_id = faction_id
			break
	_remembered_practice_faction_id = selected_id
	if is_node_ready():
		_select_practice_faction_item()
		_update_practice_faction_summary()

func get_practice_faction_id() -> StringName:
	return _remembered_practice_faction_id

func build_practice_run(short_practice: bool = false) -> RunDefinition:
	# Build once when launching, so Random cannot change between stages.
	var run_definition: RunDefinition = PracticeRunFactory.create_run(get_practice_faction_id(), short_practice)
	if run_definition == null and short_practice:
		return merc_practice_run
	return run_definition

func _refresh_practice_faction_picker() -> void:
	faction_picker.clear()
	faction_picker.add_item("Random")
	faction_picker.set_item_metadata(0, &"random")
	for definition: PracticeFactionDef in PracticeRunFactory.get_factions():
		if definition == null or definition.faction == null:
			continue
		var faction: FactionDef = definition.faction
		faction_picker.add_item(faction.get_display_name_or_default())
		faction_picker.set_item_metadata(faction_picker.item_count - 1, faction.get_faction_id())
	_select_practice_faction_item()
	_update_practice_faction_summary()

func _select_practice_faction_item() -> void:
	var selected_index: int = 0
	for index: int in faction_picker.item_count:
		if StringName(faction_picker.get_item_metadata(index)) == _remembered_practice_faction_id:
			selected_index = index
			break
	_remembered_practice_faction_id = StringName(faction_picker.get_item_metadata(selected_index))
	_select_picker_index(faction_picker, selected_index)

func _on_faction_selected(index: int) -> void:
	if _suppress_picker_callbacks or index < 0 or index >= faction_picker.item_count:
		return
	_remembered_practice_faction_id = StringName(faction_picker.get_item_metadata(index))
	_update_practice_faction_summary()

func _update_practice_faction_summary() -> void:
	if get_practice_faction_id() == &"random":
		faction_summary.text = "Random chooses one faction for the entire run."
	else:
		faction_summary.text = "%s for the entire run." % faction_picker.get_item_text(faction_picker.get_selected())

func _on_settings_pressed() -> void:
	show_page(&"settings")

func open_camera_settings() -> void:
	_camera_settings_panel.open_panel()

func _on_camera_settings_closed() -> void:
	if visible and _camera_settings_button.is_visible_in_tree():
		_camera_settings_button.grab_focus()

func _on_upgrades_pressed() -> void:
	_set_main_menu_content_visible(false)
	_upgrades_panel.show_panel()

func _on_upgrades_panel_closed() -> void:
	_set_main_menu_content_visible(true)
	_wire_page_focus()
	if btn_upgrades.is_visible_in_tree():
		btn_upgrades.grab_focus()
	else:
		_focus_default_control()

func _set_main_menu_content_visible(p_visible: bool) -> void:
	_center_container.visible = p_visible
	_high_score_container.visible = p_visible
	_flux_anchors_container.visible = p_visible
	_roadmap_panel.visible = false
	_version_container.visible = p_visible
	_preview_caption.visible = p_visible
	_navigation_hint.visible = p_visible

func _on_exit_pressed() -> void:
	get_tree().quit()

func _refresh_pilot_picker() -> void:
	pilot_picker.clear()
	_available_pilots = pilot_roster.get_pilots() if pilot_roster != null else []
	if _available_pilots.is_empty():
		_set_picker_placeholder(pilot_picker, "Default", true)
		_clear_ship_picker()
		_clear_weapon_picker()
		_update_practice_enabled()
		return

	var unlocked_indices: Array[int] = []
	pilot_picker.disabled = false
	for i in _available_pilots.size():
		var pilot: PilotDef = _available_pilots[i]
		var display_name: String = pilot.get_display_name_or_default() if pilot != null else "Unknown"
		var unlocked: bool = GameFlow.is_pilot_unlocked(pilot)
		if not unlocked:
			display_name = "%s (Locked)" % display_name
		pilot_picker.add_item(display_name)
		if not unlocked:
			pilot_picker.set_item_disabled(i, true)
		else:
			unlocked_indices.append(i)

	if unlocked_indices.is_empty():
		pilot_picker.disabled = true
		_select_picker_index(pilot_picker, 0)
		_clear_ship_picker()
		_clear_weapon_picker()
		_update_practice_enabled()
		return

	var idx: int = _resolve_initial_pilot_selection(unlocked_indices)
	_select_picker_index(pilot_picker, idx)

func _refresh_ship_picker() -> void:
	ship_picker.clear()
	_available_ship_options = []
	var pilot: PilotDef = GameFlow.selected_pilot
	if pilot == null:
		_clear_ship_picker()
		_clear_weapon_picker()
		_update_practice_enabled()
		return

	_available_ship_options = GameFlow.get_starter_ship_options(pilot)
	if _available_ship_options.is_empty():
		_clear_ship_picker()
		_clear_weapon_picker()
		_update_practice_enabled()
		return

	var unlocked_indices: Array[int] = []
	ship_picker.disabled = false
	for i in _available_ship_options.size():
		var option: PilotStarterShipOptionDef = _available_ship_options[i]
		var display_name: String = option.get_display_name_or_default() if option != null else "Unknown"
		var unlocked: bool = GameFlow.is_ship_option_unlocked(option)
		if not unlocked:
			display_name = "%s (Locked)" % display_name
		ship_picker.add_item(display_name)
		if not unlocked:
			ship_picker.set_item_disabled(i, true)
		else:
			unlocked_indices.append(i)

	if unlocked_indices.is_empty():
		ship_picker.disabled = true
		_select_picker_index(ship_picker, 0)
		_clear_weapon_picker()
		_update_practice_enabled()
		return

	var idx: int = _resolve_current_ship_index(unlocked_indices)
	_select_picker_index(ship_picker, idx)

func _refresh_weapon_picker() -> void:
	weapon_picker.clear()
	_available_weapon_options = []
	var ship: ShipDef = GameFlow.get_selected_ship()
	if ship == null:
		_clear_weapon_picker()
		_update_practice_enabled()
		return

	_available_weapon_options = GameFlow.get_starter_weapon_options(ship)
	if _available_weapon_options.is_empty():
		_clear_weapon_picker()
		_update_practice_enabled()
		return

	var unlocked_indices: Array[int] = []
	weapon_picker.disabled = false
	for i in _available_weapon_options.size():
		var option: ShipStarterWeaponOptionDef = _available_weapon_options[i]
		var display_name: String = option.get_display_name_or_default() if option != null else "Unknown"
		var unlocked: bool = GameFlow.is_weapon_option_unlocked(option)
		if not unlocked:
			display_name = "%s (Locked)" % display_name
		weapon_picker.add_item(display_name)
		if not unlocked:
			weapon_picker.set_item_disabled(i, true)
		else:
			unlocked_indices.append(i)

	if unlocked_indices.is_empty():
		weapon_picker.disabled = true
		_select_picker_index(weapon_picker, 0)
		_update_practice_enabled()
		return

	var idx: int = _resolve_current_weapon_index(unlocked_indices)
	_select_picker_index(weapon_picker, idx)

func _clear_ship_picker() -> void:
	_available_ship_options.clear()
	_set_picker_placeholder(ship_picker, "No Ships", true)

func _clear_weapon_picker() -> void:
	_available_weapon_options.clear()
	_set_picker_placeholder(weapon_picker, "No Weapons", true)

func _set_picker_placeholder(picker: OptionButton, label: String, disabled: bool) -> void:
	picker.clear()
	picker.add_item(label)
	picker.disabled = disabled
	_select_picker_index(picker, 0)

func _on_pilot_selected(_index: int) -> void:
	if _suppress_picker_callbacks:
		return
	_apply_current_pilot_selection()

func _on_ship_selected(_index: int) -> void:
	if _suppress_picker_callbacks:
		return
	_apply_current_ship_selection()

func _on_weapon_selected(_index: int) -> void:
	if _suppress_picker_callbacks:
		return
	_apply_current_weapon_selection()

func _apply_current_pilot_selection(emit_menu_signal: bool = true) -> void:
	if _available_pilots.is_empty():
		_clear_ship_picker()
		_clear_weapon_picker()
		_update_practice_enabled()
		if emit_menu_signal:
			selection_changed.emit()
		return

	var idx: int = pilot_picker.get_selected()
	if idx < 0 or idx >= _available_pilots.size() or not GameFlow.is_pilot_unlocked(_available_pilots[idx]):
		idx = _first_unlocked_pilot_index()
	if idx < 0:
		_clear_ship_picker()
		_clear_weapon_picker()
		_update_practice_enabled()
		if emit_menu_signal:
			selection_changed.emit()
		return

	if pilot_picker.get_selected() != idx:
		_select_picker_index(pilot_picker, idx)
	GameFlow.set_selected_pilot(_available_pilots[idx])
	_refresh_ship_picker()
	_apply_current_ship_selection(emit_menu_signal)

func _apply_current_ship_selection(emit_menu_signal: bool = true) -> void:
	if _available_ship_options.is_empty():
		_clear_weapon_picker()
		_update_practice_enabled()
		if emit_menu_signal:
			selection_changed.emit()
		return

	var idx: int = ship_picker.get_selected()
	if idx < 0 or idx >= _available_ship_options.size() or not GameFlow.is_ship_option_unlocked(_available_ship_options[idx]):
		idx = _first_unlocked_ship_index()
	if idx < 0:
		_clear_weapon_picker()
		_update_practice_enabled()
		if emit_menu_signal:
			selection_changed.emit()
		return

	if ship_picker.get_selected() != idx:
		_select_picker_index(ship_picker, idx)
	GameFlow.set_selected_ship(_available_ship_options[idx].ship)
	_refresh_weapon_picker()
	_apply_current_weapon_selection(emit_menu_signal)

func _apply_current_weapon_selection(emit_menu_signal: bool = true) -> void:
	if _available_weapon_options.is_empty():
		_update_practice_enabled()
		if emit_menu_signal:
			selection_changed.emit()
		return

	var idx: int = weapon_picker.get_selected()
	if idx < 0 or idx >= _available_weapon_options.size() or not GameFlow.is_weapon_option_unlocked(_available_weapon_options[idx]):
		idx = _first_unlocked_weapon_index()
	if idx < 0:
		_update_practice_enabled()
		if emit_menu_signal:
			selection_changed.emit()
		return

	if weapon_picker.get_selected() != idx:
		_select_picker_index(weapon_picker, idx)
	GameFlow.set_selected_weapon(_available_weapon_options[idx].weapon)
	_update_practice_enabled()
	if emit_menu_signal:
		selection_changed.emit()

func _resolve_initial_pilot_selection(unlocked_indices: Array[int]) -> int:
	if GameFlow.selected_pilot != null:
		for i in unlocked_indices:
			if _available_pilots[i] == GameFlow.selected_pilot:
				return i
	var default_idx: int = clamp(default_pilot_index, 0, _available_pilots.size() - 1)
	if GameFlow.is_pilot_unlocked(_available_pilots[default_idx]):
		return default_idx
	return unlocked_indices[0]

func _resolve_current_ship_index(unlocked_indices: Array[int]) -> int:
	var current_ship: ShipDef = GameFlow.get_selected_ship()
	if current_ship != null:
		for i in unlocked_indices:
			var option: PilotStarterShipOptionDef = _available_ship_options[i]
			if option != null and option.ship == current_ship:
				return i
	return unlocked_indices[0]

func _resolve_current_weapon_index(unlocked_indices: Array[int]) -> int:
	var current_weapon: WeaponDef = GameFlow.get_selected_weapon()
	if current_weapon != null:
		for i in unlocked_indices:
			var option: ShipStarterWeaponOptionDef = _available_weapon_options[i]
			if option != null and option.weapon == current_weapon:
				return i
	return unlocked_indices[0]

func _first_unlocked_pilot_index() -> int:
	for i in _available_pilots.size():
		if GameFlow.is_pilot_unlocked(_available_pilots[i]):
			return i
	return -1

func _first_unlocked_ship_index() -> int:
	for i in _available_ship_options.size():
		if GameFlow.is_ship_option_unlocked(_available_ship_options[i]):
			return i
	return -1

func _first_unlocked_weapon_index() -> int:
	for i in _available_weapon_options.size():
		if GameFlow.is_weapon_option_unlocked(_available_weapon_options[i]):
			return i
	return -1

func _select_picker_index(picker: OptionButton, idx: int) -> void:
	_suppress_picker_callbacks = true
	picker.select(idx)
	_suppress_picker_callbacks = false

func _update_practice_enabled() -> void:
	btn_practice.disabled = (
		GameFlow.selected_pilot == null
		or not GameFlow.is_pilot_unlocked(GameFlow.selected_pilot)
		or GameFlow.get_selected_ship() == null
		or GameFlow.get_selected_weapon() == null
	)
	btn_merc_practice.disabled = btn_practice.disabled

func _set_focus_modes() -> void:
	pilot_picker.focus_mode = Control.FOCUS_ALL
	ship_picker.focus_mode = Control.FOCUS_ALL
	weapon_picker.focus_mode = Control.FOCUS_ALL
	faction_picker.focus_mode = Control.FOCUS_ALL
	btn_upgrades.focus_mode = Control.FOCUS_ALL
	btn_practice.focus_mode = Control.FOCUS_ALL
	btn_merc_practice.focus_mode = Control.FOCUS_ALL
	btn_settings.focus_mode = Control.FOCUS_ALL
	btn_exit.focus_mode = Control.FOCUS_ALL
	for control: Control in [_play_button, _hangar_button, _information_button, _enemies_button, _weapons_button, _ships_button, _pilots_button, _information_panel_close, _information_details_back, _change_loadout, _continue_button, _back_button, _master_volume, _fullscreen, _motion, _camera_settings_button]:
		control.focus_mode = Control.FOCUS_ALL

func _focus_default_control() -> void:
	if not visible or _upgrades_panel.visible or _camera_settings_panel.visible:
		return
	for control: Control in _get_page_controls():
		var button: BaseButton = control as BaseButton
		if control.is_visible_in_tree() and (button == null or not button.disabled):
			control.grab_focus()
			return

func _has_connected_controller() -> bool:
	return Input.get_connected_joypads().size() > 0

func _is_controller_event(event: InputEvent) -> bool:
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null:
		return joy_button.pressed
	var joy_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	return joy_motion != null and absf(joy_motion.axis_value) >= 0.5
