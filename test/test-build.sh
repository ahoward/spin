#!/usr/bin/env bash
# test/test-build.sh — end-to-end test of `spin build` + the envelope.
# DSL → spinel → binary, driven through `spin call` (the envelope, minimal
# http). requires spinel on PATH or $SPINEL set. run from repo root.
set -euo pipefail

cd "$(dirname "$0")/.."
SPINEL="${SPINEL:-spinel}"
command -v "$SPINEL" >/dev/null 2>&1 || { echo "SKIP: spinel not found (set \$SPINEL)"; exit 0; }

bin=./_t_notes
trap 'rm -rf examples/notes.spin.rb "$bin"' EXIT

fail=0
# call <verb> <path> [body]  → prints the handler's response body
call() {
  if [ -n "${3:-}" ]; then printf '%s' "$3" | ruby bin/spin call "$bin" "$1" "$2" 2>/dev/null
  else ruby bin/spin call "$bin" "$1" "$2" 2>/dev/null; fi
}
check() { # check <desc> <expected-substr> <actual>
  if printf '%s' "$3" | grep -qF "$2"; then echo "ok: $1"
  else echo "FAIL: $1 — expected '$2', got:"; printf '%s\n' "$3"; fail=1; fi
}

SPINEL="$SPINEL" ruby bin/spin build examples/notes.rb -o "${bin#./}" >/dev/null 2>&1

check "read /notes/7 id"     "id=7"             "$(call read /notes/7)"
check "read /health"         "ok"              "$(call read /health)"
check "read /echo → 404"     "no such"         "$(call read /echo)"
check "write /echo body"     "hello"           "$(call write /echo hello)"
check "write /notes"         "wrote"           "$(call write /notes x)"
check "write /health → RO"   "read-only"       "$(call write /health x)"
check "read /unknown 404"    "no such resource" "$(call read /unknown)"
# real http method collapses
check "GET (http) → read"    "id=9"            "$(call GET /notes/9)"
check "POST (http) → write"  "wrote"           "$(call POST /notes y)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
