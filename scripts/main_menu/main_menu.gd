# main_menu.gd (Godot 4.5)
extends Control

@export var practice_scene: PackedScene
@export var pilot_roster: PilotRoster
@export var default_pilot_index: int = 0

@onready var btn_practice: Button = $CenterContainer/MainMenuContainer/ButtonsContainer/PracticeContainer/MarginContainer/Practice
@onready var btn_settings: Button = $CenterContainer/MainMenuContainer/ButtonsContainer/SettingsContainer/MarginContainer/Settings
@onready var btn_exit: Button = $CenterContainer/MainMenuContainer/ButtonsContainer/ExitContainer/Exit
@onready var pilot_picker: OptionButton = $CenterContainer/MainMenuContainer/ButtonsContainer/PilotContainer/MarginContainer/Row/PilotPicker

func _ready() -> void:
	btn_practice.pressed.connect(_on_practice_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_exit.pressed.connect(_on_exit_pressed)
	pilot_picker.item_selected.connect(_on_pilot_selected)
	_refresh_pilot_picker()

func _on_practice_pressed() -> void:
	if practice_scene != null:
		_apply_current_pilot_selection()
		get_tree().change_scene_to_packed(practice_scene)

func _on_settings_pressed() -> void:
	print("Settings clicked — not implemented yet.")

func _on_exit_pressed() -> void:
	get_tree().quit()

func _refresh_pilot_picker() -> void:
	pilot_picker.clear()
	if pilot_roster == null or pilot_roster.pilots.is_empty():
		pilot_picker.disabled = true
		pilot_picker.add_item("Default")
		return

	pilot_picker.disabled = false
	for p in pilot_roster.pilots:
		var display_name: String = p.display_name if p != null else "Unknown"
		pilot_picker.add_item(display_name)

	var idx: int = clamp(default_pilot_index, 0, pilot_roster.pilots.size() - 1)
	pilot_picker.select(idx)
	_apply_current_pilot_selection()

func _on_pilot_selected(_index: int) -> void:
	_apply_current_pilot_selection()

func _apply_current_pilot_selection() -> void:
	if pilot_roster == null or pilot_roster.pilots.is_empty():
		return
	var idx: int = pilot_picker.get_selected_id()
	if idx < 0 or idx >= pilot_roster.pilots.size():
		idx = clamp(default_pilot_index, 0, pilot_roster.pilots.size() - 1)
	GameFlow.selected_pilot = pilot_roster.pilots[idx]
