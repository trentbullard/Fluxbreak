# Project Agent Guide (Godot 4.5, GDScript typed)

## Absolute Rules
- Language: **Godot 4.5 GDScript (typed)**.
- No `:=` unless paired with an explicit `as` type. Prefer explicit `var x: float = 1.0`.
- Respect existing @export, @onready, signals, groups, and node paths.
- Do not invent autoloads, input actions, or resources—use what exists or propose adding them explicitly in diffs.
- Never suppress errors by removing types. Prefer clear fixes with types and guards.
- Don’t touch large assets or binary files. Changes are code/scenes/resources only.
- Try to use distance_squared_to over distance_to whenever possible to prevent square root calls

## Scope & Context Policy
Include (read/use for context):
- `res://scripts/**`
- `res://systems/**`
- `res://content/data/**` (cards, enemies, targets, loadouts)
- `res://scenes/world/world.tscn`, `res://scenes/main_menu/main_menu.tscn`
Exclude:
- `res://assets/**`, `res://art/**`, `res://audio/**`, `**/.import/**`, `addons/**` (unless asked)
If context is too large, ask for specific paths.

## Repo Map (authoritative)
- **Engine**: Godot 4.5; typed GDScript; autoload singletons in `project.godot`.
