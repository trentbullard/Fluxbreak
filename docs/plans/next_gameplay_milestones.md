# Fluxbreak Roadmap and Completion Goals

Updated October 27, 2026.

This is the central checklist for current progress, the next Steam Playtest milestone, the owner's goals for a complete game, and the wider backlog. Linked vision files describe the intended experience; implementation records describe what has actually shipped. Unchecked items are plans, not promises of a release date or requirements imposed by Steam.

## Next Milestone: A Polished Steam Playtest Build

The intended next public milestone is Steam Playtest once the owner is happy with polish and a selected set of small enhancements. Choose that small scope explicitly before implementation. The entire final vision and expansion backlog do not have to be finished for this milestone. No Steam page, Playtest configuration, submission or release is recorded as complete here.

- [ ] Observe unfamiliar players learning flight, automatic targeting, salvage collection, docking and upgrade purchases without coaching; improve guidance where they struggle.
- [ ] Check camera comfort and keyboard/mouse/controller usability through menus and a complete run.
- [ ] Check combat readability and frame times on ordinary hardware, including late Campaign encounters with roughly 100–200 enemies and overlapping attacks/drops. Small component probes do not establish full-game performance.
- [ ] Validate complete Campaign progression, gateways, victory/death, return to menu, and persistent progression after restarting the game. Practice must remain excluded from persistent rewards, stats and unlocks.
- [ ] Select and finish the small enhancements to include in the candidate; do not silently treat every backlog item below as part of it.
- [ ] Prepare representative screenshots, gameplay footage, an accurate Coming Soon page and a way to collect player feedback.
- [ ] Configure and test Steam distribution/Playtest when the candidate is ready, following the [production checklist](../release/PRODUCTION_CHECKLIST.md).
- [ ] Use feedback on comprehension, fairness, enjoyment, second-run interest and hardware performance to choose the next work.

## Current Implemented Foundation

These items record implemented features. They do not mean every balance, accessibility or performance question is resolved.

- [x] Main Menu, Hangar and Play navigation, passive hangar camera and the original Fluxbreak title/logo.
- [x] Four factions with regular enemies, bosses, wave decks and short Practice encounters: Machines, Mercs, Bugs and Greys.
- [x] Campaign chooses one random faction for its two-stage run. Practice retains its faction selector.
- [x] Practice grants no Flux Anchors and contributes no persistent stats, score records, progression or unlocks.
- [x] First Campaign boss opens distinct Salvage Corridor and Assault Lane gateways with explicit paused briefing/confirmation, cancellation and working temporary route modifiers.
- [x] Boss arrival preserves existing enemies and stationary targets; boss defeat advances gateways/victory immediately. Confirmed sector transfer cleans the previous battlefield.
- [x] Corrected wave purchasing, mixed package accounting and prompt formation delivery; late-wave geometric quantity scaling and faster second-sector growth.
- [x] Lightweight lateral enemy spacing without physical body collision; independent approaches remain in use.
- [x] Faction durability/attack tuning, evasive tier-one flight and minions that survive their source's death without living/lifetime summon caps.
- [x] Shared bounded attack-field presentation for Mercs, Bugs and Greys; no redundant warning meshes or floating 3D warning text. Sporeling contact clouds use static inner sprites at 25% opacity and unchanged 50% boundary opacity, with independent poison ticks.
- [x] Reduced nanobot reward growth; independent swarms decay over 120 active gameplay seconds. Enlarged bright particle swarms and dark particle outlines improve visibility without merging drops.
- [x] Flight Camera settings from the main menu and pause, retaining the original follow-camera movement.
- [x] Pause stats and separate map/faction/purchased-upgrade sections; stage helper text fades from gameplay after about 30 seconds and remains at the top of pause.
- [x] Compact faction/name durability plates with a blue shield upper half, red hull lower half and distance-based shrinking.
- [x] Information panels for enemies, weapons, ships and pilots. Discovered enemies and eligible weapons/ships use reusable rotating previews and details pages; pilot entries remain placeholders.
- [x] Debug HUD processing disabled while retaining its implementation for later use.

