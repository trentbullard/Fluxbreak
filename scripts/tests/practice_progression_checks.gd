extends Node

## Run only through the wrapper's unique save namespace.
const BASE_SHIP: ShipDef = preload("res://content/data/ships/starter_fighter.tres")
const BASE_WEAPON: WeaponDef = preload("res://content/data/weapons/pulse_mk1.tres")
const BOSS: EnemyBossDef = preload("res://content/data/enemies/machine_boss_1_mk1.tres")
const DRONE_ID: StringName = &"machine_drone_mk1"
const BASE_HIGH_SCORE: int = 1000
const BASE_ANCHORS: int = 73

var _checks: int = 0
var _failures: int = 0
var _pilot: PilotDef = null
var _locked_pilot: PilotDef = null
var _locked_ship: PilotStarterShipOptionDef = null
var _locked_weapon: ShipStarterWeaponOptionDef = null
var _signals: Dictionary = {"anchors": 0, "score": 0, "stats": 0, "unlock": 0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run_checks.call_deferred()

func _run_checks() -> void:
	if String(ProjectSettings.get_setting("application/config/name", "")) != "Fluxbreak Practice Progression Validation":
		push_error("Practice progression checks require their isolated validation wrapper.")
		get_tree().quit(2)
		return
	GameFlow.abandon_run()
	_make_fixture()
	GameFlow.high_score_updated.connect(_on_high_score)
	GameFlow.flux_anchors_updated.connect(_on_anchors)
	GameFlow.pilot_stats_updated.connect(_on_pilot_stats)
	GameFlow.pilot_unlocked.connect(_on_pilot_unlocked)
	for ending: String in ["victory", "death", "timeout", "abandon", "restart", "direct_stats"]:
		_check_practice_ending(ending)
	_check_practice_to_campaign()
	_check_campaign_to_practice()
	_check_campaign_control(true)
	_check_campaign_control(false)
	GameFlow.abandon_run()
	print("PRACTICE_PROGRESSION_CHECKS: %s (%d assertions, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _make_fixture() -> void:
	_pilot = PilotDef.new()
	_pilot.id = &"practice_progression_fixture"
	_pilot.display_name = "Progression Fixture"
	_pilot.ship = BASE_SHIP
	_locked_pilot = PilotDef.new()
	_locked_pilot.id = &"practice_locked_fixture"
	_locked_pilot.display_name = "Locked Fixture"
	_locked_pilot.ship = BASE_SHIP
	_locked_pilot.starts_unlocked = false
	var pilot_requirement: PilotUnlockRequirement = PilotUnlockRequirement.new()
	pilot_requirement.stat = UnlockRequirement.UnlockStat.KILLS
	pilot_requirement.minimum_value = 5
	_locked_pilot.unlock_requirements.assign([pilot_requirement])
	var requirement: UnlockRequirement = UnlockRequirement.new()
	requirement.stat = UnlockRequirement.UnlockStat.KILLS
	requirement.minimum_value = 5
	_locked_ship = PilotStarterShipOptionDef.new()
	_locked_ship.ship = BASE_SHIP
	_locked_ship.starts_unlocked = false
	_locked_ship.unlock_requirements.assign([requirement])
	_locked_weapon = ShipStarterWeaponOptionDef.new()
	_locked_weapon.weapon = BASE_WEAPON
	_locked_weapon.starts_unlocked = false
	_locked_weapon.unlock_requirements.assign([requirement])
	var roster: PilotRoster = PilotRoster.new()
	roster.pilots.assign([_pilot, _locked_pilot])
	GameFlow._cached_roster = roster

func _seed_baseline() -> void:
	GameFlow.abandon_run()
	var saved: ConfigFile = ConfigFile.new()
	saved.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_SAVE_SCHEMA_VERSION, GameFlow.CURRENT_SAVE_SCHEMA_VERSION)
	saved.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_GAME_VERSION, ProjectSettings.get_setting("application/config/version", "dev"))
	saved.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_SELECTED_PILOT, String(_pilot.get_pilot_id()))
	saved.set_value(GameFlow.META_SECTION, GameFlow.META_KEY_FLUX_ANCHORS, BASE_ANCHORS)
	saved.set_value(GameFlow.SCORE_SECTION, GameFlow.SCORE_KEY_HIGH_SCORE, BASE_HIGH_SCORE)
	for key: StringName in GameFlow.PILOT_STAT_DEFAULTS:
		saved.set_value(GameFlow.PILOT_STATS_SECTION_PREFIX + String(_pilot.get_pilot_id()), String(key), 2)
	saved.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "kills", 4)
	saved.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "kills|enemy|machine_sentinel_mk1", 4)
	saved.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "damage_dealt", 250)
	saved.set_value(GameFlow.META_STATS_GLOBAL_SECTION, "damage_taken", 50)
	saved.set_value(GameFlow.META_STATS_PILOT_SECTION_PREFIX + String(_pilot.get_pilot_id()), "kills", 4)
	saved.set_value(GameFlow.META_STATS_PILOT_SECTION_PREFIX + String(_pilot.get_pilot_id()), "damage_dealt", 250)
	for prefix: String in [GameFlow.BOSS_STATS_GLOBAL_SECTION_PREFIX, GameFlow.BOSS_STATS_PILOT_SECTION_PREFIX + String(_pilot.get_pilot_id()) + "."]:
		saved.set_value(prefix + BOSS.id, GameFlow.BOSS_STAT_ENCOUNTERS, 3)
		saved.set_value(prefix + BOSS.id, GameFlow.BOSS_STAT_KILLS, 1)
		saved.set_value(prefix + BOSS.id, GameFlow.BOSS_STAT_DAMAGE_DEALT, 90)
		saved.set_value(prefix + BOSS.id, GameFlow.BOSS_STAT_PLAYER_DEATHS, 1)
	_expect(saved.save(GameFlow.SAVE_PATH) == OK, "Baseline writes only the isolated save file")
	GameFlow._load_user_data()
	GameFlow.set_selected_pilot(_pilot)
	GameFlow.set_selected_ship(BASE_SHIP)
	GameFlow.set_selected_weapon(BASE_WEAPON)
	_reset_signals()
	_expect(not GameFlow.is_pilot_unlocked(_locked_pilot) and not GameFlow.is_ship_option_unlocked(_locked_ship) and not GameFlow.is_weapon_option_unlocked(_locked_weapon), "Pilot, ship and starting weapon begin below their unlock threshold")
	_expect(GameFlow.get_meta_stat_value(GameFlow.META_STAT_KILLS, &"", "kills|enemy|" + String(DRONE_ID)) == 0, "The Drone begins undiscovered in the Information kill history")

