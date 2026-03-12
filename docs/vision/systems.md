# Systems

This document describes systemic gameplay layers that govern run pressure, player scaling, and long-term progression. Systems should remain modular, data-driven, and tunable without requiring deep rewrites when balance evolves.

## Wave System

Wave pressure is procedurally generated and should feel authored through budget logic, faction grammar, and pacing rules rather than fully random composition.

A run should usually have a dominant hostile identity, and wave generation should strongly favor that identity’s combat roles, pressure tendencies, and escalation style while allowing controlled deviations to avoid excessive predictability.

The wave system should create the feeling that the player is fighting an evolving hostile force rather than isolated enemy packs.

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

## Upgrade System

Upgrades define most of the player’s build identity during a run.

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
- minion recharge rate  
- minion discharge rate  
- minion count  
- minion radio-range / command range  
- minion AI responsiveness  

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
- **Refresh** — reroll available upgrades  
- **Banish** — permanently remove specific upgrade choices from the current run pool  
- other light-touch pool-shaping tools that preserve uncertainty  

These mechanics should allow players to influence luck without eliminating uncertainty.

### Design Principle

A strong run should feel partially built and partially discovered.

The player should often feel:
- forced to pivot  
- rewarded for recognizing unexpected synergies  
- punished for chasing impossible perfection too long  

## Meta-Progression

Outside active runs, the player gains access to persistent progression through meta-currency earned over time.

Meta progression should improve long-term comfort without replacing run skill.

### Core Philosophy

Meta progression should never invalidate build decisions inside a run.

It should provide gentle baseline improvements that:
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

Meta bonuses should remain meaningful but modest.

A skilled player with weak meta progression should still outperform a weak player with heavy meta investment.

### Long-Term Goal

Meta progression should support replay longevity without making early runs trivial or late runs solved.
