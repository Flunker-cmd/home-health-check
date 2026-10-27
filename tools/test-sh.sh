#!/usr/bin/env bash
# Runs the shell tests: bash tools/test-sh.sh [<test file>...]  (default: tools/tests/test-*.sh)
# Test files are sourced and use: load_script, assert_eq, assert_match, fixture, $HHC_TMP, $HHC_ROOT.
# Works on bash 3.2 (macOS /bin/bash) and on Git Bash. Repo-only tool, not shipped in the skills.
HHC_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HHC_TMP=$(mktemp -d "${TMPDIR:-/tmp}/hhc-test.XXXXXX")
HHC_PASS=0
HHC_FAIL=0
trap 'rm -rf "$HHC_TMP"' EXIT

finish() {
  if [ "$HHC_FAIL" -eq 0 ]; then echo "OK $HHC_PASS tests"; exit 0; fi
  echo "$HHC_FAIL failures"
  exit 1
}

assert_eq() {
  if [ "$2" = "$3" ]; then HHC_PASS=$((HHC_PASS + 1)); echo "ok $1"; return 0; fi
  HHC_FAIL=$((HHC_FAIL + 1))
  echo "FAIL $1"
  echo "  expected: $2"
  echo "  actual:   $3"
  return 1
}

assert_match() {
  if printf '%s' "$3" | grep -Eq -- "$2"; then HHC_PASS=$((HHC_PASS + 1)); echo "ok $1"; return 0; fi
  HHC_FAIL=$((HHC_FAIL + 1))
  echo "FAIL $1"
  echo "  expected to match: $2"
  echo "  actual:            $3"
  return 1
}

fixture() { echo "$HHC_ROOT/tools/fixtures/$1"; }

# Sources a script without its final `main "$@"` line, so its functions can be tested.
load_script() {
  case $1 in /*|[A-Za-z]:*) src=$1 ;; *) src=$HHC_ROOT/$1 ;; esac
  last=$(awk 'NF { l = $0 } END { print l }' "$src" 2>/dev/null)
  if [ "$last" != 'main "$@"' ]; then
    HHC_FAIL=$((HHC_FAIL + 1))
    echo "FAIL load_script: the last line of $1 must be exactly: main \"\$@\""
    finish
  fi
  body=$HHC_TMP/$(basename "$src").body
  awk 'NF { n = NR } { l[NR] = $0 } END { for (i = 1; i < n; i++) print l[i] }' "$src" > "$body"
  . "$body"
  set +u
}

if [ "$#" -eq 0 ]; then set -- "$HHC_ROOT"/tools/tests/test-*.sh; fi
for t in "$@"; do
  echo "# $t"
  . "$t"
done
finish
