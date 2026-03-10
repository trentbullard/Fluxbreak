# Fluxbreak Production Checklist

Use this checklist before shipping any public build.

## Release Identity

- [ ] Bump version with script:
  - [ ] `scripts/release/bump_version.ps1 -Revision`
  - [ ] Use one switch only: `-Major`, `-Minor`, `-Revision`, or `-Hotfix`
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
  - [ ] `scripts/release/export_windows.ps1 -GodotExe "C:\path\to\Godot_v4.5-stable_win64_console.exe"`
- [ ] Optional Linux export:
  - [ ] `scripts/release/export_linux.ps1 -GodotExe "C:\path\to\Godot_v4.5-stable_win64_console.exe"`
- [ ] Confirm these files exist after export:
  - [ ] `build/windows/Fluxbreak.exe`
  - [ ] `build/windows/Fluxbreak.pck`

## Installer Packaging

- [ ] Install Inno Setup (ISCC in PATH).
- [ ] Set metadata constants in `installer/windows/Fluxbreak.iss`.
- [ ] Build installer:
  - [ ] `scripts/release/export_windows.ps1 -GodotExe "C:\path\to\Godot_v4.5-stable_win64_console.exe" -BuildInstaller`
- [ ] Confirm installer output exists:
  - [ ] `build/installer/Fluxbreak-Setup-<version>.exe`

## Final QA

- [ ] Fresh install on a clean Windows machine/VM.
- [ ] Verify save data behavior:
  - [ ] Launch creates config/save in user profile.
  - [ ] Save/load works after restart.
- [ ] Verify gameplay pass:
  - [ ] New run from main menu
  - [ ] Wave progression
  - [ ] Pause and resume
  - [ ] Return to menu
- [ ] Verify uninstall removes program files and shortcuts.
