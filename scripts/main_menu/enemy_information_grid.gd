extends InformationIconGrid
class_name EnemyInformationGrid

const COLOR_KILLED: Color = COLOR_KNOWN

## Authored reference order, with one canonical definition per saved enemy ID.
## Practice variants and summons reuse these identities rather than adding slots.
const ENEMY_DEFINITIONS: Array[EnemyDef] = [
	preload("res://content/data/enemies/machine_drone_mk1.tres"),
	preload("res://content/data/enemies/machine_sentinel_mk1.tres"),
	preload("res://content/data/enemies/machine_reaper_mk1.tres"),
	preload("res://content/data/enemies/machine_warden_mk1.tres"),
	preload("res://content/data/enemies/machine_coremind_mk1.tres"),
	preload("res://content/data/enemies/machine_boss_1_mk1.tres"),
	preload("res://content/data/enemies/merc_corvette_mk1.tres"),
	preload("res://content/data/enemies/merc_frigate_mk1.tres"),
	preload("res://content/data/enemies/merc_destroyer_mk1.tres"),
	preload("res://content/data/enemies/merc_cruiser_mk1.tres"),
	preload("res://content/data/enemies/merc_carrier_mk1.tres"),
	preload("res://content/data/enemies/merc_contract_enforcer_mk1.tres"),
	preload("res://content/data/enemies/merc_vanguard_flagship_mk1.tres"),
	preload("res://content/data/enemies/bug_sporeling_mk1.tres"),
	preload("res://content/data/enemies/bug_carapace_mk1.tres"),
	preload("res://content/data/enemies/bug_broodmother_mk1.tres"),
	preload("res://content/data/enemies/bug_devourer_mk1.tres"),
	preload("res://content/data/enemies/bug_hive_queen_mk1.tres"),
	preload("res://content/data/enemies/bug_nestbreaker_matron_mk1.tres"),
	preload("res://content/data/enemies/bug_first_queen_mk1.tres"),
	preload("res://content/data/enemies/grey_probe_mk1.tres"),
	preload("res://content/data/enemies/grey_seeker_mk1.tres"),
	preload("res://content/data/enemies/grey_vessel_mk1.tres"),
	preload("res://content/data/enemies/grey_harbinger_mk1.tres"),
	preload("res://content/data/enemies/grey_mothership_mk1.tres"),
	preload("res://content/data/enemies/grey_witness_mk1.tres"),
	preload("res://content/data/enemies/grey_veiled_mind_mk1.tres"),
]

static func get_enemy_definitions() -> Array[EnemyDef]:
	return ENEMY_DEFINITIONS.duplicate()

## Read the existing saved lifetime totals when opening, never during gameplay.
func refresh() -> void:
	if _entry_buttons.is_empty():
		_build_entries()
	for index: int in ENEMY_DEFINITIONS.size():
		var definition: EnemyDef = ENEMY_DEFINITIONS[index]
		var button: Button = _entry_buttons[index]
		var key: String = "kills|enemy|" + definition.id
		var killed: bool = GameFlow.get_meta_stat_value(GameFlow.META_STAT_KILLS, &"", key) > 0
		button.set_meta(&"killed", killed)
		_set_icon_state(button, killed, definition.get_display_name_or_default(), "Unknown enemy")
	_reset_scroll()

func _build_entries() -> void:
	var previous_faction: StringName = &""
	for definition: EnemyDef in ENEMY_DEFINITIONS:
		var faction: StringName = definition.get_faction_id()
		if _section_grid == null or faction != previous_faction:
			_begin_section(definition.get_faction_display_name())
			previous_faction = faction
		var button: Button = _append_icon(StringName(definition.id))
		button.set_meta(&"enemy_id", definition.id)
