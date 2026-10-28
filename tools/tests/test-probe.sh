# Tests for router-health-check/scripts/probe.sh. Sourced by tools/test-sh.sh.
DISCOVER=plugins/home-health-check/skills/home-inventory/scripts/discover.sh
PROBE=plugins/home-health-check/skills/router-health-check/scripts/probe.sh
TAB=$(printf '\t')
NL='
'
COPIED="have with_timeout norm_mac mask_to_prefix parse_arp parse_ip_neigh parse_upnp_desc location_host_ok lan_hint"

# the helpers copied from discover.sh must be byte-identical (each script ships alone)
load_script "$DISCOVER"
for fn in $COPIED; do eval "disc_$fn=\$(type $fn)"; done
disc_norm_awk=$NORM_AWK
load_script "$PROBE"
for fn in $COPIED; do
  eval "expected=\$disc_$fn"
  assert_eq "$fn is identical to the copy in discover.sh" "$expected" "$(type $fn)"
done
assert_eq "NORM_AWK is identical to the copy in discover.sh" "$disc_norm_awk" "$NORM_AWK"

# --- ping summaries ---
mac_ok=$(printf '%-16s loss %3d%%  min %s ms  avg %s ms  max %s ms' 192.168.1.1 0 1.788 7.261 9.327)
lin_ok=$(printf '%-16s loss %3d%%  min %s ms  avg %s ms  max %s ms' 192.168.1.1 0 1.218 1.328 1.476)
assert_eq "parse_ping_summary on macOS output" "$mac_ok" "$(parse_ping_summary 192.168.1.1 < "$(fixture macos/ping-ok.txt)")"
assert_eq "parse_ping_summary on Linux output" "$lin_ok" "$(parse_ping_summary 192.168.1.1 < "$(fixture linux/ping-ok.txt)")"
all_lost=$(printf '%-16s loss 100%%' 192.0.2.1)
assert_eq "parse_ping_summary at 100% loss (macOS)" "$all_lost" "$(parse_ping_summary 192.0.2.1 < "$(fixture macos/ping-loss.txt)")"
assert_eq "parse_ping_summary at 100% loss (Linux)" "$all_lost" "$(parse_ping_summary 192.0.2.1 < "$(fixture linux/ping-loss.txt)")"
partial=$(printf 'PING x (x): 56 data bytes\n--- x ping statistics ---\n20 packets transmitted, 15 packets received, 25.0%% packet loss\nround-trip min/avg/max/stddev = 1.0/2.0/3.0/0.5 ms\n')
assert_match "parse_ping_summary at partial loss" 'loss  25%  min 1.0 ms  avg 2.0 ms  max 3.0 ms' "$(printf '%s\n' "$partial" | parse_ping_summary x)"

# --- DHCP and DNS ---
assert_eq "parse_getpacket reads the hex lease" "192.168.1.1${TAB}7200${TAB}192.168.1.10,192.168.1.1" "$(parse_getpacket < "$(fixture macos/ipconfig-getpacket.txt)")"
assert_eq "parse_nmcli_dhcp4" "192.168.1.1${TAB}86400${TAB}192.168.1.10,192.168.1.1" "$(parse_nmcli_dhcp4 < "$(fixture linux/nmcli-dhcp4.txt)")"
assert_eq "parse_scutil_dns lists resolver #1 of the first block, unique" "192.168.1.10,2001:db8::10" "$(parse_scutil_dns < "$(fixture macos/scutil-dns.txt)")"

# --- UPnP ---
expected_services="http://192.168.1.1:1900/ctl/IPConn${TAB}urn:schemas-upnp-org:service:WANIPConnection:1${NL}http://192.168.1.1:5431/ctl/PPPConn${TAB}urn:schemas-upnp-org:service:WANPPPConnection:1"
assert_eq "parse_upnp_services joins relative urls and skips non-WAN services" "$expected_services" "$(parse_upnp_services http://192.168.1.1:1900/igd.xml < "$(fixture upnp/igd-desc.xml)")"
assert_eq "parse_port_mapping formats an entry" "TCP 51413 -> 192.168.1.20:51413  'Example Torrent'  lease 0s" "$(parse_port_mapping < "$(fixture upnp/soap-entry.xml)")"
parse_port_mapping < "$(fixture upnp/soap-fault.xml)" >/dev/null
assert_eq "parse_port_mapping returns 1 on a SOAP fault" "1" "$?"
printf '' | parse_port_mapping >/dev/null
assert_eq "parse_port_mapping returns 1 on empty input" "1" "$?"

