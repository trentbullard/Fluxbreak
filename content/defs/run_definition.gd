extends Resource
class_name RunDefinition

enum RunMode {
	STORY,
	PRACTICE,
	ENDLESS,
}

@export_group("Identity")
@export var run_id: StringName = &""
@export var display_name: String = "Run"
@export_multiline var description: String = ""
@export var run_mode: RunMode = RunMode.STORY

@export_group("Progression")
@export var stages: Array[StageDef] = []
@export var loop_last_stage: bool = false

func get_run_id() -> StringName:
	if run_id != &"":
		return run_id
	if resource_path != "":
		return StringName(resource_path.get_file().get_basename())
	return &"run"

func get_display_name_or_default() -> String:
	var trimmed: String = display_name.strip_edges()
	if trimmed != "":
		return trimmed
	var from_id: String = String(get_run_id()).replace("_", " ").strip_edges()
	if from_id != "":
		return from_id.capitalize()
	return "Run"

func get_stages() -> Array[StageDef]:
	var resolved: Array[StageDef] = []
	var seen_paths: Dictionary = {}
	var seen_ids: Dictionary = {}
	for entry in stages:
		if entry == null:
			continue
		var path_key: String = entry.resource_path
		if path_key != "" and seen_paths.has(path_key):
			continue
		var id_key: StringName = entry.get_stage_id()
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

func get_stage_count() -> int:
	return get_stages().size()

func get_stage(stage_index: int) -> StageDef:
	var resolved: Array[StageDef] = get_stages()
	if stage_index < 0 or stage_index >= resolved.size():
		return null
	return resolved[stage_index]

func find_stage_index_by_id(stage_id: StringName) -> int:
	if stage_id == &"":
		return -1
	var resolved: Array[StageDef] = get_stages()
	for i in resolved.size():
		var stage: StageDef = resolved[i]
		if stage != null and stage.get_stage_id() == stage_id:
			return i
	return -1