func _begin(short_practice: bool) -> void:
	var run: RunDefinition = PracticeRunFactory.create_run(&"machines", short_practice)
	_expect(run != null, "The real run factory creates the fixture mode")
	GameFlow.start_new_run(run)

func _combat_context(enemy_id: StringName) -> CombatStatContext:
	var context: CombatStatContext = CombatStatContext.new()
	context.pilot_id = _pilot.get_pilot_id()
	context.ship_id = BASE_SHIP.get_ship_id()
	context.weapon_direct_id = BASE_WEAPON.get_weapon_id()
	context.equipped_weapon_ids.assign([BASE_WEAPON.get_weapon_id()])
	context.enemy_id = enemy_id
	context.faction_id = &"machines"
	context.role_id = &"scout"
	return context

func _exercise_run(boss_won: bool = true) -> void:
	RunState.add_score(12000, "progression validation")
	RunState.set_wave_context(8, 200, 0, 38)
	GameFlow._run_elapsed_sec = 600.0
	RunState.nanobots_updated.emit(200)
	RunState.nanobots_updated.emit(120)
	RunState.nanobots_updated.emit(600)
	var drone: CombatStatContext = _combat_context(DRONE_ID)
	for kill: int in range(8):
		GameFlow.record_enemy_kill(drone)
	GameFlow.record_damage_dealt(1250.0, drone)
	GameFlow.record_damage_taken(120.0, drone)
	GameFlow.begin_boss_encounter(BOSS, 30)
	var boss: CombatStatContext = _combat_context(StringName(BOSS.id))
	GameFlow.record_damage_dealt(750.0, boss)
	GameFlow.record_damage_taken(80.0, boss)
	GameFlow._active_boss_encounter_time_sec = 42.0
	if boss_won:
		GameFlow.record_enemy_kill(boss)
	GameFlow.complete_boss_encounter(boss_won, not boss_won)
	if boss_won:
		GameFlow.record_stage_completed(GameFlow.get_current_stage())
	_expect(RunState.run_score == 12000 and RunState.get_progression_wave_index() == 38, "Temporary run score and wave progress still work in the encounter")
	_expect(GameFlow._run_total_nanobots_collected == 680 and GameFlow._run_peak_nanobots == 600, "Temporary collection tracks gains and spending without losing its reward inputs")

