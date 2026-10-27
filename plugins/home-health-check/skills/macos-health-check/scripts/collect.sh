#!/usr/bin/env bash
# Read-only health snapshot of the Mac this runs on. No sudo, no prompts, no macOS permission dialogs.
# Runs on the stock /bin/bash 3.2 and only uses tools that ship with macOS.
# What needs Full Disk Access or admin rights is skipped and printed as "not checked: <area>: <reason>".
# Usage: bash collect.sh [--skip-updates]
#   --skip-updates  skip "softwareupdate -l" (slow, and it contacts Apple's update servers)
# From another computer:  ssh user@mac 'bash -s' < collect.sh
export LC_ALL=C

TAB=$(printf '\t')

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

usage() {
  echo "Usage: bash collect.sh [--skip-updates]"
  echo "  --skip-updates  skip 'softwareupdate -l' (slow, contacts Apple's update servers)"
}

section() { printf '\n## %s\n' "$1"; }
not_checked() { echo "not checked: $1: $2"; }

# system_profiler SPHardwareDataType on stdin, without serial number, hardware UUID, provisioning UDID or activation lock
filter_hardware() { grep -viE 'Serial Number|Hardware UUID|Provisioning UDID|Activation Lock'; }

# softwareupdate -l on stdin -> "pending updates: N" and one line per update
parse_softwareupdate() {
  awk '
    function field(s, k, stop,   i, r) { i = index(s, k); if (!i) return ""; r = substr(s, i + length(k)); j = index(r, stop); return (j > 0) ? substr(r, 1, j - 1) : r }
    /Title: / { n++
      title = field($0, "Title: ", ", Version: "); ver = field($0, "Version: ", ",")
      rec = field($0, "Recommended: ", ","); sub(/ +$/, "", rec)
      restart = ($0 ~ /Action: restart/) ? "yes" : "no"
      line[n] = sprintf("  %s, version %s, recommended %s, restart %s", title, ver, rec, restart) }
    END { print "pending updates: " n + 0; for (i = 1; i <= n; i++) print line[i] }'
}

# netstat -anp tcp on stdin -> the sharing ports that listen on a non-loopback address
parse_listening() {
  awk '
    BEGIN { n = split("22:remote-login 88:kerberos 445:file-sharing 548:afp 3283:remote-management 5900:screen-sharing 7000:airplay-receiver", w, " ")
            for (i = 1; i <= n; i++) { split(w[i], p, ":"); name[p[1]] = p[2]; order[i] = p[1] } }
    $NF == "LISTEN" && $4 !~ /^(127\.|::1\.|localhost\.)/ { a = $4; port = a; sub(/.*[.]/, "", port); if (port in name) seen[port] = 1 }
    END { out = ""; for (i = 1; i <= n; i++) if (order[i] in seen) out = out " " order[i] "/" name[order[i]]
          if (out == "") print "listening: none of the sharing ports"; else print "listening:" out }'
}

# codesign -dv --verbose=2 output on stdin -> app-store | developer-id | apple | adhoc | unsigned | unknown
classify_signature() {
  awk '
    /not signed at all/ { c = "unsigned" }
    /^Signature=adhoc/ { if (c == "") c = "adhoc" }
    /^Authority=Apple Mac OS Application Signing/ { if (c == "") c = "app-store" }
    /^Authority=Developer ID Application/ { if (c == "") c = "developer-id" }
    /^Authority=(Software Signing|Apple Code Signing Certification Authority)/ { if (c == "") c = "apple" }
    END { print (c == "") ? "unknown" : c }'
}

# tmutil latestbackup output on stdin (a path ending in YYYY-MM-DD-HHMMSS) -> "YYYY-MM-DD HH:MM", or nothing
parse_tm_latest() {
  awk '
    match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]/) {
      s = substr($0, RSTART, RLENGTH); out = substr(s, 1, 10) " " substr(s, 12, 2) ":" substr(s, 14, 2) }
    END { if (out != "") print out }'
}

# crash report file names on stdin -> the 10 most frequent apps as "<count> <name>"
crash_counts() {
  sed -E 's/[-_][0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}.*$//' |
    awk '{ n[$0]++ } END { for (k in n) printf "%d\t%s\n", n[k], k }' |
    sort -t "$TAB" -k1,1nr -k2,2 | head -10 | awk -F '\t' '{ print $1 " " $2 }'
}

