# game_flow.gd (autoload)
extends Node

signal high_score_updated(new_score: int, old_score: int)
signal pilot_stats_updated(pilot_id: StringName, stats: Dictionary)
signal pilot_unlocked(pilot_id: StringName)
signal selection_changed(pilot: PilotDef, ship: ShipDef)
signal stage_changed(stage: StageDef, stage_index: int)
signal run_completed
signal run_victory_started(message: String, return_delay_sec: float)
signal boss_encounter_started(boss_def: EnemyBossDef, wave_index: int)
signal boss_encounter_ended(boss_def: EnemyBossDef, wave_index: int, player_won: bool, player_died: bool)

const MENU: String = "res://scenes/world/world.tscn"
const DEFAULT_PILOT_ROSTER: String = "res://content/data/pilots/pilot_roster.tres"
const DEFAULT_RUN_DEFINITION: String = "res://content/data/runs/story_mode_intro.tres"
const SAVE_PATH: String = "user://highscore.cfg"
const VICTORY_MESSAGE: String = "YOU WON"
const VICTORY_RETURN_DELAY_SEC: float = 2.5

const SCORE_SECTION: String = "scores"
const SCORE_KEY_HIGH_SCORE: String = "high_score"
const META_SECTION: String = "meta"
const META_KEY_SELECTED_PILOT: String = "selected_pilot_id"
const META_KEY_SELECTED_SHIP_ID: String = "selected_ship_id"
const META_KEY_SAVE_SCHEMA_VERSION: String = "save_schema_version"
const META_KEY_GAME_VERSION: String = "game_version"
const SELECTION_KEY_SELECTED_SHIP_ID: String = "selected_ship_id"
const SELECTION_KEY_SELECTED_WEAPON_ID: String = "selected_weapon_id"
const PILOT_STATS_SECTION_PREFIX: String = "pilot_stats."
const PILOT_SHIP_SELECTION_SECTION_PREFIX: String = "pilot_ship_selection."
const SHIP_WEAPON_SELECTION_SECTION_PREFIX: String = "ship_weapon_selection."
const META_STATS_GLOBAL_SECTION: String = "meta_stats.global"
const META_STATS_PILOT_SECTION_PREFIX: String = "meta_stats.pilot."
const BOSS_STATS_GLOBAL_SECTION_PREFIX: String = "boss_stats.global."
const BOSS_STATS_PILOT_SECTION_PREFIX: String = "boss_stats.pilot."
const ARCHIVE_SECTION_PREFIX: String = "archive."
const CURRENT_SAVE_SCHEMA_VERSION: int = 2

const STAT_HIGHEST_SCORE: StringName = &"highest_score"
const STAT_LONGEST_RUN_SECONDS: StringName = &"longest_run_seconds"
const STAT_DEATH_RUNS: StringName = &"death_runs"
const STAT_TOTAL_NANOBOTS_IN_RUN: StringName = &"total_nanobots_in_run"
const STAT_HIGHEST_NANOBOTS_IN_RUN: StringName = &"highest_nanobots_in_run"
const STAT_HIGHEST_WAVE_REACHED: StringName = &"highest_wave_reached"
const META_STAT_KILLS: StringName = &"kills"
const META_STAT_DAMAGE_DEALT: StringName = &"damage_dealt"
const META_STAT_DAMAGE_TAKEN: StringName = &"damage_taken"
const BOSS_STAT_ENCOUNTERS: String = "encounters"
const BOSS_STAT_KILLS: String = "kills"
const BOSS_STAT_PLAYER_DEATHS: String = "player_deaths"
const BOSS_STAT_DAMAGE_DEALT: String = "damage_dealt"
const BOSS_STAT_DAMAGE_TAKEN: String = "damage_taken"
const BOSS_STAT_ENCOUNTER_TIME_SEC: String = "encounter_time_sec"

const PILOT_STAT_DEFAULTS: Dictionary = {
	STAT_HIGHEST_SCORE: 0,
	STAT_LONGEST_RUN_SECONDS: 0,
	STAT_DEATH_RUNS: 0,
	STAT_TOTAL_NANOBOTS_IN_RUN: 0,
	STAT_HIGHEST_NANOBOTS_IN_RUN: 0,
	STAT_HIGHEST_WAVE_REACHED: 0,
}

const BOSS_STAT_DEFAULTS: Dictionary = {
	BOSS_STAT_ENCOUNTERS: 0,
	BOSS_STAT_KILLS: 0,
	BOSS_STAT_PLAYER_DEATHS: 0,
	BOSS_STAT_DAMAGE_DEALT: 0,
	BOSS_STAT_DAMAGE_TAKEN: 0,
	BOSS_STAT_ENCOUNTER_TIME_SEC: 0,
}

var high_score: int = 0
var selected_pilot: PilotDef = null
var selected_ship: ShipDef = null
var selected_weapon: WeaponDef = null

var _pilot_stats_by_id: Dictionary = {}
var _meta_stats_global: Dictionary = {}
var _meta_stats_by_pilot_id: Dictionary = {}
var _boss_stats_global_by_id: Dictionary = {}
var _boss_stats_by_pilot_id: Dictionary = {}
var _cached_roster: PilotRoster = null
var _loaded_selected_pilot_id: StringName = &""
var _loaded_selected_ship_id: StringName = &""
var _selected_ship_id_by_pilot_id: Dictionary = {}
var _selected_weapon_id_by_ship_id: Dictionary = {}

var _run_active: bool = false
var _run_started_msec: int = 0
var _run_elapsed_sec: float = 0.0
var _run_pilot_id: StringName = &""
var _run_total_nanobots_collected: int = 0
var _run_peak_nanobots: int = 0
var _run_last_nanobots_value: int = 0
var _run_meta_stats_global: Dictionary = {}
var _run_meta_stats_by_pilot_id: Dictionary = {}
var _run_boss_stats_global_by_id: Dictionary = {}
var _run_boss_stats_by_pilot_id: Dictionary = {}
var _active_run_definition: RunDefinition = null
var _active_stage_index: int = -1
var _stage_modifier_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rolled_stage_modifiers_by_stage_key: Dictionary = {}
var _run_end_in_progress: bool = false
var _active_boss_encounter: bool = false
var _active_boss_def: EnemyBossDef = null
var _active_boss_wave_index: int = 0
var _active_boss_encounter_time_sec: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_user_data()
	_ensure_default_pilot()
	_stage_modifier_rng.randomize()
	if not RunState.nanobots_updated.is_connected(_on_run_nanobots_updated):
		RunState.nanobots_updated.connect(_on_run_nanobots_updated)
	await get_tree().process_frame

func _process(delta: float) -> void:
	if not _run_active:
		return
	if get_tree().paused:
		return
	_run_elapsed_sec += max(delta, 0.0)
	if _active_boss_encounter:
		_active_boss_encounter_time_sec += max(delta, 0.0)

func start_new_run(run_definition: RunDefinition = null) -> void:
	RunState.start_run()
	_run_active = true
	_run_end_in_progress = false
	_run_started_msec = Time.get_ticks_msec()
	_run_elapsed_sec = 0.0
	_run_total_nanobots_collected = 0
	_run_peak_nanobots = 0
	_run_last_nanobots_value = 0
	_run_meta_stats_global.clear()
	_run_meta_stats_by_pilot_id.clear()
	_run_boss_stats_global_by_id.clear()
	_run_boss_stats_by_pilot_id.clear()
	_rolled_stage_modifiers_by_stage_key.clear()
	_clear_active_boss_encounter_state()
	_active_run_definition = _resolve_run_definition(run_definition)
	_active_stage_index = -1
	var active_pilot: PilotDef = _resolve_selected_or_default_pilot()
	_run_pilot_id = active_pilot.get_pilot_id() if active_pilot != null else &""
	_resolve_selected_or_default_ship()
	_resolve_selected_or_default_weapon()
	_emit_stage_changed(0)

