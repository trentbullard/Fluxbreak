# scripts/hud/pause_menu.gd (Godot 4.7.2)
extends CanvasLayer
class_name PauseMenu

@onready var root: Control = $ScreenRoot
@onready var btn_resume: Button = $ScreenRoot/CenterContainer/VBox/Resume
@onready var btn_restart: Button = $ScreenRoot/CenterContainer/VBox/Restart
@onready var btn_menu: Button = $ScreenRoot/CenterContainer/VBox/MainMenu
@onready var btn_quit: Button = $ScreenRoot/CenterContainer/VBox/Quit
@onready var stat_panel: StatPanel = $ScreenRoot/StatPanel
@onready var run_modifiers_panel: RunModifiersPanel = $ScreenRoot/RunModifiersPanel
@onready var btn_camera: Button = $ScreenRoot/CenterContainer/VBox/CameraSettings
@onready var camera_settings_panel: CameraSettingsPanel = $ScreenRoot/CameraSettingsPanel

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	_set_focus_modes()
	btn_resume.pressed.connect(_on_resume_clicked)
	btn_camera.pressed.connect(open_camera_settings)
	camera_settings_panel.closed.connect(_on_camera_settings_closed)
	btn_restart.pressed.connect(_on_restart_clicked)
	btn_menu.pressed.connect(_on_menu_clicked)
	btn_quit.pressed.connect(_on_quit_clicked)
	
	PauseManager.paused_changed.connect(_on_paused_changed)

func _on_paused_changed(is_paused: bool) -> void:
	visible = is_paused
	if not is_paused:
		camera_settings_panel.close_panel()
	if is_paused:
		btn_resume.grab_focus()
		if stat_panel != null:
			stat_panel.refresh()
		if run_modifiers_panel != null:
			run_modifiers_panel.refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or camera_settings_panel.visible:
		return
	if _is_controller_event(event) and get_viewport().gui_get_focus_owner() == null:
		_set_focus_modes()
		btn_resume.grab_focus()
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		PauseManager.resume_requested.emit()

func _input(event: InputEvent) -> void:
	if not visible or camera_settings_panel.visible:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	var controls: Array[Control] = [btn_resume, btn_camera, btn_restart, btn_menu, btn_quit]
	var focused_panel: ScrollContainer = _get_focused_panel(focused)
	if focused_panel != null:
		if _navigation_pressed(event, KEY_UP, "ui_up") or _navigation_pressed(event, KEY_DOWN, "ui_down"):
			var direction: int = -1 if _navigation_pressed(event, KEY_UP, "ui_up") else 1
			focused_panel.scroll_vertical += direction * 48
			get_viewport().set_input_as_handled()
			return
		var return_to_buttons: bool = (
			(focused_panel == stat_panel and _navigation_pressed(event, KEY_RIGHT, "ui_right"))
			or (focused_panel == run_modifiers_panel and _navigation_pressed(event, KEY_LEFT, "ui_left"))
		)
		if return_to_buttons:
			btn_resume.grab_focus()
			get_viewport().set_input_as_handled()
			return
	elif focused in controls:
		if _navigation_pressed(event, KEY_LEFT, "ui_left"):
			stat_panel.grab_focus()
			get_viewport().set_input_as_handled()
			return
		if _navigation_pressed(event, KEY_RIGHT, "ui_right"):
			run_modifiers_panel.grab_focus()
			get_viewport().set_input_as_handled()
			return
	var key_event: InputEventKey = event as InputEventKey
	if key_event != null and key_event.pressed:
		var key: Key = key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		if key == KEY_TAB or ((key == KEY_UP or key == KEY_DOWN) and focused_panel == null):
			var index: int = controls.find(get_viewport().gui_get_focus_owner())
			var backwards: bool = key == KEY_UP or (key == KEY_TAB and key_event.shift_pressed)
			index = posmod(index + (-1 if backwards else 1), controls.size())
			controls[index].grab_focus()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
			var button: Button = get_viewport().gui_get_focus_owner() as Button
			if button in [btn_resume, btn_camera, btn_restart, btn_menu, btn_quit] and not key_event.echo:
				button.pressed.emit()
				get_viewport().set_input_as_handled()
			return
	if not _is_controller_event(event):
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	btn_resume.grab_focus()

func _get_focused_panel(focused: Control) -> ScrollContainer:
	if focused == null:
		return null
	for panel: ScrollContainer in [stat_panel, run_modifiers_panel]:
		if focused == panel or panel.is_ancestor_of(focused):
			return panel
	return null

func _navigation_pressed(event: InputEvent, key: Key, action: StringName) -> bool:
	var key_event: InputEventKey = event as InputEventKey
	if key_event != null:
		var pressed_key: Key = key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		return key_event.pressed and pressed_key == key
	return event.is_action_pressed(action, true)

func open_camera_settings() -> void:
	if not visible or not PauseManager.is_paused:
		return
	camera_settings_panel.open_panel()

func _on_camera_settings_closed() -> void:
	if visible:
		btn_camera.grab_focus()

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
	btn_camera.focus_mode = Control.FOCUS_ALL
	btn_restart.focus_mode = Control.FOCUS_ALL
	btn_menu.focus_mode = Control.FOCUS_ALL
	btn_quit.focus_mode = Control.FOCUS_ALL

func _is_controller_event(event: InputEvent) -> bool:
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null:
		return joy_button.pressed
	var joy_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	return joy_motion != null and absf(joy_motion.axis_value) >= 0.5
