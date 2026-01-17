# hud_manager.gd (Godot 4.5)
extends CanvasLayer

@export var camera_path: NodePath    # optional; leave empty to auto-detect
@export var ship_path: NodePath
@export var wave_director_path: NodePath
@export var spawner_path: NodePath
@export var wave_label_path: NodePath
@export var countdown_label_path: NodePath
@export var alive_label_path: NodePath

@onready var ship: Node3D = get_node_or_null(ship_path)
@onready var nameplates: NameplateManager = $ScreenRoot/NameplateLayer
@onready var effects: FloatingTextLayer = $ScreenRoot/EffectsLayer
@onready var ship_hud: ShipHud = $ScreenRoot/BottomDock/Centerer/ShipHud
@onready var offscreen_indicators: OffscreenIndicatorLayer = $ScreenRoot/OffscreenIndicatorLayer

var camera: Camera3D
var _director: Node = null
var _spawner: Node = null
var _wave_label: Node = null
var _countdown_label: Label = null
var _alive_label: Label = null

func _ready() -> void:
	_refresh_camera()
	await get_tree().process_frame
	_refresh_camera()

	if nameplates != null and camera != null and ship != null:
		nameplates.init(camera, ship)
	if ship_hud != null and ship != null:
		ship_hud.init(ship)
	if effects != null and camera != null:
		effects.init(camera)
	if offscreen_indicators != null and camera != null and ship != null:
		offscreen_indicators.init(camera, ship)
	
	if wave_director_path != NodePath(""):
		_director = get_node_or_null(wave_director_path)
	if spawner_path != NodePath(""):
		_spawner = get_node_or_null(spawner_path)
	
	if wave_label_path != NodePath(""):
		_wave_label = get_node_or_null(wave_label_path) as Label
	if countdown_label_path != NodePath(""):
		_countdown_label = get_node_or_null(countdown_label_path) as Label
	if alive_label_path != NodePath(""):
		_alive_label = get_node_or_null(alive_label_path) as Label
	
	if _director != null:
		if _director.has_signal("wave_started"):
			_director.connect("wave_started", Callable(self, "_on_wave_started"))
		if _director.has_signal("wave_cleared"):
			_director.connect("wave_cleared", Callable(self, "_on_wave_cleared"))
		if _director.has_signal("downtime_started"):
			_director.connect("downtime_started", Callable(self, "_on_downtime_started"))
		if _director.has_signal("downtime_tick"):
			_director.connect("downtime_tick", Callable(self, "_on_downtime_tick"))
		if _director.has_signal("downtime_ended"):
			_director.connect("downtime_ended", Callable(self, "_on_downtime_ended"))
		if _director.has_signal("next_wave_eta"):
			_director.connect("next_wave_eta", Callable(self, "_on_next_wave_eta"))
	
	if _spawner != null and _spawner.has_signal("alive_counts_changed"):
		_spawner.connect("alive_counts_changed", Callable(self, "_on_alive_counts_changed"))
		
		if _spawner.has_method("get_alive_counts"):
			var d: Dictionary = _spawner.call("get_alive_counts")
			_on_alive_counts_changed(
				int(d.get("enemies", 0)),
				int(d.get("targets", 0)),
				int(d.get("total", 0))
			)

func _process(_dt: float) -> void:
	# If the camera changes (e.g., switch to cockpit or different scene), refresh
	if camera == null or not is_instance_valid(camera) or not camera.current:
		_refresh_camera()

func _refresh_camera() -> void:
	if camera_path != NodePath(""):
		camera = get_node_or_null(camera_path) as Camera3D
	else:
		camera = get_viewport().get_camera_3d()

func _on_wave_started(index: int, _enemy_budget: int, _target_budget: int) -> void:
	if _wave_label != null:
		_wave_label.text = "Wave %d" % index
	if _countdown_label != null:
		_countdown_label.text = ""

func _on_downtime_started(_duration: float, _next_wave_index: int) -> void:
	pass

func _on_downtime_tick(_remaining: float, _next_wave_index: int) -> void:
	pass

func _on_downtime_ended(_next_wave_index: int) -> void:
	pass

func _on_alive_counts_changed(enemies: int, targets: int, total: int) -> void:
	if _alive_label != null:
		_alive_label.text = "Enemies: %d Targets: %d Total: %d" % [enemies, targets, total]

func _on_next_wave_eta(seconds: float) -> void:
	if _countdown_label == null:
		return
	_countdown_label.text = "Next wave starts in %s" % _fmt_mm_ss(seconds)

func _fmt_mm_ss(s: float) -> String:
	var total: int = int(ceil(max(s, 0.0)))
	var m: int = total / 60
	var sec: int = total % 60
	if m <= 0:
		return ":%02d" % [sec]
	else:
		return "%d:%02d" % [m, sec]
		
