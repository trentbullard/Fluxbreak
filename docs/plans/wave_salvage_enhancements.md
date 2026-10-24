# Fluxbreak: Wave Pressure and Salvage Enhancement

## Summary and working agreements

Repository: `C:\Users\trent\workspace\fluxbreak`

Intended document location: `C:\Users\trent\workspace\fluxbreak\docs\plans\wave_salvage_enhancements.md`

Build escalating, overlapping enemy encounters while preserving faction identity, existing combat movement, and meaningful salvage collection decisions.

Implement the phases separately, validating each before continuing. **The first agent assignment covers Phase 1 only.** Phase 7 is a deferred experiment.

Established decisions:

- Leave enemy HP/damage scaling, weapon balance, upgrade prices, and base reward amounts unchanged.
- Preserve faction selection and existing Campaign/Practice distinctions.
- Remove unused legacy cap code.
- Keep nanobot swarms separate; reduce their value over time.
- Make swarms larger and readable against bright and dark backgrounds, with normal world occlusion.
- Preserve enemies and passive targets when a boss arrives.
- Boss defeat immediately opens gateways or completes the run, regardless of surviving enemies.
- Preserve accepted gateway-transfer cleanup. The subsequent faction balance pass overrides the original summon ownership limits: existing minions survive their source's death or removal, and spawning has no living or lifetime population ceiling. Release cadence, batch sizes, no-recursion rules and reward exclusions remain.
- Follow `AGENTS.md`, typed Godot 4.7.2 conventions, and existing save-isolated validation patterns.
- Do not increment versions, export executables, or build installers as part of these phases.

Numeric defaults below are initial playtest settings. Implement them as documented configuration values and report subsequent tuning explicitly.

## Implementation phases

### Phase 1 — Correct purchasing and group delivery

**Goal:** Make the existing difficulty budget reliably become a complete, promptly delivered encounter before increasing its allocation.

**Purchasing**

- Use a single accounting ledger: allocated points = purchased unit costs + explicitly reported remainder. Never overspend or discard package leftovers silently.
- Determine the requested formation count before dividing the budget. Keep the current count formula and authored minimum/maximum; reduce the actual count only when the budget cannot afford meaningful formations.
- Make each spatial package a formation that can contain primary, secondary, and support ships. Assign its members the same `package_id`; role budgets must not automatically place a capital and its escorts in unrelated formations.
- Divide available points among formations, then use the card’s role shares within them. Preserve primary-role identity, faction restrictions, tier eligibility, and anti-repetition.
- Remove incidental limits that strand affordable budget: the universal two-copy escort limit, fixed pick counts, and species blocking after a single purchase.
- Retain authored primary-count restrictions and enforce them across the purchase. Limit combined capital expenditure using the card’s primary budget share. For this purpose, classify tier 4–5 units or units meeting the card’s anchor-cost threshold as capitals.
- Permit one required anchor when its individual cost exceeds the capital allowance, provided it remains affordable within the total budget.
- Recycle unspent points into legal escorts/support before additional capitals. Prefer the card’s roles, then eligible noncapital ships from the same faction.
- Finish purchasing when no legal affordable unit remains. Report the remainder and limiting constraint.
- Preserve authored Practice budgets, card order, tier caps, and boss selection.

**Delivery**

- Replace the fixed 18-unit opening ceiling with an opening selection of whole formations covering at least 60% of purchased units. Include at least two formations when available; permit the final selected formation to exceed that percentage.
- Spawn each formation together using the existing warp presentation and brief internal stagger.
- Launch remaining formations at two-second intervals, compressing intervals when necessary so the planned launch sequence finishes within eight seconds.
- Distribute work across formations fairly; do not exhaust one ship request while every other request waits.
- Preserve the existing wave timeout duration, measured from wave start. Remove inconsistent calculations that extend it after dispatch.
- Every purchase must be recorded as spawned, pending, or cancelled with a reason. Cancel obsolete requests on run termination or wave-token invalidation; never spawn them during a subsequent boss or gateway state.
- Keep existing spawn-distance rules, combat movement, adaptive-pressure settings, and budget curve unchanged in this phase.

