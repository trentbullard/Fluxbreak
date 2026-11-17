extends Resource
class_name LogisticsDef

## Persistent purchase ID; also identifies the allowance granted at run start.
@export var id: String = ""
## Action name shown in the Logistics section.
@export var display_name: String = ""
## Explains the action and its permanent per-run allowance.
@export_multiline var description: String = ""
## Maximum purchased uses granted for each new run.
@export var max_tiers: int = 1
## Flux Anchors required for the first additional use per run.
@export var base_cost: int = 50
## Multiplies the price of each subsequent allowance tier.
@export var cost_multiplier: float = 2.0

func get_tier_cost(tier: int) -> int:
	if tier <= 0 or tier > max_tiers:
		return 0
	return maxi(int(round(float(maxi(base_cost, 0)) * pow(maxf(cost_multiplier, 0.0), float(tier - 1)))), 0)

## Positive purchases tiers; negative refunds them, matching the meta screen.
func get_total_cost_for_levels(from_tier: int, to_tier: int) -> int:
	var first: int = clampi(from_tier, 0, maxi(max_tiers, 0))
	var last: int = clampi(to_tier, 0, maxi(max_tiers, 0))
	var total: int = 0
	if last > first:
		for tier: int in range(first + 1, last + 1):
			total += get_tier_cost(tier)
	else:
		for tier: int in range(last + 1, first + 1):
			total -= get_tier_cost(tier)
	return total
