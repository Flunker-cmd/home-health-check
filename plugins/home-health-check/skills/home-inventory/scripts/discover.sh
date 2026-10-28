#!/usr/bin/env bash
# Find the devices on the local network from macOS or Linux. No sudo needed. Runs on bash 3.2.
# Only talks to the local subnet (plus one optional download of a public MAC vendor list).
# Usage: bash discover.sh [--ports] [--oui] [--json]   (-Ports, -Oui, -Json also work)
#   --ports  also check a few well-known TCP ports per device to guess what it is
#   --oui    look up MAC vendors in Wireshark's public vendor list (downloaded once to <data dir>/cache/manuf.txt;
#            <data dir> is $HOME_HEALTH_CHECK_DIR, or ~/.home-health-check when that is not set)
#   --json   print JSON instead of a table
export LC_ALL=C

TAB=$(printf '\t'); CR=$(printf '\r')
NORM_AWK='function nm(s,   a, n, i, o, sep) { n = split(s, a, /[:-]/); if (n != 6) return ""; o = ""; for (i = 1; i <= n; i++) { if (a[i] !~ /^[0-9a-fA-F]+$/ || length(a[i]) > 2) return ""; if (length(a[i]) == 1) a[i] = "0" a[i]; sep = (i > 1) ? ":" : ""; o = o sep tolower(a[i]) } return o }'
PORTS="22:ssh 53:dns 80:http 443:https 445:smb 554:rtsp 631:ipp 1400:sonos 1883:mqtt 3389:rdp 5000:nas/upnp 5001:nas 8008:cast 8009:cast 8080:http-alt 8123:home-assistant 9100:printer 32400:plex"

usage() {
  echo "Usage: bash discover.sh [--ports] [--oui] [--json]"
  echo "  --ports  check well-known TCP ports per device"
  echo "  --oui    look up MAC vendors (downloads a public list once)"
  echo "  --json   print JSON instead of a table"
}

have() { command -v "$1" >/dev/null 2>&1; }

# has_row <file> <ip> [desc]: exit 0 if the file has a row for the ip (with a non-empty second column when desc is given)
has_row() { awk -F "$TAB" -v k="$2" -v need="${3:-}" '$1 == k && (need == "" || $2 != "") { f = 1 } END { exit !f }' "$1"; }

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

is_random_mac() { local m; m=$(norm_mac "$1"); case ${m:1:1} in 2|6|a|e) return 0 ;; esac; return 1; }

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

ip_to_num() { local oldifs=$IFS; IFS=.; set -- $1; IFS=$oldifs; echo $(( ($1 << 24) | ($2 << 16) | ($3 << 8) | $4 )); }
num_to_ip() { echo "$(( ($1 >> 24) & 255 )).$(( ($1 >> 16) & 255 )).$(( ($1 >> 8) & 255 )).$(( $1 & 255 ))"; }

# arp -an (macOS or net-tools) on stdin -> "ip<TAB>mac"; optional interface filter
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

# ip -4 neigh on stdin -> "ip<TAB>mac" for live entries
parse_ip_neigh() {
  awk "$NORM_AWK"'
    { st = $NF; mac = ""
      for (i = 1; i < NF; i++) if ($i == "lladdr") mac = $(i + 1)
      if (st !~ /^(REACHABLE|STALE|DELAY|PROBE|PERMANENT)$/) next
      mac = nm(mac); if (mac == "") next
      print $1 "\t" mac }'
}

# dns-sd -Q ... PTR output on stdin -> first target name
parse_dnssd_ptr() { awk '$2 == "Add" && / PTR / && !/No Such Record/ { n = $NF; sub(/\.$/, "", n); print n; exit }'; }

