# Vision Guardrails

These vision files describe the intended finished game and are meant to guide design and implementation choices.
They are not strict feature checklists or promises about current build completeness.

When using them to make changes:
- preserve the direction, tone, and system shape
- do not treat every listed example as mandatory literal content
- prefer flexible implementations that can grow toward the target state without deep rewrites

- **Core Loop:** Auto-combat (no aiming, just hit/miss calculations), synergies > raw stats, wave-based pressure, quick reads.
- **Aesthetic:** Dark futurepunk — high-contrast UI, neon accents, industrial grime, minimal bloom, readable silhouettes.
- **Feel:** 3D space, retro-leaning readability (16-bit sensibility in 3D), crunchy SFX, clean HUD.
- **Scope Priorities:** Performance > clarity > spectacle. Modularity and data-driven defs.
- **Camera & UX:** Clarity under chaos; enemy telegraphing; legible projectiles; screen-safe color palette.

## Design Rubric (use before merging features)

- Does it strengthen **auto-battler synergies**?
- Does it preserve **readability at scale** (50+ enemies, 6-8 turrets)?
- Does it fit **dark futurepunk** (materials, palette, SFX tone)?
- Is it **data-driven** (defs/resources), not hard-coded?
- Can it run on **mid-tier GPUs** without choking?

## Supporting Design Files

- [gameplay.md](./gameplay.md) — run structure and progression
- [pilots.md](./pilots.md) — pilot identities and intended builds
- [factions.md](./factions.md) — enemy philosophies and combat roles
- [lore.md](./lore.md) — narrative foundation
- [systems.md](systems.md) — progression economy and mechanics
