extends BugBossDef
class_name BugQueenDef

@export_group("The First Queen")
## Remaining hull fraction that adds the committed Devourer charge.
@export_range(0.1, 0.95, 0.01) var second_phase_hull_threshold: float = 0.70
## Remaining hull fraction that begins the final familiar attack sequence.
@export_range(0.05, 0.9, 0.01) var final_phase_hull_threshold: float = 0.35
## Final phase changes only the quiet cadence; warnings and recovery stay intact.
@export_range(0.25, 1.0, 0.01) var final_phase_cadence_multiplier: float = 0.72
## Full warning before each pulse in the Queen's fixed spore sphere.
@export_range(0.5, 6.0, 0.05) var spore_windup_sec: float = 1.8
## Radius of the static three-dimensional spore warning and damage volume.
@export_range(5.0, 300.0, 1.0) var spore_radius: float = 95.0
## Finite pulses at the same locked position, each with its own full warning.
@export_range(1, 2, 1) var spore_pulse_count: int = 2
