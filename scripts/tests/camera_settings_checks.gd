extends Node

## Focused, save-isolated regression checks for settings on the original camera.
const WORLD_SCENE: PackedScene = preload("res://scenes/world/world.tscn")
const SHIP_DEFS: Array[ShipDef] = [
	preload("res://content/data/ships/starter_fighter.tres"),
	preload("res://content/data/ships/heavy_bruiser.tres"),
	preload("res://content/data/ships/drone_carrier.tres"),
]
const ROWS: String = "Center/Panel/Margins/Contents/Scroll/Rows/"
const BUTTONS: String = "Center/Panel/Margins/Contents/Buttons/"
const MENU_BUTTONS: String = "CenterContainer/MainMenuContainer/ButtonPanel/ButtonMargins/ButtonsContainer/"
const DEFAULTS: Dictionary = {&"fov": 75.0, &"distance_scale": 1.0, &"height_scale": 1.0, &"tightness": 1.0 / 6.0, &"look_ahead": 1.0, &"acceleration_pullback": 0.2}

var _checks: int = 0
var _failures: int = 0
var _world: Node3D
var _ship: Ship
var _rig: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_checks")

func _run_checks() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Camera Settings Validation":
		push_error("Camera settings checks require their isolated validation wrapper.")
		get_tree().quit(2)
		return
	get_tree().root.size = Vector2i(1280, 720)
	get_tree().node_added.connect(_mute_audio)
	GameFlow.abandon_run()
	_check_preferences()
	_world = WORLD_SCENE.instantiate() as Node3D
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	await _wait_frames(4)
	_ship = _world.get_node("Ship") as Ship
	_ship.freeze = true
	_ship.set_physics_process(false)
	_ship.get_node("MouseFlightController").process_mode = Node.PROCESS_MODE_DISABLED
	_ship.get_node("ControllerFlightController").process_mode = Node.PROCESS_MODE_DISABLED
	_rig = _ship.get_node("CameraPivot/CameraRig") as Node3D
	_rig.set_physics_process(false)
	_check_original_camera_formulas()
	_check_live_settings()
	await _check_menu_panel()
	await _check_pause_panel()
	CameraPreferences.reset_defaults()
	GameFlow.abandon_run()
	get_tree().paused = false
	PauseManager.is_paused = false
	_world.queue_free()
	get_tree().current_scene = self
	await _wait_frames(4)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("CAMERA_SETTINGS_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _check_preferences() -> void:
	CameraPreferences.reset_defaults()
	var settings: Dictionary = CameraPreferences.get_settings()
	_check(settings.size() == 6 and not settings.has(&"follow_cam"), "Only the six numeric camera settings exist")
	for key: StringName in DEFAULTS:
		_check(is_equal_approx(float(settings[key]), float(DEFAULTS[key])), "Fresh/reset %s matches original camera tuning" % key)
	settings[&"fov"] = 109.0
	_check(is_equal_approx(float(CameraPreferences.get_settings()[&"fov"]), 75.0), "Returned settings are a defensive copy")
	CameraPreferences.set_setting(&"fov", 92.0)
	CameraPreferences.set_setting(&"distance_scale", 1.3)
	CameraPreferences.set_setting(&"height_scale", 1.4)
	CameraPreferences.set_setting(&"tightness", 0.6)
	CameraPreferences.set_setting(&"look_ahead", 0.4)
	CameraPreferences.set_setting(&"acceleration_pullback", 0.1)
	var persisted: Dictionary = CameraPreferences.get_settings()
	_check(CameraPreferences.save_settings() == OK, "Camera preferences save successfully")
	CameraPreferences.reload()
	_check(CameraPreferences.get_settings() == persisted, "Every numeric setting survives reload")
	for invalid: Variant in [true, "90", INF, NAN]:
		CameraPreferences.set_setting(&"fov", invalid)
		_check(is_equal_approx(float(CameraPreferences.get_settings()[&"fov"]), 92.0), "Invalid numeric values cannot overwrite a setting: %s" % str(invalid))
	CameraPreferences.set_setting(&"follow_cam", false)
	_check(not CameraPreferences.get_settings().has(&"follow_cam"), "The reverted mode flag cannot be recreated")
	var raw: ConfigFile = ConfigFile.new()
	raw.set_value("camera", "fov", 999.0)
	raw.set_value("camera", "distance_scale", -10.0)
	raw.set_value("camera", "height_scale", "bad")
	raw.set_value("camera", "tightness", true)
	raw.set_value("camera", "look_ahead", INF)
	raw.set_value("camera", "acceleration_pullback", 0.13)
	raw.set_value("camera", "follow_cam", false)
	_check(raw.save(CameraPreferences.SETTINGS_PATH) == OK, "Malformed/migration fixture saves in the isolated namespace")
	CameraPreferences.reload()
	settings = CameraPreferences.get_settings()
	_check(is_equal_approx(float(settings[&"fov"]), 110.0) and is_equal_approx(float(settings[&"distance_scale"]), 0.75), "Loaded numeric values clamp to the authored ranges")
	_check(is_equal_approx(float(settings[&"height_scale"]), 1.0) and is_equal_approx(float(settings[&"tightness"]), 1.0 / 6.0) and is_equal_approx(float(settings[&"look_ahead"]), 1.0), "Malformed loaded values restore their individual defaults")
	_check(is_equal_approx(float(settings[&"acceleration_pullback"]), 0.13) and not settings.has(&"follow_cam"), "Valid saved numerics survive migration while obsolete camera modes are ignored")
	CameraPreferences.reset_defaults()

func _check_original_camera_formulas() -> void:
	var dt: float = 1.0 / 60.0
	for definition: ShipDef in SHIP_DEFS:
		_ship.call("_apply_ship_visuals", definition.visuals)
		_check(is_equal_approx(float(_rig.get("height_offset")), definition.visuals.camera_height) and is_equal_approx(float(_rig.get("distance_offset")), definition.visuals.camera_distance), "%s uses its authored camera height and distance" % definition.id)
		_ship.transform.basis = Basis.from_euler(Vector3(0.2, -0.4, 0.1))
		var previous_velocity: Vector3 = Vector3(14.0, -8.0, -24.0)
		_rig.set("_prev_velocity", previous_velocity)
		_rig.set("current_look_rot", Vector2(0.13, -0.17))
		_rig.position = Vector3(0.0, definition.visuals.camera_height, definition.visuals.camera_distance)
		var expected_look: Vector2 = Vector2(0.13, -0.17)
		var expected_distance: float = definition.visuals.camera_distance
		for local_rates: Vector3 in [Vector3(0.7, 0.5, 0.1), Vector3(-0.7, 0.5, -0.1), Vector3(-0.7, -0.5, 0.0), Vector3(0.7, -0.5, 0.0), Vector3(4.0, -4.0, 0.0), Vector3(-4.0, 4.0, 0.0), Vector3.ZERO]:
			_ship.angular_velocity = _ship.transform.basis * local_rates
			_ship.linear_velocity = previous_velocity + Vector3(0.3, -0.4, -0.7)
			var target_look: Vector2 = Vector2(clampf(-local_rates.x * -0.5, -1.0, 1.0), clampf(-local_rates.y * -0.5, -1.0, 1.0))
			expected_look = expected_look.lerp(target_look, 6.0 * dt)
			var expected_basis: Basis = Basis.IDENTITY.rotated(Vector3.RIGHT, deg_to_rad(definition.visuals.camera_angle_deg)).rotated(Vector3.RIGHT, expected_look.x).rotated(Vector3.UP, expected_look.y)
			var accel: float = (_ship.linear_velocity - previous_velocity).length() / dt
			var target_distance: float = definition.visuals.camera_distance * lerpf(1.0, 1.2, clampf(accel / 100.0, 0.0, 1.0))
			expected_distance = lerpf(expected_distance, target_distance, 5.0 * dt)
			_rig.call("_physics_process", dt)
			_check((_rig.get("current_look_rot") as Vector2).is_equal_approx(expected_look), "%s preserves independent original look and 6dt interpolation at %s" % [definition.id, str(local_rates)])
			_check(_rig.transform.basis.is_equal_approx(expected_basis), "%s preserves original yaw/pitch composition" % definition.id)
			_check(is_equal_approx(_rig.position.z, expected_distance), "%s preserves original acceleration pullback and 5dt interpolation" % definition.id)
			previous_velocity = _ship.linear_velocity
		_ship.transform.basis = Basis.IDENTITY

func _check_live_settings() -> void:
	var body_pose: Transform3D = _ship.global_transform
	var linear: Vector3 = _ship.linear_velocity
	var angular: Vector3 = _ship.angular_velocity
	CameraPreferences.set_setting(&"fov", 101.0, false)
	CameraPreferences.set_setting(&"distance_scale", 1.5, false)
	CameraPreferences.set_setting(&"height_scale", 1.25, false)
	CameraPreferences.set_setting(&"tightness", 1.0, false)
	CameraPreferences.set_setting(&"look_ahead", 0.5, false)
	CameraPreferences.set_setting(&"acceleration_pullback", 0.1, false)
	for definition: ShipDef in SHIP_DEFS:
		_ship.call("_apply_ship_visuals", definition.visuals)
		var camera: Camera3D = _rig.get_node("Camera3D") as Camera3D
		_check(is_equal_approx(camera.fov, 101.0), "Live FOV survives switching to %s" % definition.id)
		_check(is_equal_approx(float(_rig.get("height_offset")), definition.visuals.camera_height * 1.25) and is_equal_approx(float(_rig.get("distance_offset")), definition.visuals.camera_distance * 1.5), "Height/distance scales apply once to %s authored profile" % definition.id)
		_rig.set("current_look_rot", Vector2.ZERO)
		_rig.set("_prev_velocity", Vector3.ZERO)
		_rig.position.z = float(_rig.get("distance_offset"))
		_ship.angular_velocity = Vector3(4.0, -4.0, 0.0)
		_ship.linear_velocity = Vector3(0.0, 0.0, -10.0)
		_rig.call("_physics_process", 1.0 / 60.0)
		_check((_rig.get("current_look_rot") as Vector2).is_equal_approx(Vector2(0.5, -0.5) * (16.0 / 60.0)), "Look strength scales the independent caps and maximum tightness changes look response")
		_check(is_equal_approx(_rig.position.z, definition.visuals.camera_distance * 1.5 * 1.025), "Maximum tightness changes distance response while configured pullback stays bounded")
	_check(_ship.global_transform.is_equal_approx(body_pose), "Camera settings never reposition or rotate the physical ship")
	_ship.linear_velocity = linear
	_ship.angular_velocity = angular
	_check(is_equal_approx(float(_ship.get_node("MouseFlightController").get("sensitivity")), 0.13), "Camera settings leave flight input sensitivity unchanged")
	CameraPreferences.reset_defaults()

func _check_menu_panel() -> void:
	var menu: Control = _world.get_node("MainMenuOverlay") as Control
	menu.call("show_page", &"settings")
	var entry: Button = menu.get_node(MENU_BUTTONS + "SettingsControls/CameraSettings") as Button
	_check(entry.is_visible_in_tree(), "Main menu Settings exposes Flight Camera")
	entry.pressed.emit()
	await _wait_frames(3)
	var panel: Control = menu.get_node("CameraSettingsPanel") as Control
	_check(panel.is_visible_in_tree(), "Main menu opens the camera settings modal")
	await _check_panel_navigation(panel)
	await _send_key(KEY_ESCAPE)
	_check(not panel.visible and menu.call("get_current_page") == &"settings" and get_tree().paused, "Escape closes only the modal and retains its Settings origin")
	_check(get_viewport().gui_get_focus_owner() == entry, "Closing the modal restores main menu entry focus")
	menu.call("open_camera_settings")
	await _wait_frames(2)
	await _send_joy(JOY_BUTTON_B)
	_check(not panel.visible and menu.call("get_current_page") == &"settings", "Controller B closes the main menu modal without leaving Settings")

func _check_panel_navigation(panel: Control) -> void:
	var fov_slider: HSlider = panel.get_node(ROWS + "Fov/Slider") as HSlider
	var distance: HSlider = panel.get_node(ROWS + "Distance/Slider") as HSlider
	_check(get_viewport().gui_get_focus_owner() == fov_slider, "Opening the panel focuses FOV")
	var initial: float = fov_slider.value
	await _send_key(KEY_RIGHT)
	_check(fov_slider.value > initial and is_equal_approx(float(CameraPreferences.get_settings()[&"fov"]), fov_slider.value), "Keyboard Right changes the slider and applies its live preference")
	await _send_key(KEY_DOWN)
	_check(get_viewport().gui_get_focus_owner() == distance, "Keyboard Down moves through visible settings")
	initial = distance.value
	await _send_joy(JOY_BUTTON_DPAD_RIGHT)
	_check(distance.value > initial, "Controller D-pad adjusts the focused slider")
	await _send_joy(JOY_BUTTON_DPAD_DOWN)
	_check(get_viewport().gui_get_focus_owner() == panel.get_node(ROWS + "Height/Slider"), "Controller D-pad navigates to the next setting")
	var reset: Button = panel.get_node(BUTTONS + "Reset") as Button
	reset.grab_focus()
	await _send_key(KEY_ENTER)
	_check(CameraPreferences.get_settings() == DEFAULTS, "Keyboard activation of Reset restores all six original defaults")
	_check(get_viewport().get_visible_rect().encloses(reset.get_global_rect()), "Reset remains reachable at 1280x720")
	var back: Button = panel.get_node(BUTTONS + "Back") as Button
	_check(get_viewport().get_visible_rect().encloses(back.get_global_rect()), "Back remains reachable at 1280x720")
	var pullback: Control = panel.get_node(ROWS + "Pullback/Slider") as Control
	pullback.grab_focus()
	await _wait_frames(3)
	var scroll: ScrollContainer = panel.get_node("Center/Panel/Margins/Contents/Scroll") as ScrollContainer
	_check(scroll.get_global_rect().encloses(pullback.get_global_rect()), "Focusing the final slider scrolls it into view at 720p")

func _check_pause_panel() -> void:
	var menu: Control = _world.get_node("MainMenuOverlay") as Control
	menu.call("show_page", &"play")
	menu.call("set_practice_faction_id", &"machines")
	(menu.get_node(MENU_BUTTONS + "MercPracticeContainer/MercPractice") as Button).pressed.emit()
	await _wait_frames(3)
	PauseManager.pause_requested.emit()
	await _wait_frames(2)
	var pause: PauseMenu = _world.get_node("PauseMenu") as PauseMenu
	pause.call("open_camera_settings")
	await _wait_frames(3)
	var panel: Control = pause.get_node("ScreenRoot/CameraSettingsPanel") as Control
	_check(panel.is_visible_in_tree() and PauseManager.is_paused and get_tree().paused, "Pause menu opens the same settings while gameplay stays paused")
	var hull: float = _ship.hull
	var nanobots: int = _ship.get_nanobots()
	var position: Vector3 = _ship.global_position
	var fov_slider: HSlider = panel.get_node(ROWS + "Fov/Slider") as HSlider
	fov_slider.value = 89.0
	_check(is_equal_approx((_rig.get_node("Camera3D") as Camera3D).fov, 89.0), "Settings update the live camera while physics is paused")
	await _send_key(KEY_ESCAPE)
	_check(not panel.visible and pause.visible and PauseManager.is_paused and get_tree().paused, "Escape closes camera settings without resuming the run")
	pause.call("open_camera_settings")
	await _wait_frames(2)
	await _send_joy(JOY_BUTTON_B)
	_check(not panel.visible and pause.visible and PauseManager.is_paused and get_tree().paused, "Controller B closes only camera settings and leaves Pause open")
	_check(is_equal_approx(_ship.hull, hull) and _ship.get_nanobots() == nanobots and _ship.global_position.is_equal_approx(position), "Modal cancel neither repairs, spends currency, nor moves the ship")
	var disk: ConfigFile = ConfigFile.new()
	_check(disk.load(CameraPreferences.SETTINGS_PATH) == OK and is_equal_approx(float(disk.get_value("camera", "fov")), 89.0), "Closing the modal commits slider changes to its isolated preferences file")
	PauseManager.resume_requested.emit()
	await _wait_frames(2)
	_check(not get_tree().paused and not PauseManager.is_paused, "Normal Resume still works after modal cancellation")

func _send_key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _wait_frames(2)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	Input.parse_input_event(event)
	await _wait_frames(2)

func _send_joy(button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await _wait_frames(2)
	event = InputEventJoypadButton.new()
	event.button_index = button
	Input.parse_input_event(event)
	await _wait_frames(2)

func _wait_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _mute_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CAMERA_SETTINGS_CHECKS: " + message)
