# Fluxbreak

Fluxbreak is a roguelike space auto-battler built in Godot 4.7.2. You pilot a ship through escalating combat waves, collect nanobots from the wreckage, and dock at stations to shape a run with new weapons and upgrades.

The game is built around auto-combat rather than manual aiming. Your job is to stay alive, hold a readable combat line, and stack synergies that carry deeper into the run. The intended feel is dark futurepunk: sharp silhouettes, neon accents, industrial grime, crunchy combat feedback, and a clean HUD that stays legible when the screen gets busy.

## Core Pillars

- Auto-combat with hit/miss-driven weapon resolution
- Synergy-first builds over raw stat stacking
- Wave-based pressure with quick battlefield reads
- 3D space combat with retro-leaning readability
- Performance and clarity prioritized over spectacle
- Data-driven content and modular systems

## What You Do In A Run

1. Prepare your pilot, ship, and starting weapon in Hangar, then open Play. Campaign chooses one random faction for its two-stage run; Practice offers a faction selector for short introduction waves and a boss. Each run retains its faction throughout.
2. Fly through a 3D combat space while your turrets auto-acquire and fire on targets in range.
3. Survive enemy waves, destroy hostile ships, and collect nanobots.
4. Dock with points of interest such as the Arms Factory, Shield Array, and Repair Hangar.
5. Spend nanobots on run-defining upgrades or new weapons, then push into the next wave.
6. In Campaign, defeat the first boss and choose the Salvage Corridor or Assault Lane before entering the final sector. Review its threats, opportunities, and conditions, then explicitly confirm entry.
7. In Campaign, chase a higher score, a deeper wave count, unlocks and Flux Anchors for meta upgrades. Practice grants no persistent rewards, stats, score records, progression or unlocks.

## Current Content Snapshot

- Home opens Play, Hangar, Upgrades, Information, Settings, or Exit. Play shows the current loadout and offers Change Loadout; Hangar offers selection details and Continue To Play. Back or Escape returns to Home, and closing Upgrades returns to the page that opened it.
- The passive 3D hangar displays existing ships and placeholder pilot stand-ins, with a smooth camera moving between selection bays. Settings includes master volume, fullscreen, control instructions, and Animate Hangar, which can be disabled to reduce motion.
- Campaign keeps two played stages. Its first boss opens a cyan hexagonal Salvage Corridor gateway and an amber chevron Assault Lane gateway. The briefing supports mouse, keyboard, and controller confirmation; Escape, Back, or Not yet returns to flight. Your faction, ship, upgrades, and nanobots carry forward. Practice retains its existing short encounter.
- Enemies and bosses use occasional lateral spacing pulses away from the nearest crowded ship or target. Tight overlaps use stable escape directions; committed attacks retain their original movement. POIs are excluded from spacing.
- Current prototype pilot profiles are `Rookie`, `Ace`, and `Technician`. The five planned narrative characters are Trey, Laura, Roman, The Captain and Cami; their character presentation, dialogue and intros remain future work.
- Ships include `Fighter Mk1`, `Heavy Bruiser`, and `Drone Carrier`
- Weapons currently include pulse, laser, particle-beam and drone-based loadout pieces
- Upgrade families cover hull, shields, targeting, systems, salvage, and thrusters
- Enemy content includes Machines, Mercs, Bugs, and Greys, with faction wave decks, bosses, and wave-directed scaling
- Mercs have five regular ship classes, ten wave cards, Contract Enforcer, and Vanguard Flagship. Merc Practice teaches all five classes and draws one boss; Campaign uses Enforcer at the gateway and Flagship at the finale.
- Bugs have five regular organisms and ten wave cards. Bug Practice teaches the full hive and draws one boss; Campaign uses Nestbreaker Matron at the gateway and The First Queen at the finale.
- Greys have five regular ship classes and ten wave cards. Grey Practice teaches the full fleet and draws one boss; Campaign uses The Witness at the gateway and The Veiled Mind at the finale.
- Enemy purchasing/delivery and late-wave/second-sector budgets support overlapping pressure. Boss arrival preserves the battlefield; surviving minions persist after their summoner dies, and boss defeat advances the run immediately.
- Nanobot reward growth is reduced. Separate swarms decay over 120 active gameplay seconds and use larger bright particles with dark outlines. Merc, Bug and Grey attack fields avoid redundant warning meshes; Sporeling clouds use static sprites and independent poison ticks.
- Flight Camera settings are available from the main menu and pause while retaining the original follow camera. Pause also shows stats, map/faction modifiers and purchased upgrades; stage helper text remains there after fading from gameplay.
- Compact enemy/target nameplates combine faction/name with blue shield and red hull sections and shrink with distance. Information uses reusable rotating previews and details for discovered enemies and eligible weapons/ships; pilots currently have placeholder icons.

