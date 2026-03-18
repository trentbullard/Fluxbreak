extends Resource
class_name UpgradeOfferMemoryDef

@export_group("Curve")
@export var start_wave: int = 2
@export var per_wave_linear: float = 0.06
@export var per_wave_quadratic: float = 0.004
@export var intensity_cap: float = 1.5

@export_group("Family Weighting")
@export var owned_family_base_bonus: float = 1.0
@export var owned_family_count_bonus: float = 0.35
@export_range(0.0, 1.0, 0.01) var purchased_family_share_cap: float = 0.70
@export_range(0.0, 1.0, 0.01) var non_purchased_family_share_floor: float = 0.30
@export var same_family_repeat_bonus: float = 0.15
@export var same_family_next_tier_bonus: float = 0.30
