# upgrades_panel.gd (Godot 4.6.3)
# Full-screen overlay panel for browsing and purchasing meta upgrades.
# Uses a staged pending-changes flow: players stage changes with [+]/[-] buttons,
# then confirm via Apply or discard via Reset/Close.
extends CanvasLayer
class_name UpgradesPanel

signal closed

@export_group("Upgrades")
## Shared catalog used by both the main menu and runtime meta upgrade wiring.
@export var meta_upgrade_catalog: MetaUpgradeCatalog = preload("res://content/data/meta_upgrades/meta_upgrade_catalog.tres")
## List of meta upgrades to display in the panel.
## Used as a fallback when no catalog is assigned.
@export var meta_upgrades: Array[MetaUpgradeDef] = []

@export_group("Display")
## Font used for all panel UI text.
@export var menu_font: FontFile = preload("res://assets/fonts/Oxanium/Oxanium-Regular.ttf")
## Font used for upgrade description sub-text.
@export var desc_font: FontFile = preload("res://assets/fonts/Chakra_Petch/ChakraPetch-Light.ttf")

@onready var btn_close: Button = $Close

# --- Procedurally built UI references ---
var _root: Control = null
var _balance_label: Label = null
var _pending_cost_label: Label = null
var _apply_btn: Button = null
var _reset_btn: Button = null

# Per-upgrade row data: { upgrade, tier_label, plus_btn, minus_btn, cost_label }
var _row_data: Array[Dictionary] = []
var _logistics_row_data: Array[Dictionary] = []

# Staged (uncommitted) tier levels: upgrade_id -> int
var _pending_levels: Dictionary = {}
var _pending_logistics_levels: Dictionary = {}


func _ready() -> void:
	layer = 4
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if btn_close != null:
		btn_close.pressed.connect(_on_close_pressed)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_menu_font_theme()
	add_child(_root)

	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.04, 0.08, 0.0)
	_root.add_child(bg)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Header row: title + balance
	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 20)
	vbox.add_child(header_row)

	var title_label: Label = Label.new()
	title_label.text = "Upgrades & Logistics"
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_label)

	_balance_label = Label.new()
	_balance_label.text = "Flux Anchors: 0"
	_balance_label.add_theme_font_size_override("font_size", 22)
	_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_row.add_child(_balance_label)

	# Pending cost row
	_pending_cost_label = Label.new()
	_pending_cost_label.text = "No Pending Changes"
	_pending_cost_label.add_theme_font_size_override("font_size", 16)
	_pending_cost_label.modulate = Color(0.7, 0.7, 0.7, 1.0)
	vbox.add_child(_pending_cost_label)

	# Apply / Reset action row
	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 15)
	vbox.add_child(action_row)

	_apply_btn = Button.new()
	_apply_btn.text = "Apply"
	_apply_btn.focus_mode = Control.FOCUS_ALL
	_apply_btn.add_theme_font_size_override("font_size", 18)
	_apply_btn.pressed.connect(_on_apply_pressed)
	action_row.add_child(_apply_btn)

	_reset_btn = Button.new()
	_reset_btn.text = "Reset"
	_reset_btn.focus_mode = Control.FOCUS_ALL
	_reset_btn.add_theme_font_size_override("font_size", 18)
	_reset_btn.pressed.connect(_on_reset_pressed)
	action_row.add_child(_reset_btn)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(spacer)

	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	# Upgrade list in scroll container
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600.0, 350.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var scroll_vbox: VBoxContainer = VBoxContainer.new()
	scroll_vbox.add_theme_constant_override("separation", 8)
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_vbox)

	_add_section_title(scroll_vbox, "Logistics")
	var logistics_hint: Label = Label.new()
	logistics_hint.text = "Permanent allowances. Uses refill each new run and are shared across all stations."
	logistics_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	logistics_hint.add_theme_font_size_override("font_size", 13)
	logistics_hint.modulate = Color(0.65, 0.75, 0.85, 1.0)
	scroll_vbox.add_child(logistics_hint)
	_logistics_row_data.clear()
	for definition: LogisticsDef in GameFlow.get_all_logistics():
		var row: Dictionary = _add_purchase_row(scroll_vbox, definition.display_name, definition.description,
			_on_logistics_plus_pressed.bind(definition.id), _on_logistics_minus_pressed.bind(definition.id))
		row["logistics"] = definition
		_logistics_row_data.append(row)
	scroll_vbox.add_child(HSeparator.new())
	_add_section_title(scroll_vbox, "Permanent Upgrades")
	_row_data.clear()
	for upgrade: MetaUpgradeDef in _get_meta_upgrades():
		if upgrade == null:
			continue
		var row: Dictionary = _add_purchase_row(scroll_vbox, upgrade.display_name, upgrade.description,
			_on_plus_pressed.bind(upgrade.id), _on_minus_pressed.bind(upgrade.id))
		row["upgrade"] = upgrade
		_row_data.append(row)

	# Reparent close button above the dim to keep it accessible
	if btn_close != null:
		btn_close.reparent(_root)
		btn_close.focus_mode = Control.FOCUS_ALL
		btn_close.add_theme_font_size_override("font_size", 47)

