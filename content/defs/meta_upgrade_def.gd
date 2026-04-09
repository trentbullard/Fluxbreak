# content/defs/meta_upgrade_def.gd (Godot 4.5)
# Resource definition for a permanent meta progression upgrade.
# Each upgrade has multiple purchasable tiers costing Flux Anchors.
extends Resource
class_name MetaUpgradeDef

## Unique identifier used for save/load and lookup.
@export var id: String = ""
## Display name shown in the Upgrades panel.
@export var display_name: String = ""
## Short description of this upgrade's effect.
@export_multiline var description: String = ""
## Maximum number of tiers purchasable for this upgrade.
@export var max_tiers: int = 5
## Flux Anchor cost for the first tier.
@export var base_cost: int = 100
## Cost multiplier applied per tier (geometric scaling).
## Each successive tier costs base_cost * multiplier^(tier-1).
@export var cost_multiplier: float = 1.5

@export_group("Stat Modifiers")
## Stat modifiers applied per purchased tier.
## Each modifier's value represents the per-tier amount. At apply time the
## aggregator must scale by tier_count using whichever scaling contract applies:
##   ADD ops  → applied_value = modifier.value * tier_count
##   MULT ops → applied_value = 1.0 + (modifier.value - 1.0) * tier_count
##              (additive-stacking percentages, NOT compound multiplication)
## Set StatModifier.source_id = this upgrade's id to enable clean removal.
@export var modifiers_per_tier: Array[StatModifier] = []


## Returns the Flux Anchor cost to purchase a specific tier (1-indexed).
func get_tier_cost(tier: int) -> int:
	if tier <= 0:
		return 0
	return int(round(float(base_cost) * pow(cost_multiplier, float(tier - 1))))


## Returns the net Flux Anchor cost to move from from_tier to to_tier.
## Positive = total cost to buy those tiers; negative = total refund when selling.
func get_total_cost_for_levels(from_tier: int, to_tier: int) -> int:
	if from_tier == to_tier:
		return 0
	var total: int = 0
	if to_tier > from_tier:
		for t: int in range(from_tier + 1, to_tier + 1):
			total += get_tier_cost(t)
	else:
		for t: int in range(to_tier + 1, from_tier + 1):
			total -= get_tier_cost(t)
	return total
