# content/defs/pilot_def.gd (Godot 4.5)
extends Resource
class_name PilotDef

@export var id: StringName = &""
@export var display_name: String = "Pilot"
@export_multiline var description: String = ""

@export var ship: ShipDef

