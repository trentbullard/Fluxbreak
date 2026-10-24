class_name CameraSettingsPanel
extends Control

signal closed

const DISPLAY_FONT: Font = preload("res://assets/fonts/Orbitron/Orbitron-Regular.ttf")
const ROW_DEFINITIONS: Array[Dictionary] = [
	{"key": &"fov", "node": "Fov", "label": "FIELD OF VIEW", "help": "How much of space is visible around the ship.", "step": 1.0},
	{"key": &"distance_scale", "node": "Distance", "label": "CAMERA DISTANCE", "help": "Distance behind your ship, relative to its normal camera.", "step": 0.01},
	{"key": &"height_scale", "node": "Height", "label": "CAMERA HEIGHT", "help": "Height above your ship, relative to its normal camera.", "step": 0.01},
	{"key": &"tightness", "node": "Tightness", "label": "FOLLOW TIGHTNESS", "help": "Higher values make the camera respond to turns and acceleration faster.", "step": 0.01},
	{"key": &"look_ahead", "node": "LookAhead", "label": "TURN LOOK-AHEAD", "help": "How far the camera looks into your turns.", "step": 0.01},
	{"key": &"acceleration_pullback", "node": "Pullback", "label": "ACCELERATION PULLBACK", "help": "How far the camera pulls back while your ship accelerates.", "step": 0.01},
]

var _sliders: Dictionary = {}
var _values: Dictionary = {}
var _focus_controls: Array[Control] = []
var _panel: PanelContainer
var _scroll: ScrollContainer
var _reset: Button
var _back: Button
var _dragging: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("camera_settings_modal")
	_build_panel()
	EventBus.camera_preferences_changed.connect(_refresh_values)
	resized.connect(_update_layout)
	_update_layout()
	_refresh_values(CameraPreferences.get_settings())

func open_panel() -> void:
	_dragging = false
	_refresh_values(CameraPreferences.get_settings())
	show()
	_update_layout()
	_scroll.scroll_vertical = 0
	_focus_controls[0].grab_focus()

func close_panel() -> void:
	if not visible:
		return
	_dragging = false
	CameraPreferences.save_settings()
	hide()
	closed.emit()

func _build_panel() -> void:
	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.005, 0.012, 0.02, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.055, 0.075, 1.0)
	panel_style.border_color = Color(0.2, 0.7, 0.76, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(5)
	_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(_panel)
	var margins: MarginContainer = MarginContainer.new()
	margins.name = "Margins"
	for side: String in ["left", "top", "right", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 22)
	_panel.add_child(margins)
	var contents: VBoxContainer = VBoxContainer.new()
	contents.name = "Contents"
	contents.add_theme_constant_override("separation", 14)
	margins.add_child(contents)
	var title: Label = Label.new()
	title.text = "FLIGHT CAMERA"
	title.add_theme_font_override("font", DISPLAY_FONT)
	title.add_theme_font_size_override("font_size", 28)
	contents.add_child(title)
	var description: Label = Label.new()
	description.text = "Customize your cinematic follow camera. Flight handling stays the same."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color(0.65, 0.8, 0.85))
	contents.add_child(description)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	contents.add_child(_scroll)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 20)
	_scroll.add_child(rows)
	for definition: Dictionary in ROW_DEFINITIONS:
		_build_row(rows, definition)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 14)
	contents.add_child(buttons)
	_reset = Button.new()
	_reset.name = "Reset"
	_reset.text = "RESET CAMERA"
	_reset.custom_minimum_size.y = 44.0
	_reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reset.pressed.connect(CameraPreferences.reset_defaults)
	buttons.add_child(_reset)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "BACK"
	_back.custom_minimum_size.y = 44.0
	_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back.pressed.connect(close_panel)
	buttons.add_child(_back)
	_focus_controls.append_array([_reset, _back])
	for index: int in _focus_controls.size():
		var control: Control = _focus_controls[index]
		var previous: Control = _focus_controls[(index - 1 + _focus_controls.size()) % _focus_controls.size()]
		var next: Control = _focus_controls[(index + 1) % _focus_controls.size()]
		control.focus_mode = Control.FOCUS_ALL
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_previous = control.get_path_to(previous)
		control.focus_neighbor_bottom = control.get_path_to(next)
		control.focus_next = control.get_path_to(next)

