# game_flow.gd (autoload)
extends Node

signal high_score_updated(new_score: int, old_score: int)
signal pilot_stats_updated(pilot_id: StringName, stats: Dictionary)
signal pilot_unlocked(pilot_id: StringName)
signal selection_changed(pilot: PilotDef, ship: ShipDef)

const MENU := "res://scenes/world/world.tscn"
const DEFAULT_PILOT_ROSTER: String = "res://content/data/pilots/pilot_roster.tres"
const SAVE_PATH: String = "user://highscore.cfg"

const SCORE_SECTION: String = "scores"
const SCORE_KEY_HIGH_SCORE: String = "high_score"
const META_SECTION: String = "meta"
const META_KEY_SELECTED_PILOT: String = "selected_pilot_id"
const META_KEY_SELECTED_SHIP_ID: String = "selected_ship_id"
const META_KEY_SAVE_SCHEMA_VERSION: String = "save_schema_version"
const META_KEY_GAME_VERSION: String = "game_version"
const PILOT_STATS_SECTION_PREFIX: String = "pilot_stats."
const ARCHIVE_SECTION_PREFIX: String = "archive."
const CURRENT_SAVE_SCHEMA_VERSION: int = 1

const STAT_HIGHEST_SCORE: StringName = &"highest_score"
const STAT_LONGEST_RUN_SECONDS: StringName = &"longest_run_seconds"
const STAT_DEATH_RUNS: StringName = &"death_runs"
const STAT_TOTAL_NANOBOTS_IN_RUN: StringName = &"total_nanobots_in_run"
const STAT_HIGHEST_NANOBOTS_IN_RUN: StringName = &"highest_nanobots_in_run"
const STAT_HIGHEST_WAVE_REACHED: StringName = &"highest_wave_reached"

const PILOT_STAT_DEFAULTS: Dictionary = {
	STAT_HIGHEST_SCORE: 0,
	STAT_LONGEST_RUN_SECONDS: 0,
	STAT_DEATH_RUNS: 0,
	STAT_TOTAL_NANOBOTS_IN_RUN: 0,
	STAT_HIGHEST_NANOBOTS_IN_RUN: 0,
	STAT_HIGHEST_WAVE_REACHED: 0,
}

var high_score: int = 0
var selected_pilot: PilotDef = null
var selected_ship: ShipDef = null

var _pilot_stats_by_id: Dictionary = {}
var _cached_roster: PilotRoster = null
var _loaded_selected_pilot_id: StringName = &""
var _loaded_selected_ship_id: StringName = &""

var _run_active: bool = false
var _run_started_msec: int = 0
var _run_pilot_id: StringName = &""
var _run_total_nanobots_collected: int = 0
var _run_peak_nanobots: int = 0
var _run_last_nanobots_value: int = 0

func _ready() -> void:
	_load_user_data()
	_ensure_default_pilot()
	if not RunState.nanobots_updated.is_connected(_on_run_nanobots_updated):
		RunState.nanobots_updated.connect(_on_run_nanobots_updated)
	await get_tree().process_frame

func start_new_run() -> void:
	RunState.start_run()
	_run_active = true
	_run_started_msec = Time.get_ticks_msec()
	_run_total_nanobots_collected = 0
	_run_peak_nanobots = 0
	_run_last_nanobots_value = 0
	var active_pilot: PilotDef = _resolve_selected_or_default_pilot()
	_run_pilot_id = active_pilot.get_pilot_id() if active_pilot != null else &""
	_resolve_selected_or_default_ship()

func set_selected_pilot(pilot: PilotDef) -> void:
	if pilot == null:
		return
	if not pilot.is_selectable():
		push_warning("Ignoring non-selectable pilot: %s" % pilot.resource_path)
		return
	if not is_pilot_unlocked(pilot):
		push_warning("Ignoring locked pilot: %s" % String(pilot.get_pilot_id()))
		return
	selected_pilot = pilot
	selected_ship = pilot.ship
	_save_user_data()
	selection_changed.emit(selected_pilot, selected_ship)

func set_selected_ship(ship: ShipDef) -> void:
	selected_ship = ship
	_save_user_data()
	selection_changed.emit(selected_pilot, selected_ship)

