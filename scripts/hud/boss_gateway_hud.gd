extends Control
class_name BossGatewayHud

## Manager that owns route inspection and explicit sector confirmation.
@export var boss_gateway_manager_path: NodePath
## Legacy label styling resource, retained for existing scene references.
@export var label_settings: LabelSettings

var _gateway_manager: BossGatewayManager = null
var _panel: PanelContainer = null
var _body_scroll: ScrollContainer = null
var _title: Label = null
var _description: Label = null
var _threats: Label = null
var _rewards: Label = null
var _conditions: Label = null
var _destination: Label = null
var _enter_button: Button = null
var _not_yet_button: Button = null
var _feedback: Label = null
var _glyph: RouteGlyph = null

class RouteGlyph extends Control:
	var kind: int = 0
	var tint: Color = Color.CYAN

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		if kind == 2:
			for shift: float in [-9.0, 9.0]:
				draw_polyline(PackedVector2Array([center + Vector2(-20, shift + 9), center + Vector2(0, shift - 5), center + Vector2(20, shift + 9)]), tint, 4.0, true)
		else:
			var points: PackedVector2Array = PackedVector2Array()
			for index: int in range(7):
				var angle: float = PI / 6.0 + TAU * float(index) / 6.0
				points.append(center + Vector2(cos(angle), sin(angle)) * 25.0)
			draw_polyline(points, tint, 3.0, true)
			draw_line(center + Vector2(-8, 12), center + Vector2(3, -5), tint, 4.0, true)
			draw_polyline(PackedVector2Array([center + Vector2(2,-5), center + Vector2(0,-11), center + Vector2(3,-15)]), tint, 3.0, true)
			draw_polyline(PackedVector2Array([center + Vector2(3,-5), center + Vector2(10,-5), center + Vector2(14,-8)]), tint, 3.0, true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("sector_briefing_modal")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	visible = false
	resized.connect(_resize_panel)
	if boss_gateway_manager_path != NodePath(""):
		_gateway_manager = get_node_or_null(boss_gateway_manager_path) as BossGatewayManager
	if _gateway_manager != null:
		_gateway_manager.briefing_opened.connect(_show_briefing)
		_gateway_manager.briefing_closed.connect(_hide_briefing)

func _build_ui() -> void:
	var theme: Theme = Theme.new()
	theme.default_font = preload("res://assets/fonts/Chakra_Petch/ChakraPetch-Light.ttf")
	theme.default_font_size = 20
	self.theme = theme
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.005, 0.012, 0.022, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var outer: MarginContainer = MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 28)
	add_child(outer)
	var center: CenterContainer = CenterContainer.new()
	outer.add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "SectorBriefing"
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.065, 0.98)
	style.border_color = Color(0.2, 0.65, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	_panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 18)
	column.add_child(heading)
	_glyph = RouteGlyph.new()
	_glyph.custom_minimum_size = Vector2(68, 68)
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(_glyph)
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(titles)
	_add_label(titles, "SECTOR GATEWAY", 15).modulate = Color(0.5, 0.8, 0.85)
	_title = _add_label(titles, "", 28)
	_title.add_theme_font_override("font", preload("res://assets/fonts/Orbitron/Orbitron-Regular.ttf"))
	_destination = _add_label(titles, "", 17)
	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body_scroll)
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	_body_scroll.add_child(body)
	_description = _add_label(body, "", 20)
	var tradeoffs: HBoxContainer = HBoxContainer.new()
	tradeoffs.add_theme_constant_override("separation", 30)
	body.add_child(tradeoffs)
	var threat_column: VBoxContainer = VBoxContainer.new()
	threat_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tradeoffs.add_child(threat_column)
	_add_label(threat_column, "THREATS", 16).modulate = Color(1.0, 0.65, 0.36)
	_threats = _add_label(threat_column, "", 19)
	var reward_column: VBoxContainer = VBoxContainer.new()
	reward_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tradeoffs.add_child(reward_column)
	_add_label(reward_column, "OPPORTUNITIES", 16).modulate = Color(0.4, 0.92, 0.75)
	_rewards = _add_label(reward_column, "", 19)
	_add_label(body, "SECTOR CONDITIONS", 16).modulate = Color(0.5, 0.8, 0.85)
	_conditions = _add_label(body, "", 19)
	_add_label(body, "Your ship, upgrades and nanobots carry into this sector.", 17).modulate = Color(0.72, 0.8, 0.85)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	column.add_child(actions)
	_enter_button = Button.new()
	_enter_button.name = "EnterSector"
	_enter_button.text = "Enter this sector"
	_enter_button.custom_minimum_size = Vector2(0, 48)
	_enter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enter_button.focus_mode = Control.FOCUS_ALL
	_enter_button.pressed.connect(_confirm)
	actions.add_child(_enter_button)
	_not_yet_button = Button.new()
	_not_yet_button.name = "NotYet"
	_not_yet_button.text = "Not yet"
	_not_yet_button.custom_minimum_size = Vector2(160, 48)
	_not_yet_button.focus_mode = Control.FOCUS_ALL
	_not_yet_button.pressed.connect(_decline)
	actions.add_child(_not_yet_button)
	for button: Button in [_enter_button, _not_yet_button]:
		var other: Button = _not_yet_button if button == _enter_button else _enter_button
		button.focus_neighbor_left = button.get_path_to(other)
		button.focus_neighbor_right = button.get_path_to(other)
		button.focus_neighbor_top = button.get_path_to(other)
		button.focus_neighbor_bottom = button.get_path_to(other)
		button.focus_next = button.get_path_to(other)
		button.focus_previous = button.get_path_to(other)
	_feedback = _add_label(column, "Enter / A: selected action     Esc / B: not yet", 15)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.modulate = Color(0.6, 0.75, 0.8)
	_resize_panel()

