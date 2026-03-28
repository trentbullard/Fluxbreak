# Fluxbreak

Fluxbreak is a roguelike space auto-battler built in Godot 4.5. You pilot a ship through escalating combat waves, collect nanobots from the wreckage, and dock at stations to shape a run with new weapons and upgrades.

The game is built around auto-combat rather than manual aiming. Your job is to stay alive, hold a readable combat line, and stack synergies that carry deeper into the run. The intended feel is dark futurepunk: sharp silhouettes, neon accents, industrial grime, crunchy combat feedback, and a clean HUD that stays legible when the screen gets busy.

## Core Pillars

- Auto-combat with hit/miss-driven weapon resolution
- Synergy-first builds over raw stat stacking
- Wave-based pressure with quick battlefield reads
- 3D space combat with retro-leaning readability
- Performance and clarity prioritized over spectacle
- Data-driven content and modular systems

## What You Do In A Run

1. Pick a pilot from the main menu and launch a practice run.
2. Fly through a 3D combat space while your turrets auto-acquire and fire on targets in range.
3. Survive enemy waves, destroy hostile ships, and collect nanobots.
4. Dock with points of interest such as the Weapons Platform, Shield Array, and Repair Depot.
5. Spend nanobots on run-defining upgrades or new weapons, then push into the next wave.
6. Chase a higher score, a deeper wave count, and new pilot unlocks.

## Current Content Snapshot

- Pilots include `Rookie` and `Ace`
- Ships include `Fighter Mk1` and `Heavy Bruiser`
- Weapons currently include pulse, laser, and drone-based loadout pieces
- Upgrade families cover hull, shields, targeting, systems, salvage, and thrusters
- Enemy content includes machine and merc units, with wave-directed spawning and scaling

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

- Engine: Godot 4.5
- Language: typed GDScript
- Project version: `0.1.3`

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
- 8 weapon cap
- configure boss into stages

## License

Fluxbreak is proprietary and `LICENSE.txt` is authoritative. All rights are reserved unless explicit written permission is granted by the copyright holder.
