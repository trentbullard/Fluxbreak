extends EnemyBossDef
class_name MercBossDef

@export_group("Contract Enforcer")
## Arrival grace period before the first locked attack.
@export_range(0.1, 10.0, 0.1) var initial_delay_sec: float = 2.8
## Seconds to leave the corridor before the broadside resolves.
@export_range(0.25, 6.0, 0.05) var broadside_windup_sec: float = 1.8
## Seconds to leave the locked spherical salvo area.
@export_range(0.25, 6.0, 0.05) var salvo_windup_sec: float = 1.5
## Radius of the fixed three-dimensional broadside corridor.
@export_range(5.0, 300.0, 1.0) var broadside_radius: float = 65.0
## Radius of the fixed three-dimensional salvo sphere.
@export_range(5.0, 300.0, 1.0) var salvo_radius: float = 85.0
## Vulnerable recovery after every resolved attack, in seconds.
@export_range(0.1, 10.0, 0.1) var recovery_sec: float = 2.0
## Additional delay between recovery and the next attack.
@export_range(0.1, 10.0, 0.1) var cadence_sec: float = 1.5
## Remaining hull fraction that starts the second phase.
@export_range(0.05, 0.95, 0.01) var phase_hull_threshold: float = 0.55
## Multiplier on the cadence delay in the second phase; windups remain readable.
@export_range(0.25, 1.0, 0.01) var phase_cadence_multiplier: float = 0.72
## Optional single escort; it is never replaced after being killed.
@export var escort_def: EnemyDef
## Escort distance to the boss's side when it arrives.
@export_range(50.0, 600.0, 1.0) var escort_offset: float = 180.0
