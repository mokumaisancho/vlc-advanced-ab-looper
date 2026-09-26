# VLC Advanced A-B Looper (VLC 3.0.24 / macOS)

Time-specified A-B looping with multiple saved presets per media file.

## Runtime contract
- The visible A/B fields are the runtime source of truth.
- `LOOP ON` always uses the A/B values currently visible on screen.
- Saved presets are only shortcuts that populate A/B.
- Saved presets are isolated by the current media file's absolute path.
- The helper also binds the active loop to the exact current media URI, so changing tracks immediately prevents the old loop from firing.

## Persistent storage
All saved presets live in one JSON file:

`~/Library/Application Support/org.videolan.vlc/advanced_ab_looper_library.json`

Shape:

`tracks[] -> absolute path -> loops[]`

The runtime state file is transient control-plane data and is not the preset database.

## Preset selection
VLC 3's Lua `add_dropdown()` exposes the selected value but no selection-change callback.
On macOS, `RUN.command` therefore launches a small Accessibility watcher. Selecting a saved preset in the dropdown immediately copies that preset's A/B values into the visible fields. There is no Load button.

## RUN.command
Each run:
1. updates the repository from GitHub,
2. installs the extension/interface,
3. runs contract checks,
4. starts VLC with the loop helper,
5. opens Advanced A-B Looper,
6. starts the dropdown auto-load watcher,
7. captures diagnostics and pushes the log to GitHub when VLC exits.

macOS may request Accessibility permission for Terminal/osascript so the dropdown auto-load bridge can update the A/B fields.
