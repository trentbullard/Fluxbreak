# Fluxbreak Production Checklist

Updated October 27, 2026. Use this checklist when preparing a public build. Unchecked boxes are verification tasks, not evidence that a feature is broken or has never been tested. Review them for the actual candidate being distributed.

The next intended public milestone is Steam Playtest after polish and a selected set of small enhancements. Adaptive stage music, five characters/dialogue and emotional character intros are the owner's complete-game goals. Their full production scope and the wider backlog are tracked in the [central roadmap](../plans/next_gameplay_milestones.md); they are not all requirements for the first Playtest. No Steam setup, submission or release is marked complete by this documentation update.

## Playtest Candidate and Steam Preparation

- [ ] Define the candidate's included features, selected small enhancements, known limitations and deferred work.
- [ ] Watch unfamiliar players learn movement, automatic combat, salvage, docking and upgrades without coaching; improve the confusing steps.
- [ ] Check camera comfort, keyboard/mouse controls, controller navigation and readable text at supported display sizes.
- [ ] Record full-game CPU/GPU frame times on ordinary hardware during late waves with roughly 100–200 enemies, attacks and drops. Investigate frame spikes and readability failures; isolated component probes are supporting evidence only.
- [ ] Test a fresh progression profile and an invested loadout across factions. Record understandable deaths, useful upgrade choices and the incentive to restart for easier faction farming.
- [ ] Prepare representative gameplay footage, screenshots and descriptions of the candidate's actual features.
- [ ] Prepare the Coming Soon presence and Steam Playtest setup when ready, using the current [Coming Soon](https://partner.steamgames.com/doc/store/coming_soon), [Steam Playtest](https://partner.steamgames.com/doc/features/playtest) and [review](https://partner.steamgames.com/doc/store/review_process) documentation.
- [ ] Configure, upload and test the chosen Steam build through its distribution flow; verify the Steam-installed game launches on a clean machine.
- [ ] Arrange a feedback channel and collect hardware details, comprehension problems, fairness/readability observations and interest in another run.
- [ ] Review outside feedback before choosing a paid-release scope or date.

## Release Identity

- [ ] When preparing an authorized release, select the intended version change and use `scripts/release/bump_version.ps1` with one switch only: `-Major`, `-Minor`, `-Revision`, or `-Hotfix`.
- [ ] Confirm `project.godot` values:
  - [ ] `config/name`
  - [ ] `config/description`
  - [ ] `config/version`
- [ ] Update `export_presets.cfg` Windows metadata:
  - [ ] `application/company_name`
  - [ ] `application/file_version`
  - [ ] `application/product_version`
  - [ ] `application/copyright`
- [ ] Replace placeholder values in:
  - [ ] `docs/release/EULA.txt`
  - [ ] `docs/release/README.txt`

## Legal And Attribution

- [x] Fill every row in `docs/release/ATTRIBUTIONS.md`.
- [ ] Confirm all third-party license files are present in `docs/release/THIRD_PARTY_NOTICES.txt`.
- [ ] Verify license requirements for each asset:
  - [ ] Commercial use allowed
  - [ ] Modification allowed
  - [ ] Attribution language included (if required)
- [x] Confirm your ownership statement in `docs/release/EULA.txt` is accurate.

## Build Outputs

- [ ] Export Windows release build:
  - [ ] `& .\scripts\release\export_windows.ps1 -GodotExe $env:GODOT_EXE -BuildType release`
- [ ] Optional Linux export:
  - [ ] `& .\scripts\release\export_linux.ps1 -GodotExe $env:GODOT_EXE -BuildType release`
- [ ] Confirm `GODOT_EXE` and installed export templates match the project's Godot 4.7.2 configuration.
- [ ] Confirm these files exist after export:
  - [ ] `build/windows/Fluxbreak.exe`
  - [ ] Required runtime files from the actual export. The current Windows preset embeds its PCK; a separate `Fluxbreak.pck` is not expected unless that configuration changes.

## Installer Packaging

This section covers the existing standalone Windows/Inno distribution. Verify Steam distribution separately above.

- [ ] Install Inno Setup (ISCC in PATH).
- [ ] Set metadata constants in `installer/windows/Fluxbreak.iss`.
- [ ] Build installer:
  - [ ] `& .\scripts\release\export_windows.ps1 -GodotExe $env:GODOT_EXE -BuildType release -BuildInstaller`
- [ ] Confirm installer output exists:
  - [ ] `build/installer/Fluxbreak-Setup-<version>.exe`

## Final QA

- [ ] Fresh install on a clean Windows machine/VM.
- [ ] Verify save data behavior:
  - [ ] Launch creates config/save in user profile.
  - [ ] Persistent settings, currency, unlocks, selections and statistics reload after restarting the game.
  - [ ] If save protection/location changes are included later, migration preserves existing progression and handles missing/invalid data deliberately. Local encryption is not trusted high-score verification.
- [ ] Verify gameplay pass:
  - [ ] New run from main menu
  - [ ] Campaign random faction remains fixed throughout both sectors; Practice faction selection remains available.
  - [ ] Wave progression and a complete two-sector Campaign, including boss arrival with survivors, gateway briefing cancel/confirm, and immediate finale victory.
  - [ ] Practice victory/death grants no Flux Anchors, saved score/stat records, progression or unlocks.
  - [ ] Pause/resume, camera settings and modifier/history panels work without advancing paused gameplay.
  - [ ] Information discovery/unlocks and previews/details agree with persistent Campaign progression.
  - [ ] Every faction's attacks remain readable; stacked Sporeling poison and late-wave Greys remain responsive under load.
  - [ ] Return to menu
- [ ] Verify uninstall removes program files and shortcuts.
