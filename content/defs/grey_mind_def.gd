extends GreyBossDef
class_name GreyMindDef

@export_group("The Veiled Mind")
## Remaining combined hull-plus-shield fraction that adds paired collapse patterns.
@export_range(0.1, 0.95, 0.01) var phase_two_hull_threshold: float = 0.70
## Remaining combined hull-plus-shield fraction that adds three-part collapses.
@export_range(0.05, 0.9, 0.01) var phase_three_hull_threshold: float = 0.35
## Quiet cadence reduction for paired collapses; full warnings/recovery remain.
@export_range(0.25, 1.0, 0.01) var phase_two_cadence_multiplier: float = 0.85
## Quiet cadence reduction for three-part collapses; full warnings/recovery remain.
@export_range(0.25, 1.0, 0.01) var phase_three_cadence_multiplier: float = 0.65
