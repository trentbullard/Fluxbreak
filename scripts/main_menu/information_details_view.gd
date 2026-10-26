extends ScrollContainer
class_name InformationDetailsView

const COLOR_HEADING: Color = Color(0.4, 0.85, 0.9)
const COLOR_BODY: Color = Color(0.78, 0.84, 0.87)
const SCROLL_STEP: int = 56

@onready var _preview: EnemyIconPreview = $Entries/PreviewCenter/ModelPreview
@onready var _placeholder: Label = $Entries/PreviewCenter/Placeholder
@onready var _name_label: Label = $Entries/Name
@onready var _subtitle: Label = $Entries/Subtitle
@onready var _sections: VBoxContainer = $Entries/Sections

var _entry_id: StringName = &""

## Category-independent content: identity, model, optional exposure and sections.
## Sections accept a title, text and optional label/value stat rows.
func show_entry(entry: Dictionary) -> void:
	_entry_id = StringName(entry.get("id", &""))
	_name_label.text = String(entry.get("name", "Unknown"))
	_subtitle.text = String(entry.get("subtitle", ""))
	_subtitle.visible = not _subtitle.text.is_empty()
	_preview.set_exposure_multiplier(float(entry.get("exposure_multiplier", 1.0)))
	_preview.visible = _preview.set_model(entry.get("model_scene") as PackedScene)
	_placeholder.visible = not _preview.visible
	_placeholder.text = String(entry.get("placeholder", "!"))
	for child: Node in _sections.get_children():
		_sections.remove_child(child)
		child.queue_free()
	for section: Dictionary in entry.get("sections", []):
		_add_section(section)
	scroll_vertical = 0

func get_entry_id() -> StringName:
	return _entry_id

func get_preview() -> EnemyIconPreview:
	return _preview

func _add_section(section: Dictionary) -> void:
	var block: VBoxContainer = VBoxContainer.new()
	block.add_theme_constant_override("separation", 7)
	_sections.add_child(block)
	var heading: Label = _label(String(section.get("title", "")).to_upper(), 17, COLOR_HEADING)
	block.add_child(heading)
	var text: String = String(section.get("text", ""))
	if not text.is_empty():
		block.add_child(_label(text, 17, COLOR_BODY))
	var rows: Array = section.get("stats", [])
	if rows.is_empty():
		return
	var stats: GridContainer = GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 20)
	stats.add_theme_constant_override("v_separation", 6)
	block.add_child(stats)
	for row: Dictionary in rows:
		var label: Label = _label(String(row.get("label", "")), 17, COLOR_BODY)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(label)
		var value: Label = _label(String(row.get("value", "")), 17, Color(0.95, 0.78, 0.4))
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats.add_child(value)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func wire_focus(back: Button, close: Button, left_menu: Button) -> void:
	back.focus_neighbor_left = back.get_path_to(left_menu)
	back.focus_neighbor_right = back.get_path_to(close)
	back.focus_neighbor_top = back.get_path_to(close)
	back.focus_neighbor_bottom = back.get_path_to(self)
	back.focus_previous = back.get_path_to(close)
	back.focus_next = back.get_path_to(self)
	focus_neighbor_left = get_path_to(left_menu)
	focus_neighbor_right = get_path_to(close)
	focus_neighbor_top = get_path_to(back)
	focus_neighbor_bottom = get_path_to(close)
	focus_previous = get_path_to(back)
	focus_next = get_path_to(close)
	close.focus_neighbor_left = close.get_path_to(back)
	close.focus_neighbor_right = close.get_path_to(close)
	close.focus_neighbor_top = close.get_path_to(back)
	close.focus_neighbor_bottom = close.get_path_to(self)
	close.focus_previous = close.get_path_to(self)
	close.focus_next = close.get_path_to(back)

func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_down", true):
		scroll_vertical += SCROLL_STEP
		accept_event()
	elif event.is_action_pressed(&"ui_up", true):
		if scroll_vertical <= 0:
			var above: Control = get_node_or_null(focus_neighbor_top) as Control
			if above != null:
				above.grab_focus()
		else:
			scroll_vertical -= SCROLL_STEP
		accept_event()
