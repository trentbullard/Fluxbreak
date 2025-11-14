# content/defs/upgrade_def.gd (godot 4.5)
# an upgrade can have multiple stat modifiers
extends Resource
class_name Upgrade

@export var id: String
@export var display_name: String
@export var descripton: String
@export var icon: Texture2D

@export var modifiers: Array[StatModifier] = []