# sysctl -n kern.boottime on stdin -> boot time as epoch seconds
parse_boottime() { sed -n 's/^{ sec = \([0-9]*\),.*/\1/p'; }

# diskutil info / on stdin -> "container free: N% of M GB", nothing without a container
container_free() {
  awk '
    function bytes(s) { if (match(s, /\([0-9]+ Bytes\)/)) return substr(s, RSTART + 1, RLENGTH - 8) + 0; return 0 }
    /Container Total Space:/ { total = bytes($0) }
    /Container Free Space:/ { free = bytes($0) }
    END { if (total > 0) printf "container free: %.0f%% of %.0f GB\n", 100 * free / total, total / 1000000000 }'
}

# system_profiler SPPowerDataType on stdin -> one summary line, nothing on a desktop Mac
battery_summary() {
  awk '
    /Cycle Count: / { c = $0; sub(/.*Cycle Count: /, "", c) }
    /Condition: / { d = $0; sub(/.*Condition: /, "", d) }
    /Maximum Capacity: / { m = $0; sub(/.*Maximum Capacity: /, "", m) }
    END { if (c != "") printf "cycle count: %s, condition: %s, maximum capacity: %s\n", c, d, (m == "") ? "not reported" : m }'
}

# prints "class<TAB>app" for every app directly in /Applications
scan_apps() {
  local app
  for app in /Applications/*.app; do
    [ -d "$app" ] || continue
    printf '%s\t%s\n' "$(with_timeout 10 codesign -dv --verbose=2 "$app" 2>&1 | classify_signature)" "$(basename "$app" .app)"
  done
}

main() {
  local skip_updates=no a o
  for a in "$@"; do
    o=$(printf '%s' "$a" | tr 'A-Z' 'a-z')
    case $o in
      --skip-updates|-skipupdates) skip_updates=yes ;;
      -h|--help|-help) usage; return 0 ;;
      *) usage >&2; return 2 ;;
    esac
  done
  if [ "$(uname -s)" != Darwin ]; then echo "This collector reads macOS only." >&2; return 1; fi

  local work out rc v k
  work=$(mktemp -d "${TMPDIR:-/tmp}/hhc-macos.XXXXXX") || return 1
  trap 'rm -rf "$work"' EXIT

  section "System"
  echo "os: macOS $(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
  echo "model: $(sysctl -n hw.model 2>/dev/null) ($(uname -m))"
  with_timeout 30 system_profiler SPHardwareDataType 2>/dev/null | filter_hardware | grep -E 'Model Name|Chip:|Processor Name|Total Number of Cores|Memory:' | sed 's/^ */  /'
  local boot now
  boot=$(sysctl -n kern.boottime 2>/dev/null | parse_boottime); now=$(date +%s)
  [ -n "$boot" ] && echo "booted: $(date -r "$boot" '+%Y-%m-%d %H:%M') ($(( (now - boot) / 86400 )) days ago)"
  echo "user: $(id -un), admin: $(id -Gn | tr ' ' '\n' | grep -qx admin && echo yes || echo no)"
  local iface mac
  iface=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }')
  mac=$(ifconfig "$iface" 2>/dev/null | awk '$1 == "ether" { print tolower($2); exit }')
  echo "mac: ${mac:-unknown} (${iface:-unknown})"

  section "Updates"
  if [ "$skip_updates" = yes ]; then
    not_checked "pending updates" "skipped"
  else
    out=$(with_timeout 180 softwareupdate -l 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then not_checked "pending updates" "timed out"; else printf '%s\n' "$out" | parse_softwareupdate; fi
  fi
  echo "recent installs:"
  softwareupdate --history 2>/dev/null | sed -n '3,$p' | tail -5 | sed 's/^/  /'
  for k in AutomaticCheckEnabled AutomaticDownload CriticalUpdateInstall ConfigDataInstall AutomaticallyInstallMacOSUpdates; do
    v=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate "$k" 2>/dev/null)
    echo "$k: ${v:-unset}"
  done
  v=$(defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>/dev/null)
  echo "AppStore AutoUpdate: ${v:-unset}"

  section "Security"
  fdesetup status 2>/dev/null || not_checked "FileVault" "not available"
  csrutil status 2>/dev/null || not_checked "System Integrity Protection" "not available"
  echo "Gatekeeper: $(spctl --status 2>&1)"
  /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || not_checked "firewall" "not available"
  /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null
  if command -v xprotect >/dev/null 2>&1; then echo "XProtect: $(xprotect version 2>/dev/null)"
  else
    v=$(defaults read /Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist CFBundleShortVersionString 2>/dev/null)
    echo "XProtect: version ${v:-unknown}, installed $(stat -f %Sm -t '%Y-%m-%d' /Library/Apple/System/Library/CoreServices/XProtect.bundle 2>/dev/null)"
  fi

  section "Sharing"
  netstat -anp tcp 2>/dev/null | parse_listening

  section "Backup"
  out=$(tmutil destinationinfo 2>&1)
  if printf '%s' "$out" | grep -q 'No destinations configured'; then
    echo "backup: no Time Machine destination"
  else
    printf '%s\n' "$out" | grep -E '^(Name|Kind) ' | sed 's/^/  /'
    v=$(tmutil latestbackup 2>&1 | parse_tm_latest)
    if [ -n "$v" ]; then echo "last backup: $v"; else not_checked "last backup" "needs Full Disk Access"; fi
  fi

  section "Disk"
  df -h / 2>/dev/null | sed -n '2p' | awk '{ print "root volume: " $2 " size, " $4 " available" }'
  out=$(diskutil info / 2>/dev/null)
  printf '%s\n' "$out" | container_free
  v=$(printf '%s\n' "$out" | awk -F: '/SMART Status/ { gsub(/^ +/, "", $2); print $2; exit }')
  [ -n "$v" ] || v=$(diskutil info disk0 2>/dev/null | awk -F: '/SMART Status/ { gsub(/^ +/, "", $2); print $2; exit }')
  echo "SMART status: ${v:-not reported}"
  out=$(diskutil list external physical 2>/dev/null | grep -c '^/dev/')
  echo "external disks: ${out:-0}"

  section "Battery"
  v=$(with_timeout 30 system_profiler SPPowerDataType 2>/dev/null | battery_summary)
  if [ -n "$v" ]; then pmset -g batt 2>/dev/null | sed 's/ (id=[0-9]*)//' | tail -1; echo "$v"; else echo "battery: none (desktop Mac)"; fi

  section "Startup"
  for k in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
    v=$(ls "$k" 2>/dev/null | grep -v '^com\.apple\.' | grep '\.plist$' | sed 's/\.plist$//' | tr '\n' ' ')
    echo "$(basename "$k") ($( [ "$k" = "$HOME/Library/LaunchAgents" ] && echo user || echo system )): ${v:-none}"
  done
  echo "loaded non-Apple jobs: $(launchctl list 2>/dev/null | awk 'NR > 1 && $3 !~ /^com\.apple\./' | wc -l | tr -d ' ')"
  not_checked "login items" "needs admin (see System Settings > General > Login Items)"

  section "Apps"
  local brew=""
  for k in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$k" ] && { brew=$k; break; }; done
  if [ -n "$brew" ]; then
    out=$(with_timeout 60 env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 "$brew" outdated --verbose 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ]; then not_checked "homebrew outdated" "timed out"; else echo "homebrew outdated: $(printf '%s' "$out" | grep -c .)"; printf '%s\n' "$out" | grep . | head -20 | sed 's/^/  /'; fi
  else
    echo "homebrew: not installed"
  fi
  with_timeout 90 scan_apps > "$work/apps.tsv" 2>/dev/null; rc=$?
  [ "$rc" -ne 0 ] && not_checked "app signatures" "timed out (partial list)"
  awk -F '\t' '{ n[$1]++ } END { for (k in n) printf "apps %s: %d\n", k, n[k] }' "$work/apps.tsv" | sort
  awk -F '\t' '$1 == "unsigned" || $1 == "adhoc" { print "  " $1 ": " $2 }' "$work/apps.tsv"

  section "Crashes and panics (30 days)"
  find "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports -maxdepth 1 -type f -mtime -30 2>/dev/null | sed 's|.*/||' > "$work/reports.txt"
  echo "panics: $(grep -cE '^(panic|Kernel)' "$work/reports.txt")"
  grep -E '^(panic|Kernel)' "$work/reports.txt" | sed -n 's/.*\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\).*/  \1/p' | sort -u
  echo "crash reports: $(grep -vcE '^(panic|Kernel)' "$work/reports.txt")"
  grep -vE '^(panic|Kernel)' "$work/reports.txt" | crash_counts | sed 's/^/  /'
}

main "$@"
