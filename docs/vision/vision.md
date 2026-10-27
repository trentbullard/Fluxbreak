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

## Completion Direction and the Next Public Milestone

Updated October 27, 2026. The next intended public milestone is a polished Steam Playtest build once the owner is happy with polish and selected small enhancements. External first-run usability, camera comfort, combat readability, reliable progression and late-game performance are central checks. This is a planned milestone; no Steam submission or publication is recorded as complete.

The owner's three goals for Fluxbreak to feel like a complete game are:

- **Adaptive stage music:** explore several approximately 3–4 minute loops at different BPMs and intensities, transitioning up and down with sustained gameplay intensity. Menu music already exists; stage music and its transition policy remain planned.
- **Five characters and dialogue:** implement Trey, Laura, Roman, The Captain and Cami with distinct relationships and pilot/crewmate interactions. The runtime Rookie/Ace/Technician profiles are prototypes; Aggy remains the supporting AI and Ghost an optional later concept.
- **Emotional character intros:** use animations or montages to make station life, the capture and the rescue pursuit meaningful from each character's perspective.

Start with a small self-authored music and character-presentation prototype. Limited animation, shared scenes, simple artwork and deliberate sound/text can establish the style before expanding it. Commissions or licensed assets remain optional choices rather than assumed production requirements.

The [central roadmap](../plans/next_gameplay_milestones.md) tracks these completion goals separately from Playtest readiness and the wider backlog: a fifth faction, utility/ship abilities, reroll/ban tools, in-run settings, asset improvements, POIs, ammo, cross-weapon upgrades, balancing, faction-stage modifiers, elites and save protection. These are not all automatic Steam publishing prerequisites. Preserve the scope explicitly chosen for each implementation task.

## Supporting Design Files

- [gameplay.md](./gameplay.md) — run structure and progression
- [pilots.md](./pilots.md) — pilot identities and intended builds
- [factions.md](./factions.md) — enemy philosophies and combat roles
- [lore.md](./lore.md) — narrative foundation
- [systems.md](systems.md) — progression economy and mechanics
- [upgrade_system.md](./upgrade_system.md) — build diversity and future upgrade tools
- [Roadmap and completion goals](../plans/next_gameplay_milestones.md) — current status, Playtest milestone and backlog
- [Production checklist](../release/PRODUCTION_CHECKLIST.md) — build, distribution and external QA checks
