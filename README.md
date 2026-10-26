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

1. Prepare your pilot, ship, and starting weapon in Hangar, then open Play to choose a faction and launch Campaign for a two-stage run or Practice for short introduction waves and a boss. Random chooses one faction for the entire run.
2. Fly through a 3D combat space while your turrets auto-acquire and fire on targets in range.
3. Survive enemy waves, destroy hostile ships, and collect nanobots.
4. Dock with points of interest such as the Arms Factory, Shield Array, and Repair Hangar.
5. Spend nanobots on run-defining upgrades or new weapons, then push into the next wave.
6. In Campaign, defeat the first boss and choose the Salvage Corridor or Assault Lane before entering the final sector. Review its threats, opportunities, and conditions, then explicitly confirm entry.
7. Chase a higher score, a deeper wave count, and new pilot unlocks.

## Current Content Snapshot

- Home opens Play, Hangar, Upgrades, Settings, or Exit. Play shows the current loadout and offers Change Loadout; Hangar offers selection details and Continue To Play. Back or Escape returns to Home, and closing Upgrades returns to the page that opened it.
- The passive 3D hangar displays existing ships and placeholder pilot stand-ins, with a smooth camera moving between selection bays. Settings includes master volume, fullscreen, control instructions, and Animate Hangar, which can be disabled to reduce motion.
- Campaign keeps two played stages. Its first boss opens a cyan hexagonal Salvage Corridor gateway and an amber chevron Assault Lane gateway. The briefing supports mouse, keyboard, and controller confirmation; Escape, Back, or Not yet returns to flight. Your faction, ship, upgrades, and nanobots carry forward. Practice retains its existing short encounter.
- Enemies and bosses use occasional lateral spacing pulses away from the nearest crowded ship or target. Tight overlaps use stable escape directions; committed attacks retain their original movement. POIs are excluded from spacing.
- Pilots include `Rookie`, `Ace`, and `Technician`
- Ships include `Fighter Mk1`, `Heavy Bruiser`, and `Drone Carrier`
- Weapons currently include pulse, laser, and drone-based loadout pieces
- Upgrade families cover hull, shields, targeting, systems, salvage, and thrusters
- Enemy content includes Machines, Mercs, Bugs, and Greys, with faction wave decks, bosses, and wave-directed scaling
- Mercs have five regular ship classes, ten wave cards, Contract Enforcer, and Vanguard Flagship. Merc Practice teaches all five classes and draws one boss; Campaign uses Enforcer at the gateway and Flagship at the finale.
- Bugs have five regular organisms and ten wave cards. Bug Practice teaches the full hive and draws one boss; Campaign uses Nestbreaker Matron at the gateway and The First Queen at the finale.
- Greys have five regular ship classes and ten wave cards. Grey Practice teaches the full fleet and draws one boss; Campaign uses The Witness at the gateway and The Veiled Mind at the finale.

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
- Project version: `0.5.4.4`

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

See the [ordered gameplay roadmap](docs/plans/next_gameplay_milestones.md). Menu/Hangar navigation and Campaign sector choices are complete; more useful points of interest are the recommended next milestone.

- [x] Main Menu, Hangar, Play, and passive camera prototype.
- [x] Campaign sector choices with working temporary sector modifiers.
- [ ] Add salvage beacons, refit stations, and bounty relays.
- [ ] Expand special units and readable auto-combat counterplay.
- [ ] Add ammo/damage specialization and resistances.
- [ ] Add progression variants for Mercs, Bugs, and Greys.
- [ ] Define and implement the fifth faction, including its ships, bosses, and wave deck, once the first four factions' combat identities are stable.

Music, pilot artwork, and story/lore expansion remain deferred.

## License

Fluxbreak is proprietary and `LICENSE.txt` is authoritative. All rights are reserved unless explicit written permission is granted by the copyright holder.
