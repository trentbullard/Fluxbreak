extends ScrollContainer
class_name InformationIconGrid

const COLUMNS: int = 4
const COLOR_UNKNOWN: Color = Color(0.58, 0.7, 0.75)
const COLOR_KNOWN: Color = Color(0.95, 0.78, 0.4)

@onready var entries: VBoxContainer = $Entries

var _entry_buttons: Array[Button] = []
var _rows: Array[Array] = []
var _section_grid: GridContainer = null
var _section_index: int = 0

func get_entry_buttons() -> Array[Button]:
	return _entry_buttons.duplicate()

func _clear_entries() -> void:
	for child: Node in entries.get_children():
		entries.remove_child(child)
		child.queue_free()
	_entry_buttons.clear()
	_rows.clear()
	_section_grid = null
	_section_index = 0

func _begin_section(title: String) -> void:
	if not title.is_empty():
		var header: Label = Label.new()
		header.text = title.to_upper()
		header.add_theme_font_size_override("font_size", 16)
		header.add_theme_color_override("font_color", Color(0.4, 0.85, 0.9))
		entries.add_child(header)
	_section_grid = GridContainer.new()
	_section_grid.columns = COLUMNS
	_section_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section_grid.add_theme_constant_override("h_separation", 8)
	_section_grid.add_theme_constant_override("v_separation", 8)
	entries.add_child(_section_grid)
	_section_index = 0

func _append_icon(entry_id: StringName) -> Button:
	if _section_grid == null:
		_begin_section("")
	if _section_index % COLUMNS == 0:
		_rows.append([])
	var button: Button = Button.new()
	button.name = "Entry_" + String(entry_id)
	button.custom_minimum_size = Vector2(72.0, 72.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 36)
	button.set_meta(&"entry_id", entry_id)
	# Activation remains empty until reference details and portraits are authored.
	_section_grid.add_child(button)
	_entry_buttons.append(button)
	_rows[_rows.size() - 1].append(button)
	_section_index += 1
	return button

func _set_icon_state(button: Button, known: bool, display_name: String, hidden_name: String) -> void:
	button.text = "!" if known else "?"
	button.tooltip_text = display_name if known else hidden_name
	button.add_theme_color_override("font_color", COLOR_KNOWN if known else COLOR_UNKNOWN)

## One cached visual-only preview per known entry; missing models keep the marker.
func _set_model_preview(button: Button, model_scene: PackedScene, known: bool) -> void:
	var preview: EnemyIconPreview = button.get_node_or_null("ModelPreview") as EnemyIconPreview
	if not known or model_scene == null:
		if preview != null:
			preview.hide()
		return
	if preview == null:
		preview = EnemyIconPreview.new()
		preview.name = "ModelPreview"
		button.add_child(preview)
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.offset_left = 4.0
		preview.offset_top = 4.0
		preview.offset_right = -4.0
		preview.offset_bottom = -4.0
	preview.show()
	if preview.set_model(model_scene):
		button.text = ""
	else:
		preview.hide()

func _add_empty_message(message: String) -> void:
	var label: Label = Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", COLOR_UNKNOWN)
	entries.add_child(label)

## Reopening starts at the first section, not at a previously focused late icon.
func _reset_scroll() -> void:
	scroll_vertical = 0

## Grid navigation crosses sections and reaches the shared panel close button.
func wire_focus(back: Button, left_menu: Button = null) -> void:
	for row_index: int in _rows.size():
		var row: Array = _rows[row_index]
		for column: int in row.size():
			var button: Button = row[column] as Button
			var above: Button = back
			var below: Button = back
			if row_index > 0:
				var previous: Array = _rows[row_index - 1]
				above = previous[mini(column, previous.size() - 1)] as Button
			if row_index + 1 < _rows.size():
				var next: Array = _rows[row_index + 1]
				below = next[mini(column, next.size() - 1)] as Button
			button.focus_neighbor_top = button.get_path_to(above)
			button.focus_neighbor_bottom = button.get_path_to(below)
			var left: Button = row[maxi(column - 1, 0)] as Button
			if column == 0 and left_menu != null:
				left = left_menu
			button.focus_neighbor_left = button.get_path_to(left)
			button.focus_neighbor_right = button.get_path_to(row[mini(column + 1, row.size() - 1)] as Button)
	for index: int in _entry_buttons.size():
		var button: Button = _entry_buttons[index]
		button.focus_previous = button.get_path_to(_entry_buttons[index - 1] if index > 0 else back)
		button.focus_next = button.get_path_to(_entry_buttons[index + 1] if index + 1 < _entry_buttons.size() else back)
	if not _entry_buttons.is_empty():
		back.focus_neighbor_top = back.get_path_to(_entry_buttons.back())
		back.focus_previous = back.focus_neighbor_top
		back.focus_neighbor_bottom = back.get_path_to(_entry_buttons.front())
		back.focus_next = back.focus_neighbor_bottom
