# content/defs/pilot_roster.gd (Godot 4.5)
extends Resource
class_name PilotRoster

@export var pilots: Array[PilotDef] = []

func get_pilots() -> Array[PilotDef]:
	var resolved: Array[PilotDef] = []
	var seen_paths: Dictionary = {}
	var seen_ids: Dictionary = {}
	for pilot in pilots:
		if pilot == null:
			continue

		var path_key: String = pilot.resource_path
		if path_key != "" and seen_paths.has(path_key):
			continue

		var id_key: StringName = pilot.get_pilot_id()
		if id_key != &"" and seen_ids.has(id_key):
			if path_key != "":
				seen_paths[path_key] = true
			continue

		if pilot.is_selectable():
			resolved.append(pilot)
		if path_key != "":
			seen_paths[path_key] = true
		if id_key != &"":
			seen_ids[id_key] = true

	resolved.sort_custom(_sort_pilots)
	return resolved

func _sort_pilots(a: PilotDef, b: PilotDef) -> bool:
	if a.sort_order != b.sort_order:
		return a.sort_order < b.sort_order
	return a.get_display_name_or_default().nocasecmp_to(b.get_display_name_or_default()) < 0
