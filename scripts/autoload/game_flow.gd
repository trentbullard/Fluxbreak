# game_flow.gd (autoload)
extends Node

signal high_score_updated(new_score: int, old_score: int)

const MENU := "res://scenes/main_menu/main_menu.tscn"
const DEFAULT_PILOT_ROSTER: String = "res://content/data/pilots/pilot_roster.tres"
const SAVE_PATH: String = "user://highscore.cfg"
const SAVE_SECTION: String = "scores"
const SAVE_KEY: String = "high_score"

var high_score: int = 0
var selected_pilot: PilotDef = null

func _ready() -> void:
	_load_high_score()
	_ensure_default_pilot()
	await get_tree().process_frame

func start_new_run() -> void:
	RunState.start_run()

func player_died():
	_end_run_and_return_to_menu()

func _on_time_over() -> void:
	_end_run_and_return_to_menu()

func _end_run_and_return_to_menu() -> void:
	check_and_update_high_score(RunState.run_score)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU)

func check_and_update_high_score(final_run_score: int) -> void:
	if final_run_score > high_score:
		var old: int = high_score
		high_score = final_run_score
		_save_high_score()
		high_score_updated.emit(high_score, old)

func _load_high_score() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load(SAVE_PATH)
	if err == OK:
		high_score = int(cfg.get_value(SAVE_SECTION, SAVE_KEY, 0))
	else:
		high_score = 0

func _save_high_score() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value(SAVE_SECTION, SAVE_KEY, high_score)
	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Failed to save high score to %s (err %d)".format([SAVE_PATH, err]))

func _ensure_default_pilot() -> void:
	if selected_pilot != null:
		return
	var roster: PilotRoster = load(DEFAULT_PILOT_ROSTER) as PilotRoster
	if roster == null or roster.pilots.is_empty():
		return
	selected_pilot = roster.pilots[0]
