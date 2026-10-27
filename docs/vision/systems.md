# Systems

This document describes the cross-system gameplay principles that govern run pressure, player scaling, and long-term progression. Systems should remain modular, data-driven, and tunable without requiring deep rewrites when balance evolves.

Detailed design intent for specific system families lives in dedicated files:

- [Wave System](./wave_system.md)
- [Upgrade System](./upgrade_system.md)

The [current roadmap](../plans/next_gameplay_milestones.md) tracks implementation status and the Steam playtest milestone. The planned systems below describe the broader finished-game direction; they are not all prerequisites for a playtest or Steam publishing.

## Cross-System Guardrails

- Prefer systems that stay readable under heavy combat load and remain easy to tune in isolation.
- Preserve build identity through interacting layers instead of relying on flat stat inflation.
- Favor authored-feeling pressure and escalation over noisy randomness or opaque adaptation.
- Keep progression data-driven so pilots, ships, factions, upgrades, and modifiers can combine without bespoke code paths.
- New systems should strengthen target priority, positioning, and synergy evaluation rather than bypass them.

## Stat Scope And Propagation

Systemic upgrades may apply to the player, minions, or both, but scope should always be explicit and centrally resolved.

- The run or ship upgrade state should remain the source of truth for acquired modifiers.
- Combat subsystems should consume filtered local projections of that state rather than duplicating ownership rules.
- Prefer local effective-stat views over scattered conditional checks inside behavior code.
- Add new stat consumers by extending stat projection layers, not by hard-coding upgrade exceptions into individual behaviors.
- Minions should inherit the build's identity without turning into opaque parallel actors that bypass readability.
- Minion scaling should emphasize command reach, uptime, role definition, and tactical pressure before invisible DPS inflation.

### Current Sector Modifier Layer

Sector conditions apply through a temporary layer separate from purchased upgrades. Player conditions refresh when the active stage changes; enemy conditions are resolved for ships spawned in that sector. Changing sectors replaces the layer, and ending or abandoning a run clears it. Briefings and entry share one cached condition roll, so comparing or cancelling a route cannot reroll its effects.

- Salvage Tide: +25% nanobots gained from pickups.
- Sensor Static: -10% player weapon base range.
- Thruster Corridors: +15% player forward and reverse top speed.
- Armored Patrols: +15% enemy maximum hull.
- Solar Flare Front: -15% player shield regeneration.

Campaign's Salvage route fixes Salvage Tide plus Sensor Static; its Assault route fixes Thruster Corridors plus Armored Patrols. These stat effects do not imply an environmental damage-hazard system. Practice retains its existing encounter settings.

### Planned Faction Stage Conditions

Faction-specific stage modifiers remain planned. They should give each hostile faction additional recognizable conditions within a stage, with their actual effects disclosed to the player. The existing Salvage and Assault route modifiers are the implemented foundation, not evidence that this faction layer is complete. Keep faction conditions distinct from purchased upgrades and make their interaction with route conditions explicit before implementation.

### Current Enemy Spacing

One shared proximity check runs roughly every half-second. Each enemy can receive a small lateral velocity pulse away from its closest nearby enemy, boss, or target, using cached visual clearance bounds or an authored radius override. Crowding strengthens the pulse; tight or exact overlaps use a stable pair-based escape direction. Existing orbit, pursuit, retreat, escort and boss locomotion continue to control normal flight.

Pulses are suppressed during committed warnings, charges, relocations and held recovery states. Those ships remain obstacles for other enemies. Target objects retain their existing motion, and the player, POIs and gateways are excluded. This is soft dispersion rather than a physical collision constraint.

## Meta-Progression

Outside active runs, the player gains access to persistent progression through meta-currency earned over time.

Meta progression should reward continued play through greater capability and comfort while keeping movement and build decisions relevant.

### Core Philosophy

Meta progression should never invalidate build decisions inside a run.

It should provide baseline improvements and useful tools that:

- reduce frustration
- reward continued play
- create long-term goals

### Example Meta Upgrade Targets

- nanobot pickup rate
- pickup radius
- baseline speed
- baseline damage output
- shield recovery
- hull durability
- repair efficiency
- starting resources
- upgrade economy improvements

### Design Constraint

Meta investment may create a satisfying power fantasy. It should still leave meaningful choices, recognizable threats and reasons to try different builds, rather than making one farming strategy the only sensible way to progress.

### Long-Term Goal

Meta progression should support replay longevity without making early runs trivial or late runs solved.

### Current Balance Observation — October 27, 2026

The current creator playtest baseline feels reasonably balanced: a fresh Rookie with Fighter Mk1 finds survival through roughly wave 10 challenging, while an Ace with Heavy Bruiser and substantial meta investment feels like a power fantasy. Preserve those useful reference cases while collecting independent playtest feedback; this is an observation, not a completed balance guarantee.

Campaign randomly chooses a faction and retains it throughout the run. Restarting until an easier faction appears may nevertheless provide an efficient farming route. Assess faction difficulty, reward efficiency and restart behavior together before choosing a remedy. No restart penalty, reward rule or faction-selection change is decided here. Practice retains faction selection and grants no persistent progression, records or unlocks.

## Planned Utility, Ability And Settings Work — October 27, 2026

- Add a purchasable nanobot magnet tool, either single-use or activatable. Acquisition, activation, lifetime and cost remain design decisions. This is additional to the existing passive pickup range, attraction behavior and salvage upgrades.
- Expand player abilities, potentially with abilities specific to individual ships. Their role should strengthen ship identity and add readable decisions; a particular ability roster or resource system is not yet selected.
- Add more points of interest with distinct risk, cost and payoff, building on existing docking and the run economy. Salvage beacons, refit stations and bounty relays remain candidate designs in the roadmap.
- Expand settings available during a run with audio controls and performance/quality options. Flight-camera settings already exist in the main menu and pause menu; this work extends that foundation rather than replacing flight handling.

## Planned Local Save Protection — October 27, 2026

The current progression/statistics file is `user://highscore.cfg`. Encrypting it and possibly relocating it from the current Godot user-data folder are backlog items. Any change should preserve existing progression through an explicit migration and keep test saves isolated. The destination, format and migration behavior are not decided.

Local encryption can discourage casual editing, but a key shipped with the client cannot make local scores cheat-proof. A different folder is an organization choice, not a security guarantee. This proposal does not establish trusted online leaderboards or change Practice's progression isolation.