func _add_section_title(parent: VBoxContainer, text: String) -> void:
	var title: Label = Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", 20)
	parent.add_child(title)

## Both sections share presentation without treating Logistics as stat upgrades.
func _add_purchase_row(parent: VBoxContainer, display_name: String, description: String, on_plus: Callable, on_minus: Callable) -> Dictionary:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var name_col: VBoxContainer = VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 1)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_col)
	var name_label: Label = Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_col.add_child(name_label)
	var desc_label: Label = Label.new()
	desc_label.text = description
	desc_label.add_theme_font_override("font", desc_font)
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.modulate = Color(0.65, 0.75, 0.85, 1.0)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_col.add_child(desc_label)
	var tier_label: Label = Label.new()
	tier_label.add_theme_font_size_override("font_size", 16)
	tier_label.custom_minimum_size = Vector2(55.0, 0.0)
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(tier_label)
	var minus_btn: Button = Button.new()
	minus_btn.text = "[-]"
	minus_btn.focus_mode = Control.FOCUS_ALL
	minus_btn.add_theme_font_size_override("font_size", 16)
	minus_btn.custom_minimum_size = Vector2(45.0, 0.0)
	minus_btn.pressed.connect(on_minus)
	row.add_child(minus_btn)
	var plus_btn: Button = Button.new()
	plus_btn.text = "[+]"
	plus_btn.focus_mode = Control.FOCUS_ALL
	plus_btn.add_theme_font_size_override("font_size", 16)
	plus_btn.custom_minimum_size = Vector2(45.0, 0.0)
	plus_btn.pressed.connect(on_plus)
	row.add_child(plus_btn)
	var cost_label: Label = Label.new()
	cost_label.add_theme_font_size_override("font_size", 14)
	cost_label.custom_minimum_size = Vector2(80.0, 0.0)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(cost_label)
	return {"tier_label": tier_label, "plus_btn": plus_btn, "minus_btn": minus_btn, "cost_label": cost_label}


func _apply_menu_font_theme() -> void:
	if _root == null or menu_font == null:
		return
	var theme: Theme = Theme.new()
	theme.default_font = menu_font
	_root.theme = theme


func show_panel() -> void:
	_load_pending_levels()
	_refresh_display()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_focus_available_action.call_deferred()

func _load_pending_levels() -> void:
	_pending_levels = GameFlow.get_current_meta_upgrade_levels()
	_pending_logistics_levels = GameFlow.get_current_logistics_levels()

