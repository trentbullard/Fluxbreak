extends Node

## Real 720p Vulkan captures of both entry points and the original camera.
const WORLD_SCENE: PackedScene = preload("res://scenes/world/world.tscn")
const ROWS: String = "Center/Panel/Margins/Contents/Scroll/Rows/"
const BUTTONS: String = "Center/Panel/Margins/Contents/Buttons/"
const MENU_BUTTONS: String = "CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/"

var _output: String = ""
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Camera Settings Visual Validation":
		push_error("Camera settings visual checks require their isolated wrapper.")
		get_tree().quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Camera settings captures require a renderer and --output directory.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	get_tree().node_added.connect(_mute_audio)
	CameraPreferences.reset_defaults()
	GameFlow.abandon_run()
	var world: Node3D = WORLD_SCENE.instantiate() as Node3D
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await _wait_frames(25)
	var menu: Control = world.get_node("MainMenuOverlay") as Control
	menu.call("show_page", &"settings")
	await _wait_frames(10)
	await _capture("main_settings.png")
	menu.call("open_camera_settings")
	await _wait_frames(10)
	var panel: Control = menu.get_node("CameraSettingsPanel") as Control
	_check_modal_layout(panel)
	await _capture("main_camera_top.png")
	(panel.get_node(ROWS + "Pullback/Slider") as Control).grab_focus()
	await _wait_frames(10)
	_check_final_row(panel)
	await _capture("main_camera_bottom.png")
	panel.call("close_panel")
	menu.call("show_page", &"play")
	menu.call("set_practice_faction_id", &"machines")
	(menu.get_node(MENU_BUTTONS + "MercPracticeContainer/MercPractice") as Button).pressed.emit()
	await _wait_frames(10)
	var ship: Ship = world.get_node("Ship") as Ship
	ship.freeze = true
	ship.set_physics_process(false)
	ship.get_node("MouseFlightController").process_mode = Node.PROCESS_MODE_DISABLED
	ship.get_node("ControllerFlightController").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("StageRoot/WaveDirector").set_physics_process(false)
	var rig: Node3D = ship.get_node("CameraPivot/CameraRig") as Node3D
	rig.set_physics_process(false)
	ship.linear_velocity = Vector3(0.0, 0.0, -120.0)
	ship.angular_velocity = Vector3(-0.3, 0.3, 0.0)
	rig.set("_prev_velocity", ship.linear_velocity)
	for sample: int in range(90):
		rig.call("_physics_process", 1.0 / 60.0)
	await _wait_frames(10)
	await _capture("original_camera_defaults.png")
	PauseManager.pause_requested.emit()
	await _wait_frames(3)
	var pause: PauseMenu = world.get_node("PauseMenu") as PauseMenu
	pause.call("open_camera_settings")
	await _wait_frames(10)
	panel = pause.get_node("ScreenRoot/CameraSettingsPanel") as Control
	_check_modal_layout(panel)
	await _capture("pause_camera_top.png")
	(panel.get_node(ROWS + "Pullback/Slider") as Control).grab_focus()
	await _wait_frames(10)
	_check_final_row(panel)
	await _capture("pause_camera_bottom.png")
	panel.call("close_panel")
	CameraPreferences.reset_defaults()
	GameFlow.abandon_run()
	PauseManager.is_paused = false
	get_tree().paused = false
	world.queue_free()
	get_tree().current_scene = self
	await _wait_frames(4)
	print("CAMERA_SETTINGS_VISUAL_CHECKS: %s (%d assertions, %d failures); artifacts: %s" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures, _output])
	get_tree().quit(0 if _failures == 0 else 1)

func _check_modal_layout(panel: Control) -> void:
	var viewport: Rect2 = get_viewport().get_visible_rect()
	_check(panel.is_visible_in_tree(), "Camera modal is visible")
	_check(viewport.encloses((panel.get_node("Center/Panel") as Control).get_global_rect()), "Entire modal fits the 1280x720 window")
	_check(viewport.encloses((panel.get_node(BUTTONS + "Reset") as Control).get_global_rect()), "Reset is visible at 720p")
	_check(viewport.encloses((panel.get_node(BUTTONS + "Back") as Control).get_global_rect()), "Back is visible at 720p")
	var scroll: Control = panel.get_node("Center/Panel/Margins/Contents/Scroll") as Control
	_check(scroll.get_global_rect().encloses((panel.get_node(ROWS + "Fov/Slider") as Control).get_global_rect()), "FOV is reachable at the top")

func _check_final_row(panel: Control) -> void:
	var scroll: Control = panel.get_node("Center/Panel/Margins/Contents/Scroll") as Control
	_check(scroll.get_global_rect().encloses((panel.get_node(ROWS + "Pullback/Slider") as Control).get_global_rect()), "The last slider scrolls into view at 720p")

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(not image.is_empty() and image.save_png(_output.path_join(filename)) == OK, "Rendered %s captures successfully" % filename)

func _wait_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _mute_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CAMERA_SETTINGS_VISUAL_CHECKS: " + description)