## Controls

### Keyboard and Mouse

- Mouse: pitch and yaw
- `W`: thrust
- `S`: reverse thrust
- `Q` / `E`: roll left / right
- `Shift`: boost
- `R`: hull repair
- `Esc`: pause

### Controller

- Left stick: pitch and yaw
- Triggers: thrust and reverse thrust
- Shoulder buttons: roll
- South face button: boost
- East face button: hull repair
- Start/Menu: pause

Combat targeting and firing are handled automatically by the ship's weapon systems.

## Tech

- Engine: Godot 4.7.2
- Language: typed GDScript
- Project version: `0.5.6.1`

## Running The Project

This repo expects a local Godot executable exposed through the `GODOT_EXE` environment variable.

### Open The Project

```powershell
& $env:GODOT_EXE --path .
```

### Validate Imports

```powershell
& $env:GODOT_EXE --headless --path . --import --quit
```

### Windows Debug Export

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\export_windows.ps1 -GodotExe $env:GODOT_EXE -BuildType debug
```

## Project Direction

Fluxbreak is aiming for readable chaos. The guiding rubric for new work is simple:

- strengthen auto-battler synergies
- preserve readability with large enemy counts and multiple turrets
- stay inside the dark futurepunk tone
- prefer data-driven content over hard-coded behavior
- keep the game fast on mid-tier hardware

## TODO

See the [roadmap and completion checklist](docs/plans/next_gameplay_milestones.md) for current progress, open decisions and the full backlog. Updated October 27, 2026.

The next intended public milestone is a **polished Steam Playtest build**, after the owner is happy with polish and a selected set of small enhancements. The owner's three goals for a complete game are adaptive stage music, five characters with dialogue, and emotionally compelling character intro animations/montages. Those goals are tracked separately from the initial Playtest scope.

- [x] Four factions, Campaign sector choices/modifiers, wave-pressure improvements and Practice progression isolation.
- [x] Main-menu/Hangar overhaul, Information previews/details, flight-camera settings, pause modifier history and compact distance-scaled nameplates.
- [ ] Prepare and externally test a polished Steam Playtest candidate, including onboarding, full-run reliability and late-game performance on ordinary hardware.
- [ ] Create adaptive stage music, exploring several 3–4 minute loops at different BPMs/intensities and transitions in both directions.
- [ ] Implement the five narrative characters and their dialogue interactions.
- [ ] Create character intro animations/montages that establish relationships and emotional motivation.
- [ ] Expand in-run audio/performance settings, player abilities and a purchasable single-use or activated nanobot magnet.
- [ ] Add upgrade reroll/ban tools, potentially through meta purchases, plus more cross-weapon upgrades and build diversity.
- [ ] Expand POIs, ammo specialization, faction-stage modifiers, and elite/special enemies with readable indicators.
- [ ] Implement the fifth faction and further faction progression variants.
- [ ] Review faction balance and the incentive to restart Campaign for an easier faction to farm.
- [ ] Explore encrypted progression/high-score storage and a dedicated save folder with safe migration of existing data.
- [ ] Consider improved self-made, commissioned or licensed ship/enemy/weapon/pilot assets where useful.

Self-authored music and presentation remain the preferred first approach. Small prototypes will establish a manageable style; commissioning or buying assets is optional. The wider backlog does not automatically block Steam publishing.

## License

Fluxbreak is proprietary and `LICENSE.txt` is authoritative. All rights are reserved unless explicit written permission is granted by the copyright holder.