func record_damage_dealt(amount: float, combat_stat_context: CombatStatContext) -> void:
	_record_run_meta_stat(META_STAT_DAMAGE_DEALT, amount, combat_stat_context)
	_record_active_boss_metric(BOSS_STAT_DAMAGE_DEALT, amount, combat_stat_context)

func record_enemy_kill(combat_stat_context: CombatStatContext) -> void:
	_record_run_meta_stat(META_STAT_KILLS, 1.0, combat_stat_context)
	_record_active_boss_metric(BOSS_STAT_KILLS, 1.0, combat_stat_context)

func record_damage_taken(amount: float, combat_stat_context: CombatStatContext) -> void:
	_record_run_meta_stat(META_STAT_DAMAGE_TAKEN, amount, combat_stat_context)
	_record_active_boss_metric(BOSS_STAT_DAMAGE_TAKEN, amount, combat_stat_context)

func begin_boss_encounter(boss_def: EnemyBossDef, wave_index: int) -> void:
	if not _run_active or boss_def == null:
		return
	if _active_boss_encounter:
		complete_boss_encounter(false, false)
	_active_boss_encounter = true
	_active_boss_def = boss_def
	_active_boss_wave_index = max(wave_index, 0)
	_active_boss_encounter_time_sec = 0.0
	_add_run_boss_stat(_get_boss_stat_id(boss_def), BOSS_STAT_ENCOUNTERS, 1.0)
	boss_encounter_started.emit(boss_def, _active_boss_wave_index)

func complete_boss_encounter(player_won: bool, player_died: bool) -> void:
	if not _active_boss_encounter or _active_boss_def == null:
		return
	var boss_def: EnemyBossDef = _active_boss_def
	var boss_wave_index: int = _active_boss_wave_index
	var encounter_time_sec: float = _active_boss_encounter_time_sec
	_add_run_boss_stat(_get_boss_stat_id(boss_def), BOSS_STAT_ENCOUNTER_TIME_SEC, encounter_time_sec)
	if player_died:
		_add_run_boss_stat(_get_boss_stat_id(boss_def), BOSS_STAT_PLAYER_DEATHS, 1.0)
	_clear_active_boss_encounter_state()
	boss_encounter_ended.emit(boss_def, boss_wave_index, player_won, player_died)

func is_boss_encounter_active() -> bool:
	return _active_boss_encounter

func get_active_boss_def() -> EnemyBossDef:
	return _active_boss_def

func get_boss_stats(boss_id: StringName, pilot_id: StringName = &"") -> Dictionary:
	var boss_key: String = String(boss_id)
	if boss_key == "":
		return _make_default_boss_stats()
	if pilot_id == &"":
		if not _boss_stats_global_by_id.has(boss_key):
			return _make_default_boss_stats()
		return (_boss_stats_global_by_id[boss_key] as Dictionary).duplicate(true)
	var pilot_key: String = String(pilot_id)
	if not _boss_stats_by_pilot_id.has(pilot_key):
		return _make_default_boss_stats()
	var by_boss: Dictionary = _boss_stats_by_pilot_id[pilot_key] as Dictionary
	if not by_boss.has(boss_key):
		return _make_default_boss_stats()
	return (by_boss[boss_key] as Dictionary).duplicate(true)

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
	selected_ship = _resolve_ship_for_pilot(selected_pilot, null, true)
	selected_weapon = _resolve_weapon_for_ship(selected_ship, null)
	_emit_selection_changed()

func set_selected_ship(ship: ShipDef) -> void:
	var pilot: PilotDef = _resolve_selected_or_default_pilot()
	if ship == null or pilot == null:
		return
	if not _is_ship_valid_for_pilot(ship, pilot):
		push_warning("Ignoring invalid or locked starter ship: %s" % String(ship.get_ship_id()))
		return
	selected_ship = ship
	_remember_selected_ship(pilot, ship)
	selected_weapon = _resolve_weapon_for_ship(selected_ship, null)
	_emit_selection_changed()

func set_selected_weapon(weapon: WeaponDef) -> void:
	var ship: ShipDef = _resolve_selected_or_default_ship()
	if weapon == null or ship == null:
		return
	if not _is_weapon_valid_for_ship(weapon, ship):
		push_warning("Ignoring invalid or locked starter weapon: %s" % String(weapon.get_weapon_id()))
		return
	selected_weapon = weapon
	_remember_selected_weapon(ship, weapon)
	_emit_selection_changed()

func get_selected_ship() -> ShipDef:
	return _resolve_selected_or_default_ship()

func get_selected_weapon() -> WeaponDef:
	return _resolve_selected_or_default_weapon()

func get_starter_ship_options(pilot: PilotDef) -> Array[PilotStarterShipOptionDef]:
	var resolved: Array[PilotStarterShipOptionDef] = []
	var seen_paths: Dictionary = {}
	var seen_ids: Dictionary = {}
	if pilot == null:
		return resolved

	for option in pilot.starter_ship_options:
		if option == null or not option.is_selectable():
			continue
		var ship: ShipDef = option.ship
		var path_key: String = ship.resource_path if ship != null else ""
		if path_key != "" and seen_paths.has(path_key):
			continue
		var ship_id: StringName = option.get_ship_id()
		if ship_id != &"" and seen_ids.has(ship_id):
			if path_key != "":
				seen_paths[path_key] = true
			continue
		resolved.append(option)
		if path_key != "":
			seen_paths[path_key] = true
		if ship_id != &"":
			seen_ids[ship_id] = true

	if resolved.is_empty():
		var fallback_option: PilotStarterShipOptionDef = _make_fallback_ship_option(pilot.ship)
		if fallback_option != null:
			resolved.append(fallback_option)

	resolved.sort_custom(_sort_ship_options)
	return resolved

func get_starter_weapon_options(ship: ShipDef) -> Array[ShipStarterWeaponOptionDef]:
	var resolved: Array[ShipStarterWeaponOptionDef] = []
	var seen_paths: Dictionary = {}
	var seen_ids: Dictionary = {}
	if ship == null:
		return resolved

	for option in ship.starter_weapon_options:
		if option == null or not option.is_selectable():
			continue
		var weapon: WeaponDef = option.weapon
		var path_key: String = weapon.resource_path if weapon != null else ""
		if path_key != "" and seen_paths.has(path_key):
			continue
		var weapon_id: StringName = option.get_weapon_id()
		if weapon_id != &"" and seen_ids.has(weapon_id):
			if path_key != "":
				seen_paths[path_key] = true
			continue
		resolved.append(option)
		if path_key != "":
			seen_paths[path_key] = true
		if weapon_id != &"":
			seen_ids[weapon_id] = true

	if resolved.is_empty():
		var fallback_weapon: WeaponDef = _get_first_weapon_in_loadout(ship.loadout)
		var fallback_option: ShipStarterWeaponOptionDef = _make_fallback_weapon_option(fallback_weapon)
		if fallback_option != null:
			resolved.append(fallback_option)

	resolved.sort_custom(_sort_weapon_options)
	return resolved

func is_ship_option_unlocked(option: PilotStarterShipOptionDef) -> bool:
	if option == null or not option.is_selectable():
		return false
	return _is_unlockable(
		option.starts_unlocked,
		option.unlock_requirement_mode == PilotStarterShipOptionDef.UnlockRequirementMode.ALL,
		option.unlock_requirements
	)

func is_weapon_option_unlocked(option: ShipStarterWeaponOptionDef) -> bool:
	if option == null or not option.is_selectable():
		return false
	return _is_unlockable(
		option.starts_unlocked,
		option.unlock_requirement_mode == ShipStarterWeaponOptionDef.UnlockRequirementMode.ALL,
		option.unlock_requirements
	)

func player_died() -> void:
	if _active_boss_encounter:
		complete_boss_encounter(false, true)
	_end_run_and_return_to_menu(true)

func player_won() -> void:
	if not _finalize_run_end(false):
		return
	run_completed.emit()
	run_victory_started.emit(VICTORY_MESSAGE, VICTORY_RETURN_DELAY_SEC)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	var victory_timer: SceneTreeTimer = get_tree().create_timer(VICTORY_RETURN_DELAY_SEC, true)
	await victory_timer.timeout
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU)

