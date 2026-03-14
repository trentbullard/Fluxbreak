# content/defs/upgrade_def.gd (godot 4.5)
# an upgrade can have multiple stat modifiers
extends Resource
class_name Upgrade

@export var id: String
@export var display_name: String
@export_multiline var descripton: String = ""
@export var icon: Texture2D
@export var cost: int = 1000
@export var tags: Array[String] = []
@export var tier: int = 1
@export var family_id: String = ""

@export var modifiers: Array[StatModifier] = []
