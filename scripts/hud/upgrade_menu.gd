# scripts/hud/upgrade_menu.gd (Godot 4.7.2)
# Shared POI purchase UI; offer generation and exclusions live in UpgradeOfferService.
extends CanvasLayer
class_name UpgradeMenu

signal upgrade_selected(upgrade: Upgrade)
signal weapon_selected(weapon: WeaponDef)
signal menu_closed

@export_group("Upgrade Pool")
## Upgrade catalog supplied to the shared offer service.
@export var available_upgrades: Array[Upgrade] = []
## Separate weapon offers, unaffected by upgrade Logistics actions.
@export var available_weapons: Array[WeaponDef] = []
## Existing purchase-memory weighting configuration.
@export var offer_memory_def: UpgradeOfferMemoryDef

@export_group("Display")
## Fallback number of choices when a POI does not specify its own.
@export var num_upgrade_choices: int = 3
## Shared modal font.
@export var menu_font: FontFile = preload("res://assets/fonts/Oxanium/Oxanium-Regular.ttf")

@onready var btn_close: Button = $Close
const FULL_WEAPON_MOUNTS_TEXT: String = "All weapon mounts occupied"

var _root: Control
var _dim: ColorRect
var _container: VBoxContainer
var _title_label: Label
var _buttons: Array[Button] = []
var _upgrade_buttons: Array[Button] = []
var _blacklist_buttons: Array[Button] = []
var _upgrade_rows: Array[HBoxContainer] = []
var _upgrade_column: VBoxContainer
var _refresh_stock_button: Button
var _weapon_button: Button
var _weapon_separator: HSeparator
var _weapon_section: VBoxContainer
var _empty_upgrades_label: Label
var _current_poi: PoiInstance = null
var _offer_service: UpgradeOfferService = UpgradeOfferService.new()

# Presentation snapshots; each POI owns its cached offers and base prices.
var _upgrade_choices: Array[Upgrade] = []
var _upgrade_offer_costs: Array[int] = []
var _weapon_choice: WeaponDef = null
var _last_offer_debug: Dictionary = {}
var _current_nanobots: int = 0
var _was_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	RunState.nanobots_updated.connect(_on_nanobots_updated)
	RunState.logistics_changed.connect(_on_logistics_changed)
	layer = 3
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_menu_font_theme()
	add_child(_root)

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.7)
	_root.add_child(_dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	center.add_child(panel)

	if btn_close != null:
		btn_close.reparent(_root)
		btn_close.focus_mode = Control.FOCUS_ALL
		btn_close.pressed.connect(_close_without_purchase)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 25)
	margin.add_theme_constant_override("margin_bottom", 25)
	panel.add_child(margin)

	_container = VBoxContainer.new()
	_container.add_theme_constant_override("separation", 16)
	margin.add_child(_container)
	_title_label = Label.new()
	_title_label.text = "Choose an Upgrade or Weapon"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	_container.add_child(_title_label)
	_container.add_child(HSeparator.new())

	var upgrade_section: HBoxContainer = HBoxContainer.new()
	upgrade_section.add_theme_constant_override("separation", 18)
	_container.add_child(upgrade_section)
	var refresh_column: CenterContainer = CenterContainer.new()
	upgrade_section.add_child(refresh_column)
	_refresh_stock_button = Button.new()
	_refresh_stock_button.name = "RefreshStock"
	_refresh_stock_button.custom_minimum_size = Vector2(155.0, 52.0)
	_refresh_stock_button.focus_mode = Control.FOCUS_ALL
	_refresh_stock_button.pressed.connect(_on_refresh_stock_pressed)
	refresh_column.add_child(_refresh_stock_button)

	_upgrade_column = VBoxContainer.new()
	_upgrade_column.add_theme_constant_override("separation", 12)
	upgrade_section.add_child(_upgrade_column)
	_empty_upgrades_label = Label.new()
	_empty_upgrades_label.text = "No eligible upgrades remaining."
	_empty_upgrades_label.custom_minimum_size = Vector2(400.0, 52.0)
	_empty_upgrades_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_column.add_child(_empty_upgrades_label)

	_weapon_section = VBoxContainer.new()
	_weapon_section.add_theme_constant_override("separation", 14)
	_container.add_child(_weapon_section)
	_weapon_separator = HSeparator.new()
	_weapon_section.add_child(_weapon_separator)
	var weapon_label: Label = Label.new()
	weapon_label.text = "WEAPON"
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.88))
	_weapon_section.add_child(weapon_label)
	_weapon_button = Button.new()
	_weapon_button.name = "WeaponOffer"
	_weapon_button.custom_minimum_size = Vector2(400.0, 52.0)
	_weapon_button.focus_mode = Control.FOCUS_ALL
	_weapon_button.pressed.connect(_on_weapon_pressed)
	_weapon_section.add_child(_weapon_button)
	_ensure_upgrade_rows(maxi(num_upgrade_choices, 1))
	_update_buttons()