For the wave/salvage work, Phases 1, 2, 4 and 6 are implemented; Phases 3 and 5 were explicitly skipped after playtesting; Phase 7 remains deferred and disabled. See [the implementation record](wave_salvage_enhancements.md). This roadmap does not reactivate the skipped phases.

## Three Goals for the Complete Game

These are the owner's October 27 priorities for making Fluxbreak feel complete. They replace the older blanket deferral of music, characters and story presentation. Their production scope can grow after a small prototype; they are not all prerequisites for the initial Playtest.

### 1. Stage Music That Follows Combat Intensity

Menu music exists. Adaptive stage music remains planned.

- [ ] Make an initial self-authored stage loop, then explore several approximately 3–4 minute loops with different BPMs and intensity levels.
- [ ] Prototype transitions both toward higher intensity and back toward calmer music as gameplay changes.
- [ ] Define a readable, stable intensity signal and prevent rapid switching during short fluctuations. Enemy count alone may not reflect actual danger; test candidate signals before settling the policy.
- [ ] Explore musically compatible phrase boundaries, short transitions or fades between loops. The number of tracks, BPMs, transition method and boss treatment remain open design choices.
- [ ] Preserve combat cues and dialogue intelligibility, with usable music/audio controls.
- [ ] Playtest the music over ordinary waves, intense overlapping attacks, downtime, bosses and sector transitions.

### 2. Five Characters and Dialogue Interactions

The current playable profiles are Rookie, Ace and Technician. The planned narrative cast is Trey, Laura, Roman, The Captain and Cami, with Aggy as the supporting AI. Ghost remains an optional later concept outside the five-character completion goal.

- [ ] Implement the five characters' identities, playable presentation and appropriate unlock/loadout integration.
- [ ] Map prototype profiles to the final roster deliberately; no one-to-one mapping or migration has been decided.
- [ ] Implement the pilot/remaining-crewmate dialogue pairings and reactive interactions described in [pilots](../vision/pilots.md) and [lore](../vision/lore.md).
- [ ] Give each character a recognizable relationship, voice in the writing and emotional reason to pursue the rescue.
- [ ] Keep dialogue readable during combat, avoid excessive repetition and make interruption/skip behavior deliberate. Voice acting is not a committed requirement.

### 3. Emotional Character Intro Animations or Montages

- [ ] Storyboard the selected character's station life, crew relationships, attack/capture and urgent departure.
- [ ] Make a short self-authored first pass for one character using a manageable visual style: stills, limited motion, camera work, existing models, text and sound are viable starting tools.
- [ ] Test whether it creates attachment and motivation before expanding the technique to all five characters.
- [ ] Reuse shared scenes and assets while preserving each pilot's emotional perspective and dialogue pairing.
- [ ] Make repeat viewing and skipping intentional; intro presentation must not disrupt run controls or progression.

### Creative Production Approach

The owner's preference is to make the game personally, including its music and presentation. Artistic confidence and production effort are open concerns, not a decision to outsource. Start with one small music prototype and one character's intro/dialogue slice; judge the emotional effect and consistency in the actual game. Commissioned work or licensed assets remain optional tools if a specific gap justifies them. There is no purchasing commitment or requirement for realistic art, elaborate cinematics or full voice acting.

## Wider Backlog

These are desired enhancements and open design tasks. They do not automatically block Steam publishing or belong in the first Playtest. Some extend systems already present. Select and scope each task before implementation; costs, controls and exact balance values remain undecided unless already authored.

