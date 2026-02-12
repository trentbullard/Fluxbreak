extends Node

signal pause_requested
signal resume_requested
signal paused_changed(is_paused: bool)
signal paused
signal resumed
signal restart_requested
signal menu_requested
signal quit_requested

var _was_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var is_paused: bool = false
var default_weapon: WeaponDef

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	pause_requested.connect(_on_pause_request)
	resume_requested.connect(_on_resume_requested)
	restart_requested.connect(_on_restart)
	menu_requested.connect(_on_menu)
	quit_requested.connect(_on_quit)

func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("pause"):
		# Avoid pausing on the main menu
		var cs: Node = get_tree().current_scene
		if cs != null and cs.name == "MainMenu":
			return
		toggle_pause()

func toggle_pause() -> void:
	if is_paused:
		_on_resume_requested()
	else:
		_on_pause_request()

func _on_pause_request() -> void:
	if is_paused: return
	is_paused = true
	paused_changed.emit(true)
	paused.emit()
	get_tree().paused = true
	_was_mouse_mode = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_resume_requested() -> void:
	if not is_paused: return
	get_tree().paused = false
	is_paused = false
	paused_changed.emit(false)
	resumed.emit()
	Input.set_mouse_mode(_was_mouse_mode)

func _on_restart() -> void:
	get_tree().paused = false
	is_paused = false
	get_tree().reload_current_scene()

func _on_menu() -> void:
	get_tree().paused = false
	is_paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")

func _on_quit() -> void:
	get_tree().quit()
