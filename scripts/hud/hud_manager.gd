# hud_manager.gd (Godot 4.5)
extends CanvasLayer

@export var camera_path: NodePath    # optional; leave empty to auto-detect
@export var ship_path: NodePath
@export var wave_director_path: NodePath
@export var spawner_path: NodePath
@export var wave_label_path: NodePath
@export var countdown_label_path: NodePath
@export var alive_label_path: NodePath
@export var run_details_label_path: NodePath
@export var stage_details_label_path: NodePath
@export var stage_modifiers_label_path: NodePath
@export var victory_label_path: NodePath

@onready var ship: Node3D = get_node_or_null(ship_path)
@onready var nameplates: NameplateManager = $ScreenRoot/NameplateLayer
@onready var effects: FloatingTextLayer = $ScreenRoot/EffectsLayer
@onready var ship_hud: ShipHud = $ScreenRoot/BottomDock/ShipHud
@onready var offscreen_indicators: OffscreenIndicatorLayer = $ScreenRoot/OffscreenIndicatorLayer

var camera: Camera3D
var _director: WaveDirector = null
var _spawner: Node = null
var _wave_label: Label = null
var _countdown_label: Label = null
var _alive_label: Label = null
var _run_details_label: Label = null
var _stage_details_label: Label = null
var _stage_modifiers_label: Label = null
var _victory_label: Label = null

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
		_director = get_node_or_null(wave_director_path) as WaveDirector
	if spawner_path != NodePath(""):
		_spawner = get_node_or_null(spawner_path)
	
	if wave_label_path != NodePath(""):
		_wave_label = get_node_or_null(wave_label_path) as Label
	if countdown_label_path != NodePath(""):
		_countdown_label = get_node_or_null(countdown_label_path) as Label
	if alive_label_path != NodePath(""):
		_alive_label = get_node_or_null(alive_label_path) as Label
	if run_details_label_path != NodePath(""):
		_run_details_label = get_node_or_null(run_details_label_path) as Label
	if stage_details_label_path != NodePath(""):
		_stage_details_label = get_node_or_null(stage_details_label_path) as Label
	if stage_modifiers_label_path != NodePath(""):
		_stage_modifiers_label = get_node_or_null(stage_modifiers_label_path) as Label
	if victory_label_path != NodePath(""):
		_victory_label = get_node_or_null(victory_label_path) as Label
		if _victory_label != null:
			_victory_label.visible = false
	
	if _spawner != null and _spawner.has_signal("alive_counts_changed"):
		_spawner.connect("alive_counts_changed", Callable(self, "_on_alive_counts_changed"))
		
		if _spawner.has_method("get_alive_counts"):
			var d: Dictionary = _spawner.call("get_alive_counts")
			_on_alive_counts_changed(
				int(d.get("enemies", 0)),
				int(d.get("targets", 0)),
				int(d.get("total", 0))
			)

	if not GameFlow.stage_changed.is_connected(_on_game_flow_stage_changed):
		GameFlow.stage_changed.connect(_on_game_flow_stage_changed)
	if not GameFlow.run_completed.is_connected(_on_game_flow_run_completed):
		GameFlow.run_completed.connect(_on_game_flow_run_completed)
	if not GameFlow.run_victory_started.is_connected(_on_game_flow_run_victory_started):
		GameFlow.run_victory_started.connect(_on_game_flow_run_victory_started)

	_refresh_run_details()
	_refresh_stage_details()

func _process(_dt: float) -> void:
	# If the camera changes (e.g., switch to cockpit or different scene), refresh
	if camera == null or not is_instance_valid(camera) or not camera.current:
		_refresh_camera()
	_refresh_timer_readouts()

func _refresh_camera() -> void:
	if camera_path != NodePath(""):
		camera = get_node_or_null(camera_path) as Camera3D
	else:
		camera = get_viewport().get_camera_3d()

func _on_alive_counts_changed(enemies: int, targets: int, total: int) -> void:
	if _alive_label != null:
		_alive_label.text = "Enemies: %d Targets: %d Total: %d" % [enemies, targets, total]

func _on_game_flow_stage_changed(_stage: StageDef, _stage_index: int) -> void:
	_refresh_run_details()
	_refresh_stage_details()

func _on_game_flow_run_completed() -> void:
	_refresh_run_details()
	_refresh_stage_details()

func _on_game_flow_run_victory_started(message: String, _return_delay_sec: float) -> void:
	if _victory_label == null:
		return
	_victory_label.text = message
	_victory_label.visible = true

func _refresh_run_details() -> void:
	if _run_details_label == null:
		return

	var run_definition: RunDefinition = GameFlow.get_active_run_definition()
	if run_definition == null:
		_run_details_label.text = "Run: Inactive"
		return

	var stage_count: int = max(run_definition.get_stage_count(), 0)
	var stage_index: int = max(GameFlow.get_active_stage_index(), 0)
	var current_stage_number: int = min(stage_index + 1, stage_count) if stage_count > 0 else 0
	_run_details_label.text = "%s\nStage %d/%d" % [
		_get_run_mode_text(run_definition),
		current_stage_number,
		stage_count,
	]

func _refresh_stage_details() -> void:
	if _stage_details_label == null:
		return

	var stage: StageDef = GameFlow.get_current_stage()
	if stage == null:
		_stage_details_label.text = "Stage: Inactive"
		return
	_stage_details_label.text = stage.get_display_name_or_default()

	var lines: PackedStringArray = PackedStringArray()
	var modifiers: Array[StageModifierDef] = GameFlow.get_active_stage_modifiers()
	if modifiers.is_empty():
		lines.append("No stage modifiers")
	else:
		for modifier in modifiers:
			if modifier == null:
				continue
			lines.append("%s" % modifier.get_display_name_or_default())

	if _stage_modifiers_label != null:
		_stage_modifiers_label.text = "\n".join(lines)

func _refresh_timer_readouts() -> void:
	if _countdown_label != null:
		_countdown_label.text = "Run %s" % _fmt_elapsed_time(GameFlow.get_run_elapsed_seconds())

	if _wave_label == null:
		return
	if _director == null:
		_wave_label.text = "Intermission"
		return

	if _director.get_state() == RunState.State.IN_WAVE:
		_wave_label.text = "Wave %d • %s left" % [
			_director.get_wave_index(),
			_fmt_mm_ss(_director.get_wave_time_remaining()),
		]
		return

	_wave_label.text = "Intermission • %s until Wave %d" % [
		_fmt_mm_ss(_director.get_downtime_remaining()),
		_director.get_next_wave_index(),
	]

func _get_run_mode_text(run_definition: RunDefinition) -> String:
	if run_definition == null:
		return "Run"

	match run_definition.run_mode:
		RunDefinition.RunMode.STORY:
			return "Story Mode"
		RunDefinition.RunMode.PRACTICE:
			return "Practice"
		RunDefinition.RunMode.ENDLESS:
			return "Endless"
	return "Run"

func _fmt_mm_ss(s: float) -> String:
	var total: int = int(ceil(max(s, 0.0)))
	var m: int = total / 60
	var sec: int = total % 60
	return "%02d:%02d" % [m, sec]

func _fmt_elapsed_time(s: float) -> String:
	var total: int = int(floor(max(s, 0.0)))
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var seconds: int = total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds]
	return "%02d:%02d" % [minutes, seconds]
