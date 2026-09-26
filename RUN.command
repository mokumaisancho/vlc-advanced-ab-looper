#!/bin/bash
set -Eeuo pipefail

REPO_OWNER="mokumaisancho"
REPO_NAME="vlc-advanced-ab-looper"
REPO_SSH="git@github.com:${REPO_OWNER}/${REPO_NAME}.git"
REPO_HTTPS="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"

WORK_ROOT="$HOME/.vlc-advanced-ab-looper"
REPO_DIR="$WORK_ROOT/repo"
LOG_DIR="$WORK_ROOT/runtime-logs"

VLC_APP="/Applications/VLC.app"
VLC_BIN="$VLC_APP/Contents/MacOS/VLC"
VLC_DATA="$HOME/Library/Application Support/org.videolan.vlc"
EXT_DIR="$VLC_DATA/lua/extensions"
INTF_DIR="$VLC_DATA/lua/intf"

STAMP="$(date '+%Y%m%d_%H%M%S')"
HOST="$(scutil --get ComputerName 2>/dev/null | tr ' /:' '___' || hostname | tr ' /:' '___')"
LOG_FILE="$LOG_DIR/${STAMP}_${HOST}.log"

WATCHER_PID=""

mkdir -p "$WORK_ROOT" "$LOG_DIR"
sayline(){ printf '%s\n' "$*"; }

clone_or_update() {
  if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" fetch origin main --quiet
    git -C "$REPO_DIR" reset --hard origin/main --quiet
  else
    rm -rf "$REPO_DIR"
    if ! git clone --depth 1 "$REPO_SSH" "$REPO_DIR"; then
      git clone --depth 1 "$REPO_HTTPS" "$REPO_DIR"
    fi
  fi
}

install_assets() {
  [ -x "$VLC_BIN" ] || { echo "ERROR: /Applications/VLC.app not found"; exit 10; }
  mkdir -p "$EXT_DIR" "$INTF_DIR" "$VLC_DATA"
  install -m 0644 "$REPO_DIR/src/extensions/advanced_ab_looper.lua" \
    "$EXT_DIR/advanced_ab_looper.lua"
  install -m 0644 "$REPO_DIR/src/intf/advanced_ab_looper_intf.lua" \
    "$INTF_DIR/advanced_ab_looper_intf.lua"
}

open_looper_ui() {
  /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
on tryOpen(menuName)
  tell application "System Events"
    tell process "VLC"
      if exists menu bar item menuName of menu bar 1 then
        tell menu bar item menuName of menu bar 1
          click
          delay 0.3
          if exists menu item "Advanced A-B Looper" of menu 1 then
            click menu item "Advanced A-B Looper" of menu 1
            return true
          end if
        end tell
      end if
    end tell
  end tell
  return false
end tryOpen

tell application "VLC" to activate
delay 2
if not tryOpen("View") then
  tryOpen("表示")
end if
APPLESCRIPT
}

start_preset_watcher() {
  local watcher="$REPO_DIR/tools/preset_autoload_watcher.applescript"
  if [ -f "$watcher" ]; then
    /usr/bin/osascript "$watcher" >/dev/null 2>&1 &
    WATCHER_PID=$!
  fi
}

cleanup_watcher() {
  if [ -n "${WATCHER_PID:-}" ]; then
    kill "$WATCHER_PID" >/dev/null 2>&1 || true
  fi
}

push_log() {
  local status=$?
  set +e
  cleanup_watcher

  if [ -d "$REPO_DIR/.git" ] && [ -f "$LOG_FILE" ]; then
    mkdir -p "$REPO_DIR/logs/$HOST"
    cp "$LOG_FILE" "$REPO_DIR/logs/$HOST/${STAMP}.log"

    {
      echo
      echo "===== environment ====="
      date
      sw_vers 2>/dev/null || true
      "$VLC_BIN" --version 2>&1 | head -n 4 || true
      echo "loop_library=$VLC_DATA/advanced_ab_looper_library.json"
      echo "exit_status=$status"
    } >> "$REPO_DIR/logs/$HOST/${STAMP}.log"

    git -C "$REPO_DIR" add "logs/$HOST/${STAMP}.log"
    if ! git -C "$REPO_DIR" diff --cached --quiet; then
      git -C "$REPO_DIR" \
        -c user.name="VLC AB Looper Diagnostics" \
        -c user.email="vlc-ab-looper@localhost" \
        commit -m "diagnostics: ${HOST} ${STAMP}" --quiet

      for n in 1 2 3; do
        git -C "$REPO_DIR" pull --rebase origin main --quiet \
          && git -C "$REPO_DIR" push origin main \
          && break
        sleep $((n*2))
      done
    fi
  fi

  exit "$status"
}
trap push_log EXIT INT TERM

sayline "[1/6] Downloading/updating all assets from GitHub..."
clone_or_update

sayline "[2/6] Installing VLC extension and track-safe loop engine..."
install_assets

sayline "[3/6] Running local contract checks..."
bash "$REPO_DIR/tests/smoke_test.sh"

sayline "[4/6] Starting VLC..."
("$VLC_BIN" \
  --extraintf=luaintf \
  --lua-intf=advanced_ab_looper_intf \
  --verbose=2 \
  "$@" 2>&1 | tee "$LOG_FILE") &
VLC_PIPE_PID=$!

sayline "[5/6] Opening Advanced A-B Looper..."
open_looper_ui

sayline "[6/6] Starting preset auto-load bridge..."
start_preset_watcher

sayline "READY: presets are isolated by absolute track path."
sayline "DB: $VLC_DATA/advanced_ab_looper_library.json"

wait "$VLC_PIPE_PID"