| Status | Item | Intended work / current distinction |
| --- | --- | --- |
| [ ] | Fifth faction | Define its identity, ships, bosses and wave deck after the existing factions are sufficiently stable. |
| [ ] | Save protection and location | Explore encryption for `highscore.cfg` and a dedicated application folder outside the default `%APPDATA%\Godot\app_userdata\Fluxbreak`. The file also holds progression, selections, currency and statistics; preserve them through any format/path migration. Local encryption is a tampering deterrent, not trusted score verification, and moving the folder adds no integrity guarantee. |
| [ ] | Purchasable nanobot magnet | Explore a single-use purchase or activated collection ability. Keep this distinct from existing passive magnet/collection upgrades, and preserve collection decisions. |
| [ ] | Upgrade reroll and ban | Add ways to reroll offerings or exclude choices, possibly purchased/unlocked through meta upgrades. Define purchase model, limits, ban duration/scope and UI feedback before implementation. |
| [ ] | Expanded in-run settings | Add accessible audio and performance/quality controls while paused. Main-menu master volume/fullscreen/hangar motion and in-run camera settings already exist. |
| [ ] | More player abilities | Explore additional active abilities, including ship-specific identities and clear costs/cooldowns. |
| [ ] | Model/art improvements | Optionally replace ship, enemy, weapon and pilot models with improved self-made, commissioned or licensed assets. Preserve readable silhouettes and performance; replacing every model is not a release requirement. |
| [ ] | More points of interest | Extend docking decisions with opportunities such as salvage beacons, refit stations and bounty relays. |
| [ ] | Ammo types | Develop readable weapon/ammo specialization, compatible upgrades and any enemy/player defensive interactions in a scoped balance pass. |
| [ ] | More upgrades and build diversity | Add useful cross-weapon stat modifiers and interactions that support multiple viable builds. Show scope and effects clearly. |
| [ ] | Balance and faction-farming review | Preserve a meaningful fresh-start challenge and satisfying meta progression. Investigate Campaign restart fishing for easier factions/rewards before selecting a remedy. |
| [ ] | Faction-stage modifiers | Add faction-dependent conditions with clear indicators and descriptions. Existing Salvage/Assault route modifiers work; the faction modifier layer currently supplies no active effects. |
| [ ] | Elite and special enemies | Extend existing support/summoning behaviors with distinct elite/special roles, modifiers and readable indicators. New generic elite/affix effects remain planned. |

## Balance Observations to Revisit

The owner's current playtest observation is that a fresh Rookie/Fighter run feels challenging through about wave 10, while an Ace/Heavy Bruiser with many meta upgrades delivers a power fantasy. This is useful direction, not independent proof that the balance is settled.

Campaign's random faction can encourage restarting until an easier matchup appears, potentially making progression farming more efficient than accepting varied runs. Compare outcomes and rewards by faction and progression level. Decide whether encounter/reward balance or another policy needs adjustment after measuring the issue; do not assume random selection alone solves it. Practice remains progression-free, and this concern does not authorize restoring Campaign faction selection or adding a restart penalty.

## Retained Gameplay Design Notes

### Additional POIs

- Salvage beacon: remain nearby while it extracts resources and attracts enemies.
- Refit station: exchange an acquired upgrade for a choice from another family.
- Bounty relay: accept an optional dangerous encounter for a known reward.
- Show purpose, cost and reward before commitment; build on the existing docking/economy flow.

### Special Units and Counterplay

Merc shield support, escort carriers, Bug brood production and Grey coordination already exist. Expand those foundations where useful with repair/shield pulses, announced exploders or protectors with recovery windows. Positioning, range, movement, build choices and readable timing must provide practical responses within automatic combat. Indicators must stay legible in crowded late waves.

### Ammo and Upgrade Specialization

Shield disruption, damage over time and splash are possible starting interactions. Keep player upgrades, enemy ammo effects and defensive options understandable, then test a small set before broad expansion. Preserve flexible builds rather than requiring one correct counter for each faction.

## Related Records

- [Vision guardrails](../vision/vision.md)
- [Pilot identities](../vision/pilots.md) and [narrative foundation](../vision/lore.md)
- [Gameplay](../vision/gameplay.md), [systems](../vision/systems.md), [upgrades](../vision/upgrade_system.md) and [factions](../vision/factions.md)
- [Wave pressure and salvage implementation](wave_salvage_enhancements.md)
- [Faction tuning history](faction_balance_pass.md)
- [Camera settings](camera_settings.md)
- [Production and Playtest checklist](../release/PRODUCTION_CHECKLIST.md)