func _snapshot() -> Dictionary:
	return {
		"saved": FileAccess.get_file_as_string(GameFlow.SAVE_PATH),
		"score": GameFlow.high_score,
		"anchors": GameFlow.flux_anchors,
		"pilots": GameFlow._pilot_stats_by_id.duplicate(true),
		"meta": GameFlow._meta_stats_global.duplicate(true),
		"meta_pilots": GameFlow._meta_stats_by_pilot_id.duplicate(true),
		"bosses": GameFlow._boss_stats_global_by_id.duplicate(true),
		"boss_pilots": GameFlow._boss_stats_by_pilot_id.duplicate(true),
		"levels": GameFlow.get_current_meta_upgrade_levels(),
		"unlocks": [GameFlow.is_pilot_unlocked(_locked_pilot), GameFlow.is_ship_option_unlocked(_locked_ship), GameFlow.is_weapon_option_unlocked(_locked_weapon)],
	}

func _expect_unchanged(before: Dictionary, signals_before: Dictionary, label: String) -> void:
	var after: Dictionary = _snapshot()
	for key: String in before:
		_expect(before[key] == after[key], "%s preserves %s" % [label, key])
	_expect(_signals == signals_before, label + " emits no currency, high-score, pilot-stat or unlock updates")
	_expect(GameFlow.get_last_flux_anchor_reward_breakdown().is_empty(), label + " reports no Flux Anchor reward")

func _check_practice_ending(ending: String) -> void:
	_seed_baseline()
	var before: Dictionary = _snapshot()
	var signals_before: Dictionary = _signals.duplicate()
	_begin(true)
	_exercise_run(ending != "death")
	GameFlow.check_and_update_high_score(999999)
	_expect_unchanged(before, signals_before, "Active Practice (" + ending + ")")
	match ending:
		"abandon":
			GameFlow.abandon_run()
		"restart":
			GameFlow.abandon_run()
			_begin(true)
			_expect(RunState.run_score == 0 and RunState.get_progression_wave_index() == 0, "Restart starts a fresh temporary encounter")
			_exercise_run()
			GameFlow.abandon_run()
		"direct_stats":
			GameFlow._finalize_run_stats(false)
			GameFlow._finalize_run_stats(true)
			_expect(not GameFlow._finalize_run_end(false), "Direct finalization cannot be finalized a second time through the public end gate")
			GameFlow.abandon_run()
		_:
			_expect(GameFlow._finalize_run_end(ending == "death"), "Practice " + ending + " finalizes its normal shared end path")
			_expect(not GameFlow._finalize_run_end(true), "Practice completion/death is idempotent")
	_expect_unchanged(before, signals_before, "Practice " + ending)
	GameFlow._load_user_data()
	_expect_unchanged(before, signals_before, "Reload after Practice " + ending)

func _check_practice_to_campaign() -> void:
	_seed_baseline()
	_begin(true)
	_exercise_run()
	# Private finalization deliberately leaves context/buffers until normal cleanup.
	GameFlow._finalize_run_stats(false)
	_begin(false)
	_expect(RunState.run_score == 0 and GameFlow._run_enemy_kills == 0, "Campaign after Practice resets encounter score and kills")
	RunState.add_score(1500, "Campaign control")
	RunState.set_wave_context(3, 0, 0, 3)
	GameFlow._run_elapsed_sec = 300.0
	GameFlow.record_enemy_kill(_combat_context(DRONE_ID))
	_expect(GameFlow._finalize_run_end(false), "Campaign after direct Practice finalization completes normally")
	_expect(GameFlow.get_meta_stat_value(GameFlow.META_STAT_KILLS) == 5 and GameFlow.get_meta_stat_value(GameFlow.META_STAT_KILLS, &"", "kills|enemy|" + String(DRONE_ID)) == 1, "Only the new Campaign kill contributes after Practice")
	_expect(int(GameFlow.get_boss_stats(StringName(BOSS.id))[GameFlow.BOSS_STAT_ENCOUNTERS]) == 3, "Practice boss encounters cannot leak into the following Campaign")
	_expect(GameFlow.high_score == 1500 and GameFlow.flux_anchors > BASE_ANCHORS, "A following Campaign can earn a legitimate score record and Flux Anchors")
	_expect(GameFlow.get_meta_stat_value(GameFlow.META_STAT_DAMAGE_DEALT) == 250, "Discarded Practice damage does not enter Campaign lifetime totals")

