extends Resource
class_name StageDef

enum CompletionFlow {
	BOSS_GATEWAY,
	RUN_COMPLETE,
	ENDLESS,
}

@export_group("Identity")
@export var stage_id: StringName = &""
@export var display_name: String = "Stage"
@export_multiline var description: String = ""
@export var next_stage_id: StringName = &""

@export_group("Scene Prep")
@export var stage_scene: PackedScene
@export var boss_scene: PackedScene
@export var gateway_scene: PackedScene
@export var completion_flow: CompletionFlow = CompletionFlow.BOSS_GATEWAY

@export_group("Boss Encounter")
@export_range(1, 99, 1) var boss_wave_index: int = 30
@export var boss_faction: FactionDef
@export var boss_pool: Array[EnemyBossDef] = []

@export_group("Skybox")
@export var panorama_options: Array[Texture2D] = []

@export_group("Lighting")
@export_range(0.0, 8.0, 0.01) var background_energy_multiplier: float = 1.5
@export var ambient_light_color: Color = Color(0.0, 0.1804, 0.3705, 1.0)
@export_range(0.0, 16.0, 0.01) var ambient_light_energy: float = 6.0
@export_range(0.0, 1.0, 0.01) var ambient_light_sky_contribution: float = 0.15
@export var star_light_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.0, 8.0, 0.01) var star_light_energy: float = 2.0

@export_group("Fog / Glow")
@export var glow_enabled: bool = true
@export_range(0.0, 4.0, 0.01) var glow_intensity: float = 0.5
@export_range(0.0, 4.0, 0.01) var glow_strength: float = 0.4
@export_range(0.0, 1.0, 0.0001) var volumetric_fog_density: float = 0.01
@export var volumetric_fog_albedo: Color = Color(0.9547, 0.9547, 1.0, 1.0)
@export var volumetric_fog_emission: Color = Color(0.2478, 0.2478, 0.3492, 1.0)
@export_range(0.0, 4.0, 0.01) var volumetric_fog_emission_energy: float = 0.1

@export_group("Procedural Modifiers")
@export var guaranteed_modifiers: Array[StageModifierDef] = []
@export var bonus_pool: Array[StageModifierDef] = []
@export var debuff_pool: Array[StageModifierDef] = []
@export_range(0, 8, 1) var random_bonus_count: int = 0
@export_range(0, 8, 1) var random_debuff_count: int = 0

@export_group("Future Encounter Overrides")
@export var wave_cards: Array[WaveCard] = []
@export var poi_defs: Array[PoiDef] = []

func get_stage_id() -> StringName:
	if stage_id != &"":
		return stage_id
	if resource_path != "":
		return StringName(resource_path.get_file().get_basename())
	return &"stage"

func get_display_name_or_default() -> String:
	var trimmed: String = display_name.strip_edges()
	if trimmed != "":
		return trimmed
	var from_id: String = String(get_stage_id()).replace("_", " ").strip_edges()
	if from_id != "":
		return from_id.capitalize()
	return "Stage"

func get_panorama_options() -> Array[Texture2D]:
	var resolved: Array[Texture2D] = []
	var seen_paths: Dictionary = {}
	for entry in panorama_options:
		if entry == null:
			continue
		var path_key: String = entry.resource_path
		if path_key != "" and seen_paths.has(path_key):
			continue
		resolved.append(entry)
		if path_key != "":
			seen_paths[path_key] = true
	return resolved

func pick_random_panorama(rng: RandomNumberGenerator) -> Texture2D:
	var options: Array[Texture2D] = get_panorama_options()
	if options.is_empty():
		return null
	if rng == null:
		return options[0]
	var index: int = rng.randi_range(0, options.size() - 1)
	return options[index]

func get_guaranteed_modifiers() -> Array[StageModifierDef]:
	return _dedupe_modifiers(guaranteed_modifiers)

func get_bonus_pool() -> Array[StageModifierDef]:
	return _dedupe_modifiers(bonus_pool)

func get_debuff_pool() -> Array[StageModifierDef]:
	return _dedupe_modifiers(debuff_pool)

func get_wave_cards() -> Array[WaveCard]:
	var resolved: Array[WaveCard] = []
	var seen_paths: Dictionary = {}
	var seen_ids: Dictionary = {}
	for entry in wave_cards:
		if entry == null:
			continue
		var path_key: String = entry.resource_path
		if path_key != "" and seen_paths.has(path_key):
			continue
		var id_key: StringName = entry.get_card_id()
		if id_key != &"" and seen_ids.has(id_key):
			if path_key != "":
				seen_paths[path_key] = true
			continue
		resolved.append(entry)
		if path_key != "":
			seen_paths[path_key] = true
		if id_key != &"":
			seen_ids[id_key] = true
	return resolved

func should_spawn_boss_wave() -> bool:
	if completion_flow != CompletionFlow.BOSS_GATEWAY:
		return false
	return not get_boss_pool().is_empty()

func get_boss_pool() -> Array[EnemyBossDef]:
	var resolved: Array[EnemyBossDef] = []
	var seen_paths: Dictionary = {}
	var seen_ids: Dictionary = {}
	var wanted_faction_id: StringName = boss_faction.get_faction_id() if boss_faction != null else &""
	for entry in boss_pool:
		if entry == null:
			continue
		if wanted_faction_id != &"" and entry.get_faction_id() != wanted_faction_id:
			continue
		var path_key: String = entry.resource_path
		if path_key != "" and seen_paths.has(path_key):
			continue
		var id_key: String = entry.id.strip_edges()
		if id_key != "" and seen_ids.has(id_key):
			if path_key != "":
				seen_paths[path_key] = true
			continue
		resolved.append(entry)
		if path_key != "":
			seen_paths[path_key] = true
		if id_key != "":
			seen_ids[id_key] = true
	return resolved

func _dedupe_modifiers(source: Array[StageModifierDef]) -> Array[StageModifierDef]:
	var resolved: Array[StageModifierDef] = []
	var seen_paths: Dictionary = {}
	var seen_ids: Dictionary = {}
	for entry in source:
		if entry == null:
			continue
		var path_key: String = entry.resource_path
		if path_key != "" and seen_paths.has(path_key):
			continue
		var id_key: StringName = entry.get_modifier_id()
		if id_key != &"" and seen_ids.has(id_key):
			if path_key != "":
				seen_paths[path_key] = true
			continue
		resolved.append(entry)
		if path_key != "":
			seen_paths[path_key] = true
		if id_key != &"":
			seen_ids[id_key] = true
	return resolved
