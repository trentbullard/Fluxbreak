extends Resource
class_name MercBehaviorDef

enum Mode { CORVETTE, FRIGATE, DESTROYER, CRUISER, CARRIER }

## Tactical role used by the shared Merc actor.
@export var mode: Mode = Mode.CORVETTE

@export_group("Movement")
## Desired inner combat range; Corvettes begin their burst inside this radius.
@export_range(1.0, 2000.0, 1.0) var approach_range: float = 220.0
## Outer combat range and the distance a retreating Corvette tries to reach.
@export_range(1.0, 2000.0, 1.0) var retreat_range: float = 340.0
## Preferred maximum movement speed, constrained by the hull's effective thrust.
@export_range(1.0, 500.0, 1.0) var max_speed: float = 160.0
## Velocity correction applied to steering before the effective thrust cap.
@export_range(0.1, 10.0, 0.1) var steering_response: float = 2.0
## Fraction of preferred speed used for lateral movement while in position.
@export_range(0.0, 1.0, 0.05) var orbit_strength: float = 0.25

@export_group("Weapon Cadence")
## Shots per Corvette attack; each shot still uses the shared weapon hit roll.
@export_range(1, 8, 1) var burst_shots: int = 3
## Delay between individual shots of a Corvette burst.
@export_range(0.05, 3.0, 0.05) var burst_interval_sec: float = 0.3
## Recovery after a burst, Frigate shot, or resolved Destroyer charge.
@export_range(0.1, 20.0, 0.1) var attack_cooldown_sec: float = 3.6
## Time spent pulling away after a Corvette has completed its burst.
@export_range(0.1, 10.0, 0.1) var retreat_duration_sec: float = 2.0

@export_group("Frigate Support")
## Offset maintained behind the escorted ally, away from the player.
@export_range(1.0, 500.0, 1.0) var escort_distance: float = 90.0
## Maximum distance to an ally receiving a shield pulse.
@export_range(1.0, 1000.0, 1.0) var shield_radius: float = 320.0
## Pulse interval; recipients share this cooldown across all Merc Frigates.
@export_range(0.5, 30.0, 0.1) var shield_pulse_interval_sec: float = 4.5
## Maximum shield points restored to one recipient by one pulse.
@export_range(0.0, 100.0, 1.0) var shield_restore_amount: float = 10.0
## Support cannot fill shields past this fraction of their effective capacity.
@export_range(0.0, 1.0, 0.05) var shield_restore_fraction: float = 0.65
## Maximum number of distinct allied recipients per pulse.
@export_range(1, 4, 1) var shield_max_targets: int = 2

@export_group("Destroyer Charge")
## Locked warning time before the corridor checks the player's current position.
@export_range(0.2, 8.0, 0.1) var charge_windup_sec: float = 1.5
## Half-width of the charged corridor; moving outside it avoids the shot.
@export_range(1.0, 200.0, 1.0) var charge_radius: float = 30.0

@export_group("Cruiser Broadside")
## Locked corridor countdown before each round of an alternating broadside.
@export_range(0.3, 8.0, 0.05) var broadside_windup_sec: float = 1.1
## Half-width of each marked broadside corridor.
@export_range(1.0, 100.0, 1.0) var broadside_radius: float = 24.0
## Committed rounds per broadside; every round receives its own warning.
@export_range(1, 6, 1) var broadside_shots: int = 3
## Quiet interval between the previous round resolving and the next warning.
@export_range(0.1, 3.0, 0.05) var broadside_interval_sec: float = 0.35
## Exposed turn after a broadside, during which weapons remain silent.
@export_range(0.3, 10.0, 0.1) var broadside_recovery_sec: float = 2.0

@export_group("Carrier Escort Wing")
## Ordinary Merc child hull launched through the encounter's real Spawner.
@export var escort_child_def: EnemyDef
## Interval before the next launch warning, including the first one.
@export_range(1.0, 40.0, 0.1) var escort_interval_sec: float = 9.0
## Visible launch countdown; killing the Carrier cancels it and its escorts.
@export_range(0.4, 8.0, 0.1) var escort_windup_sec: float = 1.4
## Requested escorts per launch, bounded by all remaining capacity limits.
@export_range(1, 6, 1) var escort_burst_count: int = 2
## Maximum living escorts belonging to one Carrier.
@export_range(1, 8, 1) var escort_alive_cap: int = 3
## Lifetime escort allowance; defeated escorts never refund this budget.
@export_range(1, 24, 1) var escort_total_cap: int = 6
## Maximum living summoned Merc escorts across all sources in the encounter.
@export_range(1, 24, 1) var escort_global_cap: int = 10
## Total encounter enemy ceiling respected by escort launches.
@export_range(1, 100, 1) var escort_enemy_cap: int = 50
## Distance from the owner at which escorts emerge.
@export_range(10.0, 300.0, 1.0) var escort_release_radius: float = 75.0
