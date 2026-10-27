# Tests for macos-health-check/scripts/collect.sh. Sourced by tools/test-sh.sh.
DISCOVER=plugins/home-health-check/skills/home-inventory/scripts/discover.sh
COLLECT=plugins/home-health-check/skills/macos-health-check/scripts/collect.sh
TAB=$(printf '\t')
NL='
'

# with_timeout is copied from discover.sh and must stay identical (each script ships alone)
load_script "$DISCOVER"
disc_with_timeout=$(type with_timeout)
load_script "$COLLECT"
assert_eq "with_timeout is identical to the copy in discover.sh" "$disc_with_timeout" "$(type with_timeout)"

# --- hardware: no serial number, UUID or UDID may get through ---
hw=$(filter_hardware < "$(fixture macos/sp-hardware.txt)")
assert_eq "filter_hardware drops serial, UUID, UDID and activation lock" "" "$(printf '%s\n' "$hw" | grep -iE 'serial|uuid|udid|activation')"
assert_match "filter_hardware keeps the model name" 'Model Name: MacBook Pro' "$hw"
assert_match "filter_hardware keeps the memory size" 'Memory: 32 GB' "$hw"

# --- updates ---
expected_updates="pending updates: 2${NL}  Safari, version 27.2, recommended YES, restart no${NL}  macOS Tahoe 26.7.2, version 26.7.2, recommended YES, restart yes"
assert_eq "parse_softwareupdate lists each update" "$expected_updates" "$(parse_softwareupdate < "$(fixture macos/softwareupdate-l.txt)")"
assert_eq "parse_softwareupdate with nothing to install" "pending updates: 0" "$(parse_softwareupdate < "$(fixture macos/softwareupdate-none.txt)")"

# --- sharing ---
assert_eq "parse_listening names sharing ports on non-loopback addresses only" "listening: 22/remote-login 7000/airplay-receiver" "$(parse_listening < "$(fixture macos/netstat-listen.txt)")"
assert_eq "parse_listening with nothing listening" "listening: none of the sharing ports" "$(printf 'tcp4 0 0 *.49185 *.* LISTEN\n' | parse_listening)"

# --- app signatures ---
assert_eq "classify_signature app store" "app-store" "$(classify_signature < "$(fixture macos/codesign-appstore.txt)")"
assert_eq "classify_signature developer id" "developer-id" "$(classify_signature < "$(fixture macos/codesign-devid.txt)")"
assert_eq "classify_signature apple" "apple" "$(classify_signature < "$(fixture macos/codesign-apple.txt)")"
assert_eq "classify_signature ad hoc" "adhoc" "$(classify_signature < "$(fixture macos/codesign-adhoc.txt)")"
assert_eq "classify_signature unsigned" "unsigned" "$(classify_signature < "$(fixture macos/codesign-unsigned.txt)")"

# --- backup ---
assert_eq "parse_tm_latest reads the stamp of the latest backup" "2026-10-20 10:30" "$(parse_tm_latest < "$(fixture macos/tmutil-latest.txt)")"
assert_eq "parse_tm_latest on a mount failure prints nothing" "" "$(parse_tm_latest < "$(fixture macos/tmutil-none.txt)")"

# --- crashes ---
assert_eq "crash_counts counts per app, most first" "2 Safari${NL}1 Finder" "$(printf 'Safari-2026-10-01-101010.ips\nSafari-2026-10-02-101010.ips\nFinder-2026-10-03-101010.ips\n' | crash_counts)"
assert_eq "crash_counts also reads the older Name_date_host.crash names" "2 Finder" "$(printf 'Finder-2026-10-03-101010.ips\nFinder_2026-10-04-101010_macbook.crash\n' | crash_counts)"

# --- boot time and free space ---
assert_eq "parse_boottime reads sec, not usec" "1790000000" "$(printf '{ sec = 1790000000, usec = 123456 } Tue Oct 27 08:13:20 2026\n' | parse_boottime)"
assert_eq "container_free reads the byte counts in parentheses" "container free: 93% of 500 GB" "$(container_free < "$(fixture macos/diskutil-info.txt)")"
assert_eq "container_free prints nothing without a container" "" "$(printf 'Volume Name: x\n' | container_free)"

# --- battery ---
assert_match "battery_summary on a laptop without a maximum capacity field" '^cycle count: [0-9]+, condition: Normal, maximum capacity: not reported$' "$(battery_summary < "$(fixture macos/sp-power.txt)")"
assert_eq "battery_summary reads maximum capacity when present" "cycle count: 300, condition: Normal, maximum capacity: 94%" "$(printf 'Health Information:\n    Cycle Count: 300\n    Condition: Normal\n    Maximum Capacity: 94%%\n' | battery_summary)"
assert_eq "battery_summary on a desktop Mac prints nothing" "" "$(battery_summary < "$(fixture macos/sp-power-desktop.txt)")"

# --- running from stdin (an agent without a skill folder) ---
out=$(bash -s -- --help < "$HHC_ROOT/$COLLECT" 2>&1); rc=$?
assert_eq "--help from stdin exits 0 and prints Usage" "0 usage" "$rc $(printf '%s' "$out" | grep -q Usage && echo usage)"
bash -s -- --bogus < "$HHC_ROOT/$COLLECT" >/dev/null 2>&1
assert_eq "an unknown option exits 2" "2" "$?"

# --- an error from softwareupdate must not read as "up to date" ---
printf 'softwareupdate: Could not contact the update server\n' | parse_softwareupdate >/dev/null
assert_eq "parse_softwareupdate returns 1 on output it does not recognize" "1" "$?"

# --- the temporary folder is removed when the script ends ---
STUBS=$HHC_TMP/stubs
make_stub "$STUBS" uname 'if [ "$1" = -s ]; then echo Darwin; else exec '"$(command -v uname)"' "$@"; fi'
mkdir -p "$HHC_TMP/tmpd"
TMPDIR="$HHC_TMP/tmpd" PATH="$STUBS:$PATH" bash "$HHC_ROOT/$COLLECT" --skip-updates >/dev/null 2>&1
assert_eq "collect.sh leaves no temporary folder behind" "0" "$(ls "$HHC_TMP/tmpd" | wc -l | tr -d ' ')"
