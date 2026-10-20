extends Resource
class_name GreyBehaviorDef

enum Mode { PROBE, SEEKER, VESSEL }

## Psionic role used by the shared Grey actor.
@export var mode: Mode = Mode.PROBE

@export_group("Movement")
## Inner edge of the preferred standoff band.
@export_range(1.0, 2000.0, 1.0) var approach_range: float = 240.0
## Outer edge of the preferred standoff band.
@export_range(1.0, 2000.0, 1.0) var retreat_range: float = 340.0
## Desired maximum speed, subject to the effective thrust limit.
@export_range(1.0, 500.0, 1.0) var max_speed: float = 140.0
## Velocity correction applied before the effective thrust limit.
@export_range(0.1, 10.0, 0.1) var steering_response: float = 2.2
## Fraction of preferred speed spent drifting sideways in the combat band.
@export_range(0.0, 1.0, 0.05) var orbit_strength: float = 0.4

@export_group("Psionic Pulse")
## Minimum time between a resolved action and another ordinary windup.
@export_range(0.1, 20.0, 0.1) var attack_cooldown_sec: float = 3.4
## Visible delay before the player's position is tested in the locked sphere.
@export_range(0.3, 8.0, 0.05) var attack_windup_sec: float = 1.2
## Radius of the pulse's locked danger volume.
@export_range(1.0, 200.0, 1.0) var attack_radius: float = 34.0
## Exposed pause after the pulse or completed tether.
@export_range(0.1, 8.0, 0.05) var attack_recovery_sec: float = 0.6

@export_group("Seeker Displacement")
## Time between Seeker displacements after the previous one completes.
@export_range(1.0, 30.0, 0.1) var displacement_interval_sec: float = 7.5
## Time for which both ends of the damage-free displacement remain visible.
@export_range(0.4, 6.0, 0.05) var displacement_windup_sec: float = 1.2
## Maximum distance moved by a single displacement.
@export_range(30.0, 700.0, 1.0) var displacement_distance: float = 230.0
## Requested minimum distance from the player at the locked destination.
@export_range(50.0, 1000.0, 1.0) var displacement_min_player_distance: float = 190.0

@export_group("Vessel Tether")
## Dodge window before the tether can attach.
@export_range(0.4, 6.0, 0.05) var tether_windup_sec: float = 1.5
## Maximum duration of a successfully attached tether.
@export_range(0.2, 3.0, 0.1) var tether_duration_sec: float = 2.4
## Movement multiplier while attached; sources never multiply their slows.
@export_range(0.65, 1.0, 0.05) var tether_slow_multiplier: float = 0.7
## Distance from the Vessel that immediately breaks the attached tether.
@export_range(100.0, 600.0, 1.0) var tether_break_distance: float = 420.0
## Radius of the locked tether warning around the player's initial position.
@export_range(1.0, 200.0, 1.0) var tether_radius: float = 38.0
