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
EXT_DIR="$HOME/Library/Application Support/org.videolan.vlc/lua/extensions"
INTF_DIR="$HOME/Library/Application Support/org.videolan.vlc/lua/intf"
STAMP="$(date '+%Y%m%d_%H%M%S')"
HOST="$(scutil --get ComputerName 2>/dev/null | tr ' /:' '___' || hostname | tr ' /:' '___')"
LOG_FILE="$LOG_DIR/${STAMP}_${HOST}.log"

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
  [ -d "$VLC_APP" ] || { echo "ERROR: /Applications/VLC.app not found"; exit 10; }
  mkdir -p "$EXT_DIR" "$INTF_DIR"
  install -m 0644 "$REPO_DIR/src/extensions/advanced_ab_looper.lua" "$EXT_DIR/advanced_ab_looper.lua"
  install -m 0644 "$REPO_DIR/src/intf/advanced_ab_looper_intf.lua" "$INTF_DIR/advanced_ab_looper_intf.lua"
}

push_log() {
  local status=$?
  set +e
  if [ -d "$REPO_DIR/.git" ] && [ -f "$LOG_FILE" ]; then
    mkdir -p "$REPO_DIR/logs/$HOST"
    cp "$LOG_FILE" "$REPO_DIR/logs/$HOST/${STAMP}.log"
    {
      echo
      echo "===== environment ====="
      date
      sw_vers 2>/dev/null || true
      "$VLC_APP/Contents/MacOS/VLC" --version 2>&1 | head -n 4 || true
      echo "exit_status=$status"
    } >> "$REPO_DIR/logs/$HOST/${STAMP}.log"
    git -C "$REPO_DIR" add "logs/$HOST/${STAMP}.log"
    if ! git -C "$REPO_DIR" diff --cached --quiet; then
      git -C "$REPO_DIR" -c user.name="VLC AB Looper Diagnostics" -c user.email="vlc-ab-looper@localhost" commit -m "diagnostics: ${HOST} ${STAMP}" --quiet
      for n in 1 2 3; do
        git -C "$REPO_DIR" pull --rebase origin main --quiet && git -C "$REPO_DIR" push origin main && break
        sleep $((n*2))
      done
    fi
  fi
  exit "$status"
}
trap push_log EXIT INT TERM

sayline "[1/4] Updating from GitHub..."
clone_or_update
sayline "[2/4] Installing VLC Lua extension/interface..."
install_assets
sayline "[3/4] Running local smoke checks..."
bash "$REPO_DIR/tests/smoke_test.sh"
sayline "[4/4] Starting VLC; diagnostics will be pushed automatically on exit."

"$VLC_APP/Contents/MacOS/VLC" \
  --extraintf=luaintf \
  --lua-intf=advanced_ab_looper_intf \
  --verbose=2 2>&1 | tee "$LOG_FILE"
