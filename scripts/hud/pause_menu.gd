# scripts/hud/pause_menu.gd (godot 4.5)
extends CanvasLayer
class_name PauseMenu

@onready var root: Control = $ScreenRoot
@onready var btn_resume: Button = $ScreenRoot/CenterContainer/VBox/Resume
@onready var btn_restart: Button = $ScreenRoot/CenterContainer/VBox/Restart
@onready var btn_menu: Button = $ScreenRoot/CenterContainer/VBox/MainMenu
@onready var btn_quit: Button = $ScreenRoot/CenterContainer/VBox/Quit
@onready var stat_panel: StatPanel = $ScreenRoot/StatPanel

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	_set_focus_modes()
	btn_resume.pressed.connect(_on_resume_clicked)
	btn_restart.pressed.connect(_on_restart_clicked)
	btn_menu.pressed.connect(_on_menu_clicked)
	btn_quit.pressed.connect(_on_quit_clicked)
	
	PauseManager.paused_changed.connect(_on_paused_changed)

func _on_paused_changed(is_paused: bool) -> void:
	visible = is_paused
	if is_paused:
		btn_resume.grab_focus()
		if stat_panel != null:
			stat_panel.refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _is_controller_event(event) and get_viewport().gui_get_focus_owner() == null:
		_set_focus_modes()
		btn_resume.grab_focus()
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		PauseManager.resume_requested.emit()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not _is_controller_event(event):
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	btn_resume.grab_focus()

func _on_resume_clicked() -> void:
	PauseManager.resume_requested.emit()

func _on_restart_clicked() -> void:
	visible = false
	PauseManager.restart_requested.emit()

func _on_menu_clicked() -> void:
	visible = false
	PauseManager.menu_requested.emit()

func _on_quit_clicked() -> void:
	PauseManager.quit_requested.emit()

func _set_focus_modes() -> void:
	btn_resume.focus_mode = Control.FOCUS_ALL
	btn_restart.focus_mode = Control.FOCUS_ALL
	btn_menu.focus_mode = Control.FOCUS_ALL
	btn_quit.focus_mode = Control.FOCUS_ALL

func _is_controller_event(event: InputEvent) -> bool:
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null:
		return joy_button.pressed
	var joy_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	return joy_motion != null and absf(joy_motion.axis_value) >= 0.5
