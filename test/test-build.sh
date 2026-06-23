#!/usr/bin/env bash
# test/test-build.sh — end-to-end test of `spin build` (DSL → spinel → binary).
# requires spinel on PATH or $SPINEL set. run from repo root.
set -euo pipefail

cd "$(dirname "$0")/.."
SPINEL="${SPINEL:-spinel}"
command -v "$SPINEL" >/dev/null 2>&1 || { echo "SKIP: spinel not found (set \$SPINEL)"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp" examples/notes.spin.rb ./_t_notes' EXIT

fail=0
check() { # check <desc> <expected-substr> <actual>
  if printf '%s' "$3" | grep -qF "$2"; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected to contain '$2', got:"; printf '%s\n' "$3"; fail=1
  fi
}

SPINEL="$SPINEL" ruby bin/spin build examples/notes.rb -o _t_notes >/dev/null 2>&1

check "read /notes/7 id"   "id=7"                 "$(PATH_INFO=/notes/7 ./_t_notes)"
check "read /health"       "ok"                   "$(PATH_INFO=/health ./_t_notes)"
check "read /echo → 404"   "404"                  "$(PATH_INFO=/echo ./_t_notes | head -1)"
check "write /echo body"   "hello"                "$(printf hello | REQUEST_METHOD=POST PATH_INFO=/echo ./_t_notes)"
check "write /notes 201"   "201"                  "$(printf x | REQUEST_METHOD=POST PATH_INFO=/notes ./_t_notes | head -1)"
check "write /health → 405" "read-only"           "$(printf x | REQUEST_METHOD=PUT PATH_INFO=/health ./_t_notes)"
check "read /unknown 404"  "no such resource"     "$(PATH_INFO=/unknown ./_t_notes)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