func _add_label(parent: Node, value: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _resize_panel() -> void:
	if _panel == null or _body_scroll == null:
		return
	var dimensions: Vector2 = get_viewport_rect().size
	_panel.custom_minimum_size.x = clampf(dimensions.x - 100.0, 540.0, 800.0)
	_body_scroll.custom_minimum_size.y = clampf(dimensions.y - 400.0, 240.0, 390.0)

func _show_briefing(gateway: BossGateway) -> void:
	var route: SectorRouteDef = gateway.get_route()
	if route == null or route.destination_stage == null:
		return
	# Keep the briefing and its input surface above the ship HUD and alerts.
	get_parent().move_child(self, -1)
	visible = true
	_enter_button.disabled = false
	_title.text = route.get_display_name()
	_description.text = route.description
	_threats.text = route.threat_summary if not route.threat_summary.is_empty() else "Continue through the hostile sector."
	_rewards.text = route.reward_summary if not route.reward_summary.is_empty() else "Prepare for the final encounter."
	var stage: StageDef = route.destination_stage
	var faction: FactionDef = GameFlow.get_run_faction()
	var faction_name: String = faction.get_display_name_or_default() if faction != null else "Hostile"
	var boss_names: PackedStringArray = PackedStringArray()
	for boss: EnemyBossDef in stage.get_boss_pool():
		boss_names.append(boss.get_display_name_or_default())
	_destination.text = "%s · Finale: %s" % [faction_name, ", ".join(boss_names)]
	var conditions: PackedStringArray = PackedStringArray()
	for modifier: StageModifierDef in GameFlow.get_stage_modifiers_for(stage):
		conditions.append("%s — %s" % [modifier.get_display_name_or_default(), modifier.description])
	_conditions.text = "\n\n".join(conditions) if not conditions.is_empty() else "No additional sector conditions."
	_glyph.kind = int(route.marker_kind)
	_glyph.tint = route.marker_color
	_glyph.queue_redraw()
	_title.modulate = route.marker_color
	_feedback.text = "Enter / A: selected action     Esc / B: not yet"
	_body_scroll.scroll_vertical = 0
	_resize_panel()
	# The safe default also prevents an arriving player's held boost from committing a route.
	_not_yet_button.grab_focus()

func _hide_briefing() -> void:
	visible = false

func _confirm() -> void:
	if _gateway_manager == null:
		return
	_enter_button.disabled = true
	if not _gateway_manager.confirm_gateway():
		_enter_button.disabled = false
		_feedback.text = "This route is unavailable. Choose Not yet to return to flight."

func _decline() -> void:
	if _gateway_manager != null:
		_gateway_manager.cancel_gateway()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")) and not event.is_echo():
		get_viewport().set_input_as_handled()
		_decline()
		return
	# The flight input map reserves the ui_* actions for gamepad navigation.
	# Support the keyboard prompt locally without changing flight bindings.
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var code: Key = key.keycode if key.keycode != KEY_NONE else key.physical_keycode
		if code == KEY_ENTER or code == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			if get_viewport().gui_get_focus_owner() == _enter_button:
				_confirm()
			else:
				_decline()
			return
		if code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			get_viewport().set_input_as_handled()
			if get_viewport().gui_get_focus_owner() == _enter_button:
				_not_yet_button.grab_focus()
			else:
				_enter_button.grab_focus()
			return
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	var joy_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if get_viewport().gui_get_focus_owner() == null and ((joy_button != null and joy_button.pressed) or (joy_motion != null and absf(joy_motion.axis_value) >= 0.5)):
		_not_yet_button.grab_focus()
