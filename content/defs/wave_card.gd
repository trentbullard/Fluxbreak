# content/defs/wave_card.gd (godot 4.5)
extends Resource
class_name WaveCard

@export var faction_bias: String = ""           # "" = any
@export var role_bias: String = ""              # "" = any
@export var batch_size_min: int = 2
@export var batch_size_max: int = 4
@export var inter_batch_sec: float = 0.7
@export var enemy_first_bias: float = 0.65      # 0..1
