## Enemy Factions

Each run selects one of five hostile factions as the dominant enemy force. Factions are not only visual identities — they represent distinct combat philosophies, wave compositions, pressure curves, scaling tendencies, and upgrade challenges.

A strong build against one faction may struggle against another.

Faction identity should influence:
- target priority  
- movement decisions  
- upgrade value  
- defensive timing  
- weapon effectiveness  
- threat recognition  

Each faction has:
- a recognizable silhouette language  
- a distinct offensive personality  
- internal tier progression  
- elite variants  
- a fixed home system for late-run escalation  

Faction home systems are always consistent and should reinforce faction identity through modifiers, atmosphere, and encounter pressure.

### Current Campaign and Practice Runs

The main menu's Faction selector offers Random, Machines, Mercs, Bugs, and Greys. Both run buttons use it. Random chooses once when a run starts; every wave, reinforcement, boss, and later stage keeps that faction. The HUD shows the resolved faction. An explicit selection remains selected when returning to the menu, while Random draws again for the next run.

Practice contains introduction waves and a boss. Mercs, Bugs, and Greys have five lessons and ten cards each; Machines currently have three lessons and six cards. Each lesson tier has two card variants, and one variant per tier is drawn at launch. A Practice boss is also chosen once at launch. Campaign retains the two-stage run with a boss gateway followed by a final boss; its full faction deck unlocks compositions as enemy tiers become available and avoids immediate card repeats. Campaign salvage and pressure tuning remain distinct from the shorter lessons.

Merc Campaign uses Contract Enforcer at its gateway and Vanguard Flagship at its finale. Bug Campaign uses Nestbreaker Matron at its gateway and The First Queen at its finale. Grey Campaign uses The Witness at its gateway and The Veiled Mind at its finale. Machines Practice uses a locally tuned version of the existing Machine Boss I; its full encounter remains in Campaign.

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

Cruisers anchor a formation with three separately warned broadside rounds, then turn through a silent recovery window. Carriers launch two Corvettes at a time, with at most three living escorts and six total launches per carrier. Summoned escorts grant no kill rewards or adaptive pressure credit, cannot summon further ships, share a global ten-escort limit and a fifty-enemy encounter ceiling, and disappear when their owner dies or leaves the scene.

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

Choose Bugs and Practice for five lessons using `content/data/runs/bugs_practice.tres` as the template: Sporeling pursuit, Carapace pressure, Broodmother releases, Devourer charges, and Hive Queen area control. One of two card variants is drawn for each class, followed by either Nestbreaker Matron or a shorter First Queen encounter. Their bodies contract before marked attacks; leaving the marked volume avoids the hit.

Devourers lock a corridor through their overshoot destination, then travel along that committed line and recover without dealing contact damage. Hive Queens alternate finite brood releases and expiring, fixed spore spheres. Each spore pulse has a full warning and checks the player's current position. Zones have owner and encounter caps; Hive Queen cards buy at most one queen in the primary package, including at late Campaign budgets. Higher-tier cards prefer their named anchor when affordable and retain a lower-tier screen if the adaptive budget temporarily lags its tier unlock.

Nestbreaker Matron alternates a locked charge lane with a swelling brood release, leaving a recovery window after each attack. At 55% hull she releases larger broods and shortens her cadence. The First Queen begins with brood and spore attacks, adds committed charges at 70% hull, and changes the familiar sequence at 35%. Her full warnings and recovery remain intact throughout, and she remains damageable. Practice uses reduced Queen hull with the same mechanics; Campaign uses her full encounter at its finale.

Broods have living and lifetime limits, cannot reproduce, and disappear when their mother dies. Summoned children grant no kill rewards or adaptive kill-pressure credit. All Bug parents share the existing twelve-brood and fifty-enemy summon ceilings. Death and stage exit clear owned brood and spore zones. The five base classes and both bosses use distinct organic placeholder models and retain targeting volumes without physical body collision; later biological variants remain future work.

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
- Unclear threat windows  

### Common Role Bias
- Displacer  
- Specter  
- Harpooner  
- Jammer  

### Home System Identity
A silent distorted system where visibility, distance, and spatial expectation become unreliable. Environmental modifiers may alter radar clarity, distort movement perception, or delay projectile interpretation.

### Grey Practice Seed

Choose Greys and Practice for five lessons: Probe pulses, Seeker shifts, Vessel tethers, Harbinger rupture pairs, and Mothership coordination. Each tier draws one of two card variants, followed by either The Witness or a shorter Veiled Mind encounter. Probes drift and mark delayed pulse spheres. Seekers show both ends of a harmless shift, then begin a separate pulse warning. Vessels alternate delayed pulses with a locked tether capture; moving out of the capture sphere prevents attachment. All ships remain visible, damageable, and available to automatic targeting.

Harbingers commit two ruptures in sequence with a quiet gap. Each has its own full warning and locks the player's position separately; the second sphere does not chase the player after commitment. Motherships coordinate pulse, harmless relocation, and tether intervals with recovery between actions. Heavy cards purchase one primary Harbinger or Mothership with lower-tier escorts. Grey controllers share an encounter limit of two active damage/capture volumes and one pending or attached tether, leaving movement space even when several sources are present. Harmless shift markers and resolved flashes do not consume danger slots.

An attached tether has a visible link and countdown. It slows forward and reverse speed and acceleration by at most 35%, lasts at most three seconds, and breaks on distance, source death, or source exit. Turning and boost remain usable. Only one tether may affect the player, it cannot refresh itself, and every break grants three seconds of tether immunity.

The Witness cycles through marked relocation, rupture, and tether as separate actions with full recovery between them. At 55% hull only the cadence shortens. The Veiled Mind begins with delayed ruptures, adds marked relocation at 70% hull, and alternates tether, rupture, and relocation intervals at 35%. Phase changes alter future sequences without truncating a current warning or recovery; neither boss gains invulnerability. Campaign uses the full Veiled Mind at its finale, while Practice uses reduced hull and shields with the same abilities.

Relocations stay within the starting gun's reach so automatic weapons can reacquire the boss. Blue arrival markers are harmless; purple pulse and capture spheres warn of an effect that resolves after their countdown. Owner death, player death, and scene exit cancel queued attacks, relocation markers, and tethers. All five base classes and both bosses use smooth, suspended placeholder models with enabled targeting volumes and no physical body collision. Later evolution variants remain future work.

# Fifth Faction (Reserved)

The fifth faction remains intentionally open during early development and should be used carefully to fill whatever strategic identity is still missing after the first four are stable.

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
