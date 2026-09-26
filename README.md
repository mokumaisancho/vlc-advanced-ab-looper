# VLC Advanced A-B Looper (VLC 3.0.24)

Time-specified multi A-B loop extension for VLC 3.x on macOS.

## Runtime rule
The A/B values currently shown in the UI are the source of truth.

- `LOOP ON` validates the visible A/B fields and immediately applies those values.
- Saving is never required before looping.
- Saved ranges are presets only.
- `Load` copies a saved preset into the A/B fields; it does not activate it.
- `Save New` stores the current A/B fields as a new preset.
- `Update` overwrites the selected preset from the current A/B fields.
- `Delete` removes only the selected preset and never changes the running loop.
- Editing A/B while a loop is already ON takes effect when `LOOP ON` is pressed again.

## Loop engine
- LOOP ON/OFF is explicit in the UI.
- Helper polls playback every 5 ms.
- It seeks at B - 20 ms to avoid intentionally crossing B before returning to A.
- The engine consumes `active_start_us` / `active_end_us`; it does not execute a preset ID.
- Runtime diagnostics are captured automatically by RUN.command and pushed to `logs/<Mac>/<timestamp>.log` when VLC exits.

## One-file operation
Keep `RUN.command` anywhere convenient. Each run:
1. downloads/resets to latest `main` from GitHub,
2. installs Lua files into VLC's user directories,
3. runs smoke checks,
4. starts VLC with the helper interface,
5. opens Advanced A-B Looper automatically,
6. captures verbose VLC logs and commits/pushes that log automatically on VLC exit.

No manual log upload is required.

## First-run defaults
Only when no state file exists:
- preset #1: 11:11 -> 11:14
- preset #2: 10:11 -> 12:39
- active runtime A/B: 11:11 -> 11:14
- LOOP ON

After the first run, existing runtime state and presets are preserved.

## Requirement
Git must already be able to authenticate to this GitHub repository (SSH key or existing HTTPS credential). No token is embedded in this repository or script.