**Cleanup and diagnostics**

- Remove all three unused legacy cap fields, their unused setters, and obsolete test assignments.
- Preserve summon release cadence, no-recursion rules and reward exclusions. Population ceilings and source-death child cleanup were superseded by the subsequent faction balance pass.
- Extend the existing debug snapshot with allocated/spent/remainder points, formation composition, planned/spawned/cancelled units, dispatch duration, and peak alive/nearby counts. Use a clearly labelled 1,000-metre radius for the initial nearby metric.
- Add seeded checks covering all factions, low budgets, high budgets, singleton role pools, and capital-heavy cards.

**Exit condition:** Affordable legal budget is spent, requested formations are created when feasible, and purchased enemies arrive promptly without the old 18-unit bottleneck. Report the result and stop for playtesting.

### Phase 2 — Preserve the battlefield at boss arrival

- Remove the boss-start arena cleanup and its unused helper. Retain ordinary enemies, owned summons, passive targets, existing damage, and active attacks.
- Continue suppressing ordinary pressure purchases during boss encounters.
- Keep existing completion semantics: the first boss immediately opens gateways; the final boss immediately completes the run.
- Survivors remain active during gateway hold. Opening the briefing pauses gameplay; cancelling it resumes the same threats.
- Confirmed sector transfer still removes the previous sector’s enemies, targets, drops, projectiles, and abilities without granting synthetic rewards.
- Source death or removal cancels its attacks and future releases; existing minions remain until killed or sector/run cleanup. This supersedes the original source-death child cleanup requirement.
- Update tests that incorrectly treat every surviving ability at boss victory as stale; distinguish legitimate living owners from orphaned effects.

**Exit condition:** Boss arrival adds pressure to the existing battlefield, and neither gateway flow nor victory requires clearing survivors.

### Phase 3 — Coordinate formation approaches and spawn placement

**Goal:** Deliver overlapping groups without replacing individual combat behavior.

- Carry a unique encounter ID and formation ID from `SpawnRequest` into `EnemySpawnContext`, including context duplication. Pressure purchases need distinct IDs even within the same wave.
- Add a scene-owned formation controller with cached membership and approximately 0.5-second coordination updates. Avoid per-frame all-pairs scans.
- Give ordinary purchased enemies a temporary transit state with loose offsets around a shared moving anchor.
- Set formation cruise pace from its slowest living transit member. Recalculate membership-dependent values on spawn/death.
- Merc, Bug, and Grey transit uses their configured movement speeds. Machines receive a configurable nominal transit pace of 100 m/s while retaining their existing force-based orbit behavior after transit.
- Expose common capabilities for transit speed, effective engagement range, and committed attack/locomotion state. Engagement range must account for weapon range and behavior-specific attack gates.
- Release a formation into existing combat movement when a member reaches its engagement envelope, receives positive damage, or begins an attack. Release is one-way.
- Exclude bosses and summoned children from formation constraints.
- Keep lateral separation active. Adjust ordinary approach steering rather than clamping total velocity or interrupting charges, retreats, telegraphs, or displacement.
- Choose spawn distances from formation pace and a target travel time of approximately eight seconds, bounded by existing minimum safe spawn distances and maximum spawn radius.
- Choose separated approach bearings with modest randomness. Target arrivals from opening formations within roughly three seconds of one another; later launch pulses retain their deliberate delay.
- Measure actual arrival times and adjust distance calculations if acceleration creates substantial divergence.

**Exit condition:** Mixed formations remain loosely coherent in transit, overlap in combat, and preserve every faction’s established attack behavior.

### Phase 4 — Strengthen late-wave and second-stage budgets

Apply these changes to procedural Campaign quantity budgets. Authored Practice budgets retain precedence.

- Keep the current early quantity curve.
- Add a multiplier of `1.025 ^ max(local_wave - 10, 0)`.
- Keep quantity progression separate from HP/damage progression.
- Preserve the preceding sector’s last ordinary-wave allocation before performance adjustments as its quantity carryover reference. Never use the boss wave’s zero budget or actual buyer expenditure.
- Stage two opens at 40% of that reference. Add 1.5 times the first-stage local budget growth above its opening value.
- Apply existing adaptive budget adjustments once, after constructing this quantity curve.
- Capture the last five seconds of active-wave performance before downtime and use that snapshot for the next opening adjustment. Do not sample a signal erased by the break.
- Preserve current downtime durations during this pass so budget and arrival changes can be assessed independently.

