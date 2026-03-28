extends Control
class_name BossGatewayHud

@export var boss_gateway_manager_path: NodePath
@export var label_settings: LabelSettings

var _gateway_manager: BossGatewayManager
var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if label_settings != null:
		_label.label_settings = label_settings
	_label.add_theme_font_size_override("font_size", 32)
	add_child(_label)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.46
	anchor_bottom = 0.46
	offset_left = -210.0
	offset_right = 210.0
	offset_top = -30.0
	offset_bottom = 30.0
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	if boss_gateway_manager_path != NodePath(""):
		_gateway_manager = get_node_or_null(boss_gateway_manager_path) as BossGatewayManager
		_connect_signals()

func _connect_signals() -> void:
	if _gateway_manager == null:
		return
	if not _gateway_manager.docking_started.is_connected(_on_docking_started):
		_gateway_manager.docking_started.connect(_on_docking_started)
	if not _gateway_manager.docking_progress.is_connected(_on_docking_progress):
		_gateway_manager.docking_progress.connect(_on_docking_progress)
	if not _gateway_manager.docking_cancelled.is_connected(_on_docking_cancelled):
		_gateway_manager.docking_cancelled.connect(_on_docking_cancelled)
	if not _gateway_manager.docking_complete.is_connected(_on_docking_complete):
		_gateway_manager.docking_complete.connect(_on_docking_complete)
	if not _gateway_manager.gateway_cleared.is_connected(_on_gateway_cleared):
		_gateway_manager.gateway_cleared.connect(_on_gateway_cleared)

func _on_docking_started(gateway: BossGateway) -> void:
	visible = true
	_update_label(gateway, _gateway_manager.get_docking_timer())

func _on_docking_progress(gateway: BossGateway, time_remaining: float) -> void:
	_update_label(gateway, time_remaining)

func _on_docking_cancelled(_gateway: BossGateway) -> void:
	visible = false

func _on_docking_complete(_gateway: BossGateway) -> void:
	visible = false

func _on_gateway_cleared() -> void:
	visible = false

func _update_label(gateway: BossGateway, time_remaining: float) -> void:
	var seconds: int = ceili(time_remaining)
	var gateway_name: String = gateway.get_display_name() if gateway != null else "Gateway"
	_label.text = "Transiting via %s... %ds" % [gateway_name, seconds]
	_label.modulate = Color(0.3, 1.0, 0.5) if seconds <= 1 else Color(1.0, 1.0, 1.0)
