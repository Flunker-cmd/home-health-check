#!/usr/bin/env bash
# Read-only health snapshot of a Raspberry Pi or other Debian-based Linux host.
# Runs as a normal user. Uses sudo only non-interactively (sudo -n) and skips what it can't read.
# Usage from another machine:  ssh user@host 'bash -s' < collect.sh
set -u
export LC_ALL=C

section() { printf '\n## %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
SUDO=""
sudo -n true 2>/dev/null && SUDO="sudo -n"

section "System"
. /etc/os-release 2>/dev/null
echo "os: ${PRETTY_NAME:-unknown} (codename ${VERSION_CODENAME:-unknown})"
echo "kernel: $(uname -r) ($(uname -m))"
[ -r /proc/device-tree/model ] && echo "model: $(tr -d '\0' < /proc/device-tree/model)"
echo "hostname: $(hostname)"
echo "uptime: $(uptime -p 2>/dev/null), booted $(uptime -s 2>/dev/null)"
echo "user: $(id -un), passwordless sudo: $([ -n "$SUDO" ] && echo yes || echo no)"
iface=$(ip route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}')
if [ -n "$iface" ] && [ -r "/sys/class/net/$iface/address" ]; then
  echo "mac: $(cat "/sys/class/net/$iface/address") ($iface)"
else
  echo "mac: unknown"
fi

section "Resources"
df -h -x tmpfs -x devtmpfs -x efivarfs 2>/dev/null
free -h
echo "load: $(cut -d' ' -f1-3 /proc/loadavg)"
if have vcgencmd; then
  vcgencmd measure_temp
  vcgencmd get_throttled   # 0x0 = never throttled or under-voltage
fi

section "Storage health"
echo "root mount options: $(findmnt -n -o OPTIONS /)"
if klog=$($SUDO journalctl -k -b --no-pager 2>/dev/null); then
  hits=$(grep -iE 'mmc[0-9].*(error|timeout)|I/O error|EXT4-fs (error|warning)|remount.*read-only|under-voltage' <<<"$klog" | tail -20)
  echo "${hits:-no storage or power errors in the kernel log since boot}"
else
  echo "(kernel log not readable)"
fi

section "Updates"
lists=$(ls -t /var/lib/apt/lists/*Release 2>/dev/null | head -1)
[ -n "$lists" ] && echo "apt lists last refreshed: $(date -r "$lists" '+%F %R')"
echo "pending upgrades (from current lists): $(apt-get -s -o Debug::NoLocking=1 full-upgrade 2>/dev/null | grep -c '^Inst')"
apt-get -s -o Debug::NoLocking=1 full-upgrade 2>/dev/null | grep '^Inst' | head -15
[ -f /var/run/reboot-required ] && echo "REBOOT REQUIRED"
echo "last apt run: $(grep '^Start-Date' /var/log/apt/history.log 2>/dev/null | tail -1)"
dpkg -s unattended-upgrades >/dev/null 2>&1 && echo "unattended-upgrades: installed" || echo "unattended-upgrades: not installed"
echo "apt sources:"
grep -rhsE '^(deb |URIs:|Suites:)' /etc/apt/sources.list /etc/apt/sources.list.d/ | sort -u

section "Services"
echo "failed:"; systemctl --failed --no-legend --plain 2>/dev/null
echo "running:"; systemctl list-units --type=service --state=running --no-legend --plain 2>/dev/null | awk '{print "  " $1}'
echo "enabled timers:"; systemctl list-timers --all --no-legend --plain 2>/dev/null | awk '{print "  " $NF}' | sort -u

section "Listening ports"
$SUDO ss -tulpnH 2>/dev/null || ss -tulnH

section "SSH"
ssh -V 2>&1
if $SUDO sshd -T >/dev/null 2>&1; then
  $SUDO sshd -T 2>/dev/null | grep -E '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication) '
else
  grep -rhsiE '^\s*(PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|PubkeyAuthentication)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
fi
echo "authorized keys for $(id -un): $(grep -cE '^(ssh-|ecdsa-|sk-)' ~/.ssh/authorized_keys 2>/dev/null || echo 0)"
echo "sudo group: $(getent group sudo | cut -d: -f4)"
ls /etc/sudoers.d/ 2>/dev/null | sed 's/^/  sudoers.d: /'

section "Firewall"
if have ufw; then $SUDO ufw status 2>/dev/null || echo "ufw installed (status needs sudo)"; fi
if have nft; then echo "nftables rules: $($SUDO nft list ruleset 2>/dev/null | grep -c . || echo '?')"; fi
have ufw || have nft || echo "no ufw/nft found"

section "Network"
ip -br addr
ip route | head -5
echo "resolvers: $(grep -E '^nameserver' /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')"
if have nmcli; then
  nmcli -t -f NAME,DEVICE,TYPE con show --active
  con=$(nmcli -t -f NAME,DEVICE con show --active | grep -vE ':lo$' | head -1 | cut -d: -f1)
  [ -n "$con" ] && nmcli -g ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns con show "$con" | paste -sd' '
fi
[ -f /etc/dhcpcd.conf ] && grep -E '^\s*(interface|static)' /etc/dhcpcd.conf
timedatectl show -p Timezone -p NTPSynchronized 2>/dev/null

section "Pi-hole"
if have pihole; then
  pihole -v 2>/dev/null
  $SUDO pihole status 2>/dev/null | grep -E '✓|✗|X|enabled|disabled'
  if [ -n "$SUDO" ]; then
    echo "upstreams: $($SUDO pihole-FTL --config dns.upstreams 2>/dev/null)"
    pw=$($SUDO pihole-FTL --config webserver.api.pwhash 2>/dev/null)
    echo "web password set: $([ -n "$pw" ] && echo yes || echo NO)"
    echo "gravity domains: $($SUDO pihole-FTL sqlite3 /etc/pihole/gravity.db 'select count(*) from gravity' 2>/dev/null)"
    echo "clients seen last 24h: $($SUDO pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db "select count(distinct client) from queries where timestamp > strftime('%s','now')-86400" 2>/dev/null)"
  else
    echo "(details need passwordless sudo)"
  fi
else
  echo "not installed"
fi

section "Encrypted DNS helpers"
if have cloudflared; then
  cloudflared --version 2>/dev/null
  if grep -rqs 'proxy-dns' /etc/cloudflared/ /etc/default/cloudflared 2>/dev/null || ps -eo args | grep -q '[c]loudflared.*proxy-dns'; then
    echo "cloudflared uses proxy-dns (removed in cloudflared 2026.2.0)"
  fi
  echo "cloudflared service: $(systemctl is-active cloudflared 2>/dev/null)"
fi
if [ -x /usr/sbin/unbound ]; then
  /usr/sbin/unbound -V 2>/dev/null | head -1
  echo "unbound service: $(systemctl is-active unbound 2>/dev/null)"
  $SUDO unbound-checkconf 2>/dev/null
  grep -rhsE '^\s*(interface|port|forward-addr|forward-tls-upstream):' /etc/unbound/unbound.conf.d/
fi
have cloudflared || [ -x /usr/sbin/unbound ] || echo "neither cloudflared nor unbound installed"

section "Scheduled jobs"
echo "user crontab:"; crontab -l 2>/dev/null | grep -v '^#' || echo "  (none)"
[ -n "$SUDO" ] && { echo "root crontab:"; $SUDO crontab -l 2>/dev/null | grep -v '^#' || echo "  (none)"; }
echo "/etc/cron.d: $(ls /etc/cron.d 2>/dev/null | tr '\n' ' ')"

section "Errors since boot"
journalctl -p err -b --no-pager -q 2>/dev/null | tail -25 || echo "(journal not readable)"

section "Home directory"
ls -la ~ | tail -n +4