Illustrative neutral budgets, assuming approximately one minute per completed wave:

| Local wave | Current stage 1 | Proposed stage 1 | Proposed stage 2 |
|---|---:|---:|---:|
| 1 | 7 | 7 | 68 |
| 10 | 39 | 39 | 116 |
| 20 | 75 | 95 | 201 |
| 25 | 92 | 134 | 258 |
| 29 | 107 | 170 | 313 |

These are points, not ship counts. Wave 30 is the boss. Actual elapsed time and performance adjustments affect allocations.

**Exit condition:** Late Campaign waves purchase substantially larger encounters, stage two provides a relative opening breather, and its wave 10 is clearly more oppressive than stage one’s wave 10.

### Phase 5 — Progress stationary salvage opportunities

Replace the conflicting target-purchasing paths with one progression-aware policy. Remove configuration and code made obsolete by that replacement.

- Use run-wide progression for target selection, preserving the transition into wrecks across sectors.
- Initial weights:
  - Waves 1–5: asteroids.
  - Waves 6–11: 40% wrecks.
  - Waves 12–19: 75% wrecks.
  - Wave 20 onward: wrecks only.
- Guarantee a wreck opportunity when entering the first wreck-enabled phase.
- Choose the desired type before allocating its purchase points. Fund that target’s actual cost; never substitute several asteroids because a wreck budget is insufficient.
- Maintain independent active-target allowances: four normally, five on Salvage, three on Assault.
- Start with two targets. Permit at most one replacement per wave normally and two on Salvage. Downtime and wave-start hooks must share this allowance rather than double-purchase.
- In mixed phases, Salvage increases wreck probability by 20 percentage points, capped at 100%.
- Give asteroids a 120-second lifetime and wrecks 180 seconds.
- Fade during the final five seconds. Recent player damage postpones expiration until ten seconds after the last hit, with a maximum 30-second extension.
- Expiration grants no rewards. Keep target rewards unchanged.
- Existing targets must not globally disable replenishment. Respect the independent count allowance and retire expired opportunities normally.
- Keep the short authored Practice runs’ existing target suppression.

**Exit condition:** Wrecks reliably appear, late runs stop producing fresh asteroids, and ignored targets cannot accumulate indefinitely or block the intended mix.

### Phase 6 — Decaying, readable nanobot swarms

**Value and collection**

- Keep every swarm independent; never merge or automatically credit it.
- Use 90 seconds of linear decay from its original value, beginning at spawn.
- Calculate remaining value directly from original value and age, using integer ceiling while positive. At 90 seconds, expire without credit.
- Decay continues outside magnet range and during attraction, and pauses with gameplay.
- Award the remaining value exactly once when pickup commits; preserve existing collection modifiers.
- Introduce explicit initialization before scene insertion. Both enemy and target drop paths currently assign value after `_ready()`, which would otherwise initialize decay from zero.
- Use terminal collected/expired states to prevent deferred pickup races and duplicate awards.

**Visibility**

- Enlarge the cloud’s extent approximately 2.5 times without increasing its particle count.
- Add a camera-facing, unshaded cyan/green and white core with a dark contour. Preserve normal depth occlusion.
- Maintain an apparent core diameter of approximately 14–36 UI-scaled pixels. Keep it readable through 3,000 metres and fade it out by 3,500 metres.
- Keep pickup geometry, magnet range, and attraction movement unchanged.
- Reduce visual strength with remaining value, retaining a readable contour until the final seconds. Reflect decay in existing offscreen drop indicators.
- Avoid per-swarm lights and additional through-object HUD markers.

**Exit condition:** Individual drops are easy to identify against every existing background, age visibly, reward prompt retrieval, and disappear without leaving permanent clutter.

### Phase 7 — Deferred perimeter coordination experiment

