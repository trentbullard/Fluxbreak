# main_menu.gd (Godot 4.5)
extends Control

@export var practice_scene: PackedScene

@onready var btn_practice: Button = $CenterContainer/MainMenuContainer/ButtonsContainer/PracticeContainer/MarginContainer/Practice
@onready var btn_settings: Button = $CenterContainer/MainMenuContainer/ButtonsContainer/SettingsContainer/MarginContainer/Settings
@onready var btn_exit: Button = $CenterContainer/MainMenuContainer/ButtonsContainer/ExitContainer/Exit

func _ready() -> void:
	btn_practice.pressed.connect(_on_practice_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_exit.pressed.connect(_on_exit_pressed)

func _on_practice_pressed() -> void:
	if practice_scene != null:
		get_tree().change_scene_to_packed(practice_scene)

func _on_settings_pressed() -> void:
	print("Settings clicked — not implemented yet.")

func _on_exit_pressed() -> void:
	get_tree().quit()