func get_selected_ship() -> ShipDef:
	return _resolve_selected_or_default_ship()

func player_died() -> void:
	_end_run_and_return_to_menu(true)

func _on_time_over() -> void:
	_end_run_and_return_to_menu(false)

func _end_run_and_return_to_menu(count_as_death: bool) -> void:
	_finalize_run_stats(count_as_death)
	check_and_update_high_score(RunState.run_score)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU)

func check_and_update_high_score(final_run_score: int) -> void:
	if final_run_score > high_score:
		var old: int = high_score
		high_score = final_run_score
		_save_user_data()
		high_score_updated.emit(high_score, old)

func get_pilot_stats(pilot_id: StringName) -> Dictionary:
	var key: String = String(pilot_id)
	if key == "":
		return _make_default_pilot_stats()
	if not _pilot_stats_by_id.has(key):
		return _make_default_pilot_stats()
	return (_pilot_stats_by_id[key] as Dictionary).duplicate(true)

func is_pilot_unlocked(pilot: PilotDef) -> bool:
	if pilot == null:
		return false
	if not pilot.is_selectable():
		return false
	if pilot.starts_unlocked:
		return true

	var requirements: Array[PilotUnlockRequirement] = pilot.unlock_requirements
	if requirements.is_empty():
		return false

	var require_all: bool = pilot.unlock_requirement_mode == PilotDef.UnlockRequirementMode.ALL
	var found_valid_requirement: bool = false
	for req in requirements:
		if req == null:
			continue
		found_valid_requirement = true
		var met: bool = _is_unlock_requirement_met(req)
		if require_all and not met:
			return false
		if not require_all and met:
			return true

	if not found_valid_requirement:
		return false
	return require_all

func get_all_pilots() -> Array[PilotDef]:
	var roster: PilotRoster = _get_roster()
	if roster == null:
		return []
	return roster.get_pilots()

func _get_roster() -> PilotRoster:
	if _cached_roster != null:
		return _cached_roster
	_cached_roster = load(DEFAULT_PILOT_ROSTER) as PilotRoster
	return _cached_roster

func _resolve_selected_or_default_pilot() -> PilotDef:
	if selected_pilot != null and selected_pilot.is_selectable() and is_pilot_unlocked(selected_pilot):
		return selected_pilot
	_ensure_default_pilot()
	return selected_pilot

func _resolve_selected_or_default_ship() -> ShipDef:
	if selected_ship != null:
		return selected_ship
	var pilot: PilotDef = _resolve_selected_or_default_pilot()
	if pilot != null:
		selected_ship = pilot.ship
	return selected_ship

func _ensure_default_pilot() -> void:
	if selected_pilot != null and selected_pilot.is_selectable() and is_pilot_unlocked(selected_pilot):
		if selected_ship == null:
			selected_ship = selected_pilot.ship
		return

	var pilots: Array[PilotDef] = get_all_pilots()
	if pilots.is_empty():
		return

	if _loaded_selected_pilot_id != &"":
		var saved_choice: PilotDef = _find_pilot_by_id(_loaded_selected_pilot_id)
		if saved_choice != null and is_pilot_unlocked(saved_choice):
			selected_pilot = saved_choice
			selected_ship = _load_ship_from_id(_loaded_selected_ship_id)
			if selected_ship == null:
				selected_ship = saved_choice.ship
			return

	for pilot in pilots:
		if pilot != null and is_pilot_unlocked(pilot):
			selected_pilot = pilot
			selected_ship = pilot.ship
			return

	selected_pilot = pilots[0]
	selected_ship = selected_pilot.ship if selected_pilot != null else null

func _find_pilot_by_id(pilot_id: StringName) -> PilotDef:
	if pilot_id == &"":
		return null
	for pilot in get_all_pilots():
		if pilot == null:
			continue
		if pilot.get_pilot_id() == pilot_id:
			return pilot
	return null

func _load_ship_from_id(ship_id: StringName) -> ShipDef:
	if ship_id == &"":
		return null
	for pilot in get_all_pilots():
		if pilot == null or pilot.ship == null:
			continue
		if _get_ship_id(pilot.ship) == ship_id:
			return pilot.ship
	return null

