#!/bin/bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI="$ROOT/src/extensions/advanced_ab_looper.lua"
INTF="$ROOT/src/intf/advanced_ab_looper_intf.lua"

fail(){ echo "FAIL: $*"; exit 1; }
pass(){ echo "PASS: $*"; }

[ -s "$UI" ] || fail "UI missing"
[ -s "$INTF" ] || fail "interface missing"

grep -q 'title = "Advanced A-B Looper"' "$UI" || fail "descriptor missing"
grep -q 'version = "2.3.0"' "$UI" || fail "UI version not 2.3.0"
grep -q 'version=3' "$UI" || fail "state schema v3 missing"
grep -q 'active_start_us=' "$UI" || fail "active start state missing"
grep -q 'active_end_us=' "$UI" || fail "active end state missing"

grep -q 'function activate_screen()' "$UI" || fail "screen activation function missing"
grep -q 'dlg:add_button("LOOP ON", activate_screen' "$UI" || fail "LOOP ON not wired to screen values"
! grep -q 'Select one loop to activate' "$UI" || fail "LOOP ON still depends on a saved preset"
grep -q 'Load only copies preset values to the screen' "$UI" || fail "preset load contract missing"
grep -q 'Deleting a preset never changes the active runtime loop' "$UI" || fail "preset delete isolation missing"

grep -q 'add_dropdown' "$UI" || fail "compact preset dropdown missing"
! grep -q 'add_list' "$UI" || fail "large list widget must not be used on macOS VLC3"
grep -q 'Current -> A' "$UI" || fail "Current->A missing"
grep -q 'Current -> B' "$UI" || fail "Current->B missing"
grep -q 'Save New' "$UI" || fail "Save New control missing"
grep -q 'Delete' "$UI" || fail "Delete control missing"
grep -q 'LOOP OFF' "$UI" || fail "LOOP OFF missing"

grep -q 'POLL_US = 5000' "$INTF" || fail "5ms poll missing"
grep -q 'SAFETY_MARGIN_US = 20000' "$INTF" || fail "pre-B guard missing"
grep -q 'state.start_us' "$INTF" || fail "engine start bound missing"
grep -q 'state.end_us' "$INTF" || fail "engine end bound missing"
! grep -q 'state.active_id' "$INTF" || fail "engine still depends on preset id"
! grep -q ':lines(' "$INTF" || fail "unsupported file:lines remains"
grep -q 'f:read("\*all")' "$INTF" || fail "state read not using read"

pass "screen-driven loop contract and VLC3/macOS compatibility checks"