# UPnP device description on stdin -> "friendlyName | manufacturer | modelName | modelNumber" of the first device
parse_upnp_desc() {
  tr '\r\n' '  ' | sed -e 's/<deviceList>.*//' | awk '
    function tag(s, t,   a, i, j) { a = "<" t ">"; i = index(s, a); if (!i) return ""; s = substr(s, i + length(a)); j = index(s, "<"); s = substr(s, 1, j - 1); gsub(/^ +| +$/, "", s); return s }
    { out = ""; n = split("friendlyName manufacturer modelName modelNumber", names, " ")
      for (k = 1; k <= n; k++) { v = tag($0, names[k]); if (v != "") { out = out sep v; sep = " | " } }
      print out }' | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&apos;/'/g" -e 's/&amp;/\&/g'
}

# only fetch a LOCATION url when its host is the device that announced it
location_host_ok() { local h; case $2 in http://*|https://*) ;; *) return 1 ;; esac; case $2 in *@*) return 1 ;; esac; h=${2#*://}; h=${h%%/*}; h=${h%%:*}; [ "$h" = "$1" ]; }

# normalized MACs on stdin -> "mac<TAB>vendor", using a Wireshark manuf file
oui_lookup() {
  [ -s "$1" ] || return 0
  awk -F '\t' '
    FNR == NR { sub(/[[:space:]]+$/, "", $1); if ($1 ~ /^[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]$/ && $3 != "") { sub(/[ \t]+$/, "", $3); v[tolower($1)] = $3 } next }
    { m = tolower($0); k = substr(m, 1, 8); if (k in v) print m "\t" v[k] }' "$1" -
}

# prints the cache path; moves a pre-0.3 top-level file there; downloads when missing or older than 90 days
ensure_oui() {
  local dir file tmp
  dir=${HOME_HEALTH_CHECK_DIR:-$HOME/.home-health-check}
  file=$dir/cache/manuf.txt
  mkdir -p "$dir/cache" 2>/dev/null
  if [ -f "$dir/manuf.txt" ] && [ ! -f "$file" ]; then mv "$dir/manuf.txt" "$file"; fi
  if [ ! -s "$file" ] || [ -n "$(find "$file" -mtime +90 -print 2>/dev/null)" ]; then
    tmp=$file.part
    if curl -fsS --max-time 60 -o "$tmp" https://www.wireshark.org/download/automated/data/manuf 2>/dev/null; then mv "$tmp" "$file"; else rm -f "$tmp"; fi
  fi
  echo "$file"
}

# records file: ip, mac, vendor, random(yes|no), name, upnp, ports separated by tabs
print_json() {
  printf '{"scanned":"%s","subnet":"%s","gateway":"%s","devices":[\n' "$1" "$2" "$3"
  awk -F '\t' '
    function js(s,   i, c, o) { o = ""; for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (c == "\\") o = o "\\\\"; else if (c == "\"") o = o "\\\""; else if (c >= " ") o = o c } return "\"" o "\"" }
    { if (NR > 1) printf ",\n"
      printf "{\"ip\":%s,\"mac\":%s,\"vendor\":%s,\"random_mac\":%s,\"name\":%s,\"upnp\":%s,\"ports\":%s}", js($1), js($2), js($3), ($4 == "yes" ? "true" : "false"), js($5), js($6), js($7) }
    END { if (NR > 0) printf "\n" }' "$4"
  printf ']}\n'
}

print_table() {
  awk -F '\t' '
    function pad(s, w) { while (length(s) < w) s = s " "; return s }
    function dashes(w,   s) { s = ""; while (length(s) < w) s = s "-"; return s }
    { n++; r[n, 1] = $1; r[n, 2] = $2; r[n, 3] = ($4 == "yes") ? "yes" : ""; r[n, 4] = $3; r[n, 5] = $5; r[n, 6] = $6; r[n, 7] = $7 }
    END {
      split("ip mac rnd vendor name upnp ports", h, " ")
      for (c = 1; c <= 7; c++) { w[c] = length(h[c]); for (i = 1; i <= n; i++) if (length(r[i, c]) > w[c]) w[c] = length(r[i, c]) }
      line = ""; rule = ""
      for (c = 1; c <= 7; c++) { sep = (c > 1) ? "  " : ""; line = line sep pad(h[c], w[c]); rule = rule sep dashes(w[c]) }
      sub(/ +$/, "", line); print line; print rule
      for (i = 1; i <= n; i++) { line = ""; for (c = 1; c <= 7; c++) { sep = (c > 1) ? "  " : ""; line = line sep pad(r[i, c], w[c]) } sub(/ +$/, "", line); print line }
    }' "$1"
}

