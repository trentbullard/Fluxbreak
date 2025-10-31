extends CanvasLayer
class_name PauseMenu

signal resume_requested
signal restart_requested
signal menu_requested
signal quit_requested

@onready var root: Control = $ScreenRoot
@onready var btn_resume: Button = $ScreenRoot/CenterContainer/VBox/Resume
@onready var btn_restart: Button = $ScreenRoot/CenterContainer/VBox/Restart
@onready var btn_menu: Button = $ScreenRoot/CenterContainer/VBox/MainMenu
@onready var btn_quit: Button = $ScreenRoot/CenterContainer/VBox/Quit

func _ready() -> void:
	#layer = 100
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	btn_resume.pressed.connect(_on_resume)
	btn_restart.pressed.connect(_on_restart)
	btn_menu.pressed.connect(_on_menu)
	btn_quit.pressed.connect(_on_quit)

func focus_first() -> void:
	if is_inside_tree():
		btn_resume.grab_focus()

func _on_resume() -> void:
	resume_requested.emit()

func _on_restart() -> void:
	restart_requested.emit()

func _on_menu() -> void:
	menu_requested.emit()

func _on_quit() -> void:
	quit_requested.emit()
