# Systems

This document describes the cross-system gameplay principles that govern run pressure, player scaling, and long-term progression. Systems should remain modular, data-driven, and tunable without requiring deep rewrites when balance evolves.

Detailed design intent for specific system families lives in dedicated files:

- [Wave System](./wave_system.md)
- [Upgrade System](./upgrade_system.md)

## Cross-System Guardrails

- Prefer systems that stay readable under heavy combat load and remain easy to tune in isolation.
- Preserve build identity through interacting layers instead of relying on flat stat inflation.
- Favor authored-feeling pressure and escalation over noisy randomness or opaque adaptation.
- Keep progression data-driven so pilots, ships, factions, upgrades, and modifiers can combine without bespoke code paths.
- New systems should strengthen target priority, positioning, and synergy evaluation rather than bypass them.

## Stat Scope And Propagation

Systemic upgrades may apply to the player, minions, or both, but scope should always be explicit and centrally resolved.

- The run or ship upgrade state should remain the source of truth for acquired modifiers.
- Combat subsystems should consume filtered local projections of that state rather than duplicating ownership rules.
- Prefer local effective-stat views over scattered conditional checks inside behavior code.
- Add new stat consumers by extending stat projection layers, not by hard-coding upgrade exceptions into individual behaviors.
- Minions should inherit the build's identity without turning into opaque parallel actors that bypass readability.
- Minion scaling should emphasize command reach, uptime, role definition, and tactical pressure before invisible DPS inflation.

## Meta-Progression

Outside active runs, the player gains access to persistent progression through meta-currency earned over time.

Meta progression should improve long-term comfort without replacing run skill.

### Core Philosophy

Meta progression should never invalidate build decisions inside a run.

It should provide gentle baseline improvements that:

- reduce frustration
- reward continued play
- create long-term goals

### Example Meta Upgrade Targets

- nanobot pickup rate
- pickup radius
- baseline speed
- baseline damage output
- shield recovery
- hull durability
- repair efficiency
- starting resources
- upgrade economy improvements

### Design Constraint

Meta bonuses should remain meaningful but modest.

A skilled player with weak meta progression should still outperform a weak player with heavy meta investment.

### Long-Term Goal

Meta progression should support replay longevity without making early runs trivial or late runs solved.