# --- Wi-Fi ---
expected_wifi="PHY Mode: 802.11ac${NL}Channel: 36 (5GHz, 80MHz)${NL}Security: WPA2/WPA3 Personal${NL}Signal / Noise: -45 dBm / -92 dBm${NL}nearby networks:${NL}  <redacted>  WPA2/WPA3 Personal  channel 36 (5GHz, 80MHz)${NL}  <redacted>  WPA2 Personal  channel 10 (2GHz, 40MHz)"
assert_eq "parse_wifi_macos reads the current and nearby networks of the first interface" "$expected_wifi" "$(parse_wifi_macos < "$(fixture macos/sp-airport.txt)")"

# --- running from stdin (an agent without a skill folder) ---
out=$(bash -s -- --help < "$HHC_ROOT/$PROBE" 2>&1); rc=$?
assert_eq "--help from stdin exits 0 and prints Usage" "0 usage" "$rc $(printf '%s' "$out" | grep -q Usage && echo usage)"
bash -s -- --bogus < "$HHC_ROOT/$PROBE" >/dev/null 2>&1
assert_eq "an unknown option exits 2" "2" "$?"

# --- the gateway must answer: otherwise the port, UPnP and DNS results are not to be trusted ---
assert_match "gw_hint on macOS names Local Network and the unreliable results" 'Local Network.*unreliable|unreliable.*Local Network' "$(gw_hint no Darwin)"
assert_match "gw_hint on Linux warns that results may be incomplete" 'incomplete' "$(gw_hint no Linux)"
assert_eq "gw_hint is quiet when the gateway answered" "" "$(gw_hint yes Darwin)"

# --- control urls on other hosts are dropped (a gateway must not choose where requests go) ---
foreign='<root><device><serviceList><service><serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType><controlURL>http://evil.example/ctl</controlURL></service><service><serviceType>urn:schemas-upnp-org:service:WANPPPConnection:1</serviceType><controlURL>http://192.168.1.1:80@evil.example/x</controlURL></service></serviceList></device></root>'
assert_eq "parse_upnp_services drops control urls on other hosts" "" "$(printf '%s' "$foreign" | parse_upnp_services http://192.168.1.1:1900/igd.xml)"

# --- whole script against fake tools ---
STUBS=$HHC_TMP/pstubs
make_stub "$STUBS" uname 'if [ "$1" = -s ]; then echo Darwin; else exec '"$(command -v uname)"' "$@"; fi'
make_stub "$STUBS" route 'cat '"$(fixture macos/route-get-default.txt)"
make_stub "$STUBS" ifconfig 'cat '"$(fixture macos/ifconfig.txt)"
make_stub "$STUBS" arp 'cat '"$(fixture macos/arp-an.txt)"
make_stub "$STUBS" ipconfig 'cat '"$(fixture macos/ipconfig-getpacket.txt)"
make_stub "$STUBS" scutil 'cat '"$(fixture macos/scutil-dns.txt)"
make_stub "$STUBS" system_profiler 'cat '"$(fixture macos/sp-airport.txt)"
for fake in networksetup nc curl dig host netstat traceroute perl; do make_stub "$STUBS" "$fake" 'exit 1'; done
make_stub "$STUBS" ping 'exit 1'
out=$(PATH="$STUBS:$PATH" bash "$HHC_ROOT/$PROBE" 2>&1)
assert_match "probe.sh warns at the top when the gateway does not answer" 'WARNING.*Local Network' "$out"
make_stub "$STUBS" ping 'echo "5 packets transmitted, 5 packets received, 0.0% packet loss"; exit 0'
out=$(PATH="$STUBS:$PATH" bash "$HHC_ROOT/$PROBE" 2>&1)
assert_eq "probe.sh prints no warning when the gateway answers" "" "$(printf '%s\n' "$out" | grep 'WARNING')"
