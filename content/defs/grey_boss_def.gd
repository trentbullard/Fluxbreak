extends EnemyBossDef
class_name GreyBossDef

@export_group("The Witness")
## Fraction of sampled velocity used by locked boss forecasts.
@export_range(0.0, 1.0, 0.05) var forecast_lead_fraction: float = 1.0
## Maximum forecast offset before a warning is committed.
@export_range(0.0, 2000.0, 5.0) var forecast_max_lead: float = 1200.0
## Half-length of the crossing lane, leaving its sides and vertical axis open.
@export_range(20.0, 400.0, 5.0) var corridor_half_length: float = 207.0
## Radius of a phase lane; a full warning precedes every release.
@export_range(5.0, 80.0, 1.0) var corridor_radius: float = 38.64
## Extra warning time between complementary members of one collapse.
@export_range(0.1, 1.0, 0.05) var echo_gap_sec: float = 0.25
## Arrival grace period before the first clearly marked relocation.
@export_range(0.1, 10.0, 0.1) var initial_delay_sec: float = 2.8
## Harmless warning at the destination before the Witness relocates.
@export_range(0.5, 6.0, 0.05) var displacement_windup_sec: float = 1.2
## Preferred destination distance from the player, inside starting weapon reach.
@export_range(170.0, 190.0, 1.0) var displacement_distance: float = 190.0
## Full time to leave the locked rupture sphere before damage resolves.
@export_range(1.6, 6.0, 0.05) var rupture_windup_sec: float = 1.8
## Radius of the fixed three-dimensional rupture sphere.
@export_range(5.0, 200.0, 1.0) var rupture_radius: float = 93.84
## Harmless acquisition warning before a bounded tether interval begins.
@export_range(0.8, 6.0, 0.05) var tether_windup_sec: float = 1.4
## Maximum active tether duration; the next major waits until it ends.
@export_range(0.5, 3.0, 0.1) var tether_duration_sec: float = 3.0
## Escape distance that breaks the tether immediately.
@export_range(100.0, 1000.0, 1.0) var tether_break_distance: float = 420.0
## Bounded movement multiplier while the tether remains attached.
@export_range(0.5, 1.0, 0.05) var tether_movement_factor: float = 0.7
## Radius of the locked tether acquisition sphere; leaving it avoids attachment.
@export_range(5.0, 120.0, 1.0) var tether_radius: float = 49.68
## Vulnerable rest after every major, unchanged in the second phase.
@export_range(0.5, 10.0, 0.1) var recovery_sec: float = 2.2
## Additional time before the next major.
@export_range(0.1, 10.0, 0.1) var cadence_sec: float = 1.4
## Remaining combined hull-plus-shield fraction that starts the second phase.
@export_range(0.05, 0.95, 0.01) var phase_hull_threshold: float = 0.55
## Phase two shortens only cadence, preserving full warnings and recovery.
@export_range(0.25, 1.0, 0.01) var phase_cadence_multiplier: float = 0.65
