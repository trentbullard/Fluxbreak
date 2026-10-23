extends Resource
class_name SectorRouteDef

enum MarkerKind { DEFAULT, SALVAGE, ASSAULT }

## Stable identity of this choice within the current stage's gateway routes.
@export var route_id: StringName = &""
## Short route name shown by the gateway marker and destination briefing.
@export var display_name: String = "Sector Route"
## Description of the next sector's battlefield and purpose.
@export_multiline var description: String = ""
## Concrete drawbacks and encounter pressure disclosed before committing.
@export_multiline var threat_summary: String = ""
## Concrete benefits and available opportunities disclosed before committing.
@export_multiline var reward_summary: String = ""
## Distinct gateway silhouette used in addition to its marker color.
@export var marker_kind: MarkerKind = MarkerKind.DEFAULT
## Accent tint for this route's gateway marker and briefing.
@export var marker_color: Color = Color(0.35, 0.7, 1.0, 1.0)
## Independent next-stage definition activated only after an explicit choice.
@export var destination_stage: StageDef

func get_route_id() -> StringName:
	if route_id != &"":
		return route_id
	if resource_path != "":
		return StringName(resource_path.get_file().get_basename())
	return get_destination_id()

func get_display_name() -> String:
	var trimmed: String = display_name.strip_edges()
	if not trimmed.is_empty():
		return trimmed
	var identity: String = String(get_route_id()).replace("_", " ").strip_edges()
	return identity.capitalize() if not identity.is_empty() else "Sector Route"

func get_destination_id() -> StringName:
	return destination_stage.get_stage_id() if destination_stage != null else &""
