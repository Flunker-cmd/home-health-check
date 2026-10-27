#!/usr/bin/env bash
# Read-only probe of the home router / mesh from a macOS or Linux computer on the LAN.
# No sudo needed. Touches only the local network, plus pings and a 3-hop traceroute to public DNS servers.
# Runs on bash 3.2. Same sections as probe.ps1.
# Usage: bash probe.sh [--sweep]   (-Sweep also works)
#   --sweep  ping every address in the local /24 first so the neighbor table lists all devices
export LC_ALL=C

TAB=$(printf '\t')
NORM_AWK='function nm(s,   a, n, i, o, sep) { n = split(s, a, /[:-]/); if (n != 6) return ""; o = ""; for (i = 1; i <= n; i++) { if (a[i] !~ /^[0-9a-fA-F]+$/ || length(a[i]) > 2) return ""; if (length(a[i]) == 1) a[i] = "0" a[i]; sep = (i > 1) ? ":" : ""; o = o sep tolower(a[i]) } return o }'

have() { command -v "$1" >/dev/null 2>&1; }

with_timeout() {
  local secs cmd dog rc
  secs=$1; shift
  "$@" & cmd=$!
  ( sleep "$secs"; kill "$cmd" 2>/dev/null ) >/dev/null 2>&1 &
  dog=$!
  { wait "$cmd"; } 2>/dev/null; rc=$?
  kill "$dog" 2>/dev/null; wait "$dog" 2>/dev/null
  return $rc
}

norm_mac() { awk -v m="$1" "$NORM_AWK"' BEGIN { print nm(m) }'; }

mask_to_prefix() {
  local n bits oldifs
  case $1 in
    0x*) n=$(( $1 )) ;;
    *.*) oldifs=$IFS; IFS=.; set -- $1; IFS=$oldifs; n=$(( ($1 << 24) | ($2 << 16) | ($3 << 8) | $4 )) ;;
    *) return 1 ;;
  esac
  bits=0
  while [ "$n" -gt 0 ]; do bits=$(( bits + (n & 1) )); n=$(( n >> 1 )); done
  echo "$bits"
}

parse_arp() {
  awk -v want="${1:-}" "$NORM_AWK"'
    { if (!match($0, /\([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\)/)) next
      ip = substr($0, RSTART + 1, RLENGTH - 2)
      mac = ""; ifc = ""
      n = split($0, f, " ")
      for (i = 1; i < n; i++) { if (f[i] == "at") mac = f[i + 1]; if (f[i] == "on") ifc = f[i + 1] }
      if (want != "" && ifc != want) next
      mac = nm(mac)
      if (mac == "" || mac == "ff:ff:ff:ff:ff:ff" || mac == "00:00:00:00:00:00") next
      if (substr(mac, 1, 8) == "01:00:5e" || substr(mac, 1, 5) == "33:33") next
      print ip "\t" mac }'
}

parse_ip_neigh() {
  awk "$NORM_AWK"'
    { st = $NF; mac = ""
      for (i = 1; i < NF; i++) if ($i == "lladdr") mac = $(i + 1)
      if (st !~ /^(REACHABLE|STALE|DELAY|PROBE|PERMANENT)$/) next
      mac = nm(mac); if (mac == "") next
      print $1 "\t" mac }'
}

parse_upnp_desc() {
  tr '\r\n' '  ' | sed -e 's/<deviceList>.*//' | awk '
    function tag(s, t,   a, i, j) { a = "<" t ">"; i = index(s, a); if (!i) return ""; s = substr(s, i + length(a)); j = index(s, "<"); s = substr(s, 1, j - 1); gsub(/^ +| +$/, "", s); return s }
    { out = ""; n = split("friendlyName manufacturer modelName modelNumber", names, " ")
      for (k = 1; k <= n; k++) { v = tag($0, names[k]); if (v != "") { out = out sep v; sep = " | " } }
      print out }' | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&apos;/'/g" -e 's/&amp;/\&/g'
}

location_host_ok() { local h; h=${2#*://}; h=${h%%/*}; h=${h%%:*}; [ "$h" = "$1" ]; }

lan_hint() {
  [ "$1" -eq 0 ] || return 0
  case $2 in
    Darwin) echo "(no other devices answered - on macOS 15 and later, if this runs inside an app instead of Terminal, allow that app under System Settings > Privacy & Security > Local Network and run again)" ;;
    *) echo "(no devices answered - check that this computer is on the home network)" ;;
  esac
}

TAG_AWK='function tag(s, t,   a, i, j) { a = "<" t ">"; i = index(s, a); if (!i) return ""; s = substr(s, i + length(a)); j = index(s, "<"); s = substr(s, 1, j - 1); gsub(/^ +| +$/, "", s); return s }'

usage() {
  echo "Usage: bash probe.sh [--sweep]"
  echo "  --sweep  ping every address in the local /24 first"
}

# ping output on stdin (macOS or Linux) -> one summary line in the probe.ps1 format
parse_ping_summary() {
  awk -v t="$1" '
    / packet loss/ { for (i = 1; i <= NF; i++) if ($i ~ /%$/) { loss = $i; sub(/%$/, "", loss); sub(/\..*/, "", loss) } }
    /^(round-trip|rtt) / { split($0, a, " = "); split(a[2], b, "/"); mn = b[1]; av = b[2]; mx = b[3] }
    END {
      if (loss == "" || loss + 0 >= 100 || mn == "") { printf "%-16s loss 100%%\n", t; exit }
      printf "%-16s loss %3d%%  min %s ms  avg %s ms  max %s ms\n", t, loss, mn, av, mx
    }'
}

# ipconfig getpacket output on stdin -> "server<TAB>lease seconds<TAB>dns,dns"
parse_getpacket() {
  local line server="" lease="" dns=""
  while IFS= read -r line; do
    case $line in
      server_identifier*) server=${line#*: } ;;
      lease_time*) lease=${line#*: } ;;
      domain_name_server*) dns=${line#*\{}; dns=${dns%\}*}; dns=$(printf '%s' "$dns" | tr -d ' ') ;;
    esac
  done
  case $lease in 0x*) lease=$(( lease )) ;; esac
  printf '%s\t%s\t%s\n' "$server" "$lease" "$dns"
}

