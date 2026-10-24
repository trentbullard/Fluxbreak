# Faction durability and attack balance pass

Status: implementation and automated validation complete (2026-10-24); ready for gameplay playtesting. These are initial playtest settings, not a claim of mathematically equal factions.

## Scope and agreements

- Machines, shared combat scaling, weapon damage, base rewards, upgrade prices, Campaign quantity budgets, and authored Practice wave budgets are unchanged.
- Mercs have the largest burst durability per purchase point, led by hull with modest shields and regeneration.
- Bugs have no shields or regeneration. Hull compensates for the missing shield pool. Sporelings remain deliberately fragile, cheap, and fast; heavier hulls move more slowly between attacks.
- Greys have modest hull, larger shields, strong regeneration, and three additional percentage points of base evasion. Sustained focus defeats regeneration; interrupted or weak focus gives them time to recover.
- Costs remain unchanged in this first pass. The current roster costs already distinguish anchors and support; formation composition, persistent summons, and new Grey attack geometry need playtesting before adjusting quantity through costs.
- Summoned minions persist after their spawner dies. Living and lifetime minion caps are removed. Killing a spawner prevents its future releases; existing minions must be killed separately. Confirmed sector transfer and run teardown still clear the old battlefield without synthetic rewards.
- No version increment or release build is part of this pass.

## Regular enemies: exact initial settings

All values are unscaled resource values. Regen is shields per second. Evasion is a probability, shown as a percentage. Pools exclude offspring and allied shield restoration.

| Faction | Enemy | Cost | Hull | Shield | Regen/sec | Evasion | Pool/point |
|---|---|---:|---:|---:|---:|---:|---:|
| Mercs | Corvette | 1 | 60 | 10 | 0.75 | 10% | 70.0 |
| Mercs | Frigate | 3 | 155 | 35 | 1.5 | 5% | 63.3 |
| Mercs | Destroyer | 3 | 185 | 25 | 0.75 | 3% | 70.0 |
| Mercs | Cruiser | 6 | 350 | 50 | 1.25 | 2% | 66.7 |
| Mercs | Carrier | 10 | 540 | 80 | 1.5 | 1% | 62.0 |
| Bugs | Sporeling | 1 | 36 | 0 | 0 | 8% | 36.0 |
| Bugs | Carapace | 3 | 180 | 0 | 0 | 1% | 60.0 |
| Bugs | Broodmother | 4 | 220 | 0 | 0 | 2% | 55.0 |
| Bugs | Devourer | 6 | 350 | 0 | 0 | 1% | 58.3 |
| Bugs | Hive Queen | 10 | 520 | 0 | 0 | 1% | 52.0 |
| Greys | Probe | 1 | 15 | 35 | 1.5 | 9% | 50.0 |
| Greys | Seeker | 3 | 45 | 110 | 3 | 9% | 51.7 |
| Greys | Vessel | 4 | 60 | 160 | 4 | 9% | 55.0 |
| Greys | Harbinger | 6 | 90 | 230 | 5 | 5% | 53.3 |
| Greys | Mothership | 10 | 130 | 370 | 7 | 5% | 50.0 |

Machine reference pools per point remain Drone 50, Sentinel 47.5, Reaper 35, Warden 40, Coremind 53.3. Their stronger evasion and regeneration are retained. The new values close large gaps without requiring every role to share the same time-to-kill.

The Frigate's hull remains lower than the Destroyer's; its stronger shield regeneration and allied restoration are part of its support value. Carapace receives substantial hull for its cost, while brood producers have slightly less raw durability per point to account for continuing offspring pressure. Merc Carrier has a larger hull investment than the other capitals; it is the most durable ordinary purchase, while its continuing Corvette releases make early interception valuable.

### Bug movement

| Enemy | Ordinary speed before | Ordinary speed after |
|---|---:|---:|
| Sporeling | 190 | 190 m/s |
| Carapace | 95 | 95 m/s |
| Broodmother | 85 | 85 m/s |
| Devourer | 145 | 80 m/s |
| Hive Queen | 75 | 65 m/s |

Devourer's committed charge remains 220 m/s. Its reduced cruise speed creates a deliberate slow heavy approach followed by the existing fast warned charge. No attack damage, charge distance, warning duration, or recovery was changed by the durability pass. Merc and Grey movement speeds are unchanged.

## Bosses: separate Campaign and Practice baselines

The previous first Campaign bosses used roughly 650–770 combined health, compared with the Machine Campaign boss's 6,800. Campaign resources now use the Campaign scale. Short Practice stages use separate resource variants with the same boss IDs, models, mechanics, rewards, and selection behavior.

