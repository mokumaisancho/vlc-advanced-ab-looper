#!/bin/bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI="$ROOT/src/extensions/advanced_ab_looper.lua"
INTF="$ROOT/src/intf/advanced_ab_looper_intf.lua"
RUN="$ROOT/RUN.command"
WATCHER="$ROOT/tools/preset_autoload_watcher.applescript"

fail(){ echo "FAIL: $*"; exit 1; }
pass(){ echo "PASS: $*"; }

[ -s "$UI" ] || fail "UI missing"
[ -s "$INTF" ] || fail "interface missing"
[ -s "$RUN" ] || fail "RUN.command missing"
[ -s "$WATCHER" ] || fail "preset watcher missing"

grep -q 'version = "2.4.0"' "$UI" || fail "UI version not 2.4.0"
grep -q 'capabilities = {"input-listener"}' "$UI" || fail "input listener missing"
grep -q 'advanced_ab_looper_library.json' "$UI" || fail "single JSON library missing"
grep -q 'vlc.strings.make_path(uri)' "$UI" || fail "absolute path derivation missing"
grep -q 'function input_changed()' "$UI" || fail "track change isolation missing"
grep -q 'library.tracks\[current_path\]' "$UI" || fail "track-keyed library missing"
grep -q 'visible A/B' "$UI" || fail "screen-driven runtime contract missing"
! grep -q 'dlg:add_button("Load"' "$UI" || fail "Load button must not exist"
grep -q '#%d | %s | %s' "$UI" || fail "preset dropdown bridge format missing"

grep -q 'version) ~= 4' "$INTF" || fail "runtime schema v4 missing"
grep -q 'state.track_uri == uri' "$INTF" || fail "track URI hard guard missing"
grep -q 'POLL_US = 5000' "$INTF" || fail "5ms poll missing"
grep -q 'SAFETY_MARGIN_US = 20000' "$INTF" || fail "pre-B guard missing"
! grep -q ':lines(' "$INTF" || fail "unsupported file:lines remains"

grep -q 'preset_autoload_watcher.applescript' "$RUN" || fail "watcher not launched"
grep -q 'advanced_ab_looper_library.json' "$RUN" || fail "library path not surfaced"
! grep -q 'initialize_defaults_once' "$RUN" || fail "global default loops must not be seeded"
grep -q 'AXPopUpButton' "$WATCHER" || fail "dropdown watcher missing"
grep -q 'AXTextField' "$WATCHER" || fail "A/B auto-fill missing"

bash -n "$RUN" || fail "RUN.command shell syntax"
bash -n "$0" || fail "smoke test shell syntax"

pass "track-scoped JSON library / cross-track isolation / no-Load contract"
