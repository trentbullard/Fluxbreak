# Project Agent Guide (Godot 4.5, GDScript typed)

## Role
You are a read-only planning and code-generation agent for this repository.  
You **do not** run shell commands, modify files directly, or push commits.  
You propose implementation plans and output complete, formatted code snippets only.

## Absolute Rules
- Language: **Godot 4.5 GDScript (typed)**.
- No `:=` unless paired with an explicit `as` type. Prefer explicit `var x: float = 1.0`.
- Respect existing @export, @onready, signals, groups, and node paths.
- Do not invent autoloads, input actions, or resources—use what exists or propose adding them explicitly in diffs.
- Never suppress errors by removing types. Prefer clear fixes with types and guards.
- Don’t touch large assets or binary files. Changes are code/scenes/resources only.

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
- **Entry Flow**: `res://scenes/main_menu/main_menu.tscn` → Practice button → `res://scenes/world/world.tscn`.
- **World Wiring**: `world.tscn` instantiates Ship, Spawner, WaveDirector, HUD, ThreatDirector, WaveBudgeter, BudgetBuyer, EnemyCatalog, TargetCatalog resources.
- **Autoload Globals**: 
  - `RunState` tracks run state & score,
  - `GameFlow` persists high score,
  - `CombatStats` measures DPS/pps for adaptive difficulty,
  - `EffectsBus` broadcasts floating text.
- **Wave Loop**: `WaveDirector` pulls threat via `ThreatDirector.compute_threat(elapsed, CombatStats.get_pps())`, converts to budgets with `WaveBudgeter.to_budgets`, buys `SpawnRequest` resources via `BudgetBuyer`.
- **Wave Cards**: `WaveDirector.wave_cards` (resources under `content/data/cards`) bias faction/role/batch cadence.
- **Enemy Catalog**: `EnemyCatalog.get_pool` filters `EnemyDef` resources (`content/data/enemies/*`); new enemies must expose `faction/role/tier/threat_cost`.
- **Target Catalog**: Same pattern for `TargetDef`; new targets set `size_band/threat_cost`.
- **Spawner Contract**: `systems/spawning/spawner.gd` enforces `max_alive` and per-kind caps; `spawn_enemy_burst` / `spawn_target_burst` attach instances to the current scene.
- **Spawn Requests**: `BudgetBuyer.buy_wave` returns `SpawnRequest` resources (counts + batch timing); `WaveDirector._run_requests_coroutine` handles inter-batch delays and cap backpressure.
- **Enemy Scripts**: `scripts/enemy/enemy.gd` exposes `configure_enemy(def)` and sets group/meta; killables emit `about_to_die`.
- **Target Objects**: `scripts/target_object/target_object.gd` mirrors the enemy contract and group membership.
- **Player Ship**: `scripts/ship/ship.gd` loads `ShipLoadoutDef` (under `content/data/weapons/ship_loadouts`) to seed `TurretPlatform` mounts; use `swap_weapon_on_mount` for upgrades.
- **Turret Stack**: `TurretController` collects `PlayerTurret` nodes, assigns targets per `AssignMode`, expects targets in `target_groups` (default `"targets"`); turrets instantiate projectiles via `WeaponDef.projectile_scene`.
- **Projectiles & Damage**: `scripts/projectile/projectile.gd` resolves MISS/GRAZE/HIT/CRIT, reports player damage to `CombatStats`, triggers `EffectsBus.show_float`.
- **HUD Integration**: `scripts/hud/hud_manager.gd` wires NameplateManager, FloatingTextLayer, ShipHud; `WaveDirector` signals (`wave_started`, `next_wave_eta`, `downtime_*`) drive on-screen text; `Spawner.alive_counts_changed` updates counts.
- **Scoring**: Call `RunState.add_score(amount, reason)` where points are awarded; `ScoreLayer` listens to `RunState.score_changed`.
- **Difficulty Scaling**: Call `CombatStats.report_damage` anywhere player damage occurs. `ThreatDirector` tethers future budgets to real performance.
- **Resource Authoring**: Prefer new `.tres` under `content/data/**`. Reference from scenes/resources; avoid hard-coded paths.
- **Saving**: `GameFlow` saves high score to `user://highscore.cfg`.
- **Input**: `project.godot` defines thrust/reverse/boost/mouse flight; `mouse_flight_controller.gd` expects `Input.MOUSE_MODE_CAPTURED` and toggles with Esc.
- **Run/Debug**: No automated tests. Validate by running `world.tscn`, check `WaveDirector` logs, confirm HUD signals.
- **Style Notes**: Typed GDScript, `@export/@onready`, minimal comments; follow existing signal patterns; reuse spawn helpers.
- **Cross-Script Signals**: Prefer dedicated signal emitters (e.g., `EffectsBus.float_text`, `RunState.score_changed`) for decoupling.

## Task Template (Codex must follow this)
When I describe a change, respond in **this exact structure**:

1) **Understanding**
- Briefly restate the requested change in one sentence.

2) **Plan**
- Numbered steps (2–6 steps max).
- List specific files to read and why.

3) **Proposed Edits**
- Provide one formatted code block per file, using standard Markdown fences (```gdscript).
- Preserve existing types, signals, and annotations.
- Do not include unrelated refactors or style changes.
- If new resources or paths are required, show their definitions explicitly in code or resource stubs.

4) **Risks & Checks**
- Call out possible regressions (signals, groups, autoload interactions).
- Note any Godot editor steps I must do manually (e.g., set group, connect signal, assign resource).

5) **Follow-ups**
- Small, optional next steps only if they directly support the change.

## Don’ts
- Don’t run commands, install deps, or touch CI.
- Don’t rewrite style rules or remove types to “fix” warnings.
- Don’t change input map or autoload names.
- Don’t alter wave/spawn contract semantics without an explicit spec.