func _on_time_over() -> void:
	_end_run_and_return_to_menu(false)

func _end_run_and_return_to_menu(count_as_death: bool) -> void:
	if not _finalize_run_end(count_as_death):
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU)

func _finalize_run_end(count_as_death: bool) -> bool:
	if _run_end_in_progress or not _run_active:
		return false
	_run_end_in_progress = true
	_finalize_run_stats(count_as_death)
	_clear_run_progression()
	check_and_update_high_score(RunState.run_score)
	return true

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

func get_meta_stat_value(metric_key: StringName, pilot_id: StringName = &"", key: String = "") -> int:
	var slice: Dictionary = _meta_stats_global
	if pilot_id != &"":
		slice = _meta_stats_by_pilot_id.get(String(pilot_id), {})
	if key == "":
		return max(0, int(slice.get(String(metric_key), 0)))
	return max(0, int(slice.get(key, 0)))

func is_pilot_unlocked(pilot: PilotDef) -> bool:
	if pilot == null:
		return false
	if not pilot.is_selectable():
		return false
	return _is_unlockable(
		pilot.starts_unlocked,
		pilot.unlock_requirement_mode == PilotDef.UnlockRequirementMode.ALL,
		pilot.unlock_requirements
	)

func get_all_pilots() -> Array[PilotDef]:
	var roster: PilotRoster = _get_roster()
	if roster == null:
		return []
	return roster.get_pilots()

func build_selected_starting_loadout(base_loadout: ShipLoadoutDef) -> ShipLoadoutDef:
	return _build_loadout_with_weapon(base_loadout, get_selected_weapon())

func get_active_run_definition() -> RunDefinition:
	return _active_run_definition

func get_active_stage_index() -> int:
	return _active_stage_index

func get_run_elapsed_seconds() -> float:
	return max(_run_elapsed_sec, 0.0)

func get_current_stage() -> StageDef:
	if _active_run_definition == null or _active_stage_index < 0:
		return null
	return _active_run_definition.get_stage(_active_stage_index)

func get_active_stage_modifiers() -> Array[StageModifierDef]:
	var stage: StageDef = get_current_stage()
	if stage == null:
		return []
	var key: String = _get_stage_roll_key(stage)
	if key == "":
		return stage.get_guaranteed_modifiers()
	if not _rolled_stage_modifiers_by_stage_key.has(key):
		_roll_stage_modifiers(stage)
	var stored: Array = _rolled_stage_modifiers_by_stage_key.get(key, [])
	return _copy_stage_modifier_array(stored)

func has_next_stage() -> bool:
	if _active_run_definition == null:
		return false
	var current_stage: StageDef = get_current_stage()
	if current_stage != null and current_stage.next_stage_id != &"":
		return _active_run_definition.find_stage_index_by_id(current_stage.next_stage_id) >= 0
	return _active_run_definition.get_stage(_active_stage_index + 1) != null

func advance_to_next_stage(target_stage_id: StringName = &"") -> bool:
	if _active_run_definition == null:
		return false

	var next_stage_index: int = -1
	if target_stage_id != &"":
		next_stage_index = _active_run_definition.find_stage_index_by_id(target_stage_id)
	else:
		var current_stage: StageDef = get_current_stage()
		if current_stage != null and current_stage.next_stage_id != &"":
			next_stage_index = _active_run_definition.find_stage_index_by_id(current_stage.next_stage_id)
		if next_stage_index < 0:
			next_stage_index = _active_stage_index + 1

	var next_stage: StageDef = _active_run_definition.get_stage(next_stage_index)
	if next_stage == null:
		if _active_run_definition.loop_last_stage:
			next_stage_index = max(_active_run_definition.get_stage_count() - 1, 0)
			next_stage = _active_run_definition.get_stage(next_stage_index)
		else:
			run_completed.emit()
			return false
	if next_stage == null:
		return false

	_emit_stage_changed(next_stage_index)
	return true

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
	var pilot: PilotDef = _resolve_selected_or_default_pilot()
	if pilot == null:
		selected_ship = null
		selected_weapon = null
		return null
	if selected_ship != null and _is_ship_valid_for_pilot(selected_ship, pilot):
		_remember_selected_ship(pilot, selected_ship)
		return selected_ship
	selected_ship = _resolve_ship_for_pilot(pilot, null, true)
	selected_weapon = _resolve_weapon_for_ship(selected_ship, null)
	return selected_ship

func _resolve_selected_or_default_weapon() -> WeaponDef:
	var ship: ShipDef = _resolve_selected_or_default_ship()
	if ship == null:
		selected_weapon = null
		return null
	if selected_weapon != null and _is_weapon_valid_for_ship(selected_weapon, ship):
		_remember_selected_weapon(ship, selected_weapon)
		return selected_weapon
	selected_weapon = _resolve_weapon_for_ship(ship, null)
	return selected_weapon

func _ensure_default_pilot() -> void:
	if selected_pilot != null and selected_pilot.is_selectable() and is_pilot_unlocked(selected_pilot):
		selected_ship = _resolve_ship_for_pilot(selected_pilot, selected_ship, false)
		selected_weapon = _resolve_weapon_for_ship(selected_ship, selected_weapon)
		return

	selected_pilot = null
	selected_ship = null
	selected_weapon = null

	var pilots: Array[PilotDef] = get_all_pilots()
	if pilots.is_empty():
		return

	if _loaded_selected_pilot_id != &"":
		var saved_choice: PilotDef = _find_pilot_by_id(_loaded_selected_pilot_id)
		if saved_choice != null and is_pilot_unlocked(saved_choice):
			selected_pilot = saved_choice
			selected_ship = _resolve_ship_for_pilot(selected_pilot, _load_ship_from_id(_loaded_selected_ship_id), true)
			selected_weapon = _resolve_weapon_for_ship(selected_ship, null)
			return

	for pilot in pilots:
		if pilot != null and is_pilot_unlocked(pilot):
			selected_pilot = pilot
			selected_ship = _resolve_ship_for_pilot(selected_pilot, null, false)
			selected_weapon = _resolve_weapon_for_ship(selected_ship, null)
			return

	selected_pilot = pilots[0]
	selected_ship = _resolve_ship_for_pilot(selected_pilot, null, false)
	selected_weapon = _resolve_weapon_for_ship(selected_ship, null)

func _resolve_ship_for_pilot(pilot: PilotDef, preferred_ship: ShipDef, allow_legacy_current: bool) -> ShipDef:
	if pilot == null:
		return null
	if preferred_ship != null and _is_ship_valid_for_pilot(preferred_ship, pilot):
		_remember_selected_ship(pilot, preferred_ship)
		return preferred_ship

	var remembered_ship_id: StringName = _get_remembered_ship_id_for_pilot(pilot)
	if remembered_ship_id != &"":
		var remembered_ship: ShipDef = _find_ship_for_pilot_by_id(pilot, remembered_ship_id, true)
		if remembered_ship != null:
			_remember_selected_ship(pilot, remembered_ship)
			return remembered_ship

	if allow_legacy_current and _loaded_selected_ship_id != &"":
		var legacy_ship: ShipDef = _find_ship_for_pilot_by_id(pilot, _loaded_selected_ship_id, true)
		if legacy_ship != null:
			_remember_selected_ship(pilot, legacy_ship)
			return legacy_ship

	var fallback_ship: ShipDef = _find_first_unlocked_ship_for_pilot(pilot)
	if fallback_ship != null:
		_remember_selected_ship(pilot, fallback_ship)
	return fallback_ship