**Do not implement or enable this during the initial rollout.**

After the preceding phases are playtested, prototype group awareness using the formation controller:

- Sample approximately every 0.5 seconds.
- Count both enemies within their effective attack envelope and enemies actively executing attacks. Include bosses and summons in awareness, but never constrain their movement.
- Use one-way approach → staging → committed → normal combat states.
- Eligible formations stage approximately 200 metres outside their effective engagement perimeter.
- When another formation is ready, commit the ready formations together on the next coordination update.
- Limit staging to six seconds; a lone formation must eventually attack.
- Positive damage, player entry into a member’s attack envelope, or an attack already beginning immediately releases that formation into ordinary combat.
- Synchronize final approach movement, preserving individual weapon cooldowns and telegraph timing.
- Keep the experiment disabled by default and compare it against ordinary coordinated transit.

**Evaluation:** Does staging create stronger arrival overlap without excessive waiting, synchronized unavoidable attacks, or an exploitable queue? Decide whether to enable it only after that comparison.

## Interfaces and verification

Keep configuration in existing resources/components where practical. The necessary interface additions are runtime formation identity, shared enemy transit/engagement capabilities, explicit swarm initialization, and expanded debug accounting. Do not add a new autoload.

Validate each phase using focused checks plus relevant existing faction, Practice, gateway, modifier, and separation suites. Use the configured `GODOT_EXE` and isolated save namespaces.

Required scenarios:

- **Purchasing:** all four factions; tiny and large budgets; constrained capitals; singleton pools; repeated escorts; no overspend; accounted remainder; distinct valid formation IDs.
- **Delivery:** whole-group launches, opening participation, completion within eight seconds, pause/resume, timeout consistency, and no stale spawning after transitions.
- **Bosses:** survivors, summons, passive targets, and active warnings survive arrival; no synthetic rewards; gateway cancel resumes threats; transfer cleans the sector; victory fires once.
- **Movement:** slow capitals with fast escorts; member death; player interception; Machines; charges, retreats, displacement, and separation pulses.
- **Progression:** waves 1/10/20/25/29 in both sectors; carryover uses the ordinary allocation; authored Practice overrides remain effective.
- **Targets:** guaranteed affordable wrecks, route differences, replacement allowances, expiration grace, no expiration loot, and no fresh asteroids after the cutoff.
- **Swarms:** both initialization paths; correct value at 0/30/60/90 seconds; pause; out-of-range decay; pickup/expiration races; unchanged magnet behavior; no merging.
- **Visual/performance checks:** fresh and aged swarms at 100/1,000/3,000 metres against empty space, asteroid fields, planets, and solar flare. Profile 50–100 combatants and 100 simultaneous swarms; report CPU/GPU frame times and investigate matched-load regressions before advancing.

After every phase, report changes, validation results, remaining limitations, and the recommended playtest. Update this document’s phase status. Stop at the assigned phase boundary.

## Starter prompt for the new agent

```text
Work in C:\Users\trent\workspace\fluxbreak using Godot 4.7.2.

Read AGENTS.md and the attached “Fluxbreak: Wave Pressure and Salvage Enhancement” plan. Save the plan unchanged to docs/plans/wave_salvage_enhancements.md if it has not already been saved, then maintain its phase status.

Implement Phase 1 only: correct enemy purchasing, formation allocation, group delivery, unused legacy cap cleanup, and diagnostic accounting.

The purpose is to make the existing budget produce complete encounters before adding more budget. Preserve the current quantity curve, spawn-distance rules, combat movement, adaptive settings, HP/damage scaling, economy, and authored Practice budgets/order/tier caps.

Follow the plan’s global budget accounting, capital restrictions, mixed spatial formations, whole-formation opening delivery, eight-second launch window, consistent wave timeout, and explicit cancellation reporting. Remove obsolete cap setters and test assignments while preserving real summon limits.

Inspect the current implementation before editing. Preserve unrelated working-tree changes. You may delegate independent implementation or review tasks, but keep ownership clear.

Add meaningful seeded checks across all four factions and representative budgets, including singleton role pools and capital-heavy cards. Run the Godot import and relevant existing validation suites using GODOT_EXE and isolated test saves.

Do not implement later phases, increment the version, export the game, or build an installer.

Complete and validate Phase 1, update its status in the plan, then stop. Report what changed, checks performed, representative before/after purchasing and delivery results, remaining limitations, and a short playtest checklist. Distinguish verified behavior from expected gameplay effects.
```