func _ensure_upgrade_rows(count: int) -> void:
	var desired: int = maxi(count, 1)
	while _upgrade_rows.size() > desired:
		var removed: HBoxContainer = _upgrade_rows.pop_back()
		_upgrade_column.remove_child(removed)
		removed.queue_free()
		_upgrade_buttons.pop_back()
		_blacklist_buttons.pop_back()
	while _upgrade_rows.size() < desired:
		var index: int = _upgrade_rows.size()
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_upgrade_column.add_child(row)
		var purchase: Button = Button.new()
		purchase.name = "Upgrade%d" % index
		purchase.custom_minimum_size = Vector2(400.0, 62.0)
		purchase.add_theme_font_size_override("font_size", 16)
		purchase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		purchase.focus_mode = Control.FOCUS_ALL
		purchase.pressed.connect(_on_button_pressed.bind(index))
		row.add_child(purchase)
		var blacklist: Button = Button.new()
		blacklist.name = "Blacklist%d" % index
		blacklist.custom_minimum_size = Vector2(130.0, 52.0)
		blacklist.focus_mode = Control.FOCUS_ALL
		blacklist.pressed.connect(_on_blacklist_pressed.bind(index))
		row.add_child(blacklist)
		_upgrade_rows.append(row)
		_upgrade_buttons.append(purchase)
		_blacklist_buttons.append(blacklist)
	_buttons = _upgrade_buttons.duplicate()
	_buttons.append(_weapon_button)

func _apply_menu_font_theme() -> void:
	if _root == null or menu_font == null:
		return
	var menu_theme: Theme = Theme.new()
	menu_theme.default_font = menu_font
	_root.theme = menu_theme

func _configure_offer_service() -> void:
	_offer_service.configure(available_upgrades, available_weapons, offer_memory_def, num_upgrade_choices)

func show_for_poi(poi: PoiInstance) -> void:
	_current_poi = poi
	_randomize_choices(poi)
	visible = true
	get_tree().paused = true
	_was_mouse_mode = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_update_buttons()
	_focus_default_control()

## Legacy entry point now reads the stable POI offer, rather than rerolling on entry.
func _randomize_choices(poi: PoiInstance) -> void:
	_configure_offer_service()
	_read_offer(_offer_service.get_or_create_offer(poi))

func _read_offer(offer: Dictionary) -> void:
	_upgrade_choices.assign(offer.get("upgrades", []))
	_upgrade_offer_costs.assign(offer.get("costs", []))
	_weapon_choice = offer.get("weapon") as WeaponDef
	_last_offer_debug = (offer.get("debug", {}) as Dictionary).duplicate(true)

func _on_refresh_stock_pressed() -> void:
	if not visible or not is_instance_valid(_current_poi):
		return
	if _offer_service.refresh_stock(_current_poi):
		_read_offer(_offer_service.get_or_create_offer(_current_poi))
	_update_buttons()

func _on_blacklist_pressed(index: int) -> void:
	if not visible or not is_instance_valid(_current_poi) or index < 0 or index >= _upgrade_choices.size():
		return
	var upgrade: Upgrade = _upgrade_choices[index]
	if _offer_service.blacklist_upgrade(_current_poi, upgrade):
		_read_offer(_offer_service.get_or_create_offer(_current_poi))
	_update_buttons()

func _on_logistics_changed() -> void:
	if visible:
		_read_offer(_offer_service.get_or_create_offer(_current_poi))
		_update_buttons()

func _get_offer_cost(index: int, upgrade: Upgrade) -> int:
	if index >= 0 and index < _upgrade_offer_costs.size():
		return _apply_poi_cost_multiplier(_upgrade_offer_costs[index])
	return _apply_poi_cost_multiplier(maxi(upgrade.cost, 1) if upgrade != null else 1)

func _get_weapon_offer_cost(weapon: WeaponDef) -> int:
	if weapon == null:
		return 1
	return _apply_poi_cost_multiplier(RunState.get_weapon_cost(weapon.cost))

