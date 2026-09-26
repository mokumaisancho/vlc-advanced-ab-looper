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
grep -q 'POLL_US = 5000' "$INTF" || fail "5ms poll missing"
grep -q 'SAFETY_MARGIN_US = 20000' "$INTF" || fail "pre-B guard missing"
! grep -q ':lines(' "$INTF" || fail "unsupported file:lines remains"
grep -q 'f:read("\*all")' "$INTF" || fail "state read not using read"
grep -q 'Add' "$UI" || fail "Add control missing"
grep -q 'Delete' "$UI" || fail "Delete control missing"
grep -q 'LOOP ON' "$UI" || fail "LOOP ON missing"
grep -q 'LOOP OFF' "$UI" || fail "LOOP OFF missing"
pass "static VLC3 compatibility checks"