| Mode | Boss | Cost | Hull | Shield | Regen/sec | Evasion |
|---|---|---:|---:|---:|---:|---:|
| Campaign | Contract Enforcer | 15 | 7,000 | 1,000 | 6 | 2% |
| Campaign | Vanguard Flagship | 30 | 7,600 | 1,200 | 7 | 1% |
| Campaign | Nestbreaker Matron | 15 | 7,000 | 0 | 0 | 1% |
| Campaign | First Queen | 25 | 7,600 | 0 | 0 | 1% |
| Campaign | Witness | 15 | 1,600 | 4,800 | 24 | 4% |
| Campaign | Veiled Mind | 25 | 1,800 | 5,200 | 28 | 4% |
| Practice | Contract Enforcer | 15 | 650 | 120 | 1.5 | 2% |
| Practice | Vanguard Flagship | 30 | 1,000 | 160 | 1.5 | 1% |
| Practice | Nestbreaker Matron | 15 | 650 | 0 | 0 | 1% |
| Practice | First Queen | 25 | 1,000 | 0 | 0 | 1% |
| Practice | Witness | 15 | 190 | 520 | 3 | 4% |
| Practice | Veiled Mind | 25 | 280 | 820 | 4 | 4% |

The final bosses gain only a modest base increase over their first-sector counterparts because stage-two combat scaling already carries forward and continues growing. Machine Campaign and Practice bosses are unchanged. Practice Grey regeneration is intentionally much lower than Campaign regeneration so early builds can make progress.

## Grey attacks and encounter pressure

Every damaging pattern remains fully warned and locks its geometry once. Forecasts use one velocity sample at commitment with a bounded lead; committed warnings never follow the player. Forward movement alone is no longer a universal answer, while turning, braking, boosting, climbing, and moving through the visible escape lanes remain useful.

- Probe retains the simple current-position rupture as the introductory pattern.
- Seeker uses forecast ruptures, including its separately warned follow-up after relocation.
- Vessel predicts a crossing capture corridor, retaining the bounded tether duration, escape distance, immunity, and single-tether rule.
- Harbinger pairs a current-position rupture with a forecast rupture; each component is separately visible and receives its full warning.
- Mothership uses complementary collapse geometry and can advance one idle nearby ally's ordinary cooldown for a forecast. Existing commitments and exposed recovery are never interrupted, and a five-second per-ally command cooldown prevents repeated acceleration. Relocation and tether actions set up a fresh warned attack rather than consuming a full empty attack cycle.
- Witness relocation sets up a current-position rupture plus a crossing lane. Its tether is directional. Below 55% combined hull and shields its cadence accelerates.
- Veiled Mind progresses from forecasts to paired current/forecast ruptures below 70% combined durability, then three-part collapses with a crossing lane below 35%. Setup actions lead into fresh warned collapses; phase progression never reverses when shields regenerate.

Both bosses use 1.2-second recovery and 0.8-second quiet cadence, with the full 1.8-second rupture warning preserved. Witness phase-two cadence multiplier is 0.75. Veiled Mind uses 0.75 in phase two and 0.5 in phase three. These values apply to both Campaign and Practice resources; the modes differ in defenses, not warning fairness.

Following explicit playtest feedback, all faction-wide warning allowances, boss reservations and multipart admission queues have been removed. Every regular ship and boss starts its complete attack pattern independently, subject to its own range, cooldown, recovery and committed action. Multiple tether capture warnings may overlap. The player's existing status handling still allows only one applied slow, with the same duration, distance break and immunity; a ship uses its damaging alternative when the player already has a tether or immunity. There is no replacement maximum on simultaneous damage or capture volumes.

Validation of independent timing: 33 simultaneous damage volumes across ordinary ships, several heavy patterns and both bosses; three overlapping tether capture warnings; independent cancellation/completion and new arrivals; source removal before deferred deletion. All 589 focused Grey checks and the complete Practice encounter passed. Gateway and separation suites also passed after the limiter was removed.

## Subsequent attack-size tuning — 2026-10-24

All Grey attack radii and corridor lengths/radii were increased by 20% in both Campaign and Practice, including capture corridors and companion echoes. This is a 1.2 multiplier on linear dimensions. Probe/Seeker/Vessel/Harbinger/Mothership base pulse radii are now 37.2/57.6/57.6/69.6/72 metres; both bosses use an 81.6-metre rupture radius. Regular crossing/capture lanes use 126-metre half-length and 30-metre radius; boss lanes use 180-metre half-length and 33.6-metre radius. The same dimensions drive warning drawings and hit checks. Attack damage, timing, forecast placement, weapon range, tether break distance, threat limits and harmless relocation markers are unchanged.

Validation after this tuning: Godot 4.7.2 import and all six Grey suites passed, including the full six-wave Practice run, with no engine errors, warnings or leaked objects.

## EHP interpretation and limits