## Phase status

- Phase 1: implemented and automated validation passed (2026-10-24); Phase 2 subsequently authorized by the user.
- Phase 2: implemented and automated validation passed (2026-10-24); ready for gameplay playtesting.
- Phases 3–6: not started.
- Phase 7: deferred; not implemented or enabled.
- Subsequent faction balance pass: implemented and automated validation passed (2026-10-24). See [durability, persistent minions and Grey attacks](faction_balance_pass.md). This explicitly supersedes original summon population/owner-death cleanup rules; it does not advance Phases 3–7.

### Phase 1 implementation record — 2026-10-24

Implemented one purchase ledger with mixed spatial formations, shared role requests, purchase-wide primary limits, combined capital allowance, and explicit remainder constraints. Formation seeds are reserved before splitting remaining points. Unused allocations return to the global ledger and buy eligible escorts before more capitals.

Capital allowance is `floor(total points * normalized primary_budget_share)`. One affordable required anchor may exceed that allowance. `max_primary_budget_share` still limits the chosen primary species when `allow_swarm_primary` is false; it no longer limits unrelated escorts. `primary_count_max` counts all qualifying primary-role hulls across the purchase, including hulls selected through recycling. Lower-tier hulls remain eligible as escorts.

Whole opening formations cover at least 60% of purchased enemies and include at least two formations when available. Later formations launch at two-second intervals, compressed into an eight-second window. The wave timeout is measured from wave start. Main, pressure, and downtime purchases record delivery or explicit cancellation; completed value-only ledgers are available in the latest 32 delivery-history records. Enemy and target unit accounting are separate.

The debug HUD exposes allocation, expenditure, remainder, formations, delivery counts, and peaks. Alive counts are captured immediately after dispatch and actual living enemies are sampled every 0.5 seconds; nearby peaks use the labelled 1,000-metre radius and are sampled rather than continuous measurements. Removed the three legacy spawner caps, their setters and obsolete fixture assignments, plus unused buyer and director fields/helpers superseded by this implementation. Active pressure tuning and summon limits remain in use.

#### Representative verified results

| Seeded purchase or delivery | Result |
|---|---|
| Merc Carrier Group, 100 points | Previously 7 ships / 48 points; now 26 ships / 100 points across 3 formations |
| Machine Core Guard, 100 points | 38 ships / 100 points across 3 formations |
| Merc Reserve Wing, 100 points | 42 ships / 100 points across 3 formations |
| Bug Royal Swarm, 100 points | 32 ships / 100 points across 3 formations |
| Grey Psionic Convergence, 100 points | 29 ships / 100 points across 3 formations |
| Synthetic 120-ship delivery | 80 opening ships in 8 complete formations; all 120 delivered by 8.017 seconds |

These are seeded examples, not promises of identical randomized compositions. The previous Carrier result is derived from the previous purchase rules; the new results are engine-validated. The dispatch measurement uses synthetic actors with the real director coroutine. Actual combat arrival overlap and perceived difficulty still require playtesting; movement and spawn-distance tuning belong to Phase 3.

#### Validation passed

- Godot 4.7.2 headless import.
- New save-isolated purchasing/delivery suite: 26,008 assertions; four faction decks, budgets 0–240, singleton pools, capital/primary constraints, recycling, primary history, seeded reproducibility, whole launches, pause, timeout, unavailable spawns, and stale-pressure cancellation.
- Existing Practice faction suite: 15,373 assertions; all four factions, Practice and Campaign routing, gateways, finales, and random selection.
- Existing Merc, Bug, and Grey regular, advanced, boss, and Practice suites.
- Existing gateway choice suite: 737 checks; all four factions and both routes.
- Existing stage modifier suite: 76 checks.
- Existing separation suite: 115 checks, including 50- and 100-enemy crowds. Its 100-enemy headless proximity benchmark averaged 1.130 ms per warmed scan; this is not a rendered-combat frame-rate measurement.
- Independent static review found no actionable issues. Whitespace validation passed.

