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
rm "$dir/zwave.json"
out=$(homey_run "$dir")
assert_match "untested model keeps the real reason" '^not checked: zwave: not available \(untested model\)$' "$out"

# --- wrongly shaped responses (homey-wrong-shape/ overlays the fixtures; collect.ps1 must print the same) ---
dir=$(homey_copy wrongshape); cp "$(fixture homey-wrong-shape)"/*.json "$dir/"
homey_run "$dir" > "$HHC_TMP/homey-wrong.txt"; rc=$?
if cmp -s "$(fixture homey-wrong-shape/expected.txt)" "$HHC_TMP/homey-wrong.txt"; then same=yes; else same=no; fi
assert_eq "wrongly shaped responses match homey-wrong-shape/expected.txt" "yes" "$same" || diff "$(fixture homey-wrong-shape/expected.txt)" "$HHC_TMP/homey-wrong.txt"
assert_eq "wrongly shaped responses exit 0" "0" "$rc"

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

# --- the key never leaves for another host: no redirect, no proxy from the environment ---
# A fake Homey answers every call with a redirect to a second listener, which logs any request it gets.
cat > "$HHC_TMP/homey-srv.pl" <<'SRV'
use strict; use IO::Socket::INET; use IO::Select;
my ($portfile, $log) = @ARGV;
my @l = map { IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0, Listen => 10, ReuseAddr => 1) or die } 1, 2;
my $other = $l[1]->sockport;
open(my $pf, '>', "$portfile.tmp") or die; print $pf $l[0]->sockport, " $other\n"; close $pf; rename "$portfile.tmp", $portfile;
$SIG{ALRM} = sub { exit 0 }; alarm 120;
my $sel = IO::Select->new(@l);
while (my @r = $sel->can_read) {
  for my $s (@r) {
    my $c = $s->accept or next;
    my $head = '';
    while (defined(my $line = <$c>)) { $head .= $line; last if $line =~ /^\r?\n$/ }
    if ($s == $l[1]) {
      open(my $lf, '>>', $log) or die; print $lf 'other host got a request', ($head =~ /^Authorization:/mi ? ' with the key' : ''), "\n"; close $lf;
      print $c "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
    } else {
      print $c "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:$other/api/manager/system/\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
    }
    close $c;
  }
}
SRV
perl "$HHC_TMP/homey-srv.pl" "$HHC_TMP/homey-ports" "$HHC_TMP/homey-other.log" &
srv=$!
i=0; while [ ! -f "$HHC_TMP/homey-ports" ] && [ $i -lt 100 ]; do perl -e 'select(undef, undef, undef, 0.1)'; i=$((i + 1)); done
read -r homey_port other_port < "$HHC_TMP/homey-ports"
out=$(no_proxy= NO_PROXY= bash "$HHC_ROOT/$COLLECT" --host "127.0.0.1:$homey_port" --key-file "$HHC_TMP/homey-key.txt" 2>&1); rc=$?
assert_eq "a redirect is not followed" "" "$(cat "$HHC_TMP/homey-other.log" 2>/dev/null)"
assert_eq "a redirect reads as not available, exit 0" "0 yes" "$rc $(printf '%s\n' "$out" | grep -q '^not checked: system: not available$' && echo yes)"
rm -f "$HHC_TMP/homey-other.log"
proxy=http://127.0.0.1:$other_port
out=$(http_proxy=$proxy HTTP_PROXY=$proxy all_proxy=$proxy no_proxy= NO_PROXY= bash "$HHC_ROOT/$COLLECT" --host "127.0.0.1:$homey_port" --key-file "$HHC_TMP/homey-key.txt" 2>&1)
assert_eq "a proxy from the environment is not used" "" "$(cat "$HHC_TMP/homey-other.log" 2>/dev/null)"
kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null