# nmcli -t -f DHCP4 device show output on stdin -> same triple
parse_nmcli_dhcp4() {
  awk '
    /dhcp_server_identifier = / { s = $NF }
    /dhcp_lease_time = / { l = $NF }
    /domain_name_servers = / { sub(/.*domain_name_servers = /, ""); sub(/ +$/, ""); gsub(/ +/, ","); d = $0 }
    END { printf "%s\t%s\t%s\n", s, l, d }'
}

# scutil --dns on stdin -> unique nameservers of resolver #1 in the first block, comma separated
parse_scutil_dns() {
  awk '
    /^DNS configuration \(for scoped queries\)/ { exit }
    /^resolver #/ { r = ($0 ~ /^resolver #1$/); next }
    r && /nameserver\[[0-9]+\]/ { n = $NF; if (!(n in seen)) { seen[n] = 1; out = out sep n; sep = "," } }
    END { print out }'
}

# UPnP device description on stdin, $1 = its url -> "control url<TAB>service type" for WAN IP/PPP connection services
parse_upnp_services() {
  tr '\r\n' '  ' | awk -v loc="$1" "$TAG_AWK"'
    BEGIN { p = index(loc, "://"); rest = substr(loc, p + 3); j = index(rest, "/"); auth = (j > 0) ? substr(rest, 1, j - 1) : rest; base = substr(loc, 1, p + 2) auth }
    { s = $0
      while ((i = index(s, "</service>")) > 0) {
        rec = substr(s, 1, i - 1); s = substr(s, i + 10)
        t = tag(rec, "serviceType"); c = tag(rec, "controlURL")
        if (t ~ /WAN(IP|PPP)Connection/ && c != "") { if (c !~ /^https?:\/\//) { if (c !~ /^\//) c = "/" c; c = base c } print c "\t" t }
      } }'
}

# SOAP GetGenericPortMappingEntry response on stdin -> one line; returns 1 on a fault or empty input
parse_port_mapping() {
  tr '\r\n' '  ' | awk "$TAG_AWK"'
    { ext = tag($0, "NewExternalPort"); if (ext == "") next
      printf "%s %s -> %s:%s  \047%s\047  lease %ss\n", tag($0, "NewProtocol"), ext, tag($0, "NewInternalClient"), tag($0, "NewInternalPort"), tag($0, "NewPortMappingDescription"), tag($0, "NewLeaseDuration"); ok = 1 }
    END { exit !ok }'
}

# system_profiler SPAirPortDataType on stdin -> current network facts, then nearby networks (first interface only)
parse_wifi_macos() {
  awk '
    function flush() { if (name != "") printf "  %s  %s  channel %s\n", name, sec, ch; name = ""; sec = ""; ch = "" }
    /^        [^ ]+:$/ { ifc++; if (ifc > 1) exit }
    /Current Network Information:/ { mode = 1; next }
    /Other Local Wi-Fi Networks:/ { mode = 2; print "nearby networks:"; hdr = 1; next }
    mode == 1 && /^ +(PHY Mode|Channel|Security|Signal \/ Noise): / { t = $0; sub(/^ +/, "", t); print t }
    mode == 2 && /^            [^ ].*:$/ { flush(); name = $0; sub(/^ +/, "", name); sub(/:$/, "", name); next }
    mode == 2 && /^ +Security: / { sec = $0; sub(/^ +Security: /, "", sec) }
    mode == 2 && /^ +Channel: / { ch = $0; sub(/^ +Channel: /, "", ch) }
    END { flush(); if (!hdr) print "nearby networks:" }'
}

port_open() {
  if have nc; then
    if [ "$os" = Darwin ]; then nc -z -G 1 -w 1 "$1" "$2" </dev/null >/dev/null 2>&1; else nc -z -w 1 "$1" "$2" </dev/null >/dev/null 2>&1; fi
  else
    with_timeout 1 bash -c 'exec 3<>/dev/tcp/$1/$2' _ "$1" "$2" >/dev/null 2>&1
  fi
}

# SSDP discovery for search target $1: prints "ip<TAB>location" for every reply within 4 seconds
ssdp_scan() {
  have perl || return 0
  perl - "$1" <<'PERL' 2>/dev/null
use strict; use Socket; use IO::Socket::INET; use IO::Select;
my $s = IO::Socket::INET->new(Proto => 'udp') or exit 0;
my $msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: $ARGV[0]\r\n\r\n";
send($s, $msg, 0, pack_sockaddr_in(1900, inet_aton('239.255.255.250')));
my $sel = IO::Select->new($s);
my $end = time + 4;
while (time < $end) {
  for my $fh ($sel->can_read(0.5)) {
    my $peer = recv($fh, my $buf, 4096, 0);
    next unless defined $peer;
    my ($port, $addr) = sockaddr_in($peer);
    print inet_ntoa($addr), "\t$1\n" if $buf =~ /^LOCATION:\s*(\S+)/im;
  }
}
PERL
}

section() { printf '\n## %s\n' "$1"; }

neighbors() {
  if [ "$os" != Darwin ] && have ip; then ip -4 neigh show dev "$iface" 2>/dev/null | parse_ip_neigh
  else arp -an 2>/dev/null | parse_arp "$iface"; fi
}

# system DNS servers, comma separated
dns_servers() {
  if [ "$os" = Darwin ]; then scutil --dns 2>/dev/null | parse_scutil_dns; return; fi
  local d=""
  if have resolvectl; then d=$(resolvectl dns "$iface" 2>/dev/null | sed 's/^[^:]*: *//' | tr -s ' ' ','); fi
  [ -n "$d" ] || d=$(awk '$1 == "nameserver" { print $2 }' /etc/resolv.conf 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  echo "$d"
}

# fills $iface $gw $ip $prefix $selfmac
net_info() {
  local ifc addr maskhex
  if [ "$os" = Darwin ]; then
    iface=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }')
    gw=$(route -n get default 2>/dev/null | awk '/gateway:/ { print $2; exit }')
    ifc=$(ifconfig "$iface" 2>/dev/null)
    ip=$(printf '%s\n' "$ifc" | awk '$1 == "inet" { print $2; exit }')
    maskhex=$(printf '%s\n' "$ifc" | awk '$1 == "inet" { for (i = 1; i < NF; i++) if ($i == "netmask") print $(i + 1); exit }')
    prefix=$(mask_to_prefix "$maskhex")
  else
    iface=$(ip route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
    gw=$(ip route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit } }')
    addr=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "inet") { print $(i + 1); exit } }')
    ip=${addr%/*}; prefix=${addr#*/}
  fi
}

