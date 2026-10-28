# Tests for homey-health-check/scripts/collect.sh. Sourced by tools/test-sh.sh.
COLLECT=plugins/home-health-check/skills/homey-health-check/scripts/collect.sh
HOMEY_NOW=2026-10-28T12:00Z

# homey_run <fixture dir>: the collector in offline mode at the fixed clock, stdout and stderr together
homey_run() { bash "$HHC_ROOT/$COLLECT" --host 192.168.1.50 --from-dir "$1" --now "$HOMEY_NOW" 2>&1; }

# homey_copy <name>: a copy of the fixture folder in $HHC_TMP, printed as its path
homey_copy() { cp -R "$(fixture homey)" "$HHC_TMP/$1"; echo "$HHC_TMP/$1"; }

# --- the whole report, byte for byte ---
bash "$HHC_ROOT/$COLLECT" --host 192.168.1.50 --from-dir "$(fixture homey)" --now "$HOMEY_NOW" > "$HHC_TMP/homey-out.txt" 2>&1
rc=$?
out=$(cat "$HHC_TMP/homey-out.txt")
if cmp -s "$(fixture homey/expected.txt)" "$HHC_TMP/homey-out.txt"; then same=yes; else same=no; fi
assert_eq "collect.sh on fixtures matches expected.txt" "yes" "$same" || diff "$(fixture homey/expected.txt)" "$HHC_TMP/homey-out.txt"
assert_eq "collect.sh on fixtures exits 0" "0" "$rc"

# --- privacy ---
assert_eq "no canary in output" "" "$(printf '%s\n' "$out" | grep CANARY)"
assert_eq "presence notice not quoted" "" "$(printf '%s\n' "$out" | grep -E '^  match .*Presence')"
assert_eq "no person named by presence or security notices" "" "$(printf '%s\n' "$out" | grep Person)"

# --- a key without permission for one area (here: no zwave.json) ---
dir=$(homey_copy nozwave); rm "$dir/zwave.json"
out=$(homey_run "$dir"); rc=$?
assert_match "missing zwave.json prints not checked" '^not checked: zwave: not available$' "$out"
assert_match "missing zwave.json still prints the Flows section" '## Flows' "$out"
assert_eq "missing zwave.json exits 0" "0" "$rc"

# --- an older Homey Pro ---
dir=$(homey_copy untested)
sed 's/Homey Pro (Early 2023)/Homey Pro (2019)/' "$dir/system.json" > "$dir/system.tmp" && mv "$dir/system.tmp" "$dir/system.json"
out=$(homey_run "$dir")
assert_match "untested model" '^model_tested: no$' "$out"

# --- options, also from stdin (an agent without a skill folder) ---
bash "$HHC_ROOT/$COLLECT" --help >/dev/null 2>&1
assert_eq "--help exits 0" "0" "$?"
bash "$HHC_ROOT/$COLLECT" --bogus >/dev/null 2>&1
assert_eq "--bogus exits 2" "2" "$?"
bash "$HHC_ROOT/$COLLECT" --from-dir "$(fixture homey)" >/dev/null 2>&1
assert_eq "missing --host exits 2" "2" "$?"
out=$(bash -s -- --help < "$HHC_ROOT/$COLLECT" 2>&1); rc=$?
assert_eq "--help from stdin exits 0 and prints Usage" "0 usage" "$rc $(printf '%s' "$out" | grep -q Usage && echo usage)"
bash -s -- --bogus < "$HHC_ROOT/$COLLECT" >/dev/null 2>&1
assert_eq "--bogus from stdin exits 2" "2" "$?"
bash -s -- --from-dir "$(fixture homey)" < "$HHC_ROOT/$COLLECT" >/dev/null 2>&1
assert_eq "missing --host from stdin exits 2" "2" "$?"
out=$(bash -s -- --host 192.168.1.50 --from-dir "$(fixture homey)" --now "$HOMEY_NOW" < "$HHC_ROOT/$COLLECT" 2>&1)
assert_eq "the report from stdin matches expected.txt" "$(cat "$(fixture homey/expected.txt)")" "$out"

# --- the key never shows up in an error ---
printf 'CANARY-KEY-FILE\n' > "$HHC_TMP/homey-key.txt"
out=$(bash "$HHC_ROOT/$COLLECT" --host 127.0.0.1:9 --key-file "$HHC_TMP/homey-key.txt" 2>&1); rc=$?
assert_eq "an unreachable Homey exits 3" "3" "$rc"
assert_eq "an unreachable Homey says so" "error: cannot reach the Homey at 127.0.0.1:9" "$out"
assert_eq "no key in error output" "" "$(printf '%s\n' "$out" | grep CANARY)"

# --- perl without the modules ---
make_stub "$HHC_TMP/noperl" perl 'exit 1'
out=$(PATH="$HHC_TMP/noperl:$PATH" bash "$HHC_ROOT/$COLLECT" --host 192.168.1.50 --from-dir "$(fixture homey)" 2>&1); rc=$?
assert_eq "check_perl exits 4 when perl lacks the modules" "4 error: needs perl with HTTP::Tiny and JSON::PP" "$rc $out"
