# Tests for home-inventory/scripts/discover.sh. Sourced by tools/test-sh.sh.
DISCOVER=plugins/home-health-check/skills/home-inventory/scripts/discover.sh
load_script "$DISCOVER"
TAB=$(printf '\t')
NL='
'

# --- MAC helpers ---
assert_eq "norm_mac pads short groups" "b8:27:eb:00:00:00" "$(norm_mac b8:27:eb:0:0:0)"
assert_eq "norm_mac lowercases and accepts dashes" "b8:27:eb:00:00:00" "$(norm_mac B8-27-EB-00-00-00)"
assert_eq "norm_mac rejects an incomplete entry" "" "$(norm_mac '(incomplete)')"
is_random_mac da:a1:19:00:00:00; assert_eq "is_random_mac true for a private address" "0" "$?"
is_random_mac b8:27:eb:00:00:00; assert_eq "is_random_mac false for a vendor address" "1" "$?"

# --- address arithmetic ---
assert_eq "mask_to_prefix hex /24" "24" "$(mask_to_prefix 0xffffff00)"
assert_eq "mask_to_prefix hex /22" "22" "$(mask_to_prefix 0xfffffc00)"
assert_eq "mask_to_prefix dotted /24" "24" "$(mask_to_prefix 255.255.255.0)"
assert_eq "ip_to_num and num_to_ip round trip" "192.168.1.255" "$(num_to_ip $(( $(ip_to_num 192.168.1.0) + 255 )))"

# --- neighbor parsers ---
expected_arp="192.168.1.1${TAB}30:68:93:00:00:00${NL}192.168.1.10${TAB}b8:27:eb:00:00:00${NL}192.168.1.20${TAB}da:a1:19:00:00:00${NL}192.168.1.21${TAB}7a:b2:c3:00:00:00"
assert_eq "parse_arp (macOS) on en0 skips incomplete, broadcast, multicast and other interfaces" "$expected_arp" "$(parse_arp en0 < "$(fixture macos/arp-an.txt)")"
assert_eq "parse_arp (macOS) without interface also lists en1" "$expected_arp${NL}192.168.1.40${TAB}e0:bb:9e:00:00:00" "$(parse_arp < "$(fixture macos/arp-an.txt)")"
assert_eq "parse_arp (Linux net-tools) on eth0" "192.168.1.1${TAB}30:68:93:00:00:00${NL}192.168.1.20${TAB}da:a1:19:00:00:00" "$(parse_arp eth0 < "$(fixture linux/arp-an.txt)")"
expected_neigh="192.168.1.20${TAB}da:a1:19:00:00:00${NL}192.168.1.1${TAB}30:68:93:00:00:00${NL}192.168.1.40${TAB}e0:bb:9e:00:00:00${NL}192.168.1.41${TAB}94:b9:7e:00:00:00${NL}192.168.1.42${TAB}78:42:1c:00:00:00${NL}192.168.1.43${TAB}54:2a:1b:00:00:00"
assert_eq "parse_ip_neigh keeps live states and drops FAILED and INCOMPLETE" "$expected_neigh" "$(parse_ip_neigh < "$(fixture linux/ip-neigh.txt)")"

# --- names and descriptions ---
assert_eq "parse_dnssd_ptr prints the first added target without the dot" "macbook.local" "$(parse_dnssd_ptr < "$(fixture macos/dnssd-ptr.txt)")"
assert_eq "parse_upnp_desc joins the first device's fields" "192.168.1.30 - Example Lamp - RINCON_000000000000 | Sonos, Inc. | Example Lamp | S99" "$(parse_upnp_desc < "$(fixture upnp/sonos-desc.xml)")"
location_host_ok 192.168.1.20 http://192.168.1.20:1400/xml/device_description.xml; assert_eq "location_host_ok accepts the device's own address" "0" "$?"
location_host_ok 192.168.1.20 http://192.168.1.99/x.xml; assert_eq "location_host_ok rejects another host" "1" "$?"
location_host_ok 192.168.1.20 http://192.168.1.200/x.xml; assert_eq "location_host_ok rejects a longer address with the same prefix" "1" "$?"