func _refresh_display() -> void:
	if _balance_label == null or _pending_cost_label == null or _apply_btn == null or _reset_btn == null:
		return

	var current_balance: int = GameFlow.flux_anchors
	_balance_label.text = "Flux Anchors: %d" % [current_balance]

	var current_levels: Dictionary = GameFlow.get_current_meta_upgrade_levels()
	var pending_cost: int = _calculate_pending_cost(current_levels)

	if pending_cost > 0:
		_pending_cost_label.text = "Pending Cost: %d FA" % [pending_cost]
		_pending_cost_label.modulate = Color(1.0, 0.6, 0.1, 1.0)
	elif pending_cost < 0:
		_pending_cost_label.text = "Pending Refund: %d FA" % [-pending_cost]
		_pending_cost_label.modulate = Color(0.3, 1.0, 0.4, 1.0)
	else:
		_pending_cost_label.text = "No Pending Changes"
		_pending_cost_label.modulate = Color(0.7, 0.7, 0.7, 1.0)

	var has_changes: bool = _has_pending_changes(current_levels)
	_apply_btn.disabled = not has_changes or pending_cost > current_balance
	_reset_btn.disabled = not has_changes

	for row in _row_data:
		var upgrade: MetaUpgradeDef = row["upgrade"] as MetaUpgradeDef
		if upgrade == null:
			continue

		var pending_tier: int = int(_pending_levels.get(upgrade.id, 0))
		var current_tier: int = int(current_levels.get(upgrade.id, 0))

		var tier_label: Label = row["tier_label"] as Label
		var plus_btn: Button = row["plus_btn"] as Button
		var minus_btn: Button = row["minus_btn"] as Button
		var cost_label: Label = row["cost_label"] as Label

		tier_label.text = "[%d/%d]" % [pending_tier, upgrade.max_tiers]
		if pending_tier > current_tier:
			tier_label.modulate = Color(1.0, 0.6, 0.1, 1.0)
		elif pending_tier < current_tier:
			tier_label.modulate = Color(0.3, 1.0, 0.4, 1.0)
		else:
			tier_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

		# Plus: disabled if maxed or adding this tier would exceed remaining balance
		var next_tier_cost: int = upgrade.get_tier_cost(pending_tier + 1) if pending_tier < upgrade.max_tiers else 0
		plus_btn.disabled = (pending_tier >= upgrade.max_tiers) or ((pending_cost + next_tier_cost) > current_balance)

		# Minus: disabled if already at floor
		minus_btn.disabled = pending_tier <= 0

		# Cost label: next tier price or MAX indicator
		if pending_tier >= upgrade.max_tiers:
			cost_label.text = "MAX"
			cost_label.modulate = Color(0.5, 0.8, 1.0, 1.0)
		else:
			cost_label.text = "%d FA" % [upgrade.get_tier_cost(pending_tier + 1)]
			cost_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

	var current_logistics: Dictionary = GameFlow.get_current_logistics_levels()
	for row: Dictionary in _logistics_row_data:
		var definition: LogisticsDef = row["logistics"] as LogisticsDef
		var pending: int = int(_pending_logistics_levels.get(definition.id, 0))
		var current: int = int(current_logistics.get(definition.id, 0))
		var tier_label: Label = row["tier_label"] as Label
		var plus_btn: Button = row["plus_btn"] as Button
		var minus_btn: Button = row["minus_btn"] as Button
		var cost_label: Label = row["cost_label"] as Label
		tier_label.text = "%d/%d\nper run" % [pending, definition.max_tiers]
		tier_label.modulate = Color(1.0, 0.6, 0.1) if pending > current else (Color(0.3, 1.0, 0.4) if pending < current else Color.WHITE)
		var next_cost: int = definition.get_tier_cost(pending + 1)
		plus_btn.disabled = pending >= definition.max_tiers or pending_cost + next_cost > current_balance
		minus_btn.disabled = pending <= 0
		cost_label.text = "MAX" if pending >= definition.max_tiers else "%d FA" % next_cost
		cost_label.modulate = Color(0.5, 0.8, 1.0) if pending >= definition.max_tiers else Color.WHITE
	if visible:
		var focus: Button = get_viewport().gui_get_focus_owner() as Button
		if focus == null or focus.disabled or not focus.is_visible_in_tree():
			_focus_available_action.call_deferred()