# $1 = number of other devices that answered, $2 = uname -s
lan_hint() {
  [ "$1" -eq 0 ] || return 0
  case $2 in
    Darwin) echo "(no other devices answered - on macOS 15 and later, if this runs inside an app instead of Terminal, allow that app under System Settings > Privacy & Security > Local Network, then run it again)" ;;
    *) echo "(no devices answered - check that this computer is on the home network)" ;;
  esac
}

jobs_n=0
throttle() { jobs_n=$((jobs_n + 1)); if [ "$jobs_n" -ge "${1:-32}" ]; then wait; jobs_n=0; fi; }

name_lookup() {
  local n rev
  if [ "$os" = Darwin ]; then
    n=$(with_timeout 3 host -W 1 "$1" 2>/dev/null | awk '/domain name pointer/ { n = $NF; sub(/\.$/, "", n); print n; exit }')
    if [ -z "$n" ] && have dns-sd; then
      rev=$(echo "$1" | awk -F. '{ print $4 "." $3 "." $2 "." $1 }')
      n=$(with_timeout 3 dns-sd -Q "$rev.in-addr.arpa." PTR 2>/dev/null | parse_dnssd_ptr)
    fi
  else
    n=$(getent hosts "$1" 2>/dev/null | awk '{ print $2; exit }')
    if [ -z "$n" ] && have avahi-resolve; then n=$(with_timeout 3 avahi-resolve -a "$1" 2>/dev/null | awk '{ print $2; exit }'); fi
  fi
  printf '%s' "$n" | tr '\t\r\n' '   '
}

port_open() {
  if have nc; then
    if [ "$os" = Darwin ]; then nc -z -G 1 -w 1 "$1" "$2" </dev/null >/dev/null 2>&1; else nc -z -w 1 "$1" "$2" </dev/null >/dev/null 2>&1; fi
  else
    with_timeout 1 bash -c 'exec 3<>/dev/tcp/$1/$2' _ "$1" "$2" >/dev/null 2>&1
  fi
}

