# Follow-camera settings

The original ship-led follow camera is the only camera system. Settings configure its existing field of view, offsets, angular-velocity look, smoothing and acceleration pullback. Default values preserve the original follow calculation; there is no automatic framing, HUD exclusion or alternate flight controller.

Open **Settings → Flight Camera** from the main menu or **Pause → Camera Settings** during a run. Changes preview while paused. Back, Escape or controller B closes the panel; Resume returns to flight.

| Setting | Reset default | Range |
|---|---:|---:|
| Field of view | 75° | 60–110° |
| Camera distance | 100% | 75–175% of the ship's authored distance |
| Camera height | 100% | 50–200% of the ship's authored height |
| Follow tightness | 17% | 0–100% |
| Look ahead | 100% | 0–100% |
| Acceleration pullback | 20% | 0–20% |

Tightness maps to 4–16/s turn response and 3–15/s distance response. Its reset value of one sixth preserves the original 6/s and 5/s interpolation weights. Look ahead scales the original independently limited pitch/yaw offsets. Pullback sets the maximum extra distance under acceleration.

Distance and height multiply the selected hull's authored offsets, so changing ships does not compound these values. Preferences persist independently in `user://camera_settings.cfg`; unsupported keys from earlier camera experiments are ignored. Reset Camera restores the values above. Flight forces, handling stats, pilot g-force limits, sensitivity and input bindings are unchanged.

## Validation

- Godot 4.7.2 import: clean.
- Focused save-isolated suite: **120 assertions passed**, covering the original default camera calculation on all three hulls, all six live settings, persistence/sanitization, ship-relative offsets, keyboard/controller navigation, Reset and safe paused modal closing.
- Existing main-menu suite: **175 assertions passed**. Gateway suite: **1,041 checks passed**, covering four factions and both routes.
- Vulkan 1280×720 preview: **18 checks passed**. Six captures were visually reviewed, including both menu entry points, top/bottom scrolling and the original follow view. All sliders are reachable; Reset and Back stay visible. Logs contain no engine errors, warnings or leaks.

Repeat using `scripts/tests/run_camera_settings_checks.ps1` and `scripts/tests/run_camera_settings_visual_checks.ps1` with `GODOT_EXE`. Both use isolated saves; rendered images are written to a temporary directory. Live combat playtesting remains the way to judge personal camera comfort.

No version increment, executable export or installer build accompanies this change.
