extends Node

var _menu_scene: PackedScene = preload("res://scenes/hud/pause_menu.tscn")
var _menu: PauseMenu
var _was_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var is_paused: bool = false

func _ready() -> void:
	_menu = _menu_scene.instantiate()
	if _menu:
		get_tree().root.add_child.call_deferred(_menu)
		_menu.resume_requested.connect(_on_resume)
		_menu.restart_requested.connect(_on_restart)
		_menu.menu_requested.connect(_on_menu)
		_menu.quit_requested.connect(_on_quit)

func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("pause"):
		# Avoid pausing on the main menu
		var cs: Node = get_tree().current_scene
		if cs != null and cs.name == "MainMenu":
			return
		toggle_pause()

func toggle_pause() -> void:
	if is_paused:
		resume()
	else:
		pause()

func pause() -> void:
	if is_paused: return
	is_paused = true
	_was_mouse_mode = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _menu != null:
		_menu.visible = true
		_menu.focus_first()
	get_tree().paused = true

func resume() -> void:
	print("yoo")
	if not is_paused: return
	is_paused = false
	if _menu:
		_menu.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(_was_mouse_mode)

func _on_resume() -> void:
	resume()

func _on_restart() -> void:
	get_tree().paused = false
	is_paused = false
	if _menu:
		_menu.visible = false
	get_tree().reload_current_scene()

func _on_menu() -> void:
	get_tree().paused = false
	is_paused = false
	if _menu:
		_menu.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

func _on_quit() -> void:
	get_tree().quit()
