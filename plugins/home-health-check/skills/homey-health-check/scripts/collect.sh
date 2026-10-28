#!/usr/bin/env bash
# Read-only health snapshot of a Homey Pro through its local Web API (plain HTTP on the LAN, GET only).
# Needs perl with HTTP::Tiny and JSON::PP (core modules; macOS and most Linux distributions ship them).
# The API key is read from the first line of --key-file inside perl: never an argument, never printed.
# What the key may not read is printed as "not checked: <area>: <reason>".
# Usage: bash collect.sh --host <ip or name> --key-file <path>
# Exit codes: 0 report printed, 2 bad options, 3 Homey not reachable, 4 perl lacks the modules.
export LC_ALL=C

usage() {
  echo "Usage: bash collect.sh --host <ip or name> --key-file <path>"
  echo "  --host <ip or name>     the Homey on the LAN (host:port also works)"
  echo "  --key-file <path>       text file whose first line is a read-only Homey API key"
  echo "  --from-dir <dir>        offline: read saved API responses, for testing"
  echo "  --now <ISO 8601 UTC>    offline: the clock to use, for testing (e.g. 2026-10-28T12:00Z)"
  echo "  files read by --from-dir: system.json devices.json flows.json advancedflows.json apps.json"
  echo "    zones.json zigbee.json zwave.json updates.json notifications.json backup-state.json"
  echo "    memory-24h.json memory-7d.json memory-31d.json undervoltage-31d.json"
}

check_perl() {
  if ! perl -MHTTP::Tiny -MJSON::PP -MTime::Local -e 1 >/dev/null 2>&1; then
    echo "error: needs perl with HTTP::Tiny and JSON::PP" >&2
    exit 4
  fi
}