Raw pool is only the burst-durability baseline. An illustrative sustained comparison is `(hull + shield) / (DPS after evasion - shield regen)`, provided net DPS remains positive. It excludes discrete volleys, crit/graze distributions, target switching, shields already depleted, allied support, summons, and player upgrades. It is not measured gameplay time-to-kill.

Mercs have the largest raw burst pool per point across corresponding ordinary roster positions. Greys can outlast them under interrupted focus or sufficiently weak sustained fire because regeneration recovers continuously; this is the intended recovery theme, not a promise that Mercs win every mathematical DPS comparison. Evasion can also interfere with Particle Beam ramp maintenance, so beam and accuracy builds need explicit playtesting.

The shared curve is unchanged: stage-one late enemies use 5.2x hull, 4.9x shield, and 2.8x regeneration; stage-two late enemies use 9.4x hull, 8.8x shield, and 4.6x regeneration. Living enemies retain their spawn snapshots. Zero Bug shield capacity and regeneration remain zero at every intensity.

The focused durability suite prints a transparent reference using 200 raw incoming damage/sec before evasion, with no allied support, at early, late stage-one, and late stage-two intensity. This reference is for comparing the shipped values, not establishing expected run duration. Actual late-game player DPS should be much higher than this fixed weak-build reference.

## Validation and playtesting

The new `faction_durability_checks` suite checks theme invariants through the real stat resolver at early and late intensities, stage carryover, positive costs and broad durability-per-point bands, progression of each roster, decreasing Bug cruise speeds, retained Devourer charge speed, shield-before-hull damage, capped regeneration, and Campaign boss-scale bounds. The cross-mode suite checks separate short Practice boss resources. Runs use unique save namespaces.

Automated results under Godot 4.7.2:

| Suite | Result |
|---|---|
| Import | Clean |
| Durability | 412 assertions passed |
| Merc regular / attacks / capitals / Flagship | 38 / 24 / 90 / 86 checks passed; full six-wave Practice, victory, menu and restart passed |
| Bug regular / Matron / advanced / First Queen | 82 / 113 / 166 / 105 checks passed; full six-wave Practice, victory, menu and restart passed |
| Grey regular / Witness / tether status / advanced / Veiled Mind | 91 / 94 / 56 / 128 / 220 checks passed; full six-wave Practice and victory passed |
| Purchasing and delivery | 26,008 assertions passed; 120 purchased units delivered in approximately eight seconds |
| All-faction Practice/Campaign routing | 15,673 assertions passed; all four factions, short encounters, gateways, finales and random launches |
| Gateway choices | 1,041 checks passed; both routes for every faction, including children whose owner died before boss arrival |
| Separation | 115 checks passed, including 50/100 live combatants without collision; 100-unit warmed proximity scans averaged approximately 1.24 ms in the latest run |
| Stage modifiers | 76 checks passed |

Successful logs contain no engine errors, warnings or leaked objects. Machine enemy resources and the shared combat-scaling resource have no diff. Routing-only fixtures use large defensive capacities so a scaled boss volley cannot kill the synthetic player and obscure gateway/victory assertions; combat geometry and faction Practice checks separately exercise the actual attacks.

Regression coverage includes uncapped repeated releases beyond the former lifetime and shared ceilings, minion survival after owner death/removal, independent minion death and reward exclusion, final sector cleanup, immutable predictions at 300/400 m/s, directional and vertical escape, complete companion lifecycles, pause, monotonic shield-aware boss phases, out-of-range reapproach, and independent simultaneous regular/boss patterns beyond the former warning limits.

Headless checks do not establish visual readability, full encounter CPU/GPU frame times or final gameplay balance. The scan timing above measures the separation service alone, not total frame time. Long fights with uncapped producers and actual Grey pattern readability still require live playtesting.

Recommended playtests:

1. Compare early waves of all four factions with the same ship/loadout. Corvettes should take longer to kill than Drones; Sporelings should remain the quickest individual kill.
2. Focus then disengage from a Seeker/Vessel. Shields should recover visibly; returning quickly should retain an advantage over leaving it alone.
3. Compare Carapace, Broodmother, Devourer, and Hive Queen movement. Devourer should approach slowly but still commit rapidly after its charge warning.
4. Compare Campaign boss duration using a normal upgraded build, then confirm both possible Practice bosses remain short lessons. Do not infer Campaign TTK from Practice hulls.
5. Test Grey bosses with low weapon count, accuracy upgrades, and Particle Beam builds. Check for excessive regeneration stalls and shield-heavy phase pacing.
6. Prioritize versus ignore brood producers and Carriers. Their death should stop future production while surviving offspring remain dangerous until killed.
7. Profile long fights with several live producers. With caps removed, minion population can grow substantially; measure that cost before compensating with new restrictions.