func _get_ship_id(ship: ShipDef) -> StringName:
	if ship == null:
		return &""
	if ship.id != &"":
		return ship.id
	if ship.resource_path != "":
		return StringName(ship.resource_path.get_file().get_basename())
	return &""

func _on_run_nanobots_updated(amount: int) -> void:
	if not _run_active:
		return

	if amount > _run_peak_nanobots:
		_run_peak_nanobots = amount

	if amount > _run_last_nanobots_value:
		_run_total_nanobots_collected += amount - _run_last_nanobots_value

	_run_last_nanobots_value = amount

func _finalize_run_stats(count_as_death: bool) -> void:
	if not _run_active:
		return
	_run_active = false

	var pilot_id: StringName = _run_pilot_id
	if pilot_id == &"":
		var active_pilot: PilotDef = _resolve_selected_or_default_pilot()
		pilot_id = active_pilot.get_pilot_id() if active_pilot != null else &""
	if pilot_id == &"":
		return

	var before_unlocks: Dictionary = _build_unlock_state()
	var stats: Dictionary = _get_or_create_stats_for_pilot(pilot_id)

	var run_seconds: int = 0
	if _run_started_msec > 0:
		var elapsed_msec: int = max(Time.get_ticks_msec() - _run_started_msec, 0)
		run_seconds = int(round(float(elapsed_msec) / 1000.0))

	var final_score: int = max(RunState.run_score, 0)
	var final_wave: int = max(RunState.get_wave_index(), 0)
	var total_nanobots: int = max(_run_total_nanobots_collected, 0)
	var peak_nanobots: int = max(_run_peak_nanobots, 0)

	stats[STAT_HIGHEST_SCORE] = max(int(stats[STAT_HIGHEST_SCORE]), final_score)
	stats[STAT_LONGEST_RUN_SECONDS] = max(int(stats[STAT_LONGEST_RUN_SECONDS]), run_seconds)
	stats[STAT_TOTAL_NANOBOTS_IN_RUN] = max(int(stats[STAT_TOTAL_NANOBOTS_IN_RUN]), total_nanobots)
	stats[STAT_HIGHEST_NANOBOTS_IN_RUN] = max(int(stats[STAT_HIGHEST_NANOBOTS_IN_RUN]), peak_nanobots)
	stats[STAT_HIGHEST_WAVE_REACHED] = max(int(stats[STAT_HIGHEST_WAVE_REACHED]), final_wave)
	if count_as_death:
		stats[STAT_DEATH_RUNS] = int(stats[STAT_DEATH_RUNS]) + 1

	_pilot_stats_by_id[String(pilot_id)] = stats
	_save_user_data()
	pilot_stats_updated.emit(pilot_id, stats.duplicate(true))
	_emit_new_unlocks(before_unlocks, _build_unlock_state())

func _build_unlock_state() -> Dictionary:
	var result: Dictionary = {}
	for pilot in get_all_pilots():
		if pilot == null:
			continue
		result[String(pilot.get_pilot_id())] = is_pilot_unlocked(pilot)
	return result

func _emit_new_unlocks(before: Dictionary, after: Dictionary) -> void:
	for key in after.keys():
		var now_unlocked: bool = bool(after[key])
		var was_unlocked: bool = bool(before.get(key, false))
		if now_unlocked and not was_unlocked:
			pilot_unlocked.emit(StringName(key))

func _is_unlock_requirement_met(requirement: PilotUnlockRequirement) -> bool:
	if requirement == null:
		return false
	return _get_requirement_stat_value(requirement) >= max(requirement.minimum_value, 0)

func _get_requirement_stat_value(requirement: PilotUnlockRequirement) -> int:
	if requirement.source_pilot_id != &"":
		return _get_pilot_stat_value(requirement.source_pilot_id, requirement.stat)
	return _get_global_stat_value(requirement.stat)

func _get_pilot_stat_value(pilot_id: StringName, stat: PilotUnlockRequirement.PilotStat) -> int:
	var key: StringName = _map_unlock_stat_to_key(stat)
	var stats: Dictionary = get_pilot_stats(pilot_id)
	return int(stats.get(key, 0))