func _apply_poi_cost_multiplier(base_cost: int) -> int:
	var player_ship: Ship = _get_player_ship()
	var multiplier: float = maxf(player_ship.get_effective_poi_cost_mult(), 0.0) if player_ship != null else 1.0
	return maxi(int(round(float(maxi(base_cost, 1)) * multiplier)), 1)

func _update_buttons() -> void:
	if _refresh_stock_button == null:
		return
	_ensure_upgrade_rows(_upgrade_choices.size())
	var refresh_remaining: int = RunState.get_refresh_stock_remaining()
	var blacklist_remaining: int = RunState.get_blacklist_remaining()
	_refresh_stock_button.text = "Refresh Stock (%d)" % refresh_remaining
	_refresh_stock_button.disabled = refresh_remaining <= 0 or not is_instance_valid(_current_poi) or not _offer_service.can_refresh_stock(_current_poi)
	_refresh_stock_button.tooltip_text = "Replace upgrade offers only. Shared allowance for this run."
	if refresh_remaining <= 0:
		_refresh_stock_button.tooltip_text = "No refresh uses remaining. Purchase permanent per-run allowances in the main menu's Logistics section."
	if refresh_remaining > 0 and _refresh_stock_button.disabled:
		_refresh_stock_button.tooltip_text = "No different eligible upgrades are available. No use will be spent."
	for index: int in range(_upgrade_rows.size()):
		var has_upgrade: bool = index < _upgrade_choices.size()
		_upgrade_rows[index].visible = has_upgrade
		var purchase: Button = _upgrade_buttons[index]
		var blacklist: Button = _blacklist_buttons[index]
		blacklist.text = "Blacklist (%d)" % blacklist_remaining
		blacklist.disabled = not has_upgrade or blacklist_remaining <= 0
		if has_upgrade:
			var upgrade: Upgrade = _upgrade_choices[index]
			var offer_cost: int = _get_offer_cost(index, upgrade)
			purchase.text = "%s (%d)\n%s" % [upgrade.display_name, offer_cost, upgrade.descripton]
			purchase.disabled = offer_cost > _current_nanobots
			var family_name: String = _offer_service.get_upgrade_family(upgrade).replace("_", " ").capitalize()
			blacklist.tooltip_text = "Exclude all tiers of %s from every upgrade POI for the rest of this run. Upgrades already purchased remain active." % family_name
	_empty_upgrades_label.visible = _upgrade_choices.is_empty()
	_weapon_section.visible = _weapon_choice != null
	_weapon_button.visible = _weapon_choice != null
	if _weapon_choice != null:
		if _has_open_weapon_mount():
			var weapon_cost: int = _get_weapon_offer_cost(_weapon_choice)
			_weapon_button.text = "+ %s (%d)" % [_weapon_choice.display_name, weapon_cost]
			_weapon_button.disabled = weapon_cost > _current_nanobots
		else:
			_weapon_button.text = FULL_WEAPON_MOUNTS_TEXT
			_weapon_button.disabled = true
	_update_focus_navigation()
	if visible:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused == null or not focused.is_visible_in_tree() or (focused is BaseButton and (focused as BaseButton).disabled):
			call_deferred("_focus_default_control")

func _update_focus_navigation() -> void:
	var controls: Array[Button] = []
	if not _refresh_stock_button.disabled:
		controls.append(_refresh_stock_button)
	for index: int in range(_upgrade_choices.size()):
		if not _upgrade_buttons[index].disabled:
			controls.append(_upgrade_buttons[index])
		if not _blacklist_buttons[index].disabled:
			controls.append(_blacklist_buttons[index])
	if _weapon_choice != null and not _weapon_button.disabled:
		controls.append(_weapon_button)
	if btn_close != null:
		controls.append(btn_close)
	for index: int in range(controls.size()):
		var control: Button = controls[index]
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = control.get_path_to(controls[(index - 1 + controls.size()) % controls.size()])
		control.focus_neighbor_left = NodePath("")
		control.focus_neighbor_right = NodePath("")
		control.focus_neighbor_top = NodePath("")
		control.focus_neighbor_bottom = NodePath("")
	for index: int in range(_upgrade_choices.size()):
		var purchase: Button = _upgrade_buttons[index]
		var blacklist: Button = _blacklist_buttons[index]
		if not purchase.disabled and not blacklist.disabled:
			purchase.focus_neighbor_right = purchase.get_path_to(blacklist)
			blacklist.focus_neighbor_left = blacklist.get_path_to(purchase)
		if not purchase.disabled and not _refresh_stock_button.disabled:
			purchase.focus_neighbor_left = purchase.get_path_to(_refresh_stock_button)
	if not _refresh_stock_button.disabled and controls.size() > 1:
		_refresh_stock_button.focus_neighbor_right = _refresh_stock_button.get_path_to(controls[1])

