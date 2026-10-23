# Next Gameplay Milestones

Updated October 23, 2026.

Fluxbreak now has a working four-faction foundation: Machines, Mercs, Bugs, and Greys, with faction wave decks, Campaign runs, and shorter Practice encounters. The next steps should make that content easier to use and give the player more meaningful decisions during a run.

The order below preserves the recommended five-item roadmap. Items 1 and 2 are complete; **more useful points of interest are the recommended next gameplay milestone**.

## 1. Main Menu, Hangar, Play, and Camera Prototype

**Status: Complete — menu and hangar prototype implemented October 22, 2026.**

- Give Home five clear destinations: Play, Hangar, Upgrades, Settings, and Exit.
- Put pilot, ship, and starting weapon selection in the Hangar, with short pilot and ship details, Continue To Play, and Back.
- Put run setup under Play: a current-loadout summary, Change Loadout shortcut to the Hangar, faction selection, and the existing Campaign and Practice launch actions.
- Keep permanent progression under Upgrades and return to the page that opened it when the panel closes.
- Preserve the existing loadout unlock rules, saved selections, faction choices, and run behavior while reorganizing navigation.
- Keep keyboard, mouse, and controller navigation usable. Back or Escape returns from a subpage to Home.
- Prototype a passive full-screen 3D hangar using the existing ship models and placeholder pilot stand-ins, with a smooth camera moving between selection bays.
- Add Settings for master volume, fullscreen, the Animate Hangar reduced-motion option, and control instructions. The hangar animation can be disabled without affecting gameplay.

## 2. Campaign Sector Choices and Working Sector Modifiers

**Status: Complete — implemented October 23, 2026.**

- Campaign still plays two stages. Defeating its first boss opens a choice between Salvage Corridor and Assault Lane, retaining the selected faction and intended finale boss.
- The gateways have distinct shapes as well as colors: a cyan hexagon for Salvage and an amber chevron for Assault.
- Approaching a gateway opens a paused briefing with its destination, threats, opportunities, and actual numeric conditions. Entry requires the Enter this sector button, using mouse, keyboard, or controller. Escape, Back, or Not yet dismisses the briefing; leave that gateway's proximity area before approaching again to reopen it.
- Salvage Corridor grants **+25% nanobots from pickups** and **-10% player weapon base range**, with more wreck targets, repair/utility station opportunities, and tighter escort batches.
- Assault Lane grants **+15% forward and reverse top speed** against **+15% enemy maximum hull**, with more frequent existing heavy formations and a bias toward weapon and shield stations. Machines use their existing heaviest formations.
- Sector effects form a temporary stat layer, separate from purchased upgrades. The chosen conditions stay fixed when previewing or cancelling; the active layer is replaced at sector entry and cleared when the run ends or is abandoned.
- The same ship, build, and nanobots carry into the chosen final sector. Practice keeps its existing length, pacing, and single-stage structure.

The next recommended gameplay step is item 3: make more points of interest offer distinct decisions inside those sectors.

## 3. More Useful Points of Interest

**Status: Planned.**

- Add a salvage beacon: remain nearby while it extracts resources and attracts enemies.
- Add a refit station: exchange an acquired upgrade for a choice from another family.
- Add a bounty relay: accept an optional dangerous encounter for a known reward.
- Make the purpose and cost of each opportunity readable before docking or accepting it.
- Build on the existing docking and run economy rather than adding disconnected reward systems.

## 4. Special Units and Auto-Combat Counterplay

**Status: Planned.**

- Add or develop support units that visibly repair or shield nearby allies in bounded pulses.
- Add exploder units with an announced countdown and room to react through positioning.
- Add protector units that temporarily shield allies, with an exposed recovery window.
- Keep counterplay appropriate to auto-combat: positioning, range, movement, build choices, and attack timing should matter without requiring manual aim.
- Players need practical influence over those responses through positioning, range, or targeting priorities. A healer should create a decision rather than only extending the fight.
- Preserve clear tells and readable recovery or escape opportunities when these units appear together.

## 5. Ammo Specialization and Resistances

**Status: Planned.**

- Introduce ammo or damage specialization that gives weapons distinct strengths and useful build synergies.
- Start with recognizable shield disruption, damage over time, and splash effects, with a small upgrade family for each.
- Introduce corresponding effects on selected enemy weapons, then add defensive upgrades for the player once the sources and effects are readable.
- Add enemy resistances or vulnerabilities that make those choices meaningful.
- Show the relevant strengths and resistances clearly enough for players to make informed choices.
- Start with a small, understandable set of interactions and expand after the basic system works in normal runs.

## Deferred Work

Music, pilot artwork, and story/lore expansion remain deferred while these gameplay and navigation milestones are developed. They can be revisited once the central run decisions, combat readability, and build choices are stronger.

The fifth faction and further progression variants remain separate backlog items. The four existing factions provide the content foundation for this roadmap.
