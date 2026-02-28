extends Node3D

@export var ship_scene: PackedScene

@onready var menu: Control = $MainMenuOverlay
@onready var hud: CanvasLayer = $HUD
var _ship: Ship

func _enter_tree() -> void:
	_ensure_ship_instance()

func _ready() -> void:
	menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	menu.visible = true
	hud.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.practice_requested.connect(_on_start_pressed)
	if menu.has_signal("selection_changed"):
		menu.selection_changed.connect(_on_menu_selection_changed)
	_refresh_ship_from_selection(true)
	_set_ship_run_visibility(false)

func _on_start_pressed() -> void:
	GameFlow.start_new_run()
	_set_ship_run_visibility(true)
	menu.visible = false
	hud.visible = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_menu_selection_changed() -> void:
	if not get_tree().paused:
		return
	_refresh_ship_from_selection(true)

func _refresh_ship_from_selection(reset_current_health: bool) -> void:
	var ship: Ship = _ensure_ship_instance()
	if ship == null:
		return
	ship.reconfigure_from_selected_pilot(reset_current_health)

func _set_ship_run_visibility(ship_visible: bool) -> void:
	var ship: Ship = _ensure_ship_instance()
	if ship == null:
		return
	ship.visible = ship_visible

func _ensure_ship_instance() -> Ship:
	if _ship != null and is_instance_valid(_ship):
		return _ship

	var existing: Ship = get_node_or_null("Ship") as Ship
	if existing != null:
		_ship = existing
		return _ship

	if ship_scene == null:
		push_warning("WorldBootstrap has no ship_scene assigned; unable to spawn Ship node.")
		return null

	var inst: Ship = ship_scene.instantiate() as Ship
	if inst == null:
		push_warning("ship_scene did not instantiate a Ship.")
		return null

	inst.name = "Ship"
	add_child(inst)
	_ship = inst
	return _ship
