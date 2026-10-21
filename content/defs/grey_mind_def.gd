extends GreyBossDef
class_name GreyMindDef

@export_group("The Veiled Mind")
## Actual remaining hull fraction that adds marked harmless relocations.
@export_range(0.1, 0.95, 0.01) var phase_two_hull_threshold: float = 0.70
## Actual remaining hull fraction that alternates tether and rupture pressure.
@export_range(0.05, 0.9, 0.01) var phase_three_hull_threshold: float = 0.35
## Phase two changes only quiet cadence, keeping all warnings and recovery intact.
@export_range(0.25, 1.0, 0.01) var phase_two_cadence_multiplier: float = 0.85
## Final phase changes only quiet cadence, keeping all warnings and recovery intact.
@export_range(0.25, 1.0, 0.01) var phase_three_cadence_multiplier: float = 0.65
