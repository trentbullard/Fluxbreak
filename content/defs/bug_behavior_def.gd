extends Resource
class_name BugBehaviorDef

enum Mode { SPORELING, CARAPACE, BROODMOTHER, DEVOURER, HIVE_QUEEN }

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
## Sporeling orbit-axis change period; larger Bugs keep committed locomotion.
@export_range(0.25, 10.0, 0.05) var jink_interval_sec: float = 1.7
## Sporeling orbit-plane tilt, including throughout its locked spore warning.
@export_range(0.0, 1.0, 0.05) var jink_strength: float = 0.85

@export_group("Committed Attack")
## Minimum time between the previous attack resolving and another windup.
@export_range(0.1, 20.0, 0.1) var attack_cooldown_sec: float = 2.2
## Contraction time before testing the player's position in the locked volume.
@export_range(0.2, 8.0, 0.05) var attack_windup_sec: float = 0.75
## Radius of the locked sphere or half-width of the Carapace corridor.
@export_range(1.0, 200.0, 1.0) var attack_radius: float = 26.0
## Weapon recovery after a strike; Sporelings keep strafing during this window.
@export_range(0.1, 8.0, 0.05) var attack_recovery_sec: float = 0.55

@export_group("Brood Release")
## Time between Broodmother releases; the first release waits this long too.
@export_range(1.0, 40.0, 0.1) var brood_interval_sec: float = 8.0
## Visible gestation countdown before children are released.
@export_range(0.3, 8.0, 0.1) var brood_windup_sec: float = 1.4
## Children per completed release; repeated releases have no minion cap.
@export_range(1, 6, 1) var brood_burst_count: int = 2
## Radius around the parent at which brood children emerge.
@export_range(10.0, 300.0, 1.0) var brood_release_radius: float = 70.0

@export_group("Devourer Charge")
## Speed of the committed, non-contact charge after its corridor resolves.
@export_range(50.0, 500.0, 1.0) var charge_speed: float = 220.0
## Distance beyond the snapshotted target included in the visible corridor.
@export_range(0.0, 300.0, 1.0) var charge_overshoot_distance: float = 110.0
## Hard upper limit on committed travel before an exposed recovery.
@export_range(0.3, 6.0, 0.1) var charge_travel_sec: float = 2.6

@export_group("Hive Spore Zones")
## Full visible warning before each pulse in the fixed spore sphere.
@export_range(0.5, 5.0, 0.1) var zone_windup_sec: float = 1.6
## Radius of the static, three-dimensional spore warning volume.
@export_range(10.0, 150.0, 1.0) var zone_radius: float = 65.0
## Finite pulses in one zone; each pulse receives a fresh full warning.
@export_range(1, 2, 1) var zone_pulse_count: int = 1
## Quiet interval between zone releases, in addition to brood turns.
@export_range(1.0, 30.0, 0.1) var zone_interval_sec: float = 6.0
## Lifetime zone budget; expiration does not refund a spent zone.
@export_range(1, 12, 1) var zone_total_cap: int = 4
## Shared active zone ceiling across regular Bugs and their boss.
@export_range(1, 8, 1) var zone_global_cap: int = 8
