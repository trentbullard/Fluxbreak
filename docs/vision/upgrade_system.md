# Upgrade System

This document describes the intended final-state behavior of run-time scaling, build identity, and upgrade-driven combat expression.

Upgrades define most of the player's build identity during a run.

Implementation status and priorities live in the [current roadmap](../plans/next_gameplay_milestones.md). The categories in this document include future ideas; their presence does not mean that the corresponding upgrades or mechanics already exist.

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

Ammo types, their associated upgrades and player/enemy resistance interactions remain planned expansion work. Begin with a readable set of interactions that changes build decisions, and tune it through playtesting. No complete ammo roster or resistance matrix is fixed here.

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

Additional player abilities may be specific to ships. A purchasable nanobot magnet is a separate utility proposal whose form remains open: a single-use item or an activated ability. Existing passive pickup upgrades remain part of the current build system.

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

Players have limited tools to shape upgrade outcomes through permanent purchases in the meta screen's separate Logistics section. These actions preserve uncertainty while giving players deliberate ways to steer a build.

### Current Logistics — November 2, 2026

- **Refresh Stock:** purchase up to three allowance tiers, costing 50, 100 and 200 Flux Anchors respectively. Each tier provides one refresh per new run. The button sits to the left of the upgrade rows and displays remaining uses in parentheses.
- **Blacklist:** purchase one allowance for 150 Flux Anchors, granting one use per new run. Each upgrade row has a Blacklist button on its right, displaying the same shared remaining count. It can be used even when the upgrade itself is unaffordable.
- Both actions disable when their remaining count is zero. Refresh also disables when there are no different eligible upgrades; an unchanged selection cannot consume a use.
- A refresh prefers new eligible upgrades under the station's existing pool, tier and purchase-memory weighting, retaining current choices only when needed to fill a small pool. Unchanged retained offers keep their base prices.
- Blacklist applies to the selected upgrade family, including all tiers, at every upgrade POI for the rest of the run. Purchased effects and purchase history stay intact. Only excluded slots are replaced; an exhausted pool may show fewer or no upgrades rather than restoring excluded content.
- The weapon offer is separated from the upgrade rows by spacing and a divider. Refresh Stock and Blacklist do not alter it.
- A POI retains its choices and rolled base prices when closed and revisited. Normal applicable player discounts and progressive weapon pricing still resolve through the existing pricing systems. Visiting again never grants a free refresh.
- Allowances and exclusions are shared across POIs and persist through Campaign sector transfer. Starting a new Campaign or Practice run snapshots the purchased allowances, refills their uses and clears old exclusions. Spending uses in Practice changes no persistent purchases, Flux Anchors, stats or unlocks.
- Logistics levels are saved separately from stat upgrades; they do not enter the ship's stat aggregator or run purchase history. The meta screen stages purchases/refunds in both sections through its shared Apply/Reset flow. Logistics levels cannot be changed during an active run.

The initial prices above are playtest settings authored in `content/data/logistics/`. Existing saves start with zero Logistics allowances without resetting progression. No remaining-use count or run blacklist is written to the permanent purchase record.

`UpgradeOfferService` owns the reusable offer generation, refresh and exclusion rules. `PoiInstance` owns its current cached stock, and `RunState` owns run-wide uses and excluded families. Upgrade menus handle presentation and purchasing; future upgrade POIs can reuse this service with their own definitions, pools and choice counts. New runs invalidate old stock through a run generation token.

### Build Diversity Follow-Up — October 27, 2026

Expand the upgrade pool with more diverse modifiers that can benefit multiple weapon families or create useful interactions between them. Show exactly which weapons, minions and player stats each choice affects. Build on the existing shared modifier and stat-projection systems so combinations remain understandable and maintainable.

Use playtesting to check whether players can form several effective builds across factions, ships and levels of meta investment. Favor meaningful alternative choices and synergies rather than filling the pool with mandatory flat-stat purchases. Ammo specialization, additional abilities and further luck-mitigation extensions remain broader backlog work, not automatic prerequisites for the Steam playtest milestone.

### Design Principle

A strong run should feel partially built and partially discovered.

The player should often feel:

- forced to pivot
- rewarded for recognizing unexpected synergies
- punished for chasing impossible perfection too long