# --- vendor list ---
assert_eq "oui_lookup maps a known prefix" "b8:27:eb:00:00:00${TAB}Raspberry Pi Foundation" "$(printf 'b8:27:eb:00:00:00\n' | oui_lookup "$(fixture manuf-sample.txt)")"
assert_eq "oui_lookup prints nothing for an unknown prefix" "" "$(printf '12:34:56:00:00:00\n' | oui_lookup "$(fixture manuf-sample.txt)")"

cp "$(fixture manuf-sample.txt)" "$HHC_TMP/sample.txt"; mkdir -p "$HHC_TMP/dd"; cp "$HHC_TMP/sample.txt" "$HHC_TMP/dd/manuf.txt"
curl() { echo called >> "$HHC_TMP/curl.log"; return 1; }
out=$(HOME_HEALTH_CHECK_DIR="$HHC_TMP/dd" ensure_oui)
assert_eq "ensure_oui prints the cache path" "$HHC_TMP/dd/cache/manuf.txt" "$out"
assert_eq "ensure_oui moved the old file unchanged" "same" "$(cmp -s "$HHC_TMP/sample.txt" "$HHC_TMP/dd/cache/manuf.txt" && echo same || echo different)"
assert_eq "ensure_oui left no top-level manuf.txt" "gone" "$([ -e "$HHC_TMP/dd/manuf.txt" ] && echo present || echo gone)"
assert_eq "ensure_oui did not download again" "no" "$([ -e "$HHC_TMP/curl.log" ] && echo yes || echo no)"
curl() { while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then cp "$HHC_TMP/sample.txt" "$2"; return 0; fi; shift; done; return 1; }
out=$(HOME_HEALTH_CHECK_DIR="$HHC_TMP/new/dir" ensure_oui); rc=$?
assert_eq "ensure_oui creates a missing data dir and downloads" "0 yes" "$rc $([ -s "$HHC_TMP/new/dir/cache/manuf.txt" ] && echo yes || echo no)"
unset -f curl

# --- output ---
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 192.168.1.1 3c:22:fb:00:00:00 TP-Link no router.lan "" "80/http 443/https" > "$HHC_TMP/records.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 192.168.1.23 da:a1:19:00:00:00 "" yes "" "" "" >> "$HHC_TMP/records.tsv"
expected_json='{"scanned":"2026-10-27T09:00:00","subnet":"192.168.1.0/24","gateway":"192.168.1.1","devices":[
{"ip":"192.168.1.1","mac":"3c:22:fb:00:00:00","vendor":"TP-Link","random_mac":false,"name":"router.lan","upnp":"","ports":"80/http 443/https"},
{"ip":"192.168.1.23","mac":"da:a1:19:00:00:00","vendor":"","random_mac":true,"name":"","upnp":"","ports":""}
]}'
assert_eq "print_json output" "$expected_json" "$(print_json 2026-10-27T09:00:00 192.168.1.0/24 192.168.1.1 "$HHC_TMP/records.tsv")"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 192.168.1.9 b8:27:eb:00:00:00 "" no "$(printf 'a"b\\c\001d')" "" "" > "$HHC_TMP/odd.tsv"
assert_eq "print_json escapes quotes and backslashes and drops control characters" '{"ip":"192.168.1.9","mac":"b8:27:eb:00:00:00","vendor":"","random_mac":false,"name":"a\"b\\cd","upnp":"","ports":""}' "$(print_json now x y "$HHC_TMP/odd.tsv" | sed -n 2p)"
table=$(print_table "$HHC_TMP/records.tsv")
assert_eq "print_table has header, rule and two rows" "4" "$(printf '%s\n' "$table" | wc -l | tr -d ' ')"
assert_match "print_table header" '^ip +mac +rnd +vendor +name +upnp +ports$' "$(printf '%s\n' "$table" | sed -n 1p)"
assert_match "print_table rule line is dashes and spaces" '^[- ]+$' "$(printf '%s\n' "$table" | sed -n 2p)"
off1=$(printf '%s\n' "$table" | sed -n 1p | awk '{ print index($0, "mac") }')
off3=$(printf '%s\n' "$table" | sed -n 3p | awk '{ print index($0, "3c:22") }')
off4=$(printf '%s\n' "$table" | sed -n 4p | awk '{ print index($0, "da:a1") }')
assert_eq "print_table columns line up" "$off1 $off1" "$off3 $off4"
assert_match "print_table trims trailing blanks and marks random MACs" 'yes$' "$(printf '%s\n' "$table" | sed -n 4p)"