func _check_campaign_to_practice() -> void:
	_seed_baseline()
	_begin(false)
	_exercise_run()
	GameFlow._finalize_run_end(false)
	var before: Dictionary = _snapshot()
	var signals_before: Dictionary = _signals.duplicate()
	_expect(not GameFlow.get_last_flux_anchor_reward_breakdown().is_empty(), "Campaign exposes its earned reward before the next run")
	_begin(true)
	_expect(GameFlow.get_last_flux_anchor_reward_breakdown().is_empty(), "A fresh Practice clears the previous Campaign reward display")
	_exercise_run()
	GameFlow._finalize_run_end(true)
	_expect_unchanged(before, signals_before, "Practice following a rewarded Campaign")

func _check_campaign_control(boss_won: bool) -> void:
	_seed_baseline()
	_begin(false)
	_exercise_run(boss_won)
	_expect(GameFlow._finalize_run_end(not boss_won), "Campaign win/death finalizes normally")
	var pilot_stats: Dictionary = GameFlow.get_pilot_stats(_pilot.get_pilot_id())
	_expect(GameFlow.high_score == 12000 and GameFlow.flux_anchors > BASE_ANCHORS, "Campaign still earns global high score and Flux Anchors")
	_expect(int(pilot_stats[GameFlow.STAT_HIGHEST_SCORE]) == 12000 and int(pilot_stats[GameFlow.STAT_HIGHEST_WAVE_REACHED]) == 38 and int(pilot_stats[GameFlow.STAT_LONGEST_RUN_SECONDS]) == 600, "Campaign still records pilot score, waves and duration")
	_expect(int(pilot_stats[GameFlow.STAT_TOTAL_NANOBOTS_IN_RUN]) == 680 and int(pilot_stats[GameFlow.STAT_HIGHEST_NANOBOTS_IN_RUN]) == 600, "Campaign still records collected and peak nanobots")
	_expect(int(pilot_stats[GameFlow.STAT_DEATH_RUNS]) == (2 if boss_won else 3), "Only Campaign death increments the death-run record")
	_expect(GameFlow.get_meta_stat_value(GameFlow.META_STAT_KILLS) == (13 if boss_won else 12) and GameFlow.get_meta_stat_value(GameFlow.META_STAT_DAMAGE_DEALT) == 2250 and GameFlow.get_meta_stat_value(GameFlow.META_STAT_DAMAGE_TAKEN) == 250, "Campaign flushes its exact combat totals")
	var boss_stats: Dictionary = GameFlow.get_boss_stats(StringName(BOSS.id))
	_expect(int(boss_stats[GameFlow.BOSS_STAT_ENCOUNTERS]) == 4 and int(boss_stats[GameFlow.BOSS_STAT_DAMAGE_DEALT]) == 840, "Campaign still records boss encounters and damage")
	_expect(int(boss_stats[GameFlow.BOSS_STAT_KILLS]) == (2 if boss_won else 1) and int(boss_stats[GameFlow.BOSS_STAT_PLAYER_DEATHS]) == (1 if boss_won else 2), "Campaign records the correct boss outcome")
	_expect(GameFlow.is_pilot_unlocked(_locked_pilot) and GameFlow.is_ship_option_unlocked(_locked_ship) and GameFlow.is_weapon_option_unlocked(_locked_weapon), "Campaign still unlocks pilots, ships and starting weapons")
	_expect(GameFlow.get_meta_stat_value(GameFlow.META_STAT_KILLS, &"", "kills|enemy|" + String(DRONE_ID)) == 8, "Campaign kills still reveal an enemy in Information")
	_expect(int(_signals["anchors"]) > 0 and int(_signals["score"]) == 1 and int(_signals["stats"]) == 1 and int(_signals["unlock"]) == 1, "Campaign still emits progression updates")
	var persisted: Dictionary = _snapshot()
	GameFlow._load_user_data()
	_expect(_snapshot() == persisted, "Campaign progression survives a save reload")
	var signals_before: Dictionary = _signals.duplicate()
	_expect(not GameFlow._finalize_run_end(not boss_won) and _signals == signals_before and _snapshot() == persisted, "Duplicate Campaign completion grants no second reward")

func _reset_signals() -> void:
	for key: String in _signals:
		_signals[key] = 0

func _on_high_score(_new_score: int, _old_score: int) -> void:
	_signals["score"] = int(_signals["score"]) + 1

func _on_anchors(_new_value: int, _old_value: int) -> void:
	_signals["anchors"] = int(_signals["anchors"]) + 1

func _on_pilot_stats(_pilot_id: StringName, _stats: Dictionary) -> void:
	_signals["stats"] = int(_signals["stats"]) + 1

func _on_pilot_unlocked(_pilot_id: StringName) -> void:
	_signals["unlock"] = int(_signals["unlock"]) + 1

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("PRACTICE_PROGRESSION_CHECKS: " + description)