func _build_row(rows: VBoxContainer, definition: Dictionary) -> void:
	var key: StringName = definition["key"]
	var row: VBoxContainer = VBoxContainer.new()
	row.name = definition["node"]
	row.add_theme_constant_override("separation", 4)
	rows.add_child(row)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.name = "Heading"
	row.add_child(heading)
	var label: Label = Label.new()
	label.text = definition["label"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var value: Label = Label.new()
	value.name = "Value"
	value.add_theme_color_override("font_color", Color(0.4, 0.9, 0.9))
	heading.add_child(value)
	_values[key] = value
	var help: Label = Label.new()
	help.text = definition["help"]
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_color_override("font_color", Color(0.65, 0.76, 0.8))
	row.add_child(help)
	var slider: HSlider = HSlider.new()
	slider.name = "Slider"
	slider.custom_minimum_size.y = 28.0
	var bounds: Vector2 = CameraPreferences.LIMITS[key]
	slider.min_value = bounds.x
	slider.max_value = bounds.y
	slider.step = float(definition["step"])
	slider.value_changed.connect(_on_value_changed.bind(key))
	slider.drag_started.connect(_on_drag_started)
	slider.drag_ended.connect(_on_drag_ended)
	row.add_child(slider)
	_sliders[key] = slider
	_focus_controls.append(slider)

func _update_layout() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_panel.custom_minimum_size.x = minf(680.0, maxf(300.0, viewport_size.x - 48.0))
	_scroll.custom_minimum_size.y = clampf(viewport_size.y - 260.0, 120.0, 470.0)

func _refresh_values(settings: Dictionary) -> void:
	for key: StringName in _sliders:
		var value: float = float(settings[key])
		var slider: HSlider = _sliders[key]
		slider.set_value_no_signal(value)
		var value_label: Label = _values[key]
		if key == &"fov":
			value_label.text = "%d°" % int(roundf(value))
		elif key == &"distance_scale" or key == &"height_scale":
			value_label.text = "%.2fx" % value
		else:
			value_label.text = "%d%%" % int(roundf(value * 100.0))

func _on_value_changed(value: float, key: StringName) -> void:
	CameraPreferences.set_setting(key, value, not _dragging)

func _on_drag_started() -> void:
	_dragging = true

func _on_drag_ended(_value_changed: bool) -> void:
	_dragging = false
	CameraPreferences.save_settings()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")) and not event.is_echo():
		get_viewport().set_input_as_handled()
		close_panel()
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed:
		return
	var key: Key = key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
	match key:
		KEY_UP, KEY_DOWN, KEY_TAB:
			var backwards: bool = key == KEY_UP or (key == KEY_TAB and key_event.shift_pressed)
			_move_focus(-1 if backwards else 1)
		KEY_LEFT, KEY_RIGHT:
			var focused: HSlider = get_viewport().gui_get_focus_owner() as HSlider
			if focused != null:
				focused.value += focused.step * (-1.0 if key == KEY_LEFT else 1.0)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			var button: Button = get_viewport().gui_get_focus_owner() as Button
			if button != null and not key_event.echo:
				button.pressed.emit()
		_:
			return
	get_viewport().set_input_as_handled()

func _move_focus(direction: int) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	var index: int = _focus_controls.find(focused)
	if index < 0:
		index = 0 if direction > 0 else _focus_controls.size() - 1
	else:
		index = posmod(index + direction, _focus_controls.size())
	_focus_controls[index].grab_focus()
