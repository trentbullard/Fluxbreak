# Wave System

This document describes the intended final-state behavior of run pressure, enemy composition, and escalation pacing.

Wave pressure is procedurally generated and should feel authored through budget logic, faction grammar, and pacing rules rather than fully random composition.

A run should usually have a dominant hostile identity, and wave generation should strongly favor that identity's combat roles, pressure tendencies, and escalation style while allowing controlled deviations to avoid excessive predictability.

The wave system should create the feeling that the player is fighting an evolving hostile force rather than isolated enemy packs.

In practical terms, this should increasingly come from a small encounter deck rather than a single scalar buyer.
Wave cards should define role bias, budget splits, pacing cadence, and objective pressure so procedural waves can still feel authored.

### Core Intent

- Early waves should feel readable and relatively stable across pilot, ship, faction, and system combinations.
- The first minute or two should establish rhythm rather than chaos.
- Difficulty should rise non-linearly rather than through flat linear increases.
- The system should bias toward implementations that are easy to tune, easy to reason about, and capable of supporting authored escalation later.

### Scaling Inputs

Wave generation should be driven first by a clear pressure model that is easy to tune and understand.

Core inputs are likely to include:

- elapsed run time
- current wave / phase
- player offensive pressure
- faction pressure rules
- battlefield / system modifiers

Secondary adaptive hooks may later include things like survivability state, enemy survival rate, economy velocity, or kill-speed signals, but the system should not depend on opaque overreaction to player behavior.

The goal is to make escalation feel responsive and authored without feeling arbitrary or obviously rubber-banded.

Performance adaptation should stay bounded.
Time, wave index, and stage identity should remain the primary macro difficulty drivers, while performance only nudges density, reinforcements, and composition inside controlled limits.

### Scaling Dimensions

Difficulty should increase through multiple overlapping layers:

- enemy count
- enemy durability
- enemy offensive output
- enemy movement pressure
- enemy role composition
- affix frequency
- elite probability
- support density
- disruption density

This prevents scaling from becoming only an HP inflation problem.

### Composition Philosophy

Threat should increasingly come from composition rather than raw enemy volume.

Examples:

- durable units shielding fragile support targets
- suppressors protecting artillery
- scouts extending pressure for heavy units
- elite variants embedded inside otherwise ordinary waves

As the run progresses, players should be forced to evaluate:

- which enemies matter most
- which targets must die immediately
- when repositioning is worth lost pressure
- when objectives outweigh kills

Wave assembly should therefore favor systems that can express:

- role mixtures
- pressure packages
- support relationships
- curated exceptions
- downtime salvage windows or bait objectives between spikes
- anti-repetition guards that preserve faction identity without exact looped waves

It should not be overly locked to simplistic "buy the biggest affordable unit repeatedly" logic in the final form.

### Faction Bias

Faction identity should strongly influence wave logic, but not require one rigid implementation strategy.

In practice, this can be expressed through weighted roles, budget partitioning, special rules, encounter templates, affix pools, scripted exceptions, or other tunable systems.

Occasional off-pattern moments are acceptable if they preserve readability and do not weaken faction identity.

### Affix and Elite Pressure

Elite enemies should not simply be stronger versions of baseline units.

Elite pressure should alter tactical decisions through:

- affixes
- role reinforcement
- unusual survivability
- movement disruption
- resource denial

Affix emergence should feel increasingly consequential as waves deepen.

### Standard / Story Mode Scaling

In standard or narrative-complete runs, wave pressure should leave room for strong builds to stabilize, spike, and occasionally recover.

This allows:

- successful synergy discovery
- meaningful power spikes
- recoverable mistakes
- satisfying boss preparation

A strong build should feel capable of overcoming late pressure if the player makes smart decisions, but it should not become trivialized by low-risk stat accumulation.

### Endless Mode Scaling

In endless mode, wave pressure should eventually scale faster than any realistic player build can sustain indefinitely.

The player should eventually lose no matter how strong the build becomes.

Endless mode success is measured by:

- duration survived
- efficiency under pressure
- build optimization
- positioning quality
- late-stage decision discipline

The best endless runs should feel like delaying inevitability rather than reaching immortality.

### Design Principle

Every second of the run should matter.

The player should constantly feel subtle pressure to evaluate:

- upgrade choices
- movement
- resource pathing
- target priority
- whether to commit or disengage
