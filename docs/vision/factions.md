## Enemy Factions

The final vision includes five hostile factions; four are currently implemented. Each run has one dominant hostile faction. Factions are not only visual identities — they represent distinct combat philosophies, wave compositions, pressure curves, scaling tendencies, and upgrade challenges.

A strong build against one faction may struggle against another.

Faction identity should influence:
- target priority  
- movement decisions  
- upgrade value  
- defensive timing  
- weapon effectiveness  
- threat recognition  

Each faction should ultimately have:
- a recognizable silhouette language  
- a distinct offensive personality  
- internal tier progression  
- elite variants  
- a fixed home system for late-run escalation  

The intended faction home systems should remain consistent and reinforce faction identity through modifiers, atmosphere, and encounter pressure. Home-system concepts, elite affixes and variant tags below are final-vision directions rather than a claim that every variant or modifier is implemented.

The [current roadmap](../plans/next_gameplay_milestones.md) tracks priorities and the Steam playtest milestone. Completing the fifth faction and the other planned expansion systems is not a prerequisite for Steam publishing.

### Current Campaign and Practice Runs

The main menu's Practice Faction selector offers Random, Machines, Mercs, Bugs, and Greys. Campaign always chooses randomly at launch; Practice uses the selector. Every wave, reinforcement, boss, and later stage keeps the resolved faction, which the HUD displays. The Practice selection remains selected when returning to the menu. Practice does not earn Flux Anchors or contribute to saved stats, records, discoveries or unlocks.

Practice contains introduction waves and a boss. Mercs, Bugs, and Greys have five lessons and ten cards each; Machines currently have three lessons and six cards. Each lesson tier has two card variants, and one variant per tier is drawn at launch. A Practice boss is also chosen once at launch. Campaign retains the two-stage run with a boss gateway followed by a final boss; its full faction deck unlocks compositions as enemy tiers become available and avoids immediate card repeats. Campaign salvage and pressure tuning remain distinct from the shorter lessons.