func _on_button_pressed(index: int) -> void:
	if index >= 0 and index < _upgrade_choices.size():
		var upgrade: Upgrade = _upgrade_choices[index]
		if RunState.is_upgrade_family_blacklisted(_offer_service.get_upgrade_family(upgrade)):
			return
		var offer_cost: int = _get_offer_cost(index, upgrade)
		if offer_cost > _current_nanobots:
			return
		_spend_nanobots(offer_cost)
		RunState.record_upgrade_purchase(upgrade.id, upgrade)
		if _current_poi != null and _current_poi.poi_def != null:
			RunState.record_upgrade_purchase_for_poi(upgrade.id, _offer_service.get_upgrade_family(upgrade), int(_current_poi.poi_def.poi_type))
		_apply_upgrade(upgrade)
		upgrade_selected.emit(upgrade)
	elif index == _buttons.size() - 1:
		_on_weapon_pressed()
		return
	else:
		return
	_close_menu()

func _on_weapon_pressed() -> void:
	if _weapon_choice == null or not _has_open_weapon_mount():
		return
	var weapon_cost: int = _get_weapon_offer_cost(_weapon_choice)
	if weapon_cost > _current_nanobots:
		return
	_spend_nanobots(weapon_cost)
	_apply_weapon(_weapon_choice)
	weapon_selected.emit(_weapon_choice)
	_close_menu()

func _apply_upgrade(upgrade: Upgrade) -> void:
	var id: String = upgrade.id.to_lower()
	if "bulkhead" in id or "reinforced" in id:
		EventBus.add_bulkhead_requested.emit(upgrade)
	elif "shield" in id or "adaptive" in id:
		EventBus.add_shield_requested.emit(upgrade)
	elif "targeting" in id or "precision" in id or "capacitor" in id or "overcharged" in id:
		EventBus.add_targeting_requested.emit(upgrade)
	elif "systems" in id or "optimization" in id:
		EventBus.add_systems_requested.emit(upgrade)
	elif "salvage" in id or "magnet" in id:
		EventBus.add_salvage_requested.emit(upgrade)
	elif "thruster" in id or "vectoring" in id:
		EventBus.add_thrusters_requested.emit(upgrade)
	else:
		EventBus.add_bulkhead_requested.emit(upgrade)

func _apply_weapon(weapon: WeaponDef) -> void:
	RunState.record_weapon_purchase()
	EventBus.add_gun_requested.emit(weapon)

func _has_open_weapon_mount() -> bool:
	var player_ship: Ship = _get_player_ship()
	if player_ship == null or player_ship.hardpoint_manager == null:
		return true
	var manager: TurretHardpointManager = player_ship.hardpoint_manager
	return manager.get_weapon_count() < manager.max_assemblies

func _get_player_ship() -> Ship:
	return get_tree().get_first_node_in_group("player") as Ship

func _close_menu() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(_was_mouse_mode)
	if is_instance_valid(_current_poi):
		_current_poi.queue_free()
	_current_poi = null
	menu_closed.emit()

func _close_without_purchase() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(_was_mouse_mode)
	_current_poi = null
	menu_closed.emit()

func _spend_nanobots(amount: int) -> void:
	if amount > 0:
		_current_nanobots -= amount
		RunState.nanobots_spent.emit(amount)

func _on_nanobots_updated(amount: int) -> void:
	_current_nanobots = amount
	if visible:
		_update_buttons()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _is_controller_event(event) and get_viewport().gui_get_focus_owner() == null:
		call_deferred("_focus_default_control")
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_without_purchase()

func _focus_default_control() -> void:
	for button: Button in _buttons:
		if button.is_visible_in_tree() and not button.disabled:
			button.grab_focus()
			return
	if not _refresh_stock_button.disabled:
		_refresh_stock_button.grab_focus()
		return
	for button: Button in _blacklist_buttons:
		if button.is_visible_in_tree() and not button.disabled:
			button.grab_focus()
			return
	if btn_close != null and btn_close.is_visible_in_tree():
		btn_close.grab_focus()

func _is_controller_event(event: InputEvent) -> bool:
	var joy_button: InputEventJoypadButton = event as InputEventJoypadButton
	if joy_button != null:
		return joy_button.pressed
	var joy_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	return joy_motion != null and absf(joy_motion.axis_value) >= 0.5

func get_last_offer_debug() -> Dictionary:
	return _last_offer_debug.duplicate(true)