# SSDP discovery: prints "ip<TAB>location" for every reply within 4 seconds
ssdp_scan() {
  have perl || return 0
  perl <<'PERL' 2>/dev/null
use strict; use Socket; use IO::Socket::INET; use IO::Select;
my $s = IO::Socket::INET->new(Proto => 'udp') or exit 0;
my $msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n";
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

fetch_desc() { curl -fsS --max-time 3 "$1" 2>/dev/null | parse_upnp_desc | tr '\t\r\n' '   '; }

main() {
  local want_ports=no want_oui=no want_json=no a o
  for a in "$@"; do
    o=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    case $o in
      --ports|-ports) want_ports=yes ;;
      --oui|-oui) want_oui=yes ;;
      --json|-json) want_json=yes ;;
      -h|--help|-help) usage; return 0 ;;
      *) usage >&2; return 2 ;;
    esac
  done

  os=$(uname -s)
  work=$(mktemp -d "${TMPDIR:-/tmp}/hhc-discover.XXXXXX") || return 1
  trap 'rm -rf "$work"' EXIT

  local iface gw ifc ip prefix addr maskhex selfmac net mask count i n h hosts_ip replies
  if [ "$os" = Darwin ]; then
    iface=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }')
    gw=$(route -n get default 2>/dev/null | awk '/gateway:/ { print $2; exit }')
    ifc=$(ifconfig "$iface" 2>/dev/null)
    ip=$(printf '%s\n' "$ifc" | awk '$1 == "inet" { print $2; exit }')
    maskhex=$(printf '%s\n' "$ifc" | awk '$1 == "inet" { for (i = 1; i < NF; i++) if ($i == "netmask") print $(i + 1); exit }')
    prefix=$(mask_to_prefix "$maskhex")
    selfmac=$(printf '%s\n' "$ifc" | awk '$1 == "ether" { print $2; exit }')
  else
    iface=$(ip route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
    gw=$(ip route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit } }')
    addr=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "inet") { print $(i + 1); exit } }')
    ip=${addr%/*}; prefix=${addr#*/}
    selfmac=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
  fi
  if [ -z "$ip" ] || [ -z "$prefix" ] || [ -z "$gw" ]; then echo "No default network found. Connect to the home network and try again." >&2; return 1; fi
  [ "$prefix" -lt 22 ] && prefix=22                      # never sweep more than 1024 addresses
  n=$(ip_to_num "$ip")
  mask=$(( 4294967295 ^ ((1 << (32 - prefix)) - 1) ))
  net=$(( n & mask ))
  count=$(( (1 << (32 - prefix)) - 2 ))

  # ping sweep so the neighbor table fills up
  # every reply from another address is recorded: no reply at all means no access to the LAN (see lan_hint)
  : > "$work/replies"
  i=1
  while [ "$i" -le "$count" ]; do
    n=$((net + i))
    h="$(( (n >> 24) & 255 )).$(( (n >> 16) & 255 )).$(( (n >> 8) & 255 )).$(( n & 255 ))"
    if [ "$h" != "$ip" ]; then
      if [ "$os" = Darwin ]; then ( ping -c 1 -t 1 "$h" >/dev/null 2>&1 && echo 1 >> "$work/replies" ) & else ( ping -c 1 -W 1 "$h" >/dev/null 2>&1 && echo 1 >> "$work/replies" ) & fi
      throttle 64
    fi
    i=$((i + 1))
  done
  wait; jobs_n=0
  replies=$(wc -l < "$work/replies" | tr -d ' ')
  sleep 1

  # neighbors (this computer first, so its own name wins)
  selfmac=$(norm_mac "$selfmac")
  myname=$(hostname 2>/dev/null); myname=${myname%%.*}
  printf '%s\t%s\n' "$ip" "$selfmac" > "$work/all.tsv"
  if [ "$os" != Darwin ] && have ip; then ip -4 neigh show dev "$iface" 2>/dev/null | parse_ip_neigh >> "$work/all.tsv"
  else arp -an 2>/dev/null | parse_arp "$iface" >> "$work/all.tsv"; fi
  awk -F '\t' '!seen[$1]++' "$work/all.tsv" > "$work/neigh.tsv"
  : > "$work/vend.tsv"; : > "$work/names.tsv"; : > "$work/upnp.tsv"; : > "$work/ports.tsv"
  printf '%s\t%s (this computer)\n' "$ip" "$myname" > "$work/names.tsv"

  if [ "$want_oui" = yes ]; then
    cut -f2 "$work/neigh.tsv" | oui_lookup "$(ensure_oui)" > "$work/vend.tsv"
  fi

  # names from DNS or mDNS, in parallel
  while IFS= read -r hosts_ip; do
    [ "$hosts_ip" = "$ip" ] && continue
    ( printf '%s\t%s\n' "$hosts_ip" "$(name_lookup "$hosts_ip")" > "$work/named.$hosts_ip" ) &
    throttle 32
  done < <(cut -f1 "$work/neigh.tsv")
  wait; jobs_n=0
  cat "$work"/named.* >> "$work/names.tsv" 2>/dev/null

  # UPnP / SSDP descriptions
  ssdp_scan | awk -F '\t' '!seen[$1]++' > "$work/ssdp.tsv"
  while IFS="$TAB" read -r hosts_ip loc; do
    location_host_ok "$hosts_ip" "$loc" || continue
    ( printf '%s\t%s\n' "$hosts_ip" "$(fetch_desc "$loc")" > "$work/upnpd.$hosts_ip" ) &
    throttle 16
    has_row "$work/neigh.tsv" "$hosts_ip" || printf '%s\t\n' "$hosts_ip" >> "$work/neigh.tsv"
  done < "$work/ssdp.tsv"
  wait; jobs_n=0
  cat "$work"/upnpd.* >> "$work/upnp.tsv" 2>/dev/null

  # well-known ports (opt-in)
  if [ "$want_ports" = yes ]; then
    : > "$work/ports.raw"
    while IFS= read -r hosts_ip; do
      for p in $PORTS; do
        ( port_open "$hosts_ip" "${p%%:*}" && printf '%s\t%s/%s\n' "$hosts_ip" "${p%%:*}" "${p#*:}" >> "$work/ports.raw" ) &
        throttle 64
      done
    done < <(cut -f1 "$work/neigh.tsv")
    wait; jobs_n=0
    sort -t "$TAB" -k1,1 -k2,2n "$work/ports.raw" | awk -F '\t' '{ p[$1] = p[$1] (p[$1] == "" ? "" : " ") $2 } END { for (k in p) print k "\t" p[k] }' > "$work/ports.tsv"
    # SSDP replies are often blocked; ask the well-known description URLs directly
    while IFS="$TAB" read -r hosts_ip plist; do
      has_row "$work/upnp.tsv" "$hosts_ip" desc && continue
      case " $plist " in *" 1400/"*) u="http://$hosts_ip:1400/xml/device_description.xml" ;; *" 8008/"*) u="http://$hosts_ip:8008/ssdp/device-desc.xml" ;; *) continue ;; esac
      d=$(fetch_desc "$u")
      [ -n "$d" ] && printf '%s\t%s\n' "$hosts_ip" "$d" >> "$work/upnp.tsv"
    done < "$work/ports.tsv"
  fi

  # records: one line per device
  awk -F '\t' -v OFS='\t' -v fv="$work/vend.tsv" -v fn="$work/names.tsv" -v fu="$work/upnp.tsv" -v fp="$work/ports.tsv" '
    FILENAME == fv { vend[$1] = $2; next }
    FILENAME == fn { name[$1] = $2; next }
    FILENAME == fu { if ($2 != "") upnp[$1] = $2; next }
    FILENAME == fp { ports[$1] = $2; next }
    { rnd = "no"; d = substr($2, 2, 1); if (d == "2" || d == "6" || d == "a" || d == "e") rnd = "yes"
      print $1, $2, vend[$2], rnd, name[$1], upnp[$1], ports[$1] }' \
    "$work/vend.tsv" "$work/names.tsv" "$work/upnp.tsv" "$work/ports.tsv" "$work/neigh.tsv" |
    sort -t . -k1,1n -k2,2n -k3,3n -k4,4n > "$work/records.tsv"

  local subnet total
  subnet="$(num_to_ip "$net")/$prefix"
  total=$(wc -l < "$work/records.tsv" | tr -d ' ')
  if [ "$want_json" = yes ]; then
    lan_hint "$replies" "$os" >&2
    print_json "$(date '+%Y-%m-%dT%H:%M:%S')" "$subnet" "$gw" "$work/records.tsv"
  else
    echo "scanned: $(date '+%Y-%m-%d %H:%M')  subnet: $subnet  gateway: $gw  devices: $total"
    lan_hint "$replies" "$os"
    [ -s "$work/ssdp.tsv" ] || echo "(no SSDP replies - UPnP may be off, or perl is not available)"
    if [ "$want_oui" = yes ] && [ ! -s "$work/vend.tsv" ]; then echo "(vendor list could not be downloaded)"; fi
    print_table "$work/records.tsv"
  fi
}

main "$@"
