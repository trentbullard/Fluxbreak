extends EnemyBossDef
class_name BugBossDef

@export_group("Nestbreaker Matron")
## Arrival grace period before the first locked attack.
@export_range(0.1, 10.0, 0.1) var initial_delay_sec: float = 2.8
## Time to leave the fixed charge corridor before its damage resolves.
@export_range(0.5, 6.0, 0.05) var charge_windup_sec: float = 1.8
## Radius of the three-dimensional charge corridor.
@export_range(5.0, 300.0, 1.0) var charge_radius: float = 58.0
## Committed travel duration after the charge warning resolves.
@export_range(0.1, 3.0, 0.05) var charge_move_sec: float = 0.72
## Travel beyond the locked target position; the Matron cannot steer mid-charge.
@export_range(0.0, 400.0, 1.0) var charge_overshoot: float = 105.0
## Visible swelling time before the harmless brood release.
@export_range(0.5, 6.0, 0.05) var brood_windup_sec: float = 1.8
## Vulnerable rest after every attack, unchanged in phase two.
@export_range(0.1, 10.0, 0.1) var recovery_sec: float = 2.2
## Extra delay between recovery and the next attack.
@export_range(0.1, 10.0, 0.1) var cadence_sec: float = 1.4
## Actual remaining hull fraction that starts the second phase.
@export_range(0.05, 0.95, 0.01) var phase_hull_threshold: float = 0.55
## Phase two reduces only the cadence; warnings and recovery remain readable.
@export_range(0.25, 1.0, 0.01) var phase_cadence_multiplier: float = 0.65
## Spawned Sporeling definition. Summons inherit encounter scaling and grant no rewards.
@export var brood_child_def: EnemyDef
## Maximum living brood owned by this Matron.
@export_range(0, 16, 1) var brood_alive_cap: int = 8
## Maximum brood this Matron can release across the whole fight.
@export_range(0, 32, 1) var brood_total_cap: int = 16
## Requested brood per release before the hull threshold.
@export_range(0, 8, 1) var brood_release_count: int = 3
## Requested brood per release after the hull threshold.
@export_range(0, 8, 1) var phase_brood_release_count: int = 4
## Distance from the Matron at which her brood appears.
@export_range(20.0, 300.0, 1.0) var brood_spawn_radius: float = 85.0