func _calculate_pending_cost(current_levels: Dictionary) -> int:
	var total: int = 0
	for upgrade in _get_meta_upgrades():
		if upgrade == null or upgrade.id == "":
			continue
		var pending_tier: int = int(_pending_levels.get(upgrade.id, 0))
		var current_tier: int = int(current_levels.get(upgrade.id, 0))
		total += upgrade.get_total_cost_for_levels(current_tier, pending_tier)
	var current_logistics: Dictionary = GameFlow.get_current_logistics_levels()
	for definition: LogisticsDef in GameFlow.get_all_logistics():
		total += definition.get_total_cost_for_levels(int(current_logistics.get(definition.id, 0)), int(_pending_logistics_levels.get(definition.id, 0)))
	return total


func _has_pending_changes(current_levels: Dictionary) -> bool:
	for upgrade in _get_meta_upgrades():
		if upgrade == null or upgrade.id == "":
			continue
		var pending_tier: int = int(_pending_levels.get(upgrade.id, 0))
		var current_tier: int = int(current_levels.get(upgrade.id, 0))
		if pending_tier != current_tier:
			return true
	var current_logistics: Dictionary = GameFlow.get_current_logistics_levels()
	for definition: LogisticsDef in GameFlow.get_all_logistics():
		if int(_pending_logistics_levels.get(definition.id, 0)) != int(current_logistics.get(definition.id, 0)):
			return true
	return false


func _on_plus_pressed(upgrade_id: String) -> void:
	var upgrade: MetaUpgradeDef = _find_upgrade_by_id(upgrade_id)
	if upgrade == null:
		return
	var current_pending: int = int(_pending_levels.get(upgrade_id, 0))
	if current_pending < upgrade.max_tiers:
		_pending_levels[upgrade_id] = current_pending + 1
		_refresh_display()


func _on_minus_pressed(upgrade_id: String) -> void:
	var current_pending: int = int(_pending_levels.get(upgrade_id, 0))
	if current_pending > 0:
		_pending_levels[upgrade_id] = current_pending - 1
		_refresh_display()


func _on_apply_pressed() -> void:
	if GameFlow.apply_meta_purchases(_pending_levels, _pending_logistics_levels):
		_load_pending_levels()
		_refresh_display()


func _on_reset_pressed() -> void:
	_load_pending_levels()
	_refresh_display()

func _on_logistics_plus_pressed(logistics_id: String) -> void:
	for definition: LogisticsDef in GameFlow.get_all_logistics():
		if definition.id != logistics_id:
			continue
		var pending: int = int(_pending_logistics_levels.get(logistics_id, 0))
		if pending < definition.max_tiers:
			_pending_logistics_levels[logistics_id] = pending + 1
			_refresh_display()
		return

func _on_logistics_minus_pressed(logistics_id: String) -> void:
	var pending: int = int(_pending_logistics_levels.get(logistics_id, 0))
	if pending > 0:
		_pending_logistics_levels[logistics_id] = pending - 1
		_refresh_display()

func _focus_available_action() -> void:
	if not visible:
		return
	for row: Dictionary in _logistics_row_data + _row_data:
		for key: String in ["plus_btn", "minus_btn"]:
			var button: Button = row[key] as Button
			if not button.disabled and button.is_visible_in_tree():
				button.grab_focus()
				return
	if btn_close != null:
		btn_close.grab_focus()


func _on_close_pressed() -> void:
	_on_reset_pressed()
	visible = false
	closed.emit()


func _find_upgrade_by_id(upgrade_id: String) -> MetaUpgradeDef:
	for upgrade in _get_meta_upgrades():
		if upgrade != null and upgrade.id == upgrade_id:
			return upgrade
	return null


func _get_meta_upgrades() -> Array[MetaUpgradeDef]:
	if meta_upgrade_catalog != null:
		var catalog_upgrades: Array[MetaUpgradeDef] = meta_upgrade_catalog.get_upgrades()
		if not catalog_upgrades.is_empty():
			return catalog_upgrades
	return meta_upgrades