func _resolve_weapon_for_ship(ship: ShipDef, preferred_weapon: WeaponDef) -> WeaponDef:
	if ship == null:
		return null
	if preferred_weapon != null and _is_weapon_valid_for_ship(preferred_weapon, ship):
		_remember_selected_weapon(ship, preferred_weapon)
		return preferred_weapon

	var remembered_weapon_id: StringName = _get_remembered_weapon_id_for_ship(ship)
	if remembered_weapon_id != &"":
		var remembered_weapon: WeaponDef = _find_weapon_for_ship_by_id(ship, remembered_weapon_id, true)
		if remembered_weapon != null:
			_remember_selected_weapon(ship, remembered_weapon)
			return remembered_weapon

	var fallback_weapon: WeaponDef = _find_first_unlocked_weapon_for_ship(ship)
	if fallback_weapon != null:
		_remember_selected_weapon(ship, fallback_weapon)
	return fallback_weapon

func _find_first_unlocked_ship_for_pilot(pilot: PilotDef) -> ShipDef:
	for option in get_starter_ship_options(pilot):
		if is_ship_option_unlocked(option):
			return option.ship
	return null

func _find_first_unlocked_weapon_for_ship(ship: ShipDef) -> WeaponDef:
	for option in get_starter_weapon_options(ship):
		if is_weapon_option_unlocked(option):
			return option.weapon
	return null

func _find_ship_for_pilot_by_id(pilot: PilotDef, ship_id: StringName, require_unlocked: bool) -> ShipDef:
	if pilot == null or ship_id == &"":
		return null
	for option in get_starter_ship_options(pilot):
		if option == null or not option.is_selectable():
			continue
		if option.get_ship_id() != ship_id:
			continue
		if require_unlocked and not is_ship_option_unlocked(option):
			return null
		return option.ship
	return null

func _find_weapon_for_ship_by_id(ship: ShipDef, weapon_id: StringName, require_unlocked: bool) -> WeaponDef:
	if ship == null or weapon_id == &"":
		return null
	for option in get_starter_weapon_options(ship):
		if option == null or not option.is_selectable():
			continue
		if option.get_weapon_id() != weapon_id:
			continue
		if require_unlocked and not is_weapon_option_unlocked(option):
			return null
		return option.weapon
	return null

func _is_ship_valid_for_pilot(ship: ShipDef, pilot: PilotDef) -> bool:
	if ship == null or pilot == null:
		return false
	var ship_id: StringName = ship.get_ship_id()
	if ship_id == &"":
		return false
	return _find_ship_for_pilot_by_id(pilot, ship_id, true) != null

func _is_weapon_valid_for_ship(weapon: WeaponDef, ship: ShipDef) -> bool:
	if weapon == null or ship == null:
		return false
	var weapon_id: StringName = weapon.get_weapon_id()
	if weapon_id == &"":
		return false
	return _find_weapon_for_ship_by_id(ship, weapon_id, true) != null

func _remember_selected_ship(pilot: PilotDef, ship: ShipDef) -> void:
	if pilot == null or ship == null:
		return
	var pilot_key: String = String(pilot.get_pilot_id())
	var ship_id: StringName = ship.get_ship_id()
	if pilot_key == "" or ship_id == &"":
		return
	_selected_ship_id_by_pilot_id[pilot_key] = ship_id

func _remember_selected_weapon(ship: ShipDef, weapon: WeaponDef) -> void:
	if ship == null or weapon == null:
		return
	var ship_key: String = String(ship.get_ship_id())
	var weapon_id: StringName = weapon.get_weapon_id()
	if ship_key == "" or weapon_id == &"":
		return
	_selected_weapon_id_by_ship_id[ship_key] = weapon_id

func _get_remembered_ship_id_for_pilot(pilot: PilotDef) -> StringName:
	if pilot == null:
		return &""
	var pilot_key: String = String(pilot.get_pilot_id())
	if pilot_key == "":
		return &""
	return StringName(String(_selected_ship_id_by_pilot_id.get(pilot_key, "")))

func _get_remembered_weapon_id_for_ship(ship: ShipDef) -> StringName:
	if ship == null:
		return &""
	var ship_key: String = String(ship.get_ship_id())
	if ship_key == "":
		return &""
	return StringName(String(_selected_weapon_id_by_ship_id.get(ship_key, "")))

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
	for ship in _get_all_candidate_ships():
		if ship == null:
			continue
		if ship.get_ship_id() == ship_id:
			return ship
	return null

func _load_weapon_from_id(weapon_id: StringName) -> WeaponDef:
	if weapon_id == &"":
		return null
	for weapon in _get_all_candidate_weapons():
		if weapon == null:
			continue
		if weapon.get_weapon_id() == weapon_id:
			return weapon
	return null

func _get_all_candidate_ships() -> Array[ShipDef]:
	var result: Array[ShipDef] = []
	var seen_ids: Dictionary = {}
	var seen_paths: Dictionary = {}
	for pilot in get_all_pilots():
		if pilot == null:
			continue
		for option in get_starter_ship_options(pilot):
			if option == null or option.ship == null:
				continue
			var ship: ShipDef = option.ship
			var path_key: String = ship.resource_path
			var ship_id: StringName = ship.get_ship_id()
			if path_key != "" and seen_paths.has(path_key):
				continue
			if ship_id != &"" and seen_ids.has(ship_id):
				if path_key != "":
					seen_paths[path_key] = true
				continue
			result.append(ship)
			if path_key != "":
				seen_paths[path_key] = true
			if ship_id != &"":
				seen_ids[ship_id] = true
	return result

func _get_all_candidate_weapons() -> Array[WeaponDef]:
	var result: Array[WeaponDef] = []
	var seen_ids: Dictionary = {}
	var seen_paths: Dictionary = {}
	for ship in _get_all_candidate_ships():
		if ship == null:
			continue
		for option in get_starter_weapon_options(ship):
			if option == null or option.weapon == null:
				continue
			var weapon: WeaponDef = option.weapon
			var path_key: String = weapon.resource_path
			var weapon_id: StringName = weapon.get_weapon_id()
			if path_key != "" and seen_paths.has(path_key):
				continue
			if weapon_id != &"" and seen_ids.has(weapon_id):
				if path_key != "":
					seen_paths[path_key] = true
				continue
			result.append(weapon)
			if path_key != "":
				seen_paths[path_key] = true
			if weapon_id != &"":
				seen_ids[weapon_id] = true
	return result

func _make_fallback_ship_option(ship: ShipDef) -> PilotStarterShipOptionDef:
	if ship == null:
		return null
	var option: PilotStarterShipOptionDef = PilotStarterShipOptionDef.new()
	option.ship = ship
	option.starts_unlocked = true
	return option

func _make_fallback_weapon_option(weapon: WeaponDef) -> ShipStarterWeaponOptionDef:
	if weapon == null:
		return null
	var option: ShipStarterWeaponOptionDef = ShipStarterWeaponOptionDef.new()
	option.weapon = weapon
	option.starts_unlocked = true
	return option

func _get_first_weapon_in_loadout(loadout: ShipLoadoutDef) -> WeaponDef:
	if loadout == null:
		return null
	for mount in loadout.mounts:
		if mount != null and mount.weapon != null:
			return mount.weapon
	return null

func _build_loadout_with_weapon(base_loadout: ShipLoadoutDef, weapon: WeaponDef) -> ShipLoadoutDef:
	if base_loadout == null:
		return null
	var generated: ShipLoadoutDef = ShipLoadoutDef.new()
	var mounts: Array[MountLoadoutDef] = []
	for source in base_loadout.mounts:
		if source == null:
			continue
		var mount: MountLoadoutDef = MountLoadoutDef.new()
		mount.mount_id = source.mount_id
		mount.team_id = source.team_id
		mount.weapon = weapon if weapon != null else source.weapon
		mounts.append(mount)
	generated.mounts = mounts
	return generated

func _sort_ship_options(a: PilotStarterShipOptionDef, b: PilotStarterShipOptionDef) -> bool:
	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order
	return a.get_display_name_or_default().nocasecmp_to(b.get_display_name_or_default()) < 0

func _sort_weapon_options(a: ShipStarterWeaponOptionDef, b: ShipStarterWeaponOptionDef) -> bool:
	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order
	return a.get_display_name_or_default().nocasecmp_to(b.get_display_name_or_default()) < 0

