extends MercBossDef
class_name MercFlagshipDef

@export_group("Vanguard Flagship")
## Remaining hull fraction that starts the escort-supported second phase.
@export_range(0.1, 0.95, 0.01) var phase_two_hull_threshold: float = 0.7
## Remaining hull fraction that starts the final broadside sequence.
@export_range(0.05, 0.9, 0.01) var phase_three_hull_threshold: float = 0.35
## Phase two changes time between attacks, leaving warnings and recovery intact.
@export_range(0.5, 1.0, 0.01) var phase_two_cadence_multiplier: float = 0.85
## Phase three changes time between attacks, leaving warnings and recovery intact.
@export_range(0.5, 1.0, 0.01) var phase_three_cadence_multiplier: float = 0.7
## Finite escorts requested once on arrival and once at each hull transition.
@export_range(0, 4, 1) var escorts_per_wing: int = 2
## Maximum number of this flagship's living escorts at one time.
@export_range(0, 6, 1) var escort_living_cap: int = 3
## Maximum escorts this flagship can ever create, shared across every phase.
@export_range(0, 12, 1) var escort_lifetime_cap: int = 6
## Seconds between bounded shield restorations for this flagship's escorts.
@export_range(2.0, 30.0, 0.5) var escort_shield_interval_sec: float = 12.0
## Shield restored by one support pulse; never exceeds an escort's maximum.
@export_range(0.0, 50.0, 1.0) var escort_shield_restore: float = 18.0
## Escorts outside this distance receive no support from the flagship.
@export_range(50.0, 900.0, 10.0) var escort_shield_radius: float = 480.0
