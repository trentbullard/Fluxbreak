# main_menu.gd (Godot 4.5)
extends Control

signal practice_requested
signal selection_changed

@export var pilot_roster: PilotRoster
@export var default_pilot_index: int = 0

@onready var btn_practice: Button = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/PracticeContainer/Practice
@onready var btn_settings: Button = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/SettingsContainer/Settings
@onready var btn_exit: Button = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/ExitContainer/Exit
@onready var pilot_picker: OptionButton = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/PilotContainer/Row/PilotPicker
@onready var ship_picker: OptionButton = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/ShipContainer/Row/ShipPicker
@onready var weapon_picker: OptionButton = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/WeaponContainer/Row/WeaponPicker
@onready var version_label: Label = $VersionContainer/VersionLabel
@onready var music: AudioStreamPlayer = $MenuMusic

var _available_pilots: Array[PilotDef] = []
var _available_ship_options: Array[PilotStarterShipOptionDef] = []
var _available_weapon_options: Array[ShipStarterWeaponOptionDef] = []
var _music_tween: Tween
var _suppress_picker_callbacks: bool = false

func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()
	btn_practice.pressed.connect(_on_practice_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_exit.pressed.connect(_on_exit_pressed)
	pilot_picker.item_selected.connect(_on_pilot_selected)
	ship_picker.item_selected.connect(_on_ship_selected)
	weapon_picker.item_selected.connect(_on_weapon_selected)
	_set_version_label()
	_set_focus_modes()
	_refresh_pilot_picker()
	_apply_current_pilot_selection(false)
	if visible and _has_connected_controller():
		call_deferred("_focus_default_control")

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
	if visible:
		_start_music()
		if _has_connected_controller():
			call_deferred("_focus_default_control")
	else:
		_stop_music()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not _is_controller_event(event):
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	call_deferred("_focus_default_control")

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

func _on_settings_pressed() -> void:
	print("Settings clicked — not implemented yet.")

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

func _set_focus_modes() -> void:
	pilot_picker.focus_mode = Control.FOCUS_ALL
	ship_picker.focus_mode = Control.FOCUS_ALL
	weapon_picker.focus_mode = Control.FOCUS_ALL
	btn_practice.focus_mode = Control.FOCUS_ALL
	btn_settings.focus_mode = Control.FOCUS_ALL
	btn_exit.focus_mode = Control.FOCUS_ALL

func _focus_default_control() -> void:
	if not visible:
		return
	if not btn_practice.disabled:
		btn_practice.grab_focus()
		return
	if not pilot_picker.disabled:
		pilot_picker.grab_focus()
		return
	if not ship_picker.disabled:
		ship_picker.grab_focus()
		return
	if not weapon_picker.disabled:
		weapon_picker.grab_focus()
		return
	if not btn_settings.disabled:
		btn_settings.grab_focus()
		return
	if not btn_exit.disabled:
		btn_exit.grab_focus()

func _has_connected_controller() -> bool:
	return Input.get_connected_joypads().size() > 0

func _is_controller_event(event: InputEvent) -> bool:
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null:
		return joy_button.pressed
	var joy_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	return joy_motion != null and absf(joy_motion.axis_value) >= 0.5