func _get_global_stat_value(stat: PilotUnlockRequirement.PilotStat) -> int:
	if stat == PilotUnlockRequirement.PilotStat.HIGHEST_SCORE:
		return high_score

	if stat == PilotUnlockRequirement.PilotStat.DEATH_RUNS:
		var total_runs: int = 0
		for pilot_stats in _pilot_stats_by_id.values():
			var stats: Dictionary = pilot_stats as Dictionary
			total_runs += int(stats.get(STAT_DEATH_RUNS, 0))
		return total_runs

	var key: StringName = _map_unlock_stat_to_key(stat)
	var best: int = 0
	for pilot_stats in _pilot_stats_by_id.values():
		var stats: Dictionary = pilot_stats as Dictionary
		best = max(best, int(stats.get(key, 0)))
	return best

func _map_unlock_stat_to_key(stat: PilotUnlockRequirement.PilotStat) -> StringName:
	match stat:
		PilotUnlockRequirement.PilotStat.HIGHEST_SCORE:
			return STAT_HIGHEST_SCORE
		PilotUnlockRequirement.PilotStat.LONGEST_RUN_SECONDS:
			return STAT_LONGEST_RUN_SECONDS
		PilotUnlockRequirement.PilotStat.DEATH_RUNS:
			return STAT_DEATH_RUNS
		PilotUnlockRequirement.PilotStat.TOTAL_NANOBOTS_IN_RUN:
			return STAT_TOTAL_NANOBOTS_IN_RUN
		PilotUnlockRequirement.PilotStat.HIGHEST_NANOBOTS_IN_RUN:
			return STAT_HIGHEST_NANOBOTS_IN_RUN
		PilotUnlockRequirement.PilotStat.HIGHEST_WAVE_REACHED:
			return STAT_HIGHEST_WAVE_REACHED
	return STAT_HIGHEST_SCORE

func _get_or_create_stats_for_pilot(pilot_id: StringName) -> Dictionary:
	var key: String = String(pilot_id)
	if key == "":
		return _make_default_pilot_stats()
	if not _pilot_stats_by_id.has(key):
		_pilot_stats_by_id[key] = _make_default_pilot_stats()
	return (_pilot_stats_by_id[key] as Dictionary).duplicate(true)

func _make_default_pilot_stats() -> Dictionary:
	return PILOT_STAT_DEFAULTS.duplicate(true)

func _get_current_game_version() -> String:
	var value: String = String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	return value if value != "" else "dev"

func _should_reset_save(saved_schema_version: int, saved_game_version: String, current_game_version: String) -> bool:
	if saved_schema_version > 0 and saved_schema_version != CURRENT_SAVE_SCHEMA_VERSION:
		return true
	if saved_game_version != "" and saved_game_version != current_game_version:
		return true
	return false

func _archive_current_save(cfg: ConfigFile, saved_schema_version: int, saved_game_version: String, current_game_version: String) -> void:
	var archive_stamp: int = int(Time.get_unix_time_from_system())
	var archive_base: String = "%s%d" % [ARCHIVE_SECTION_PREFIX, archive_stamp]
	var sections: PackedStringArray = cfg.get_sections()
	for section in sections:
		if section.begins_with(ARCHIVE_SECTION_PREFIX):
			continue
		var keys: PackedStringArray = cfg.get_section_keys(section)
		for key in keys:
			cfg.set_value("%s.%s" % [archive_base, section], key, cfg.get_value(section, key))
	cfg.set_value("%s.meta" % archive_base, "reason", "version_mismatch")
	cfg.set_value("%s.meta" % archive_base, "saved_schema_version", saved_schema_version)
	cfg.set_value("%s.meta" % archive_base, "saved_game_version", saved_game_version)
	cfg.set_value("%s.meta" % archive_base, "current_schema_version", CURRENT_SAVE_SCHEMA_VERSION)
	cfg.set_value("%s.meta" % archive_base, "current_game_version", current_game_version)
	cfg.set_value("%s.meta" % archive_base, "archived_at_unix", archive_stamp)

func _clear_live_save_sections(cfg: ConfigFile) -> void:
	var sections: PackedStringArray = cfg.get_sections()
	for section in sections:
		if section.begins_with(ARCHIVE_SECTION_PREFIX):
			continue
		cfg.erase_section(section)