func _emit_selection_changed() -> void:
	_save_user_data()
	selection_changed.emit(selected_pilot, selected_ship)

func _resolve_run_definition(run_definition: RunDefinition) -> RunDefinition:
	if run_definition != null:
		return run_definition
	return load(DEFAULT_RUN_DEFINITION) as RunDefinition

func _emit_stage_changed(stage_index: int) -> void:
	if _active_run_definition == null:
		_active_stage_index = -1
		return

	var stage: StageDef = _active_run_definition.get_stage(stage_index)
	if stage == null:
		_active_stage_index = -1
		return

	_active_stage_index = stage_index
	_roll_stage_modifiers(stage)
	stage_changed.emit(stage, _active_stage_index)

func _roll_stage_modifiers(stage: StageDef) -> void:
	if stage == null:
		return
	var key: String = _get_stage_roll_key(stage)
	if key == "":
		return
	if _rolled_stage_modifiers_by_stage_key.has(key):
		return

	var rolled: Array[StageModifierDef] = []
	for modifier in stage.get_guaranteed_modifiers():
		_append_unique_stage_modifier(rolled, modifier)
	for modifier in _pick_weighted_unique_modifiers(stage.get_bonus_pool(), stage.random_bonus_count):
		_append_unique_stage_modifier(rolled, modifier)
	for modifier in _pick_weighted_unique_modifiers(stage.get_debuff_pool(), stage.random_debuff_count):
		_append_unique_stage_modifier(rolled, modifier)
	_rolled_stage_modifiers_by_stage_key[key] = rolled

func _pick_weighted_unique_modifiers(pool: Array[StageModifierDef], count: int) -> Array[StageModifierDef]:
	var remaining: Array[StageModifierDef] = []
	for modifier in pool:
		if modifier != null:
			remaining.append(modifier)

	var picked: Array[StageModifierDef] = []
	var picks_remaining: int = min(max(count, 0), remaining.size())
	while picks_remaining > 0 and not remaining.is_empty():
		var choice_index: int = _pick_weighted_modifier_index(remaining)
		var chosen: StageModifierDef = remaining[choice_index]
		if chosen != null:
			picked.append(chosen)
		remaining.remove_at(choice_index)
		picks_remaining -= 1
	return picked

func _pick_weighted_modifier_index(pool: Array[StageModifierDef]) -> int:
	if pool.is_empty():
		return 0

	var total_weight: float = 0.0
	for modifier in pool:
		if modifier != null:
			total_weight += max(modifier.weight, 0.0)

	if total_weight <= 0.0:
		return _stage_modifier_rng.randi_range(0, pool.size() - 1)

	var roll: float = _stage_modifier_rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for i in pool.size():
		var modifier: StageModifierDef = pool[i]
		cursor += max(modifier.weight, 0.0) if modifier != null else 0.0
		if roll <= cursor:
			return i
	return pool.size() - 1

func _append_unique_stage_modifier(target: Array[StageModifierDef], modifier: StageModifierDef) -> void:
	if modifier == null:
		return
	var incoming_key: String = _get_modifier_roll_key(modifier)
	for existing in target:
		if existing == null:
			continue
		if _get_modifier_roll_key(existing) == incoming_key:
			return
	target.append(modifier)

func _get_stage_roll_key(stage: StageDef) -> String:
	if stage == null:
		return ""
	var stage_id: StringName = stage.get_stage_id()
	if stage_id != &"":
		return String(stage_id)
	return stage.resource_path

func _get_modifier_roll_key(modifier: StageModifierDef) -> String:
	if modifier == null:
		return ""
	var modifier_id: StringName = modifier.get_modifier_id()
	if modifier_id != &"":
		return String(modifier_id)
	return modifier.resource_path

func _copy_stage_modifier_array(source: Array) -> Array[StageModifierDef]:
	var copied: Array[StageModifierDef] = []
	for entry in source:
		var modifier: StageModifierDef = entry as StageModifierDef
		if modifier != null:
			copied.append(modifier)
	return copied

func _clear_run_progression() -> void:
	_active_run_definition = null
	_active_stage_index = -1
	_run_elapsed_sec = 0.0
	_run_meta_stats_global.clear()
	_run_meta_stats_by_pilot_id.clear()
	_run_boss_stats_global_by_id.clear()
	_run_boss_stats_by_pilot_id.clear()
	_clear_active_boss_encounter_state()
	_rolled_stage_modifiers_by_stage_key.clear()

func _on_run_nanobots_updated(amount: int) -> void:
	if not _run_active:
		return

	if amount > _run_peak_nanobots:
		_run_peak_nanobots = amount

	if amount > _run_last_nanobots_value:
		_run_total_nanobots_collected += amount - _run_last_nanobots_value

	_run_last_nanobots_value = amount

func _record_run_meta_stat(metric_key: StringName, amount: float, combat_stat_context: CombatStatContext) -> void:
	if not _run_active:
		return
	if combat_stat_context == null:
		return
	if amount <= 0.0:
		return

	var effective_context: CombatStatContext = _prepare_combat_stat_context(combat_stat_context)
	var keys: Array[String] = _build_meta_stat_keys_for_context(String(metric_key), effective_context)
	if keys.is_empty():
		return

	for key in keys:
		_add_run_meta_stat_value(_run_meta_stats_global, key, amount)

	var pilot_id: StringName = effective_context.pilot_id
	if pilot_id != &"":
		var pilot_slice: Dictionary = _get_or_create_run_meta_stat_slice(pilot_id)
		for key in keys:
			_add_run_meta_stat_value(pilot_slice, key, amount)

func _prepare_combat_stat_context(combat_stat_context: CombatStatContext) -> CombatStatContext:
	var effective_context: CombatStatContext = combat_stat_context.duplicate_context()
	if effective_context.pilot_id == &"":
		effective_context.pilot_id = _run_pilot_id
	if effective_context.ship_id == &"":
		var active_ship: ShipDef = _resolve_selected_or_default_ship()
		effective_context.ship_id = active_ship.get_ship_id() if active_ship != null else &""
	effective_context.equipped_weapon_ids = effective_context.get_normalized_equipped_weapon_ids()
	return effective_context

func _add_run_meta_stat_value(target: Dictionary, key: String, amount: float) -> void:
	target[key] = float(target.get(key, 0.0)) + amount

func _get_or_create_run_meta_stat_slice(pilot_id: StringName) -> Dictionary:
	var key: String = String(pilot_id)
	if key == "":
		return {}
	if not _run_meta_stats_by_pilot_id.has(key):
		_run_meta_stats_by_pilot_id[key] = {}
	return _run_meta_stats_by_pilot_id[key] as Dictionary

func _get_or_create_meta_stat_slice(pilot_id: StringName) -> Dictionary:
	var key: String = String(pilot_id)
	if key == "":
		return _meta_stats_global
	if not _meta_stats_by_pilot_id.has(key):
		_meta_stats_by_pilot_id[key] = {}
	return _meta_stats_by_pilot_id[key] as Dictionary

func _flush_run_meta_stats_to_lifetime() -> void:
	_merge_run_meta_stat_slice(_meta_stats_global, _run_meta_stats_global)
	for pilot_key_variant in _run_meta_stats_by_pilot_id.keys():
		var pilot_key: String = String(pilot_key_variant)
		var target_slice: Dictionary = _get_or_create_meta_stat_slice(StringName(pilot_key))
		var source_slice: Dictionary = _run_meta_stats_by_pilot_id[pilot_key] as Dictionary
		_merge_run_meta_stat_slice(target_slice, source_slice)

func _merge_run_meta_stat_slice(target: Dictionary, source: Dictionary) -> void:
	for raw_key_variant in source.keys():
		var raw_key: String = String(raw_key_variant)
		var amount: float = float(source[raw_key_variant])
		var rounded_amount: int = int(round(amount))
		if rounded_amount <= 0:
			continue
		target[raw_key] = int(target.get(raw_key, 0)) + rounded_amount

