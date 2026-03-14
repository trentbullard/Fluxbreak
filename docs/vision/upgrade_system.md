# Upgrade System

This document describes the intended final-state behavior of run-time scaling, build identity, and upgrade-driven combat expression.

Upgrades define most of the player's build identity during a run.

The goal is not to force a single correct build, but to create shifting incentives based on the interaction between:

- pilot
- ship
- faction
- system modifiers
- available upgrade rolls

### Build Philosophy

No starting condition should hard-lock a build path.

Instead, starting conditions should act as soft mitigators that make certain paths less efficient, less natural, or more situational.

Examples:

- a system-wide EM field reducing drone command reliability
- faction armor reducing effectiveness of certain damage types
- a pilot naturally weaker with specific weapon classes
- environmental modifiers weakening sensor-driven builds

The player should still be able to force unusual builds if willing to accept tradeoffs.

### Upgrade Scope And Delivery

Upgrade scope should be explicit.

An upgrade may affect:

- the player
- minions
- both

The run's acquired upgrade state should remain the source of truth, but combat subsystems should consume filtered local projections of that state rather than re-implementing scope rules in behavior code.

Future implementations should prefer:

- centralized scope filtering
- local effective-stat caches for each consumer
- extending stat projection layers when new consumers appear

Future implementations should avoid:

- hard-coded upgrade exceptions inside combat behaviors
- hidden minion-only bonuses that are difficult to reason about
- parallel upgrade ownership models that drift out of sync

### Upgrade Categories

Upgradeable systems should include nearly every variable affecting combat performance and run efficiency.

The categories below are intended to cover the current stat model as well as likely future extensions.
They should be treated as a broad design map, not a demand that every upgrade family exist at all times.

### Mobility

- acceleration
- forward max velocity
- reverse max velocity
- turn responsiveness
- angular rate by axis
- angular acceleration by axis
- boost efficiency
- drift control
- drag / handling stability

### Weapons And Fire Control

- raw damage range
- fire rate
- base accuracy
- range
- range falloff
- critical chance
- critical effect
- graze behavior
- penetration
- weapon-system accuracy bonuses
- anti-shield effectiveness
- anti-hull effectiveness

Weapon scaling should stay legible in combat and should not collapse target-priority gameplay into invisible background damage.

### Damage-Type Specialization

- kinetic
- laser
- plasma
- explosive
- rail
- pulse

Damage-type specialization may be represented through dedicated damage-type stats, through status / weapon families, or through other future systems as the combat model expands.

### Status And Effect Warfare

- applied status duration
- applied status tick rate
- applied status damage
- status damage crit chance
- status damage crit bonus
- resistance to sustained hostile effects
- reduction of hostile effect magnitude

### Projectile Shaping

- projectile size
- projectile speed
- projectile lifetime
- projectile spread behavior

### Drone / Minion Systems

- minion damage
- minion charge capacity
- minion recharge rate
- minion discharge rate
- minion count
- minion radio-range / command range
- minion AI responsiveness

Minion scaling should preserve readability and tactical intent.

Improvements should bias toward:

- command reach
- uptime
- formation quality
- responsiveness
- role clarity

before raw hidden damage inflation.

Minions should inherit the build's identity without becoming opaque parallel actors that bypass target-priority play, movement tradeoffs, or combat readability.

### Defensive Systems

- shield maximum
- shield recharge
- shield delay reduction
- hull maximum
- evasion
- damage taken reduction / amplification
- critical hit resistance
- reflect / retaliation effects
- hull repair effectiveness
- repair cost reduction

### Utility Systems

- pickup range
- nanobot efficiency
- score gain
- sensor range
- target acquisition
- objective interaction speed

### Ability And Area Control

- cooldown efficiency
- ship-centered area effects
- remote area effects

### Energy And Power Management

- energy regeneration
- max energy
- system efficiency
- overheat threshold
- heat dissipation

### Pilot Attribute Reinforcement

- G-load tolerance
- G-load hard limit
- perception influence
- charisma-linked bonuses
- ingenuity-linked bonuses
- pilot-specific forward-load mobility shaping

### Resource Scaling

- nanobot gain
- drop amplification
- upgrade efficiency

### Upgrade Availability Philosophy

Upgrade offerings should always contain partial randomness.

The player should not reliably receive every desired upgrade in every run.

This creates:

- adaptation pressure
- build improvisation
- meaningful reroll decisions

### Upgrade POIs

Each upgrade point of interest offers only a limited set of upgrades.

Because POI offerings are constrained:

- some upgrades may appear late
- some upgrades may rarely appear
- some desired synergies may never fully assemble

This variability is intentional.

POIs should act as directional nudges rather than absolute gates.

Their role is to bias the run toward certain families of decisions, not to eliminate improvisation.

### Luck Mitigation

Players should have limited tools to shape upgrade outcomes.

Examples may include:

- **Refresh** - reroll available upgrades
- **Banish** - permanently remove specific upgrade choices from the current run pool
- other light-touch pool-shaping tools that preserve uncertainty

These mechanics should allow players to influence luck without eliminating uncertainty.

### Design Principle

A strong run should feel partially built and partially discovered.

The player should often feel:

- forced to pivot
- rewarded for recognizing unexpected synergies
- punished for chasing impossible perfection too long
