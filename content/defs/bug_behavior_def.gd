extends Resource
class_name BugBehaviorDef

enum Mode { SPORELING, CARAPACE, BROODMOTHER }

## Biological role used by the shared Bug actor.
@export var mode: Mode = Mode.SPORELING

@export_group("Movement")
## Pursuers attack inside this range; Broodmothers retreat when closer.
@export_range(1.0, 2000.0, 1.0) var approach_range: float = 105.0
## Outer edge of the Broodmother's preferred standoff band.
@export_range(1.0, 2000.0, 1.0) var retreat_range: float = 160.0
## Desired maximum speed, subject to effective hull thrust.
@export_range(1.0, 500.0, 1.0) var max_speed: float = 190.0
## Velocity correction applied before the effective thrust limit.
@export_range(0.1, 10.0, 0.1) var steering_response: float = 2.4
## Fraction of preferred speed spent circling within the combat band.
@export_range(0.0, 1.0, 0.05) var orbit_strength: float = 0.15

@export_group("Committed Attack")
## Minimum time between the previous attack resolving and another windup.
@export_range(0.1, 20.0, 0.1) var attack_cooldown_sec: float = 2.2
## Contraction time before testing the player's position in the locked volume.
@export_range(0.2, 8.0, 0.05) var attack_windup_sec: float = 0.75
## Radius of the locked sphere or half-width of the Carapace corridor.
@export_range(1.0, 200.0, 1.0) var attack_radius: float = 26.0
## Vulnerable pause after the strike, during which pursuit is suspended.
@export_range(0.1, 8.0, 0.05) var attack_recovery_sec: float = 0.55

@export_group("Brood Release")
## Time between Broodmother releases; the first release waits this long too.
@export_range(1.0, 40.0, 0.1) var brood_interval_sec: float = 8.0
## Visible gestation countdown before children are released.
@export_range(0.3, 8.0, 0.1) var brood_windup_sec: float = 1.4
## Requested children per release, clamped by every remaining cap.
@export_range(1, 6, 1) var brood_burst_count: int = 2
## Maximum living children owned by one Broodmother.
@export_range(1, 8, 1) var brood_alive_cap: int = 4
## Lifetime child limit; defeated children do not replenish this budget.
@export_range(1, 24, 1) var brood_total_cap: int = 8
## Maximum living summoned Bugs across all parents in the encounter.
@export_range(1, 24, 1) var brood_global_cap: int = 12
## Encounter enemy ceiling that brood releases may not exceed.
@export_range(1, 100, 1) var brood_enemy_cap: int = 50
## Radius around the parent at which brood children emerge.
@export_range(10.0, 300.0, 1.0) var brood_release_radius: float = 70.0
