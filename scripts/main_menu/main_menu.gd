# main_menu.gd (Godot 4.5)
extends Control

signal practice_requested

@export var pilot_roster: PilotRoster
@export var default_pilot_index: int = 0

@onready var btn_practice: Button = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/PracticeContainer/Practice
@onready var btn_settings: Button = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/SettingsContainer/Settings
@onready var btn_exit: Button = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/ExitContainer/Exit
@onready var pilot_picker: OptionButton = $CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/PilotContainer/Row/PilotPicker
@onready var music: AudioStreamPlayer = $MenuMusic
var _available_pilots: Array[PilotDef] = []
var _music_tween: Tween

func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()
	btn_practice.pressed.connect(_on_practice_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_exit.pressed.connect(_on_exit_pressed)
	pilot_picker.item_selected.connect(_on_pilot_selected)
	_set_focus_modes()
	_refresh_pilot_picker()
	if visible and _has_connected_controller():
		call_deferred("_focus_default_control")

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
	_apply_current_pilot_selection()
	if GameFlow.selected_pilot == null or not GameFlow.is_pilot_unlocked(GameFlow.selected_pilot):
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
		pilot_picker.disabled = true
		btn_practice.disabled = true
		pilot_picker.add_item("Default")
		return

	var unlocked_indices: Array[int] = []
	pilot_picker.disabled = false
	for i in _available_pilots.size():
		var p: PilotDef = _available_pilots[i]
		var display_name: String = p.get_display_name_or_default() if p != null else "Unknown"
		var unlocked: bool = GameFlow.is_pilot_unlocked(p)
		if not unlocked:
			display_name = "%s (Locked)" % display_name
		pilot_picker.add_item(display_name)
		if not unlocked:
			pilot_picker.set_item_disabled(i, true)
		else:
			unlocked_indices.append(i)

	if unlocked_indices.is_empty():
		pilot_picker.disabled = true
		btn_practice.disabled = true
		pilot_picker.select(0)
		return

	btn_practice.disabled = false
	var idx: int = _resolve_initial_selection(unlocked_indices)
	pilot_picker.select(idx)
	_apply_current_pilot_selection()

func _on_pilot_selected(_index: int) -> void:
	_apply_current_pilot_selection()

func _apply_current_pilot_selection() -> void:
	if _available_pilots.is_empty():
		return
	var idx: int = pilot_picker.get_selected()
	if idx < 0 or idx >= _available_pilots.size() or not GameFlow.is_pilot_unlocked(_available_pilots[idx]):
		idx = _first_unlocked_index()
	if idx < 0:
		return
	if pilot_picker.get_selected() != idx:
		pilot_picker.select(idx)
	GameFlow.set_selected_pilot(_available_pilots[idx])

func _resolve_initial_selection(unlocked_indices: Array[int]) -> int:
	if GameFlow.selected_pilot != null:
		for i in unlocked_indices:
			if _available_pilots[i] == GameFlow.selected_pilot:
				return i
	var default_idx: int = clamp(default_pilot_index, 0, _available_pilots.size() - 1)
	if GameFlow.is_pilot_unlocked(_available_pilots[default_idx]):
		return default_idx
	return unlocked_indices[0]

func _first_unlocked_index() -> int:
	for i in _available_pilots.size():
		if GameFlow.is_pilot_unlocked(_available_pilots[i]):
			return i
	return -1

func _set_focus_modes() -> void:
	pilot_picker.focus_mode = Control.FOCUS_ALL
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
