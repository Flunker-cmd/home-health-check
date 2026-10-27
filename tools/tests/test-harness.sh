# Self-test of tools/test-sh.sh. Sourced by the harness, so assert_eq, load_script and fixture are defined.

# a nested harness run on a deliberately failing test file must exit 1
printf 'assert_eq "deliberate failure" "a" "b"\n' > "$HHC_TMP/failing-test.sh"
nested_out=$(bash "$HHC_ROOT/tools/test-sh.sh" "$HHC_TMP/failing-test.sh" 2>&1)
nested_rc=$?
assert_eq "nested harness exits 1 on a failing test" "1" "$nested_rc"

# load_script refuses a script whose last line is not: main "$@"
printf 'echo hello\n' > "$HHC_TMP/no-main.sh"
( load_script "$HHC_TMP/no-main.sh" ) >/dev/null 2>&1
assert_eq "load_script refuses a script without main call" "1" "$?"

assert_eq "fixture points to an existing file" "yes" "$([ -f "$(fixture macos/arp-an.txt)" ] && echo yes || echo no)"
