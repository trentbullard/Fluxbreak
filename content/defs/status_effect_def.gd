extends Resource
class_name StatusEffectDef

enum Kind { BURN, SLOW, ARMOR_SHRED, STUN, POISON }

@export var id: String = ""
@export var kind: Kind = Kind.BURN
@export var duration: float = 3.0
@export var magnitude: float = 1.0
@export var max_stacks: int = 1

# per-outcome proc chances (0..1)
@export var chance_on_hit: float = 0.0
@export var chance_on_graze: float = 0.0
@export var chance_on_crit: float = 0.0