After the first Campaign boss, the player chooses Salvage Corridor or Assault Lane through distinct cyan hexagonal and amber chevron gateways. A paused briefing discloses the route's real conditions before explicit confirmation. Both choices preserve the run's faction, ship, build, nanobots, and finale boss; their wave-card and station opportunities differ. See [current sector choices](gameplay.md#current-campaign-sector-choices) for the tradeoffs and controls. Practice has no route choice.

Merc Campaign uses Contract Enforcer at its gateway and Vanguard Flagship at its finale. Bug Campaign uses Nestbreaker Matron at its gateway and The First Queen at its finale. Grey Campaign uses The Witness at its gateway and The Veiled Mind at its finale. Machines Practice uses a locally tuned version of the existing Machine Boss I; its full encounter remains in Campaign.

### Current Durability and Summon Identities

Machines retain their existing stats as the baseline. Mercs concentrate durability in strong hull with modest shields and regeneration. Bugs have no shields or shield regeneration; evolved carapace is represented by strong hull, with fast, cheap Sporelings below the heavier, slower classes. The latest Bug tuning doubles every base hull, including Campaign and Practice bosses and summoned Sporelings, giving Bugs larger raw pools than their comparable Merc classes. Greys have modest hull, stronger shields and sustained shield regeneration, plus slightly higher base evasion. Their regeneration rewards focused damage and can make interrupted attacks less effective than their raw pool suggests. Exact initial values, subsequent tuning and playtest priorities are recorded in [the faction balance pass](../plans/faction_balance_pass.md).

Summoned enemies remain independent combatants after their source dies or leaves the scene. Spawners have no per-owner or encounter-wide living/lifetime minion ceiling; warned release batches and launch cadence remain authored. Children cannot create further generations and grant no kill rewards or adaptive kill-pressure credit. Killing a spawner prevents future releases rather than clearing its existing force. Confirmed sector transfer and actual run/scene cleanup remove all remaining enemies, including children whose original source no longer exists.

Merc, Bug and Grey committed attacks use one shared, bounded field that charges during windup, flashes at the damage frame and fades after release. Merc fields retain amber colors, Bugs use their authored greens, and Greys retain their blue spatial effects. Cached line geometry and one shared unshaded shader replace the extra countdown rings, floating 3D attack text and per-frame mesh rebuilding. Sporeling contact clouds are the exception: their static sprites and outline use native materials as detailed below. Normal depth occlusion remains. Hit volumes, warning duration, damage and HUD warning metadata are unchanged by the shared presentation; multi-pulse spore zones recharge the same field before each hit. Harmless brood/escort launch cues and shield-support links remain separate.

### Planned Faction Variety And Balance — October 27, 2026

- Add faction-specific stage modifiers, distinct from the implemented Salvage/Assault route conditions. Disclose their effects and keep their visual indicators readable in crowded battles.
- Expand elite and special enemies with recognizable indicators, explicit modifiers and meaningful counterplay. Existing shield-support ships, brood carriers, displacement and tether attacks provide some specialized behavior; a general elite/modifier presentation and broader special-unit roster remain planned.
- Preserve differences in faction difficulty and build matchups while investigating whether repeated Campaign restarts make an easy faction the most efficient progression farm. Campaign's random assignment does not by itself prevent this behavior. No balance correction or restart rule is selected yet.
- Evaluate these changes with representative early, late and heavily upgraded runs, including the observed challenging fresh Rookie/Fighter and powerful meta-invested Ace/Heavy Bruiser cases. Performance and clarity at 100–200 combatants remain important validation targets.

# Machines (AI Collective)

Machines are highly ordered synthetic warforms built around precision, pressure consistency, and escalating mechanical superiority. They are clean, sterile, symmetrical, and increasingly intimidating as tier rises.

Their behavior rewards disciplined formation pressure rather than chaos.

They tend to favor:
- lasers  
- beam suppression  
- direct tracking fire  
- coordinated spacing  
- system interference  

Machines should feel relentless rather than emotional.

### Core Progression
- Drone  
- Sentinel  
- Reaper  
- Warden  
- Coremind  

### Elite Affixes
- Prime  
- Core  
- Sigma  

### Variant Tags
- Mk I  
- Mk II  
- Mk III  
- Mk IV  
- Mk V  

### Combat Identity
- Predictable but oppressive  
- Strong sustained pressure  
- High target discipline  
- Little wasted movement  

### Common Role Bias
- Suppressor  
- Jammer  
- Spawner  
- Assimilator  

### Home System Identity
A cold machine-controlled sector with stable geometry, artificial structures, reduced visual noise, and hostile efficiency. Environmental modifiers may enhance enemy targeting, reduce player recovery windows, or amplify system disruption.

# Mercs (Human / Corporate Force)

Mercenaries are disciplined military contractors and private war fleets operating under profit, hierarchy, and tactical efficiency.

Unlike Machines, Mercs should feel adaptive and intentionally aggressive.

They favor:
- missiles  
- ballistic weapons  
- coordinated formations  
- shield layering  
- role specialization  

Their fleets resemble recognizable military doctrine.

### Core Progression
- Corvette  
- Frigate  
- Destroyer  
- Cruiser  
- Carrier

### Elite Affixes
- Veteran  
- Elite  
- Vanguard  

### Variant Tags
- Mk I  
- Mk II  
- Mk III  
- Mk IV  
- Mk V  

### Combat Identity
- Combined-arms pressure  
- Tactical spacing  
- Focus fire  
- Mid-range threat layering  

### Common Role Bias
- Sniper  
- Support  
- Bruiser  
- Interceptor  

### Home System Identity
A militarized industrial war-zone with patrol structures, weapons platforms, debris corridors, and heavy sensor traffic. Environmental modifiers may increase missile saturation, turret pressure, or shield interactions.

### Merc Practice Seed

The Merc short encounter uses `content/data/runs/merc_practice.tres` as its template. Choose Mercs and Practice for five lessons: Corvette burst-and-retreat, Frigate shield support, Destroyer charged corridors, Cruiser broadsides, and Carrier escort deployment. Each class has two card variants. The boss is drawn from Contract Enforcer and a shorter Vanguard Flagship encounter; defeating it completes the run.

Corvettes approach quickly and keep strafing through their firing burst and timed retreat, weaving in three dimensions rather than holding beside the player. Cruisers anchor a formation with three separately warned broadside rounds, then turn through a silent recovery window. Carriers continue launching their authored two-Corvette batches while alive, without living or lifetime population limits. Existing escorts survive their carrier's destruction, remain independently targetable and are removed by genuine sector/run cleanup.

Contract Enforcer alternates marked corridor and spherical salvo attacks, calling one Frigate escort at 55% hull. Vanguard Flagship uses distinct sequences at 70% and 35% hull, requests finite escort wings on arrival and each phase transition, and periodically restores only its own escorts' shields. Its warnings and recovery remain full length throughout the fight. It never gains an invulnerability phase. Campaign uses the full Flagship at its finale; Practice uses reduced hull and shields with the same mechanics.

Amber volumes and a screen-space countdown show when a special attack will resolve. Leaving the marked volume avoids that special; ordinary gunfire retains the game's hit/miss calculations. Cyan support links show bounded Frigate restoration, while Flagship support pulses identify the affected escorts. All Merc actors retain targeting volumes without physical body collision. The five base classes and both bosses are implemented with readable placeholder models; later progression variants remain future work.

# Bugs (Swarm Hive)

Bugs are biological swarm organisms driven by overwhelming pressure, breeding momentum, and predatory adaptation.

They should feel dangerous through numbers, unpredictability, and constant encroachment.

They favor:
- close-range aggression  
- swarm density  
- biological spawning  
- attrition pressure  

Their threat often comes from volume rather than precision.

### Core Progression
- Sporeling  
- Carapace  
- Broodmother  
- Devourer  
- Hive Queen  

### Elite Affixes
- Alpha  
- Apex  
- Matron  

### Biological Stage Variants
- Larval  
- Mature  
- Apex  
- Royal  

### Combat Identity
- High density  
- Rapid pressure escalation  
- Limited fear of loss  
- Constant positional harassment  

### Common Role Bias
- Brawler  
- Seeder  
- Devourer  
- Collector  

### Home System Identity
An overgrown living battlefield full of organic structures, drifting biomass, spores, and unstable biological hazards. Environmental modifiers may increase spawn pressure, healing behavior, or movement interference.

### Bug Practice Seed

Choose Bugs and Practice for five lessons using `content/data/runs/bugs_practice.tres` as the template: Sporeling pursuit, Carapace pressure, Broodmother releases, Devourer charges, and Hive Queen area control. One of two card variants is drawn for each class, followed by either Nestbreaker Matron or a shorter First Queen encounter. Carapace and larger Bugs retain their marked attack warnings. Sporelings instead create three-second, fixed poison clouds shown as small static green sprites at 25% opacity inside a simple spherical outline that remains at 50% opacity, without internal lightning or custom shaders. Contact causes an immediate tick, then another every 0.5 seconds while inside, with no separate opening or final strike. Every overlapping cloud ticks independently. Unscaled tick damage is 1.92–3.36, calculated as the former strike damage times 1.2 divided by three. The six full-exposure ticks occur before the exclusive three-second expiry. Leaving stops damage, and returning never grants a backlog or bypasses that cloud's existing half-second cooldown. Sporelings keep weaving through their close orbit, cloud lifetime and recovery; moving their hull never drags the deposited cloud.

Devourers lock a corridor through their overshoot destination, then travel along that committed line and recover without dealing contact damage. Hive Queens alternate brood releases and expiring, fixed spore spheres. Each spore pulse has a full warning and checks the player's current position. Spore zones retain their separate owner and encounter caps; Hive Queen cards buy at most one queen in the primary package, including at late Campaign budgets. Higher-tier cards prefer their named anchor when affordable and retain a lower-tier screen if the adaptive budget temporarily lags its tier unlock.

Nestbreaker Matron alternates a locked charge lane with a swelling brood release, leaving a recovery window after each attack. At 55% hull she releases larger broods and shortens her cadence. The First Queen begins with brood and spore attacks, adds committed charges at 70% hull, and changes the familiar sequence at 35%. Her full warnings and recovery remain intact throughout, and she remains damageable. Practice uses reduced Queen hull with the same mechanics; Campaign uses her full encounter at its finale.

Broodmothers and Hive Queens continue releasing their authored batches while alive. Broods have no living or lifetime population ceiling, cannot reproduce, and survive their mother's death. Summoned children grant no kill rewards or adaptive kill-pressure credit. Source death still cancels that source's warnings and spore zones; stage exit clears all remaining brood and abilities. Sporelings have the lowest hull and fastest cruise, while heavier carapaces slow the larger classes. Devourers retain their separately committed high-speed charge. The five base classes and both bosses use distinct organic placeholder models and retain targeting volumes without physical body collision; later biological variants remain future work.

# Greys (Ethereal / Psionic Aliens)

Greys are enigmatic psionic entities whose ships feel less manufactured and more implied — smooth, unnatural, silent, and difficult to predict.

They should feel psychologically disruptive rather than physically overwhelming.

They favor:
- distortion  
- displacement  
- psychic interference  
- delayed threat recognition  

Their presence should create uncertainty.

### Core Progression
- Probe  
- Seeker  
- Vessel  
- Harbinger  
- Mothership  

### Elite Affixes
- Eternal  
- Awoken  
- Voidborn  

### Evolution Tags
- Proto  
- Awakened  
- Ascendant  

### Combat Identity
- Strange movement patterns  
- Delayed pressure  
- Spatial disruption  
- Unfamiliar but readable threat windows

### Common Role Bias
- Displacer  
- Specter  
- Harpooner  
- Jammer  

### Home System Identity
A silent distorted system where visibility, distance, and spatial expectation become unreliable. Environmental modifiers may alter radar clarity, distort movement perception, or delay projectile interpretation.

### Grey Practice Seed

Choose Greys and Practice for five lessons: Probe pulses, Seeker forecasts and shifts, Vessel capture corridors, Harbinger rupture pairs, and Mothership coordination. Each tier draws one of two card variants, followed by either a shorter Witness or Veiled Mind encounter. Probes strafe in a changing three-dimensional orbit, including during their simple delayed pulse warnings and recovery. The marked sphere remains locked in space while its source moves. Seekers mark an anticipated position from the player's velocity at commitment; changing course defeats the forecast. Vessels alternate damaging patterns with crosswise capture corridors; turn or climb out of the locked lane to prevent attachment. All ships remain visible, damageable, and available to automatic targeting.

Harbingers commit complementary current-position and forecast echoes, each with a full charge-up field. Motherships combine a crossing lane with a forecast requested from an idle nearby ally. Their relocation and tether setups lead into a warned collapse rather than consuming a full empty damage cycle. Heavy cards purchase one primary Harbinger or Mothership with lower-tier escorts. There is no faction-wide limit or queue for active warnings: each ship and boss starts its complete patterns on its own cooldown, range and recovery rules. Multiple tether capture warnings may overlap; the player's movement slow still cannot stack or refresh an existing link.

An attached tether has a visible flowing link. It slows forward and reverse speed and acceleration by at most 35%, lasts at most three seconds, and breaks on distance, source death, or source exit. Turning and boost remain usable. Only one tether may affect the player, it cannot refresh itself, and every break grants three seconds of tether immunity.

The Witness uses marked relocation and tether setups to lead into complementary rupture/crossing patterns. The Veiled Mind progresses from forecast ruptures to paired echoes and then three-part collapse patterns, increasing decisions per damage cycle. Phase thresholds use combined remaining hull and shields so shield-heavy bosses reach their later patterns before their hull is nearly exhausted; phases never reverse when shields regenerate. Phase changes alter future sequences without truncating a current warning or recovery; neither boss gains invulnerability. Both Campaign bosses have full-size defenses, while Practice uses reduced pools and regeneration with the same abilities.

Relocations stay within the starting gun's reach so automatic weapons can reacquire the boss. Blue arrival markers are harmless; bounded rupture and crossing/capture fields charge before their effect resolves. Predictions sample velocity when committed and never track the player afterward; complementary warnings retain open lateral or vertical escape. Source death, player death, and scene exit cancel queued attacks, relocation markers, and tethers. All five base classes and both bosses use smooth, suspended placeholder models with enabled targeting volumes and no physical body collision. Later evolution variants remain future work.

# Fifth Faction (Reserved)

The fifth faction remains intentionally open during early development and should be used carefully to fill whatever strategic identity is still missing after the first four are stable.

It remains planned expansion scope, with its identity, ships, bosses and wave deck still to be defined. The existing four factions are the foundation for the upcoming polished Steam playtest.

This faction should not duplicate existing pressure patterns.

Potential directions:
- scavenger nomads  
- rogue bio-mechanical hybrids  
- ancient automated relic civilization  
- dimensional predators  
- corrupted human remnants  

The fifth faction should ideally introduce a pressure model that forces players to rethink assumptions learned from the first four.

## Combat Roles

Enemy power should scale through composition, not just raw numbers.

A dangerous wave is often defined by role synergy rather than tier alone.

---

### Core Combat Roles

- **Brawler** — closes distance aggressively and pressures the player into retreat  
- **Sniper** — maintains standoff range and punishes passive positioning  
- **Support** — buffs, shields, repairs, or amplifies nearby allies  
- **Scout** — low durability, fast, extends threat awareness for heavier units  
- **Bruiser / Vanguard** — durable front-line pressure that protects fragile allies  

---

### Disruption Roles

- **Suppressor** — reduces player output through beam pressure or system interference  
- **Interceptor** — blocks projectiles or interrupts attack windows  
- **Tether / Harpooner** — slows or drags the player into danger  
- **Displacer** — appears unpredictably to break rhythm  
- **Jammer** — interferes with HUD, targeting, or battlefield awareness  

---

### Area Control Roles

- **Seeder / Spawner** — deploys mines, spores, drones, or secondary threats  
- **Siege / Artillery** — long-range delayed AoE pressure  
- **Webber** — creates temporary movement penalties or vulnerability zones  
- **Terraformer** — alters battlefield conditions directly  

---

### Adaptive / Utility Roles

- **Assimilator** — consumes wreckage to evolve or repair  
- **Hijacker** — interferes with player systems or allied constructs  
- **Echo / Clone** — produces false targets or visual confusion  
- **Specter / Phase** — vulnerable only during controlled windows  
- **Collector** — attempts to deny player resource gain  

## Wave Composition Principle

The most interesting waves combine 2–3 roles that reinforce one another.

Examples:
- Bruisers + Supports + Snipers  
- Suppressors + Scouts + Siege  
- Spawners + Brawlers + Jammers  

Threat should escalate through composition complexity, not only health and damage inflation.

## Faction Role Tendencies

- **Machines:** Suppressor, Jammer, Spawner  
- **Mercs:** Sniper, Support, Bruiser  
- **Bugs:** Brawler, Seeder, Collector  
- **Greys:** Displacer, Specter, Harpooner  

Faction identity should remain visible even when elite variants or late-run compositions become chaotic.