func _build_meta_stat_keys_for_context(metric_key: String, combat_stat_context: CombatStatContext) -> Array[String]:
	var keys_set: Dictionary = {}
	if metric_key == "":
		return []
	keys_set[metric_key] = true

	var axes: Array[Dictionary] = []
	if combat_stat_context.ship_id != &"":
		axes.append({ "axis": "ship", "values": [String(combat_stat_context.ship_id)] })
	if combat_stat_context.weapon_direct_id != &"":
		axes.append({ "axis": "weapon_direct", "values": [String(combat_stat_context.weapon_direct_id)] })
	var equipped_weapon_values: Array[String] = []
	for weapon_id in combat_stat_context.get_normalized_equipped_weapon_ids():
		equipped_weapon_values.append(String(weapon_id))
	if not equipped_weapon_values.is_empty():
		axes.append({ "axis": "weapon_equipped", "values": equipped_weapon_values })
	if combat_stat_context.enemy_id != &"":
		axes.append({ "axis": "enemy", "values": [String(combat_stat_context.enemy_id)] })
	if combat_stat_context.faction_id != &"":
		axes.append({ "axis": "faction", "values": [String(combat_stat_context.faction_id)] })
	if combat_stat_context.role_id != &"":
		axes.append({ "axis": "role", "values": [String(combat_stat_context.role_id)] })

	var initial_parts: Array[String] = []
	_append_meta_stat_key_combinations(metric_key, axes, 0, initial_parts, keys_set)

	var keys: Array[String] = []
	for key_variant in keys_set.keys():
		keys.append(String(key_variant))
	return keys

func _append_meta_stat_key_combinations(metric_key: String, axes: Array[Dictionary], axis_index: int, parts: Array[String], keys_set: Dictionary) -> void:
	if axis_index >= axes.size():
		if parts.is_empty():
			return
		keys_set["%s|%s" % [metric_key, "|".join(parts)]] = true
		return

	_append_meta_stat_key_combinations(metric_key, axes, axis_index + 1, parts, keys_set)

	var axis_entry: Dictionary = axes[axis_index] as Dictionary
	var axis_name: String = String(axis_entry.get("axis", ""))
	var values: Array = axis_entry.get("values", [])
	for raw_value in values:
		var next_parts: Array[String] = parts.duplicate()
		next_parts.append(axis_name)
		next_parts.append(String(raw_value))
		_append_meta_stat_key_combinations(metric_key, axes, axis_index + 1, next_parts, keys_set)

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

	var run_seconds: int = int(round(get_run_elapsed_seconds()))

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
	_flush_run_meta_stats_to_lifetime()
	_flush_run_boss_stats_to_lifetime()
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

func _is_unlockable(starts_unlocked: bool, require_all: bool, requirements: Array) -> bool:
	if starts_unlocked:
		return true
	if requirements.is_empty():
		return false

	var found_valid_requirement: bool = false
	for entry in requirements:
		var requirement: UnlockRequirement = entry as UnlockRequirement
		if requirement == null:
			continue
		found_valid_requirement = true
		var met: bool = _is_unlock_requirement_met(requirement)
		if require_all and not met:
			return false
		if not require_all and met:
			return true

	if not found_valid_requirement:
		return false
	return require_all

func _is_unlock_requirement_met(requirement: UnlockRequirement) -> bool:
	if requirement == null:
		return false
	return _get_requirement_stat_value(requirement) >= max(requirement.minimum_value, 0)

func _get_requirement_stat_value(requirement: UnlockRequirement) -> int:
	if _is_matrix_unlock_stat(requirement.stat):
		return _get_matrix_requirement_stat_value(requirement)
	if requirement.source_pilot_id != &"":
		return _get_pilot_stat_value(requirement.source_pilot_id, requirement.stat)
	return _get_global_stat_value(requirement.stat)

func _is_matrix_unlock_stat(stat: UnlockRequirement.UnlockStat) -> bool:
	return (
		stat == UnlockRequirement.UnlockStat.KILLS
		or stat == UnlockRequirement.UnlockStat.DAMAGE_DEALT
		or stat == UnlockRequirement.UnlockStat.DAMAGE_TAKEN
	)

func _get_matrix_requirement_stat_value(requirement: UnlockRequirement) -> int:
	var metric_key: StringName = _map_unlock_stat_to_meta_stat_key(requirement.stat)
	if metric_key == &"":
		return 0
	var storage_key: String = _build_requirement_meta_stat_key(metric_key, requirement)
	return get_meta_stat_value(metric_key, requirement.source_pilot_id, storage_key)

func _get_pilot_stat_value(pilot_id: StringName, stat: UnlockRequirement.UnlockStat) -> int:
	var key: StringName = _map_unlock_stat_to_key(stat)
	var stats: Dictionary = get_pilot_stats(pilot_id)
	return int(stats.get(key, 0))

func _get_global_stat_value(stat: UnlockRequirement.UnlockStat) -> int:
	if stat == UnlockRequirement.UnlockStat.HIGHEST_SCORE:
		return high_score

	if stat == UnlockRequirement.UnlockStat.DEATH_RUNS:
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

func _map_unlock_stat_to_key(stat: UnlockRequirement.UnlockStat) -> StringName:
	match stat:
		UnlockRequirement.UnlockStat.HIGHEST_SCORE:
			return STAT_HIGHEST_SCORE
		UnlockRequirement.UnlockStat.LONGEST_RUN_SECONDS:
			return STAT_LONGEST_RUN_SECONDS
		UnlockRequirement.UnlockStat.DEATH_RUNS:
			return STAT_DEATH_RUNS
		UnlockRequirement.UnlockStat.TOTAL_NANOBOTS_IN_RUN:
			return STAT_TOTAL_NANOBOTS_IN_RUN
		UnlockRequirement.UnlockStat.HIGHEST_NANOBOTS_IN_RUN:
			return STAT_HIGHEST_NANOBOTS_IN_RUN
		UnlockRequirement.UnlockStat.HIGHEST_WAVE_REACHED:
			return STAT_HIGHEST_WAVE_REACHED
	return STAT_HIGHEST_SCORE

func _map_unlock_stat_to_meta_stat_key(stat: UnlockRequirement.UnlockStat) -> StringName:
	match stat:
		UnlockRequirement.UnlockStat.KILLS:
			return META_STAT_KILLS
		UnlockRequirement.UnlockStat.DAMAGE_DEALT:
			return META_STAT_DAMAGE_DEALT
		UnlockRequirement.UnlockStat.DAMAGE_TAKEN:
			return META_STAT_DAMAGE_TAKEN
	return &""

func _build_requirement_meta_stat_key(metric_key: StringName, requirement: UnlockRequirement) -> String:
	var parts: Array[String] = []
	if requirement.ship_id != &"":
		parts.append("ship")
		parts.append(String(requirement.ship_id))
	if requirement.weapon_id != &"":
		var axis_name: String = "weapon_direct"
		if requirement.weapon_context == UnlockRequirement.WeaponContext.EQUIPPED:
			axis_name = "weapon_equipped"
		parts.append(axis_name)
		parts.append(String(requirement.weapon_id))
	if requirement.enemy_id != &"":
		parts.append("enemy")
		parts.append(String(requirement.enemy_id))
	if requirement.faction_id != &"":
		parts.append("faction")
		parts.append(String(requirement.faction_id))
	if requirement.role_id != &"":
		parts.append("role")
		parts.append(String(requirement.role_id))
	if parts.is_empty():
		return String(metric_key)
	return "%s|%s" % [String(metric_key), "|".join(parts)]

func _get_or_create_stats_for_pilot(pilot_id: StringName) -> Dictionary:
	var key: String = String(pilot_id)
	if key == "":
		return _make_default_pilot_stats()
	if not _pilot_stats_by_id.has(key):
		_pilot_stats_by_id[key] = _make_default_pilot_stats()
	return (_pilot_stats_by_id[key] as Dictionary).duplicate(true)