# The perl program: fetch (or read --from-dir) and render. It holds no secret; the key stays in its memory.
homey_perl() {
  cat <<'PERL'
use strict;
use HTTP::Tiny;
use JSON::PP;
use Time::Local qw(timegm);
binmode STDOUT, ':encoding(UTF-8)';
my ($host, $keyfile, $dir, $nowarg) = @ARGV;
my $DAY = 86400;
my ($http, $calls, %why);
my $tested = 1;
sub fail { print STDERR "$_[0]\n"; exit $_[1] }
if ($dir eq '') {
  open(my $fh, '<', $keyfile) or fail('error: cannot read the key file', 2);
  my $k = <$fh>;
  close $fh;
  $k = '' unless defined $k;
  $k =~ s/^\xEF\xBB\xBF//;
  $k =~ s/^\s+|\s+$//g;
  fail('error: the key file is empty', 2) if $k eq '';
  $http = HTTP::Tiny->new(timeout => 15, default_headers => { Authorization => "Bearer $k" });
}

# get(<area>, <file under --from-dir>, <API path>): decoded JSON, or undef with the reason in $why{<area>}.
# Responses are never printed whole; a failed request prints nothing from the response.
sub get {
  my ($area, $file, $path) = @_;
  my ($body, $st);
  if ($dir ne '') {
    if (open(my $fh, '<', "$dir/$file")) { local $/; $body = <$fh>; close $fh } else { $st = 404 }
  } else {
    select(undef, undef, undef, 0.2) if $calls++;
    my $r = $http->get("http://$host$path");
    $st = $r->{status};
    if ($r->{success}) { $body = $r->{content} }
    elsif ($st == 599 && $calls == 1) { fail("error: cannot reach the Homey at $host", 3) }
    elsif ($st == 599 && $r->{content} =~ /timed? out/i) { $st = 'timeout' }
  }
  if (defined $body) { my $d = eval { decode_json($body) }; return $d if defined $d; $st = 'bad' }
  $why{$area} = $st =~ /^40[13]$/ ? 'key lacks permission' : $st eq 'timeout' ? 'timed out' : 'not available';
  return undef;
}
sub esc { my $s = shift; $s =~ s/([^A-Za-z0-9._:~-])/sprintf('%%%02X', ord $1)/ge; $s }
sub series { my ($id, $res) = @_; '/api/manager/insights/log/number/' . esc($id) . "/entry?resolution=$res" }

# ISO 8601 UTC string or epoch ms -> epoch seconds
sub ep {
  my $v = shift;
  return undef unless defined $v && !ref $v;
  return $v / 1000 if $v =~ /^\d+(\.\d+)?$/;
  return undef unless $v =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d)(?::(\d\d)(\.\d+)?)?Z$/;
  return timegm($6 || 0, $5, $4, $3, $2 - 1, $1);
}
sub dt { my @g = gmtime(int shift); sprintf('%04d-%02d-%02dT%02d:%02dZ', $g[5] + 1900, $g[4] + 1, $g[3], $g[2], $g[1]) }
# round half away from zero, so collect.ps1 can match it
sub rnd { my ($x, $d) = @_; my $m = 10 ** $d; my $r = int(abs($x) * $m + 0.5) / $m; sprintf("%.${d}f", $x < 0 ? -$r : $r) }
sub mean { my $s = 0; $s += $_ for @_; $s / scalar @_ }
sub yn { $_[0] ? 'yes' : 'no' }
sub one { my $t = defined $_[0] ? $_[0] : ''; $t =~ s/\s+/ /g; $t =~ s/^ | $//g; $t }
sub txt { my $v = shift; ref $v eq 'HASH' ? (defined $v->{message} ? $v->{message} : 'unknown') : ref $v ? 'unknown' : $v }
sub ord_ci { uc($_[0]) cmp uc($_[1]) or $_[0] cmp $_[1] }
# pick(<test>, <objects>): [name, object] pairs that pass the test, sorted by name
sub pick { my $f = shift; sort { ord_ci($a->[0], $b->[0]) } map { [defined $_->{name} ? $_->{name} : '', $_] } grep { ref $_ eq 'HASH' && $f->($_) } @_ }
sub objs { my $v = shift; ref $v eq 'HASH' ? map { $v->{$_} } sort keys %$v : ref $v eq 'ARRAY' ? @$v : () }
sub pts { my $s = shift; map { [ep($_->{t}), $_->{v}] } grep { ref $_ eq 'HASH' } @{ref $s->{values} eq 'ARRAY' ? $s->{values} : []} }
# first-week and last-week means of the non-null values of a 31-day series
sub weeks {
  my @v = grep { defined $_->[0] } pts(shift);
  return () unless @v;
  my ($t0, $t1) = ($v[0][0], $v[-1][0]);
  my @f = map { $_->[1] } grep { defined $_->[1] && $_->[0] < $t0 + 7 * $DAY } @v;
  my @l = map { $_->[1] } grep { defined $_->[1] && $_->[0] > $t1 - 7 * $DAY } @v;
  return () unless @f && @l;
  return (mean(@f), mean(@l));
}
sub sec { print "## $_[0]\n" }
sub nc { my ($label, $area) = @_; print "not checked: $label: ", ($tested ? $why{defined $area ? $area : $label} || 'not available' : 'untested model'), "\n" }
sub kv { my ($k, $v) = @_; if (defined $v && $v ne '') { print "$k: $v\n" } else { nc($k) } }

my $now = $nowarg ne '' ? ep($nowarg) : time;
fail('error: --now must look like 2026-10-28T12:00Z', 2) unless defined $now;

my $sys = get('system', 'system.json', '/api/manager/system/');
$tested = (!$sys || (defined $sys->{homeyModelName} ? $sys->{homeyModelName} : '') =~ /\(Early 2023\)/) ? 1 : 0;
my $upd = get('firmware_update', 'updates.json', '/api/manager/updates/update/');
my %mem;
$mem{'24h'} = get('memory_24h', 'memory-24h.json', series('homey:manager:system:memory', 'last24Hours'));
$mem{'7d'} = get('memory_7d', 'memory-7d.json', series('homey:manager:system:memory', 'last7Days'));
$mem{'31d'} = get('memory_31d', 'memory-31d.json', series('homey:manager:system:memory', 'last31Days'));
my $uv = get('undervoltage_31d_max', 'undervoltage-31d.json', series('homey:manager:system:undervoltageratio', 'last31Days'));
my $bk = get('backup', 'backup-state.json', '/api/manager/backup/state');
my $nt = get('notifications', 'notifications.json', '/api/manager/notifications/notification/');
my $apps = get('apps', 'apps.json', '/api/manager/apps/app/');
my $devs = get('devices', 'devices.json', '/api/manager/devices/device/');
my $zones = get('zones', 'zones.json', '/api/manager/zones/zone/');
my $fl = get('flows', 'flows.json', '/api/manager/flow/flow/');
my $af = get('advanced_flows', 'advancedflows.json', '/api/manager/flow/advancedflow/');
my $zb = get('zigbee', 'zigbee.json', '/api/manager/zigbee/state');
my $zw = get('zwave', 'zwave.json', '/api/manager/zwave/state');

sec('Homey');
if (!$sys) { nc('system') } else {
  my %s = %$sys;
  kv('model', $s{homeyModelName});
  print 'model_tested: ', yn($tested), "\n";
  kv('firmware', $s{homeyVersion});
  if (!$upd) { nc('firmware_update') } else {
    my ($u) = grep { ref $_ eq 'HASH' } objs($upd);
    print 'firmware_update: ', ($u ? txt($u->{version}) . ' (' . txt($u->{channel}) . ')' : 'none'), "\n";
  }
  my $b = ep($s{bootDate});
  kv('booted', defined $b ? dt($b) : undef);
  kv('uptime_days', defined $s{uptime} ? rnd($s{uptime} / $DAY, 1) : undef);
  print 'reboot_reason: ', (defined $s{rebootReason} && $s{rebootReason} ne '' ? $s{rebootReason} : 'unknown'), "\n";
  kv('memory', defined $s{totalmem} && defined $s{freemem} ? rnd(($s{totalmem} - $s{freemem}) / 1048576, 0) . ' MB used of ' . rnd($s{totalmem} / 1048576, 0) . ' MB' : undef);
  kv('loadavg', ref $s{loadavg} eq 'ARRAY' ? join(' ', map { rnd($_, 2) } @{$s{loadavg}}) : undef);
  kv('power', defined $s{videoCoreUnderVoltageCurrently} && defined $s{videoCoreUndervoltageOccured} && defined $s{videoCoreThrottleOccured}
    ? 'undervoltage_now=' . yn($s{videoCoreUnderVoltageCurrently}) . ' undervoltage_seen=' . yn($s{videoCoreUndervoltageOccured}) . ' throttled_seen=' . yn($s{videoCoreThrottleOccured}) : undef);
  my $if = $s{ethernetConnected} ? 'ethernet' : $s{wifiConnected} ? 'wifi' : undef;
  kv('network', $if);
  kv('wifi_signal', defined $s{wifiStrength} && defined $s{wifiFrequency} ? "$s{wifiStrength}%, $s{wifiFrequency} MHz" : undef) if $if && $if eq 'wifi';
  kv('mac', $if && defined $s{$if . 'Mac'} ? lc $s{$if . 'Mac'} : undef);
  kv('address', $if ? $s{$if . 'Address'} : undef);
}

sec('Stability');
for (['24h', 60, 'min'], ['7d', 3600, 'h'], ['31d', 3600, 'h']) {
  my ($w, $div, $unit) = @$_;
  my $s = $mem{$w};
  if (!$s) { nc("outages_$w", "memory_$w"); next }
  my @v = pts($s);
  pop @v if @v && !defined $v[-1][1];
  my (@out, $run);
  for my $p (@v) {
    if (defined $p->[1]) { $run = undef } elsif ($run) { $run->[1]++ } else { $run = [$p->[0], 1]; push @out, $run }
  }
  print "outages_$w: ", (@out ? scalar @out : 'none'), "\n";
  print '  ', dt($_->[0]), ' ', rnd($_->[1] * ($s->{step} || 0) / 1000 / $div, 0), " $unit\n" for @out;
}
my ($f, $l) = $mem{'31d'} ? weeks($mem{'31d'}) : ();
if (defined $f && $f > 0) {
  my $pct = ($l - $f) / $f * 100;
  my $r = rnd($pct, 0);
  print 'memory_trend_31d: ', rnd($f, 0), ' MB -> ', rnd($l, 0), ' MB (', ($r =~ /^-/ ? '' : '+'), "$r%)\n";
} else { nc('memory_trend_31d', 'memory_31d') }
my @u = grep { defined } map { $_->[1] } ($uv ? pts($uv) : ());
if (@u) { my $mx = $u[0]; for (@u) { $mx = $_ if $_ > $mx } print 'undervoltage_31d_max: ', rnd($mx, 2), "\n" } else { nc('undervoltage_31d_max') }

# notifications as [epoch, ownerUri, ownerName, text with whitespace collapsed]
my @N = grep { defined $_->[0] } map { [ep($_->{dateCreated}), (defined $_->{ownerUri} ? $_->{ownerUri} : ''), (defined $_->{ownerName} ? $_->{ownerName} : $_->{ownerUri}), one($_->{excerpt})] } grep { ref $_ eq 'HASH' } objs($nt);

sec('Backup');
if (!$bk) { nc('backup') } else {
  kv('backup_state', $bk->{backupStateString});
  print 'backup_error: ', (defined $bk->{backupError} ? txt($bk->{backupError}) : 'none'), "\n";
}
if (!$nt) { nc('notifications') } else {
  my @b = sort { $a->[0] <=> $b->[0] } grep { $_->[1] eq 'homey:manager:backup' } @N;
  my ($old) = sort { $a <=> $b } map { $_->[0] } @N;
  print 'backup_notices: ', scalar @b, (defined $old ? ' since ' . dt($old) : ''), "\n";
  for (@b) {
    my $k = $_->[3] =~ /problem|fail|error/i ? 'failed' : $_->[3] =~ /success|complete|created/i ? 'succeeded' : 'other';
    print '  ', dt($_->[0]), " $k: ", substr($_->[3], 0, 120), "\n";
  }
}

sec('Apps');
if (!$apps) { nc('apps') } else {
  my @A = grep { ref $_ eq 'HASH' } objs($apps);
  print 'apps: ', scalar @A, ' (', scalar(grep { ($_->{state} || '') eq 'running' } @A), " running)\n";
  for my $x (pick(sub { 1 }, @A)) {
    my $p = $x->[1];
    my @i;
    push @i, "crashed $p->{crashedCount} times" if ($p->{crashedCount} || 0) > 0;
    if (!$p->{enabled}) { push @i, 'disabled' } elsif (($p->{state} || '') ne 'running') { push @i, 'not running (' . ($p->{state} || 'unknown') . ')' }
    my $up = $p->{updateAvailable};
    if (JSON::PP::is_bool($up)) { push @i, 'update available' if $up }
    elsif (defined $up) { push @i, 'update ' . (ref $up eq 'HASH' ? txt($up->{version}) : txt($up)) }
    push @i, "origin $p->{origin}" if defined $p->{origin} && $p->{origin} ne 'appstore';
    print "  $x->[0] ", (defined $p->{version} ? $p->{version} : ''), ": $_\n" for @i;
  }
}

my @D = grep { ref $_ eq 'HASH' } objs($devs);
my %zn = map { $_->{id} => $_->{name} } grep { ref $_ eq 'HASH' && defined $_->{id} } objs($zones);
sub cap { my ($d, $c) = @_; my $o = $d->{capabilitiesObj}; ref $o eq 'HASH' && ref $o->{$c} eq 'HASH' ? $o->{$c} : undef }
sub cls { ' [' . (defined $_[0]{class} ? $_[0]{class} : '') . ']' }
sub newest {
  my $d = shift;
  my $m;
  for (ep($d->{lastSeenAt}), map { ep($_->{lastUpdated}) } grep { ref $_ eq 'HASH' } values %{ref $d->{capabilitiesObj} eq 'HASH' ? $d->{capabilitiesObj} : {}}) {
    $m = $_ if defined $_ && (!defined $m || $_ > $m);
  }
  $m;
}

sec('Devices');
if (!$devs) { nc('devices') } else {
  print 'devices: ', scalar @D, "\n";
  for (pick(sub { defined $_[0]{available} && !$_[0]{available} }, @D)) {
    my ($n, $d) = @$_;
    my $z = defined $d->{zone} ? (defined $zn{$d->{zone}} ? $zn{$d->{zone}} : $d->{zone}) : '';
    print "  unavailable: $n", cls($d), " $z", (defined $d->{unavailableMessage} ? ": $d->{unavailableMessage}" : ''), "\n";
  }
  print "  warning: $_->[0]", cls($_->[1]), ": $_->[1]{warningMessage}\n" for pick(sub { defined $_[0]{warningMessage} && $_[0]{warningMessage} ne '' }, @D);
  for (pick(sub { ref $_[0]{firmwareUpdate} eq 'HASH' && defined $_[0]{firmwareUpdate}{availableVersion} }, @D)) {
    my $u = $_->[1]{firmwareUpdate};
    print "  firmware: $_->[0]: ", (defined $u->{currentVersion} ? $u->{currentVersion} : 'unknown'), " -> $u->{availableVersion}", ($u->{requiresWake} ? ', needs wake' : ''), "\n";
  }
  for (pick(sub { ($_[0]{class} || '') =~ /^(sensor|thermostat)$/ }, @D)) {
    my $t = newest($_->[1]);
    if (!defined $t) { print "  stale: $_->[0]", cls($_->[1]), " last never\n" }
    elsif ($now - $t > 3 * $DAY) { print "  stale: $_->[0]", cls($_->[1]), ' last ', dt($t), ' (', int(($now - $t) / $DAY), " days)\n" }
  }
}

sec('Batteries');
if (!$devs) { nc('devices') } else {
  my %low;
  for (pick(sub { my $c = cap($_[0], 'measure_battery'); $c && defined $c->{value} && !ref $c->{value} && $c->{value} =~ /^-?\d+(\.\d+)?$/ && $c->{value} <= 20 }, @D)) {
    my $d = $_->[1];
    $low{$d} = 1;
    my $ab = cap($d, 'alarm_battery');
    print "  low: $_->[0] ", cap($d, 'measure_battery')->{value}, '%', ($ab && $ab->{value} ? ', alarm' : ''), "\n";
  }
  print "  alarm: $_->[0] alarm_battery on\n" for pick(sub { my $c = cap($_[0], 'alarm_battery'); !$low{$_[0]} && $c && $c->{value} }, @D);
  for (pick(sub { my $d = shift; !cap($d, 'measure_battery') && !cap($d, 'alarm_battery') && grep { cap($d, "alarm_$_") } qw(water smoke co heat) }, @D)) {
    my $d = $_->[1];
    print "  no_battery_report: $_->[0] [", join(', ', map { "alarm_$_" } grep { cap($d, "alarm_$_") } qw(water smoke co heat)), "]\n";
  }
}

sec('Flows');
sub fcount { my @v = grep { ref $_ eq 'HASH' } objs(shift); scalar(@v) . ' (' . scalar(grep { $_->{enabled} } @v) . ' enabled)' }
if ($fl && $af) { print 'flows: ', fcount($fl), ', advanced: ', fcount($af), "\n" }
nc('flows') unless $fl;
nc('advanced_flows') unless $af;
my @all = grep { ref $_ eq 'HASH' } (objs($fl), objs($af));
print "  broken: $_->[0]\n" for pick(sub { $_[0]{broken} }, @all);
print "  disabled: $_->[0]\n" for pick(sub { !$_[0]{enabled} }, @all);

sec('Radio');
if (!$zb) { nc('zigbee') } else {
  my $nodes = scalar grep { ref $_ eq 'HASH' && ($_->{type} || '') ne 'coordinator' } objs($zb->{nodes});
  print 'zigbee: ready=', yn($zb->{zigbee_ready}), ' error=', (defined $zb->{zigbee_error} ? txt($zb->{zigbee_error}) : 'none'), " nodes=$nodes\n";
}
my $zs = ref $zw eq 'HASH' && ref $zw->{zw_state} eq 'HASH' ? $zw->{zw_state} : undef;
if (!$zs || ref $zs->{nodes} ne 'ARRAY') { nc('zwave') } else {
  my $me = defined $zs->{nodeId} ? $zs->{nodeId} : '';
  print 'zwave: nodes=', scalar(grep { $_ ne $me } @{$zs->{nodes}}), ' no_ack=', scalar(ref $zs->{noAckNodes} eq 'ARRAY' ? @{$zs->{noAckNodes}} : ()), "\n";
}

sec('Notifications (14 days)');
if (!$nt) { nc('notifications') } else {
  my @w = grep { $_->[0] >= $now - 14 * $DAY } @N;
  my %c;
  $c{$_->[2]}++ for @w;
  print "  $_: $c{$_}\n" for sort { ord_ci($a, $b) } keys %c;
  # presence and security notices can name people: counted above, never matched or quoted
  for (sort { $a->[0] <=> $b->[0] } grep { $_->[1] !~ /^homey:manager:(presence|security|backup)$/ && $_->[3] =~ /backup|offline|disconnect|connection lost|lost connection|unreachable|failed|error|crash|sync.*disabled|battery/i } @w) {
    print '  match ', dt($_->[0]), " $_->[2]: ", substr($_->[3], 0, 120), "\n";
  }
}

sec('Tidiness');
if (!$devs || !$zones) { nc($devs ? 'zones' : 'devices') } else {
  my %zo = map { $_->{id} => $_ } grep { ref $_ eq 'HASH' && defined $_->{id} } objs($zones);
  my %used;
  $used{defined $_->{zone} ? $_->{zone} : ''}++ for @D;
  $used{$_->{parent}}++ for grep { defined $_->{parent} } values %zo;
  print "  no_zone: $_->[0]\n" for pick(sub { my $z = $zo{defined $_[0]{zone} ? $_[0]{zone} : ''}; $z && !defined $z->{parent} }, @D);
  print "  empty_zone: $_->[0]\n" for pick(sub { defined $_[0]{parent} && !$used{$_[0]{id}} }, values %zo);
  print "  name_spaces: \"$_->[0]\"\n" for pick(sub { (defined $_[0]{name} ? $_[0]{name} : '') =~ /^\s|\s$|  / }, @D);
}
exit 0;
PERL
}

main() {
  local host='' keyfile='' dir='' now=''
  while [ $# -gt 0 ]; do
    case $1 in
      --host|--key-file|--from-dir|--now)
        if [ $# -lt 2 ]; then usage >&2; exit 2; fi
        case $1 in
          --host) host=$2 ;;
          --key-file) keyfile=$2 ;;
          --from-dir) dir=$2 ;;
          --now) now=$2 ;;
        esac
        shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  if [ -z "$host" ] || { [ -z "$keyfile" ] && [ -z "$dir" ]; }; then usage >&2; exit 2; fi
  check_perl
  perl -e "$(homey_perl)" -- "$host" "$keyfile" "$dir" "$now"
}

main "$@"