All checks used isolated player-data namespaces. No version increment, executable export, or installer build was performed.

#### Next playtest

1. Play a Merc Campaign with the same strong weapon/upgrade choices that exposed the trickle. Compare early waves with waves 15–29, especially Carrier Group encounters.
2. Note whether opening formations create immediate overlapping pressure and whether reserves arrive as recognizable groups. Movement speeds and distant arrival separation are intentionally unchanged until Phase 3.
3. Check short Practice and a Campaign sample for the other factions for preserved lesson order, boss selection, faction identity, and unexpected capital concentration.
4. Use the debug snapshot/HUD to distinguish purchased, delivered, alive, and nearby counts; record any remainder reason or cancellation that occurs during normal play.
5. Report difficulty and delivery observations before beginning Phase 2. Boss-arrival clearing, target selection/lifetimes, nanobot behavior, and the stronger budget curve remain scheduled for later phases.

### Phase 2 implementation record — 2026-10-24

Removed the boss-start arena cleanup and its now-unused helper. Boss arrival preserves the same living ordinary enemies, their owned summons, damaged hull/shields, stationary targets, and active attacks. Existing drops and projectiles also remain. Already-purchased requests that have not launched are still cancelled at the boss transition, and ordinary pressure purchasing remains suppressed during the boss encounter.

Boss defeat still opens the first sector's gateways immediately or completes the final encounter immediately, without requiring other enemies to die. Survivors continue fighting during gateway hold, pause with the briefing, and resume when it is dismissed. Accepted gateway transfer retains its existing cleanup of the old sector. Real summon ownership cleanup and caps are unchanged.

Updated all-faction routing and gateway checks to seed damaged actors and pending attacks before the actual boss transition. Faction-specific Practice checks now accept living survivors while checking every remaining attack/summon has a valid living owner. Dead boss-owned effects must disappear immediately; full combat cleanup remains mandatory after transfer and world teardown. Grey boss-ability demonstrations move away from ordinary survivors and allow their existing warnings to finish naturally so shared warning limits do not invalidate the isolated demonstration. This changes test staging only.

#### Validation passed

- Godot 4.7.2 headless import.
- All-faction Practice/Campaign routing suite: 15,682 assertions; all four factions, damaged enemy and wreck preservation, survivor-owned warnings, reward/progression guards, immediate gateway/finale completion, exactly-once victory, and final world cleanup.
- Gateway choice suite: 997 checks; all four factions and both routes, real boss arrival/defeat, Carrier/Broodmother summons, preserved asteroids/drops/projectiles, attack pause/resume, pending-pressure cancellation, physical mouse/keyboard/controller confirmation and dismissal, and reward-free old-sector cleanup.
- Merc, Bug, and Grey regular, advanced, boss, and Practice suites; real summon caps/ownership, major warnings, tether cleanup, and menu return remain valid.
- Phase 1 purchasing/delivery suite: 26,008 assertions; no regression in whole formation delivery, timeout, pause, or stale-request cancellation.
- Final validation logs have no engine errors, warnings, or leak reports. Independent review found no actionable issues; whitespace checks passed.

No HP/damage, quantity curve, movement, target-purchasing/lifetime, or nanobot changes were made. Version remains 0.4.2; the executable and installer have not been rebuilt for Phase 2. Phases 3–6 remain unstarted and Phase 7 remains deferred.

#### Next playtest

1. Reach a boss with surviving wave enemies and an asteroid or wreck nearby. Confirm the same actors and their existing damage remain as the boss arrives.
2. Defeat the first Campaign boss while ordinary enemies remain; confirm both gateways appear immediately and the survivors continue engaging.
3. Inspect a gateway, dismiss it with Not yet/Escape/controller Back, and confirm the same fight resumes. Choose a route and verify the old battlefield is removed on transfer.
4. Defeat a Practice or final Campaign boss with survivors still alive. Confirm victory appears immediately and returns to a clean menu once.