hops() {
  if have traceroute; then traceroute -n -m 3 -w 1 -q 1 1.1.1.1 2>/dev/null | awk '/^ *[0-9]+ / { print "  " $0 }' | sed 's/^   */ /'
  elif have tracepath; then tracepath -n -m 3 1.1.1.1 2>/dev/null | awk '/^ *[0-9]+:/ { print " " $0 }' | head -3
  else
    local ttl=1 out addr
    while [ "$ttl" -le 3 ]; do
      if [ "$os" = Darwin ]; then out=$(ping -c 1 -m "$ttl" -t 1 1.1.1.1 2>&1); else out=$(ping -c 1 -t "$ttl" -W 1 1.1.1.1 2>&1); fi
      addr=$(printf '%s\n' "$out" | grep -i 'exceeded' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      echo " $ttl  ${addr:-*}"
      ttl=$((ttl + 1))
    done
  fi
}

main() {
  local want_sweep=no a o
  for a in "$@"; do
    o=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    case $o in
      --sweep|-sweep) want_sweep=yes ;;
      -h|--help|-help) usage; return 0 ;;
      *) usage >&2; return 2 ;;
    esac
  done

  os=$(uname -s)
  work=$(mktemp -d "${TMPDIR:-/tmp}/hhc-probe.XXXXXX") || return 1
  trap 'rm -rf "$work"' EXIT
  local iface gw ip prefix
  net_info
  if [ -z "$ip" ] || [ -z "$gw" ]; then echo "No default network found. Connect to the home network and try again." >&2; return 1; fi

  section "Gateway and DHCP"
  local port_name="" gwmac dhcp dhcp_server dhcp_lease dhcp_dns dnslist
  if [ "$os" = Darwin ]; then port_name=$(networksetup -listallhardwareports 2>/dev/null | awk -v d="$iface" '/^Hardware Port:/ { p = substr($0, 16) } $1 == "Device:" && $2 == d { print p; exit }'); fi
  echo "adapter:        ${port_name:-$iface}${port_name:+ ($iface)}"
  echo "this computer:  $ip/$prefix"
  echo "gateway:        $gw"
  if [ "$os" = Darwin ]; then ping -c 1 -t 1 "$gw" >/dev/null 2>&1; else ping -c 1 -W 1 "$gw" >/dev/null 2>&1; fi
  gwmac=$(neighbors | awk -F '\t' -v g="$gw" '$1 == g { print $2; exit }')
  echo "gateway mac:    ${gwmac:-unknown}"
  dhcp=""
  if [ "$os" = Darwin ]; then dhcp=$(ipconfig getpacket "$iface" 2>/dev/null | parse_getpacket)
  elif have nmcli; then dhcp=$(nmcli -t -f DHCP4 device show "$iface" 2>/dev/null | parse_nmcli_dhcp4); fi
  dhcp_server=$(printf '%s' "$dhcp" | cut -f1); dhcp_lease=$(printf '%s' "$dhcp" | cut -f2); dhcp_dns=$(printf '%s' "$dhcp" | cut -f3)
  if [ -n "$dhcp_server" ]; then
    echo "DHCP server:    $dhcp_server"
    [ -n "$dhcp_lease" ] && echo "DHCP lease:     $(awk -v s="$dhcp_lease" 'BEGIN { printf "%.1f h", s / 3600 }')"
    [ -n "$dhcp_dns" ] && echo "DNS from DHCP:  $dhcp_dns"
  else
    echo "DHCP:           not readable (static address, or no DHCP client information available)"
  fi
  dnslist=$(dns_servers)
  echo "DNS servers:    $dnslist"

  section "Latency and packet loss (20 pings each)"
  local targets t k=0
  targets=$(printf '%s\n' "$gw" $(printf '%s' "$dnslist" | tr ',' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') 1.1.1.1 9.9.9.9 8.8.8.8 | awk '!s[$0]++')
  for t in $targets; do
    k=$((k + 1))
    if [ "$os" = Darwin ]; then ( ping -c 20 -t 40 "$t" > "$work/ping.$k" 2>&1 ) & else ( ping -c 20 -W 1 "$t" > "$work/ping.$k" 2>&1 ) & fi
  done
  wait
  k=0
  for t in $targets; do k=$((k + 1)); parse_ping_summary "$t" < "$work/ping.$k"; done

  section "Open TCP ports on the gateway"
  local p open=""
  for p in 21 22 23 53 80 443 445 5000 7547 8080 8443 20001 49152; do port_open "$gw" "$p" && open="$open${open:+, }$p"; done
  echo "open:   $open"
  echo "tested: 21, 22, 23, 53, 80, 443, 445, 5000, 7547, 8080, 8443, 20001, 49152"

  section "UPnP devices (SSDP)"
  : > "$work/ctl.tsv"
  ssdp_scan upnp:rootdevice | awk -F '\t' '!seen[$2]++' > "$work/ssdp.tsv"
  local sip loc xml
  if [ -s "$work/ssdp.tsv" ]; then
    while IFS="$TAB" read -r sip loc; do
      location_host_ok "$sip" "$loc" || continue
      xml=$(curl -fsS --max-time 4 "$loc" 2>/dev/null) || continue
      printf '%-15s %s | %s\n' "$sip" "$(printf '%s' "$xml" | parse_upnp_desc)" "$loc"
      [ "$sip" = "$gw" ] && printf '%s' "$xml" | parse_upnp_services "$loc" >> "$work/ctl.tsv"
    done < "$work/ssdp.tsv"
  else
    echo "no UPnP devices answered (UPnP may be off, or perl is not available)"
  fi

  section "UPnP port mappings on the gateway"
  local url stype i body resp line
  if [ ! -s "$work/ctl.tsv" ]; then echo "no WAN connection service found (UPnP IGD off or not exposed)"; fi
  while IFS="$TAB" read -r url stype; do
    i=0
    while [ "$i" -lt 64 ]; do
      body='<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:GetGenericPortMappingEntry xmlns:u="'"$stype"'"><NewPortMappingIndex>'"$i"'</NewPortMappingIndex></u:GetGenericPortMappingEntry></s:Body></s:Envelope>'
      resp=$(curl -fsS --max-time 4 -H 'Content-Type: text/xml; charset="utf-8"' -H "SOAPAction: \"$stype#GetGenericPortMappingEntry\"" -d "$body" "$url" 2>/dev/null) || { [ "$i" -eq 0 ] && echo "no mappings"; break; }
      line=$(printf '%s' "$resp" | parse_port_mapping) || { [ "$i" -eq 0 ] && echo "no mappings"; break; }
      echo "$line"
      i=$((i + 1))
    done
  done < "$work/ctl.tsv"

  section "First hops to the internet (double NAT / CGNAT check)"
  hops
  echo "(a private 2nd hop = double NAT; 100.64.x.x-100.127.x.x = carrier-grade NAT)"

  section "DNS path"
  local srv ans
  for srv in $(printf '%s\n' "$gw" $(printf '%s' "$dnslist" | tr ',' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') | awk '!s[$0]++'); do
    ans=""
    if have dig; then ans=$(dig +short +time=2 +tries=1 "@$srv" doubleclick.net A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    elif have host; then ans=$(host -W 2 doubleclick.net "$srv" 2>/dev/null | awk '/has address/ { print $NF; exit }'); fi
    printf 'doubleclick.net via %-15s -> %s\n' "$srv" "${ans:-(no answer)}"
  done
  have dig || have host || echo "(dig and host not available: install dnsutils to test DNS filtering)"
  echo "(0.0.0.0 or no answer = filtered; a real address = not filtered)"

  section "IPv6"
  if [ "$os" = Darwin ]; then
    ifconfig "$iface" 2>/dev/null | awk '$1 == "inet6" && $2 !~ /^fe80/ { print "address: " $2 "/" $4 }'
    netstat -rn -f inet6 2>/dev/null | awk '$1 == "default" { print "IPv6 default route via " $2; exit }'
  else
    ip -6 addr show dev "$iface" scope global 2>/dev/null | awk '$1 == "inet6" { print "address: " $2 }'
    ip -6 route show default 2>/dev/null | awk '{ print "IPv6 default route via " $3; exit }'
  fi
  printf '%s' "$dnslist" | tr ',' '\n' | grep ':' | while IFS= read -r a; do echo "IPv6 DNS: $a"; done

  section "Wi-Fi"
  if [ "$os" = Darwin ]; then with_timeout 20 system_profiler SPAirPortDataType 2>/dev/null | parse_wifi_macos
  elif have nmcli; then
    nmcli -t -f ACTIVE,SSID,CHAN,SIGNAL,SECURITY dev wifi list --rescan no 2>/dev/null | awk -F: '{ printf "  %s%s  %s  channel %s signal %s\n", ($1 == "yes") ? "* " : "", $2, $5, $3, $4 }'
  else echo "no Wi-Fi tool found (nmcli)"; fi

  section "Devices on the LAN (ARP)"
  if [ "$want_sweep" = yes ] && [ "$prefix" -ge 24 ]; then
    local net=${ip%.*} n=1
    while [ "$n" -le 254 ]; do
      if [ "$os" = Darwin ]; then ping -c 1 -t 1 "$net.$n" >/dev/null 2>&1 & else ping -c 1 -W 1 "$net.$n" >/dev/null 2>&1 & fi
      n=$((n + 1)); [ $((n % 64)) -eq 0 ] && wait
    done
    wait
    sleep 1
  fi
  neighbors | sort -t . -k1,1n -k2,2n -k3,3n -k4,4n > "$work/arp.tsv"
  awk -F '\t' '{ printf "%-15s %s\n", $1, $2 }' "$work/arp.tsv"
  lan_hint "$(awk -F '\t' -v g="$gw" '$1 != g' "$work/arp.tsv" | wc -l | tr -d ' ')" "$os"
  echo "(look up the first three MAC bytes for the vendor; random-looking MACs with the 2nd hex digit 2/6/a/e are private phone/tablet addresses)"
}

main "$@"
