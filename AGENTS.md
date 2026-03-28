# Project Agent Guide (Godot 4.5, GDScript typed)

## Absolute Rules
- Language: **Godot 4.5 GDScript (typed)**.
- No `:=` unless paired with an explicit `as` type. Prefer explicit `var x: float = 1.0`.
- Respect existing @export, @onready, signals, groups, and node paths.
- Do not invent autoloads, input actions, or resources—use what exists or propose adding them explicitly in diffs.
- Never suppress errors by removing types. Prefer clear fixes with types and guards.
- Don’t touch large assets or binary files. Changes are code/scenes/resources only.
- Try to use distance_squared_to over distance_to whenever possible to prevent square root calls
- Exported variables should have brief documentation comments
- Consider updating vision docs when broad changes are made

## Scope & Context Policy
Include (read/use for context):
- `res://docs/vision/vision.md` (general game vision/vibe/mood with links to specific vision files)
- `res://scripts/**` (node attached and autoload scripts for node logic/controls)
- `res://systems/**` (scripts for systems logic e.g. stats, spawning, mounts, wave director, catalogs)
- `res://content/defs/**` (definitions for game objects/configurations)
- `res://content/data/**` (definitions for the static game resources)
- `res://scenes/**` (the .tscn files that contain the nodes, scripts, and resources used to load the game)
Exclude:
- `res://assets/**`, `res://build/**` (unless asked)

If context is too large, ask for specific paths.

If other files are needed, ask with justifications.

## Repo Map (authoritative)
- **Engine**: Godot 4.5; typed GDScript; autoload singletons in `project.godot`.

## Local Godot CLI (required for validation/builds)
- Configure `GODOT_EXE` in the user environment to the local Godot console executable.
- Keep repo config machine-agnostic: `.vscode/settings.json` should use `${env:GODOT_EXE}`.
- Do not assume `godot` is in PATH. Use `GODOT_EXE` or pass `-GodotExe`.
- Validation/import command:
  `& $env:GODOT_EXE --headless --path . --import --quit`
- Windows export script (existing project script):
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release\export_windows.ps1 -GodotExe $env:GODOT_EXE -BuildType debug`
- Example one-time setup (PowerShell):
  `setx GODOT_EXE "C:\path\to\Godot_v4.5-stable_mono_win64_console.exe"`

## Blender Policy
- When working on Blender assets, scenes, or mesh/material tasks, always use the `blender` MCP server (via adapter) first before guessing or writing abstract instructions.
- For adapter setup, startup checks, and the required Blender MCP workflow, read `scripts/tools/blender/blender.md` before proceeding.
- Prefer making concrete Blender changes through MCP tools when possible.
- When generating Blender Python, keep scripts modular, readable, and safe to rerun.

## REAPER Policy
- When working on REAPER sessions, tracks, FX, MIDI, automation, or arrangement tasks, always use the `reaper` MCP server (via adapter) first before guessing or writing abstract instructions.
- For adapter setup, startup checks, and the required REAPER MCP workflow, read `scripts/tools/reaper/reaper.md` before proceeding.
- Prefer making concrete REAPER changes through MCP tools when possible.
- When generating REAPER automation code, keep scripts modular, readable, and safe to rerun.