func _write_default_live_save(cfg: ConfigFile, game_version: String) -> void:
	cfg.set_value(SCORE_SECTION, SCORE_KEY_HIGH_SCORE, 0)
	cfg.set_value(META_SECTION, META_KEY_SELECTED_PILOT, "")
	cfg.set_value(META_SECTION, META_KEY_SELECTED_SHIP_ID, "")
	cfg.set_value(META_SECTION, META_KEY_SAVE_SCHEMA_VERSION, CURRENT_SAVE_SCHEMA_VERSION)
	cfg.set_value(META_SECTION, META_KEY_GAME_VERSION, game_version)

func _load_user_data() -> void:
	_pilot_stats_by_id.clear()
	_loaded_selected_pilot_id = &""
	_loaded_selected_ship_id = &""
	high_score = 0

	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load(SAVE_PATH)
	if err != OK:
		return

	var current_game_version: String = _get_current_game_version()
	var saved_schema_version: int = int(cfg.get_value(META_SECTION, META_KEY_SAVE_SCHEMA_VERSION, -1))
	var saved_game_version: String = String(cfg.get_value(META_SECTION, META_KEY_GAME_VERSION, "")).strip_edges()
	if _should_reset_save(saved_schema_version, saved_game_version, current_game_version):
		_archive_current_save(cfg, saved_schema_version, saved_game_version, current_game_version)
		_clear_live_save_sections(cfg)
		_write_default_live_save(cfg, current_game_version)
		var reset_err: int = cfg.save(SAVE_PATH)
		if reset_err != OK:
			push_warning("Failed to write reset save data to %s (err %d)".format([SAVE_PATH, reset_err]))
		return

	high_score = int(cfg.get_value(SCORE_SECTION, SCORE_KEY_HIGH_SCORE, 0))
	_loaded_selected_pilot_id = StringName(String(cfg.get_value(META_SECTION, META_KEY_SELECTED_PILOT, "")))
	_loaded_selected_ship_id = StringName(String(cfg.get_value(META_SECTION, META_KEY_SELECTED_SHIP_ID, "")))

	for section in cfg.get_sections():
		if not section.begins_with(PILOT_STATS_SECTION_PREFIX):
			continue
		var pilot_id: String = section.trim_prefix(PILOT_STATS_SECTION_PREFIX)
		if pilot_id == "":
			continue
		var loaded_stats: Dictionary = _make_default_pilot_stats()
		for key in PILOT_STAT_DEFAULTS.keys():
			var stat_key: StringName = key as StringName
			var default_value: int = int(PILOT_STAT_DEFAULTS[stat_key])
			loaded_stats[stat_key] = max(0, int(cfg.get_value(section, String(stat_key), default_value)))
		_pilot_stats_by_id[pilot_id] = loaded_stats

func _save_user_data() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SAVE_PATH)

	cfg.set_value(SCORE_SECTION, SCORE_KEY_HIGH_SCORE, high_score)
	cfg.set_value(META_SECTION, META_KEY_SELECTED_PILOT, String(selected_pilot.get_pilot_id()) if selected_pilot != null else "")
	cfg.set_value(META_SECTION, META_KEY_SELECTED_SHIP_ID, String(_get_ship_id(selected_ship)))
	cfg.set_value(META_SECTION, META_KEY_SAVE_SCHEMA_VERSION, CURRENT_SAVE_SCHEMA_VERSION)
	cfg.set_value(META_SECTION, META_KEY_GAME_VERSION, _get_current_game_version())

	for section in cfg.get_sections():
		if section.begins_with(PILOT_STATS_SECTION_PREFIX):
			cfg.erase_section(section)

	for pilot_id in _pilot_stats_by_id.keys():
		var section: String = "%s%s" % [PILOT_STATS_SECTION_PREFIX, String(pilot_id)]
		var stats: Dictionary = _pilot_stats_by_id[pilot_id] as Dictionary
		for key in PILOT_STAT_DEFAULTS.keys():
			var stat_key: StringName = key as StringName
			cfg.set_value(section, String(stat_key), max(0, int(stats.get(stat_key, 0))))

	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Failed to save user data to %s (err %d)".format([SAVE_PATH, err]))
