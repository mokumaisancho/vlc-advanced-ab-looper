# VLC Advanced A-B Looper (VLC 3.0.24)

Time-specified multi A-B loop extension for VLC 3.x on macOS.

## Behavior
- Multiple loop ranges can be added, updated, selected and deleted.
- Only the selected loop is active.
- LOOP ON/OFF is explicit in the UI.
- Helper polls playback every 5 ms.
- It seeks at B - 20 ms to avoid intentionally crossing B before returning to A.
- Runtime diagnostics are captured automatically by RUN.command and pushed to `logs/<Mac>/<timestamp>.log` when VLC exits.

## One-file operation
Keep `RUN.command` anywhere convenient. Each run:
1. downloads/resets to latest `main` from GitHub,
2. installs Lua files into VLC's user directories,
3. runs smoke checks,
4. starts VLC with the helper interface,
5. captures verbose VLC logs,
6. commits/pushes that log automatically on VLC exit.

No manual log upload is required.

## Requirement
Git must already be able to authenticate to this GitHub repository (SSH key or existing HTTPS credential). No token is embedded in this repository or script.
