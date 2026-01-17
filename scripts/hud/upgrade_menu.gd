# scripts/hud/upgrade_menu.gd (Godot 4.5)
# Modal menu shown when docking at a POI is complete.
# Displays upgrade choices and allows player to pick one.
extends CanvasLayer
class_name UpgradeMenu

signal upgrade_selected(upgrade: Upgrade)
signal weapon_selected(weapon: WeaponDef)
signal menu_closed

@export_group("Upgrade Pool")
@export var available_upgrades: Array[Upgrade] = []
@export var available_weapons: Array[WeaponDef] = []

@export_group("Display")
@export var num_upgrade_choices: int = 3

@onready var btn_close: Button = $Close

var _root: Control
var _dim: ColorRect
var _container: VBoxContainer
var _title_label: Label
var _buttons: Array[Button] = []
var _current_poi: PoiInstance = null

# Choices for this menu instance
var _upgrade_choices: Array[Upgrade] = []
var _weapon_choice: WeaponDef = null

# Nanobot tracking
var _current_nanobots: int = 0
var _was_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	RunState.nanobots_updated.connect(_on_nanobots_updated)
	layer = 3  # Above pause menu
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	_build_ui()


func _build_ui() -> void:
	# Root control
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	
	# Dim background
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.7)
	_root.add_child(_dim)
	
	# Center container
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	
	# Panel for the menu
	var panel: PanelContainer = PanelContainer.new()
	center.add_child(panel)
	
	# Reparent the close button into the root so it's above the dim background
	if btn_close != null:
		btn_close.reparent(_root)
		btn_close.pressed.connect(_close_without_purchase)
	
	# Margin inside panel
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)
	
	# VBox for content
	_container = VBoxContainer.new()
	_container.add_theme_constant_override("separation", 15)
	margin.add_child(_container)
	
	# Title
	_title_label = Label.new()
	_title_label.text = "Choose 1 Upgrade"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	_container.add_child(_title_label)
	
	# Separator
	var sep: HSeparator = HSeparator.new()
	_container.add_child(sep)
	
	# Create buttons (3 upgrades + 1 weapon)
	for i in 4:
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(400, 50)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_button_pressed.bind(i))
		_container.add_child(btn)
		_buttons.append(btn)


func show_for_poi(poi: PoiInstance) -> void:
	_current_poi = poi
	_randomize_choices(poi)
	_update_buttons()
	
	visible = true
	get_tree().paused = true
	
	# Show mouse cursor
	_was_mouse_mode = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Focus first button
	if _buttons.size() > 0:
		_buttons[0].grab_focus()


func _randomize_choices(poi: PoiInstance) -> void:
	_upgrade_choices.clear()
	_weapon_choice = null
	
	# Shuffle available upgrades and pick up to num_upgrade_choices
	var shuffled_upgrades: Array[Upgrade] = available_upgrades.duplicate()
	shuffled_upgrades.shuffle()
	
	for i in mini(num_upgrade_choices, shuffled_upgrades.size()):
		_upgrade_choices.append(shuffled_upgrades[i])
	
	# Pick a random weapon
	if available_weapons.size() > 0:
		var shuffled_weapons: Array[WeaponDef] = available_weapons.duplicate()
		shuffled_weapons.shuffle()
		_weapon_choice = shuffled_weapons[0]


func _update_buttons() -> void:
	var nb: int = _current_nanobots
	
	# Update upgrade buttons
	for i in _buttons.size():
		var btn: Button = _buttons[i]
		
		if i < _upgrade_choices.size():
			# Upgrade button
			var upgrade: Upgrade = _upgrade_choices[i]
			btn.text = "%s (%d)\n%s" % [upgrade.display_name, upgrade.cost, upgrade.descripton]
			btn.visible = true
			btn.disabled = upgrade.cost > nb
		elif i == _buttons.size() - 1 and _weapon_choice != null:
			# Weapon button (last button)
			btn.text = "+ %s (%d)" % [_weapon_choice.display_name, _weapon_choice.cost]
			btn.visible = true
			btn.disabled = _weapon_choice.cost > nb
		else:
			btn.visible = false


func _on_button_pressed(index: int) -> void:
	if index < _upgrade_choices.size():
		# Upgrade selected
		var upgrade: Upgrade = _upgrade_choices[index]
		if upgrade.cost > _current_nanobots:
			return  # Can't afford
		_spend_nanobots(upgrade.cost)
		_apply_upgrade(upgrade)
		upgrade_selected.emit(upgrade)
	elif index == _buttons.size() - 1 and _weapon_choice != null:
		# Weapon selected
		if _weapon_choice.cost > _current_nanobots:
			return  # Can't afford
		_spend_nanobots(_weapon_choice.cost)
		_apply_weapon(_weapon_choice)
		weapon_selected.emit(_weapon_choice)
	
	_close_menu()


func _apply_upgrade(upgrade: Upgrade) -> void:
	# Emit the appropriate signal based on upgrade type
	# For now, use a generic approach - check the upgrade id prefix
	var id: String = upgrade.id.to_lower()
	
	if "bulkhead" in id or "reinforced" in id:
		EventBus.add_bulkhead_requested.emit(upgrade)
	elif "shield" in id or "adaptive" in id:
		EventBus.add_shield_requested.emit(upgrade)
	elif "targeting" in id or "precision" in id:
		EventBus.add_targeting_requested.emit(upgrade)
	elif "systems" in id or "optimization" in id:
		EventBus.add_systems_requested.emit(upgrade)
	elif "salvage" in id or "magnet" in id:
		EventBus.add_salvage_requested.emit(upgrade)
	elif "thruster" in id or "vectoring" in id:
		EventBus.add_thrusters_requested.emit(upgrade)
	else:
		# Default: try bulkhead signal as generic upgrade
		EventBus.add_bulkhead_requested.emit(upgrade)


func _apply_weapon(weapon: WeaponDef) -> void:
	EventBus.add_gun_requested.emit(weapon)


func _close_menu() -> void:
	visible = false
	get_tree().paused = false
	
	# Restore mouse mode
	Input.set_mouse_mode(_was_mouse_mode)
	
	# Destroy the POI after purchase
	if _current_poi != null and is_instance_valid(_current_poi):
		_current_poi.queue_free()
		_current_poi = null
	
	menu_closed.emit()


func _close_without_purchase() -> void:
	# Close menu without destroying the POI (player can return later)
	visible = false
	get_tree().paused = false
	
	# Restore mouse mode
	Input.set_mouse_mode(_was_mouse_mode)
	
	# Keep the POI alive - just clear reference
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
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close_without_purchase()