func _make_default_pilot_stats() -> Dictionary:
	return PILOT_STAT_DEFAULTS.duplicate(true)

func _make_default_boss_stats() -> Dictionary:
	return BOSS_STAT_DEFAULTS.duplicate(true)

func _get_current_game_version() -> String:
	var value: String = String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	return value if value != "" else "dev"

func _should_reset_save(saved_schema_version: int, _saved_game_version: String, _current_game_version: String) -> bool:
	if saved_schema_version > 0 and saved_schema_version != CURRENT_SAVE_SCHEMA_VERSION:
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
	cfg.set_value("%s.meta" % archive_base, "reason", "schema_mismatch")
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
	_meta_stats_global.clear()
	_meta_stats_by_pilot_id.clear()
	_boss_stats_global_by_id.clear()
	_boss_stats_by_pilot_id.clear()
	_selected_ship_id_by_pilot_id.clear()
	_selected_weapon_id_by_ship_id.clear()
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
		if section.begins_with(PILOT_STATS_SECTION_PREFIX):
			var pilot_id: String = section.trim_prefix(PILOT_STATS_SECTION_PREFIX)
			if pilot_id == "":
				continue
			var loaded_stats: Dictionary = _make_default_pilot_stats()
			for key in PILOT_STAT_DEFAULTS.keys():
				var stat_key: StringName = key as StringName
				var default_value: int = int(PILOT_STAT_DEFAULTS[stat_key])
				loaded_stats[stat_key] = max(0, int(cfg.get_value(section, String(stat_key), default_value)))
			_pilot_stats_by_id[pilot_id] = loaded_stats
			continue
		if section == META_STATS_GLOBAL_SECTION:
			_meta_stats_global = _load_meta_stat_section(cfg, section)
			continue
		if section.begins_with(META_STATS_PILOT_SECTION_PREFIX):
			var meta_pilot_id: String = section.trim_prefix(META_STATS_PILOT_SECTION_PREFIX)
			if meta_pilot_id == "":
				continue
			_meta_stats_by_pilot_id[meta_pilot_id] = _load_meta_stat_section(cfg, section)
			continue
		if section.begins_with(BOSS_STATS_GLOBAL_SECTION_PREFIX):
			var global_boss_id: String = section.trim_prefix(BOSS_STATS_GLOBAL_SECTION_PREFIX)
			if global_boss_id == "":
				continue
			_boss_stats_global_by_id[global_boss_id] = _load_boss_stat_section(cfg, section)
			continue
		if section.begins_with(BOSS_STATS_PILOT_SECTION_PREFIX):
			var trimmed_boss_section: String = section.trim_prefix(BOSS_STATS_PILOT_SECTION_PREFIX)
			var split_index: int = trimmed_boss_section.find(".")
			if split_index <= 0 or split_index >= trimmed_boss_section.length() - 1:
				continue
			var boss_pilot_id: String = trimmed_boss_section.substr(0, split_index)
			var boss_id: String = trimmed_boss_section.substr(split_index + 1)
			if boss_pilot_id == "" or boss_id == "":
				continue
			if not _boss_stats_by_pilot_id.has(boss_pilot_id):
				_boss_stats_by_pilot_id[boss_pilot_id] = {}
			var boss_stats_by_id: Dictionary = _boss_stats_by_pilot_id[boss_pilot_id] as Dictionary
			boss_stats_by_id[boss_id] = _load_boss_stat_section(cfg, section)
			_boss_stats_by_pilot_id[boss_pilot_id] = boss_stats_by_id
			continue
		if section.begins_with(PILOT_SHIP_SELECTION_SECTION_PREFIX):
			var selection_pilot_id: String = section.trim_prefix(PILOT_SHIP_SELECTION_SECTION_PREFIX)
			if selection_pilot_id == "":
				continue
			var selected_ship_id: StringName = StringName(String(cfg.get_value(section, SELECTION_KEY_SELECTED_SHIP_ID, "")))
			if selected_ship_id != &"":
				_selected_ship_id_by_pilot_id[selection_pilot_id] = selected_ship_id
			continue
		if section.begins_with(SHIP_WEAPON_SELECTION_SECTION_PREFIX):
			var selection_ship_id: String = section.trim_prefix(SHIP_WEAPON_SELECTION_SECTION_PREFIX)
			if selection_ship_id == "":
				continue
			var selected_weapon_id: StringName = StringName(String(cfg.get_value(section, SELECTION_KEY_SELECTED_WEAPON_ID, "")))
			if selected_weapon_id != &"":
				_selected_weapon_id_by_ship_id[selection_ship_id] = selected_weapon_id

func _save_user_data() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SAVE_PATH)

	cfg.set_value(SCORE_SECTION, SCORE_KEY_HIGH_SCORE, high_score)
	cfg.set_value(META_SECTION, META_KEY_SELECTED_PILOT, String(selected_pilot.get_pilot_id()) if selected_pilot != null else "")
	cfg.set_value(META_SECTION, META_KEY_SELECTED_SHIP_ID, String(selected_ship.get_ship_id()) if selected_ship != null else "")
	cfg.set_value(META_SECTION, META_KEY_SAVE_SCHEMA_VERSION, CURRENT_SAVE_SCHEMA_VERSION)
	cfg.set_value(META_SECTION, META_KEY_GAME_VERSION, _get_current_game_version())

	for section in cfg.get_sections():
		if section.begins_with(PILOT_STATS_SECTION_PREFIX):
			cfg.erase_section(section)
			continue
		if section == META_STATS_GLOBAL_SECTION:
			cfg.erase_section(section)
			continue
		if section.begins_with(META_STATS_PILOT_SECTION_PREFIX):
			cfg.erase_section(section)
			continue
		if section.begins_with(BOSS_STATS_GLOBAL_SECTION_PREFIX):
			cfg.erase_section(section)
			continue
		if section.begins_with(BOSS_STATS_PILOT_SECTION_PREFIX):
			cfg.erase_section(section)
			continue
		if section.begins_with(PILOT_SHIP_SELECTION_SECTION_PREFIX):
			cfg.erase_section(section)
			continue
		if section.begins_with(SHIP_WEAPON_SELECTION_SECTION_PREFIX):
			cfg.erase_section(section)

	for pilot_id in _pilot_stats_by_id.keys():
		var section: String = "%s%s" % [PILOT_STATS_SECTION_PREFIX, String(pilot_id)]
		var stats: Dictionary = _pilot_stats_by_id[pilot_id] as Dictionary
		for key in PILOT_STAT_DEFAULTS.keys():
			var stat_key: StringName = key as StringName
			cfg.set_value(section, String(stat_key), max(0, int(stats.get(stat_key, 0))))

	_save_meta_stat_section(cfg, META_STATS_GLOBAL_SECTION, _meta_stats_global)
	for pilot_id in _meta_stats_by_pilot_id.keys():
		var meta_section: String = "%s%s" % [META_STATS_PILOT_SECTION_PREFIX, String(pilot_id)]
		var meta_stats: Dictionary = _meta_stats_by_pilot_id[pilot_id] as Dictionary
		_save_meta_stat_section(cfg, meta_section, meta_stats)

	for boss_id_variant in _boss_stats_global_by_id.keys():
		var boss_id: String = String(boss_id_variant)
		if boss_id == "":
			continue
		var global_boss_section: String = "%s%s" % [BOSS_STATS_GLOBAL_SECTION_PREFIX, boss_id]
		var global_boss_stats: Dictionary = _boss_stats_global_by_id[boss_id] as Dictionary
		_save_boss_stat_section(cfg, global_boss_section, global_boss_stats)

	for pilot_id_variant in _boss_stats_by_pilot_id.keys():
		var pilot_key: String = String(pilot_id_variant)
		var boss_entries: Dictionary = _boss_stats_by_pilot_id[pilot_key] as Dictionary
		for boss_id_variant in boss_entries.keys():
			var boss_key: String = String(boss_id_variant)
			if pilot_key == "" or boss_key == "":
				continue
			var pilot_boss_section: String = "%s%s.%s" % [BOSS_STATS_PILOT_SECTION_PREFIX, pilot_key, boss_key]
			var pilot_boss_stats: Dictionary = boss_entries[boss_key] as Dictionary
			_save_boss_stat_section(cfg, pilot_boss_section, pilot_boss_stats)

	for pilot_id in _selected_ship_id_by_pilot_id.keys():
		var ship_section: String = "%s%s" % [PILOT_SHIP_SELECTION_SECTION_PREFIX, String(pilot_id)]
		var ship_id: String = String(_selected_ship_id_by_pilot_id[pilot_id])
		if ship_id == "":
			continue
		cfg.set_value(ship_section, SELECTION_KEY_SELECTED_SHIP_ID, ship_id)

	for ship_id in _selected_weapon_id_by_ship_id.keys():
		var weapon_section: String = "%s%s" % [SHIP_WEAPON_SELECTION_SECTION_PREFIX, String(ship_id)]
		var weapon_id: String = String(_selected_weapon_id_by_ship_id[ship_id])
		if weapon_id == "":
			continue
		cfg.set_value(weapon_section, SELECTION_KEY_SELECTED_WEAPON_ID, weapon_id)

	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Failed to save user data to %s (err %d)".format([SAVE_PATH, err]))