# --- hints ---
assert_match "lan_hint on macOS with no neighbors mentions Local Network" 'Local Network' "$(lan_hint 0 Darwin)"
assert_eq "lan_hint stays quiet when devices answered" "" "$(lan_hint 3 Darwin)"
assert_match "lan_hint on Linux with no neighbors" 'no devices answered' "$(lan_hint 0 Linux)"

# --- with_timeout ---
SECONDS=0; with_timeout 1 sleep 5; rc=$?
assert_eq "with_timeout kills a slow command quickly and reports failure" "fail fast" "$([ "$rc" -ne 0 ] && echo fail) $([ "$SECONDS" -lt 4 ] && echo fast)"
SECONDS=0; out=$(with_timeout 5 echo hi)
assert_eq "with_timeout returns the output as soon as the command ends" "hi fast" "$out $([ "$SECONDS" -lt 3 ] && echo fast)"

# --- running from stdin (an agent without a skill folder) ---
out=$(bash -s -- --help < "$HHC_ROOT/$DISCOVER" 2>&1); rc=$?
assert_eq "--help from stdin exits 0 and prints Usage" "0 usage" "$rc $(printf '%s' "$out" | grep -q Usage && echo usage)"
bash -s -- --bogus < "$HHC_ROOT/$DISCOVER" >/dev/null 2>&1
assert_eq "an unknown option exits 2" "2" "$?"

# --- location_host_ok must not be fooled by a user part in the url ---
location_host_ok 192.168.1.5 'http://192.168.1.5:80@example.com/x'; assert_eq "location_host_ok rejects a url whose real host follows an @" "1" "$?"
location_host_ok 192.168.1.5 'http://user@192.168.1.5/x'; assert_eq "location_host_ok rejects any url with a user part" "1" "$?"
location_host_ok 192.168.1.5 'ftp://192.168.1.5/x'; assert_eq "location_host_ok rejects a scheme other than http and https" "1" "$?"
location_host_ok 192.168.1.5 'https://192.168.1.5/x'; assert_eq "location_host_ok accepts https on the device's own address" "0" "$?"

# --- run the whole script against fake tools: access denied on macOS must be reported even when the neighbor cache holds devices ---
STUBS=$HHC_TMP/stubs
make_stub "$STUBS" uname 'if [ "$1" = -s ]; then echo Darwin; else exec '"$(command -v uname)"' "$@"; fi'
make_stub "$STUBS" route 'cat '"$(fixture macos/route-get-default.txt)"
make_stub "$STUBS" ifconfig 'sed s/0xffffff00/0xfffffffc/ '"$(fixture macos/ifconfig.txt)"
make_stub "$STUBS" arp 'cat '"$(fixture macos/arp-an.txt)"
make_stub "$STUBS" perl 'exit 0'
make_stub "$STUBS" host 'exit 1'
make_stub "$STUBS" dns-sd 'exit 1'
make_stub "$STUBS" ping 'exit 1'
out=$(PATH="$STUBS:$PATH" bash "$HHC_ROOT/$DISCOVER" 2>&1)
assert_match "no sweep replies on macOS prints the Local Network hint although arp lists devices" 'Local Network' "$out"
out=$(PATH="$STUBS:$PATH" bash "$HHC_ROOT/$DISCOVER" --json 2>"$HHC_TMP/hint.err")
assert_eq "--json keeps stdout clean and puts the hint on stderr" "{ yes" "$(printf '%s' "$out" | head -c1) $(grep -q 'Local Network' "$HHC_TMP/hint.err" && echo yes)"
make_stub "$STUBS" ping 'exit 0'
out=$(PATH="$STUBS:$PATH" bash "$HHC_ROOT/$DISCOVER" 2>&1)
assert_eq "no hint when the sweep got replies" "" "$(printf '%s\n' "$out" | grep 'Local Network')"
