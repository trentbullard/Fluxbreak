extends EnemyDef
class_name BugEnemyDef

## Movement, attack cadence, and finite brood rules for this organism.
@export var behavior: BugBehaviorDef
## Child definition released by an unsummoned Broodmother; normally Sporelings.
@export var brood_child_def: EnemyDef