func _load_meta_stat_section(cfg: ConfigFile, section: String) -> Dictionary:
	var loaded: Dictionary = {}
	for key in cfg.get_section_keys(section):
		loaded[String(key)] = max(0, int(cfg.get_value(section, key, 0)))
	return loaded

func _save_meta_stat_section(cfg: ConfigFile, section: String, values: Dictionary) -> void:
	for key_variant in values.keys():
		var key: String = String(key_variant)
		var amount: int = max(0, int(values[key_variant]))
		if amount <= 0:
			continue
		cfg.set_value(section, key, amount)

func _record_active_boss_metric(metric_key: String, amount: float, combat_stat_context: CombatStatContext) -> void:
	if not _active_boss_encounter or _active_boss_def == null:
		return
	if combat_stat_context == null or amount <= 0.0:
		return
	var effective_context: CombatStatContext = _prepare_combat_stat_context(combat_stat_context)
	if effective_context.enemy_id != StringName(_get_boss_stat_id(_active_boss_def)):
		return
	_add_run_boss_stat(_get_boss_stat_id(_active_boss_def), metric_key, amount)

func _add_run_boss_stat(boss_id: String, metric_key: String, amount: float) -> void:
	var normalized_boss_id: String = boss_id.strip_edges()
	var normalized_metric_key: String = metric_key.strip_edges()
	if normalized_boss_id == "" or normalized_metric_key == "" or amount <= 0.0:
		return
	var global_slice: Dictionary = _get_or_create_run_boss_stat_global_slice(normalized_boss_id)
	_add_run_boss_stat_value(global_slice, normalized_metric_key, amount)
	if _run_pilot_id != &"":
		var pilot_slice: Dictionary = _get_or_create_run_boss_stat_pilot_slice(_run_pilot_id, normalized_boss_id)
		_add_run_boss_stat_value(pilot_slice, normalized_metric_key, amount)

func _add_run_boss_stat_value(target: Dictionary, key: String, amount: float) -> void:
	target[key] = float(target.get(key, 0.0)) + amount

func _get_or_create_run_boss_stat_global_slice(boss_id: String) -> Dictionary:
	if not _run_boss_stats_global_by_id.has(boss_id):
		_run_boss_stats_global_by_id[boss_id] = _make_default_boss_stats()
	return _run_boss_stats_global_by_id[boss_id] as Dictionary

func _get_or_create_run_boss_stat_pilot_slice(pilot_id: StringName, boss_id: String) -> Dictionary:
	var pilot_key: String = String(pilot_id)
	if pilot_key == "":
		return _make_default_boss_stats()
	if not _run_boss_stats_by_pilot_id.has(pilot_key):
		_run_boss_stats_by_pilot_id[pilot_key] = {}
	var boss_entries: Dictionary = _run_boss_stats_by_pilot_id[pilot_key] as Dictionary
	if not boss_entries.has(boss_id):
		boss_entries[boss_id] = _make_default_boss_stats()
		_run_boss_stats_by_pilot_id[pilot_key] = boss_entries
	return boss_entries[boss_id] as Dictionary

func _get_or_create_boss_stat_global_slice(boss_id: String) -> Dictionary:
	if not _boss_stats_global_by_id.has(boss_id):
		_boss_stats_global_by_id[boss_id] = _make_default_boss_stats()
	return _boss_stats_global_by_id[boss_id] as Dictionary

func _get_or_create_boss_stat_pilot_slice(pilot_id: StringName, boss_id: String) -> Dictionary:
	var pilot_key: String = String(pilot_id)
	if pilot_key == "":
		return _make_default_boss_stats()
	if not _boss_stats_by_pilot_id.has(pilot_key):
		_boss_stats_by_pilot_id[pilot_key] = {}
	var boss_entries: Dictionary = _boss_stats_by_pilot_id[pilot_key] as Dictionary
	if not boss_entries.has(boss_id):
		boss_entries[boss_id] = _make_default_boss_stats()
		_boss_stats_by_pilot_id[pilot_key] = boss_entries
	return boss_entries[boss_id] as Dictionary

func _flush_run_boss_stats_to_lifetime() -> void:
	for boss_id_variant in _run_boss_stats_global_by_id.keys():
		var boss_id: String = String(boss_id_variant)
		var target_global: Dictionary = _get_or_create_boss_stat_global_slice(boss_id)
		var source_global: Dictionary = _run_boss_stats_global_by_id[boss_id] as Dictionary
		_merge_run_boss_stat_slice(target_global, source_global)
	for pilot_id_variant in _run_boss_stats_by_pilot_id.keys():
		var pilot_key: String = String(pilot_id_variant)
		var boss_entries: Dictionary = _run_boss_stats_by_pilot_id[pilot_key] as Dictionary
		for boss_id_variant in boss_entries.keys():
			var boss_id: String = String(boss_id_variant)
			var target_pilot: Dictionary = _get_or_create_boss_stat_pilot_slice(StringName(pilot_key), boss_id)
			var source_pilot: Dictionary = boss_entries[boss_id] as Dictionary
			_merge_run_boss_stat_slice(target_pilot, source_pilot)

func _merge_run_boss_stat_slice(target: Dictionary, source: Dictionary) -> void:
	for raw_key_variant in source.keys():
		var raw_key: String = String(raw_key_variant)
		var amount: float = float(source[raw_key_variant])
		var rounded_amount: int = int(round(amount))
		if rounded_amount <= 0:
			continue
		target[raw_key] = int(target.get(raw_key, 0)) + rounded_amount

func _load_boss_stat_section(cfg: ConfigFile, section: String) -> Dictionary:
	var loaded: Dictionary = _make_default_boss_stats()
	for key_variant in BOSS_STAT_DEFAULTS.keys():
		var key: String = String(key_variant)
		loaded[key] = max(0, int(cfg.get_value(section, key, int(BOSS_STAT_DEFAULTS[key]))))
	return loaded

func _save_boss_stat_section(cfg: ConfigFile, section: String, values: Dictionary) -> void:
	for key_variant in BOSS_STAT_DEFAULTS.keys():
		var key: String = String(key_variant)
		var amount: int = max(0, int(values.get(key, 0)))
		if amount <= 0:
			continue
		cfg.set_value(section, key, amount)

func _clear_active_boss_encounter_state() -> void:
	_active_boss_encounter = false
	_active_boss_def = null
	_active_boss_wave_index = 0
	_active_boss_encounter_time_sec = 0.0

func _get_boss_stat_id(boss_def: EnemyBossDef) -> String:
	if boss_def == null:
		return ""
	var trimmed: String = boss_def.id.strip_edges()
	if trimmed != "":
		return trimmed
	if boss_def.resource_path != "":
		return boss_def.resource_path.get_file().get_basename()
	return ""
