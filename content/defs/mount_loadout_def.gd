# content/defs/mount_loadout_def
extends Resource
class_name MountLoadoutDef

@export var mount_id: String = ""   # e.g. "fore_left", "dorsal_1"
@export var weapon: WeaponDef
@export var team_id: int = 1
