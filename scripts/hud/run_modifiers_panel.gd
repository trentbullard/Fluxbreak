extends ScrollContainer
class_name RunModifiersPanel

const COLOR_HEADER: Color = Color(0.7, 0.7, 0.7)
const COLOR_NAME: Color = Color(0.9, 0.8, 0.5)
const COLOR_DESCRIPTION: Color = Color(0.8, 0.8, 0.8)
const COLOR_EMPTY: Color = Color(0.58, 0.61, 0.66)

## Match the pause menu's existing ship statistics typography.
@export var menu_font: FontFile = preload("res://assets/fonts/Oxanium/Oxanium-Regular.ttf")

@onready var entries: VBoxContainer = $Entries

func _ready() -> void:
	var font_theme: Theme = Theme.new()
	font_theme.default_font = menu_font
	theme = font_theme
	get_viewport().size_changed.connect(_update_panel_width)
	_update_panel_width()
	refresh()

func refresh() -> void:
	for child: Node in entries.get_children():
		entries.remove_child(child)
		child.queue_free()
	_add_section("MAP MODIFIERS")
	var stage_modifiers: Array[StageModifierDef] = GameFlow.get_active_stage_modifiers()
	var has_map_modifier: bool = false
	for modifier: StageModifierDef in stage_modifiers:
		if modifier == null:
			continue
		has_map_modifier = true
		_add_entry(modifier.get_display_name_or_default(), modifier.description)
	if not has_map_modifier:
		_add_label("No active map modifiers.", 13, COLOR_EMPTY)

	_add_section("FACTION MODIFIERS")
	var faction: FactionDef = GameFlow.get_run_faction()
	if faction != null:
		_add_label(faction.get_display_name_or_default(), 14, COLOR_DESCRIPTION)
	# Factions currently have no authored modifier data. Do not present their
	# descriptive lore or individual ship statistics as active run modifiers.
	_add_label("No active faction modifiers.", 13, COLOR_EMPTY)

	_add_section("RUN UPGRADES")
	var upgrades: Array[Dictionary] = RunState.get_purchased_upgrade_entries()
	if upgrades.is_empty():
		_add_label("No upgrades chosen this run.", 13, COLOR_EMPTY)
	else:
		for upgrade: Dictionary in upgrades:
			_add_entry(String(upgrade.get("name", "Upgrade")), String(upgrade.get("description", "")))

func _update_panel_width() -> void:
	var panel_width: float = clampf(get_viewport_rect().size.x * 0.27, 220.0, 360.0)
	offset_left = -20.0 - panel_width
	offset_right = -20.0

func _add_section(title: String) -> void:
	if entries.get_child_count() > 0:
		var spacer: Control = Control.new()
		spacer.custom_minimum_size = Vector2(0.0, 12.0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entries.add_child(spacer)
	_add_label(title, 16, COLOR_HEADER)

func _add_entry(title: String, description: String) -> void:
	var entry: VBoxContainer = VBoxContainer.new()
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_theme_constant_override("separation", 3)
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entries.add_child(entry)
	_add_label(title, 15, COLOR_NAME, entry)
	if not description.strip_edges().is_empty():
		_add_label(description, 13, COLOR_DESCRIPTION, entry)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 5.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(spacer)

func _add_label(text: String, font_size: int, color: Color, parent: VBoxContainer = null) -> void:
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	var target: VBoxContainer = entries if parent == null else parent
	target.add_child(label)
