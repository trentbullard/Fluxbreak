# content/defs/stat_modifier.gd (godot 4.5)
extends Resource
class_name StatModifier

const Stat = StatTypes.Stat
const Phase = StatTypes.Phase
const Op = StatTypes.Op
const DamageType = StatTypes.DamageTypes

@export var stat: Stat
@export var phase: Phase = Phase.ADD_MULT
@export var priority: int = 10             # tie-break inside phase (low first)
@export var op: Op = Op.ADD
@export var enabled: bool = true
@export var value: float = 0.0
@export var source_id: String = ""         # e.g. upgrade id for grouping
@export var applies_to_damage_types: Array[DamageType] = []
@export var applies_to_minions: bool = false
@export var applies_to_player: bool = true
