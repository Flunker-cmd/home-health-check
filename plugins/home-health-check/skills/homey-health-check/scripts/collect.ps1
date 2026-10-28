# Read-only Homey Pro snapshot via its local Web API (HTTP GET only). Output and exit codes equal collect.sh.
# The key (first line of -KeyFile) goes only into the Authorization header. Unknown options print usage, exit 2.
$ErrorActionPreference = 'Stop'
$Inv = [Globalization.CultureInfo]::InvariantCulture
$DT = [Collections.Generic.Dictionary[string, object]]; $AR = [object[]]
$U8 = New-Object Text.UTF8Encoding($false)
$Epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
$Std = New-Object IO.StreamWriter([Console]::OpenStandardOutput(), $U8)
$Std.NewLine = "`n"
function Say([string]$s) { $Std.WriteLine($s) }
function Fail([string]$m, [int]$c) { $Std.Flush(); [Console]::Error.Write("$m`n"); exit $c }
function Usage {
  @('Usage: powershell -NoProfile -ExecutionPolicy Bypass -File collect.ps1 -Homey <ip or name> -KeyFile <path>',
  '  -Homey <ip or name[:port]>, -KeyFile <file whose first line is a read-only API key>',
  '  -FromDir <dir> -Now <ISO 8601 UTC>: offline: read saved API responses, for testing') -join "`n"
}
$Homey = ''; $KeyFile = ''; $FromDir = ''; $Now = ''
for ($i = 0; $i -lt $args.Count; $i += 2) {
  $o = [string]$args[$i]
  if ($o -match '^-(h|help|\?)$') { Say (Usage); $Std.Flush(); exit 0 }
  if ($o -notmatch '^-(Homey|KeyFile|FromDir|Now)$' -or $i + 1 -ge $args.Count) { Fail (Usage) 2 }
  Set-Variable -Name $Matches[1] -Value ([string]$args[$i + 1])
}
if ($Homey -eq '' -or ($KeyFile -eq '' -and $FromDir -eq '')) { Fail (Usage) 2 }
if ($FromDir -ne '') { $FromDir = [IO.Path]::GetFullPath($FromDir) } else {
  $k = $null
  try { $r = New-Object IO.StreamReader($KeyFile, $U8, $true); $k = $r.ReadLine(); $r.Close() } catch { Fail 'error: cannot read the key file' 2 }
  if ($null -eq $k -or $k.Trim() -eq '') { Fail 'error: the key file is empty' 2 }
  $Auth = 'Bearer ' + $k.Trim(); Remove-Variable k
}
# perl semantics: S string, Num number, T truth
function IsNum($v) { $v -is [ValueType] -and $v -isnot [bool] }
function Num($v) {
  if (IsNum $v) { return [double]::Parse($v.ToString($Inv), $Inv) }; if ($v -is [bool]) { return [double][int]$v }
  if ($v -is [string] -and $v -match '^\s*(-?\d+(\.\d+)?([eE][-+]?\d+)?)') { return [double]::Parse($Matches[1], $Inv) }; [double]0
}
function S($v) {
  if (Nul $v) { return '' }; if ($v -is [string]) { return $v }; if ($v -is [bool]) { if ($v) { return '1' }; return '0' }
  if ($v -is [int] -or $v -is [long]) { return $v.ToString($Inv) }
  if (IsNum $v) { return (Num $v).ToString('G15', $Inv).Replace('E', 'e') }; ''
}
function T($v) {
  if (Nul $v) { return $false }; if ($v -is [bool]) { return $v }
  if ($v -is [string]) { return ($v -ne '' -and $v -ne '0') }; if (IsNum $v) { return ((Num $v) -ne 0) }; $true
}
# G: member or $null. Objs: members by sorted key. Hs: objects only
function G($o, [string]$k) { if ($o -is $DT) { $v = $null; if ($o.TryGetValue($k, [ref]$v) -and $null -ne $v) { return ,$v } }; $null }
function Nn($v) { $null -ne $v }
function Nul($v) { $null -eq $v }
function SG($o, [string]$k) { S (G $o $k) }
function Objs($v) {
  if ($v -is $DT) { $ks = [string[]]@($v.Keys); [Array]::Sort($ks, [StringComparer]::Ordinal); foreach ($x in $ks) { ,$v[$x] } }
  elseif ($v -is $AR) { foreach ($x in $v) { ,$x } }
}
function Hs($v) { foreach ($x in @(Objs $v)) { if ($x -is $DT) { $x } } }
function Non($v) { if (Nul $v) { return 'none' }; Txt $v }
function Txt($v) {
  if ($v -is $DT) { $m = G $v 'message'; if (Nn $m) { return S $m }; return 'unknown' }
  if ($v -is $AR -or $v -is [bool]) { return 'unknown' }; S $v
}
function Ep($v) {
  if ($v -isnot [string] -and -not (IsNum $v)) { return $null }
  $s = S $v; if ($s -cmatch '^\d+(\.\d+)?$') { return [double]::Parse($s, $Inv) / 1000 }
  if ($s -cnotmatch '^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d)(?::(\d\d)(\.\d+)?)?Z$') { return $null }
  $g = @(1..6 | % { [int]$Matches[$_] })
  try { ([DateTime]::new($g[0], $g[1], $g[2], $g[3], $g[4], $g[5], [DateTimeKind]::Utc) - $Epoch).TotalSeconds } catch { $null }
}
function Dt($e) { $Epoch.AddSeconds([Math]::Truncate([double]$e)).ToString("yyyy'-'MM'-'dd'T'HH':'mm'Z'", $Inv) }
# half away from zero, -0 like perl
function Rnd($x, [int]$d) {
  $m = [Math]::Pow(10, $d); $t = ([Math]::Floor([Math]::Abs($x) * $m + 0.5) / $m).ToString('F' + $d, $Inv)
  if ($x -lt 0) { return '-' + $t }; $t
}
function Mean($l) { $s = 0.0; $l | % { $s += $_ }; $s / $l.Count }
function Yn($v) { if (T $v) { return 'yes' }; 'no' }
function One($v) { [regex]::Replace([regex]::Replace((S $v), '\s+', ' '), '^ | $', '') }
function Cut([string]$t) { if ($t.Length -gt 120) { return $t.Substring(0, 120) }; $t }
function Cmp([string]$p, [string]$q) { $c = [string]::CompareOrdinal($p.ToUpperInvariant(), $q.ToUpperInvariant()); if ($c -eq 0) { $c = [string]::CompareOrdinal($p, $q) }; $c }
# Srt: stable sort. Pick <test on $_> <objects>: @{n; d} by name
function Srt($items, [scriptblock]$cmp) {
  $script:SortCmp = $cmp; $sl = [Collections.Generic.List[object]]::new()
  foreach ($x in $items) { $sl.Add(@{ i = $sl.Count; x = $x }) }
  $sl.Sort([Comparison[object]] { param($p, $q) $c = [int](& $script:SortCmp $p.x $q.x); if ($c -eq 0) { $c = $p.i.CompareTo($q.i) }; $c })
  foreach ($e in $sl) { ,$e.x }
}
function Pick([scriptblock]$pkT, $pkL) {
  $pkR = @(foreach ($pkX in $pkL) { if ($pkX -is $DT -and ($pkX | % $pkT)) { @{ n = (SG $pkX 'name'); d = $pkX } } })
  Srt $pkR { param($p, $q) Cmp $p.n $q.n }
}
Add-Type -AssemblyName System.Web.Extensions
$Js = New-Object Web.Script.Serialization.JavaScriptSerializer
$Js.MaxJsonLength = [int]::MaxValue
$Why = $DT::new(); $Calls = 0; $Tested = $true
# Api <area> <path> [<file>]: JSON or $null (reason in $Why). Prints no response or exception.
function Api([string]$area, [string]$path, [string]$file = "$area.json") {
  $body = $null; $st = 'bad'
  if ($FromDir -ne '') {
    $p = Join-Path $FromDir $file
    if ([IO.File]::Exists($p)) { $body = [IO.File]::ReadAllText($p, $U8) } else { $st = 404 }
  } else {
    if ($script:Calls++ -gt 0) { Start-Sleep -Milliseconds 200 }
    try {
      $rq = [Net.WebRequest]::Create("http://$Homey/api/manager/$path")
      $rq.Proxy = $null; $rq.Timeout = 15000; $rq.ReadWriteTimeout = 15000; $rq.Headers.Add('Authorization', $Auth)
      $rs = $rq.GetResponse(); $body = (New-Object IO.StreamReader($rs.GetResponseStream(), $U8)).ReadToEnd(); $rs.Close()
    } catch {
      $body = $null; $ex = $_.Exception
      while ($null -ne $ex -and -not ($ex -is [Net.WebException])) { $ex = $ex.InnerException }
      if ($null -ne $ex -and $null -ne $ex.Response) { $st = [int]$ex.Response.StatusCode }
      elseif ($script:Calls -eq 1) { Fail "error: cannot reach the Homey at $Homey" 3 }
      elseif ($null -ne $ex -and $ex.Status -eq 'Timeout') { $st = 'timeout' }
    }
  }
  if (Nn $body) { $d = $null; try { $d = $Js.DeserializeObject($body) } catch {}; if (Nn $d) { return ,$d } }
  $Why[$area] = 'not available'
  if ("$st" -match '^40[13]$') { $Why[$area] = 'key lacks permission' } elseif ("$st" -eq 'timeout') { $Why[$area] = 'timed out' }
  $null
}
function Series([string]$id, [string]$res) {
  'insights/log/number/' + [regex]::Replace($id, '[^A-Za-z0-9._:~-]', { param($m) '%{0:X2}' -f [int][char]$m.Value }) + "/entry?resolution=$res"
}
function Pts($s) { foreach ($x in @(Hs (G $s 'values'))) { @{ t = (Ep (G $x 't')); v = (G $x 'v') } } }
# Weeks: first and last 7-day means
function Weeks($s) {
  $v = @(Pts $s | ? { $null -ne $_.t }); if ($v.Count -eq 0) { return }
  $f = @($v | ? { $null -ne $_.v -and $_.t -lt $v[0].t + 7 * 86400 } | % { Num $_.v })
  $l = @($v | ? { $null -ne $_.v -and $_.t -gt $v[-1].t - 7 * 86400 } | % { Num $_.v })
  if ($f.Count -and $l.Count) { Mean $f; Mean $l }
}
function Sec([string]$n) { Say "## $n" }
function Nc([string]$label, [string]$area) {
  if ($area -eq '') { $area = $label }; $r = 'not available'
  if (-not $Tested) { $r = 'untested model' } elseif ($Why.ContainsKey($area)) { $r = $Why[$area] }
  Say "not checked: ${label}: $r"
}
function Kv([string]$k, $v) { $t = S $v; if ($t -ne '') { Say "${k}: $t" } else { Nc $k } }
try {
$NowE = [Math]::Floor(([DateTime]::UtcNow - $Epoch).TotalSeconds)
if ($Now -ne '') { $NowE = Ep $Now }
if (Nul $NowE) { Fail 'error: -Now must look like 2026-10-28T12:00Z' 2 }
$sys = Api 'system' 'system/'
$Tested = (Nul $sys) -or ((SG $sys 'homeyModelName') -cmatch '\(Early 2023\)')
$upd = Api 'firmware_update' 'updates/update/' 'updates.json'
$Mem = @{}
foreach ($x in ('24h', 'last24Hours'), ('7d', 'last7Days'), ('31d', 'last31Days')) {
  $Mem[$x[0]] = Api "memory_$($x[0])" (Series 'homey:manager:system:memory' $x[1]) "memory-$($x[0]).json"
}
$uv = Api 'undervoltage_31d_max' (Series 'homey:manager:system:undervoltageratio' 'last31Days') 'undervoltage-31d.json'
$logs = Api 'insights' 'insights/log' 'insights-logs.json'
$bk = Api 'backup' 'backup/state' 'backup-state.json'
$nt = Api 'notifications' 'notifications/notification/'
$apps = Api 'apps' 'apps/app/'
$devs = Api 'devices' 'devices/device/'
$zones = Api 'zones' 'zones/zone/'
$fl = Api 'flows' 'flow/flow/'
$af = Api 'advanced_flows' 'flow/advancedflow/' 'advancedflows.json'
$zb = Api 'zigbee' 'zigbee/state'
$zw = Api 'zwave' 'zwave/state'
Sec 'Homey'
if (Nul $sys) { Nc 'system' } else {
  Kv 'model' (G $sys 'homeyModelName'); Say ('model_tested: ' + (Yn $Tested)); Kv 'firmware' (G $sys 'homeyVersion')
  if (Nul $upd) { Nc 'firmware_update' } else {
    $u = @(Hs $upd); $t = 'none'; if ($u.Count) { $t = (Txt (G $u[0] 'version')) + ' (' + (Txt (G $u[0] 'channel')) + ')' }
    Say "firmware_update: $t"
  }
  $x = Ep (G $sys 'bootDate'); Kv 'booted' $(if (Nn $x) { Dt $x })
  $x = G $sys 'uptime'; Kv 'uptime_days' $(if (Nn $x) { Rnd ((Num $x) / 86400) 1 })
  $t = SG $sys 'rebootReason'; if ($t -eq '') { $t = 'unknown' }; Say "reboot_reason: $t"
  $tm = G $sys 'totalmem'; $fm = G $sys 'freemem'
  Kv 'memory' $(if ($null -ne $tm -and $null -ne $fm) { (Rnd (((Num $tm) - (Num $fm)) / 1048576) 0) + ' MB used of ' + (Rnd ((Num $tm) / 1048576) 0) + ' MB' })
  $x = G $sys 'loadavg'; Kv 'loadavg' $(if ($x -is $AR) { @($x | % { Rnd (Num $_) 2 }) -join ' ' })
  $p = @('videoCoreUnderVoltageCurrently', 'videoCoreUndervoltageOccured', 'videoCoreThrottleOccured' | % { G $sys $_ } | ? { $null -ne $_ })
  Kv 'power' $(if ($p.Count -eq 3) { "undervoltage_now=$(Yn $p[0]) undervoltage_seen=$(Yn $p[1]) throttled_seen=$(Yn $p[2])" })
  $if = $null; if (T (G $sys 'ethernetConnected')) { $if = 'ethernet' } elseif (T (G $sys 'wifiConnected')) { $if = 'wifi' }
  Kv 'network' $if
  $ws = G $sys 'wifiStrength'; $wf = G $sys 'wifiFrequency'
  if ($if -eq 'wifi') { Kv 'wifi_signal' $(if ($null -ne $ws -and $null -ne $wf) { "$(S $ws)%, $(S $wf) MHz" }) }
  Kv 'mac' (SG $sys "$($if)Mac").ToLowerInvariant(); Kv 'address' (G $sys "$($if)Address")
}
Sec 'Stability'
foreach ($wd in ('24h', 60, 'min'), ('7d', 3600, 'h'), ('31d', 3600, 'h')) {
  $s = $Mem[$wd[0]]
  if (Nul $s) { Nc "outages_$($wd[0])" "memory_$($wd[0])"; continue }
  $v = @(Pts $s); $n = $v.Count; if ($n -gt 0 -and $null -eq $v[$n - 1].v) { $n-- }
  $runs = @(); $run = $null
  for ($i = 0; $i -lt $n; $i++) {
    if ($null -ne $v[$i].v) { $run = $null } elseif (Nn $run) { $run.c++ } else { $run = @{ t = $v[$i].t; c = 1 }; $runs += $run }
  }
  Say ("outages_$($wd[0]): " + $(if ($runs.Count) { $runs.Count } else { 'none' }))
  $step = Num (G $s 'step')
  foreach ($o in $runs) { Say ('  ' + (Dt $o.t) + ' ' + (Rnd ($o.c * $step / 1000 / $wd[1]) 0) + ' ' + $wd[2]) }
}
$wk = @(); if (Nn $Mem['31d']) { $wk = @(Weeks $Mem['31d']) }
$pct = $null
if ($wk.Count -eq 2 -and $wk[0] -gt 0) {
  $pct = ($wk[1] - $wk[0]) / $wk[0] * 100; $r = Rnd $pct 0; if (-not $r.StartsWith('-')) { $r = '+' + $r }
  Say "memory_trend_31d: $(Rnd $wk[0] 0) MB -> $(Rnd $wk[1] 0) MB ($r%)"
} else { Nc 'memory_trend_31d' 'memory_31d' }
$u = @(Pts $uv | ? { $null -ne $_.v } | % { Num $_.v })
if ($u.Count) { $mx = $u[0]; foreach ($x in $u) { if ($x -gt $mx) { $mx = $x } }; Say "undervoltage_31d_max: $(Rnd $mx 2)" } else { Nc 'undervoltage_31d_max' }
if ($null -ne $pct -and $pct -ge 20) {
  if (Nul $logs) { Nc 'app_memory' 'insights' } else {
    $ids = [string[]]@(Hs $logs | % { if ((SG $_ 'id') -cmatch '^homey:manager:apps:(.+)-mem$') { $Matches[1] } })
    [Array]::Sort($ids, [StringComparer]::Ordinal); $am = @(); $miss = $false
    foreach ($id in $ids) {
      $s = Api 'app_memory' (Series "homey:manager:apps:$id-mem" 'last31Days') "app-mem/$id.json"
      if (Nul $s) { $miss = $true; continue }
      $m = @(Weeks $s); if ($m.Count -ne 2) { continue }
      $an = G (G $apps $id) 'name'; if (Nul $an) { $an = $id }
      $am += @{ n = (S $an); f = $m[0]; l = $m[1] }
    }
    if ($miss) { Nc 'app_memory' }
    $am = @(Srt $am { param($p, $q) $c = ($q.l - $q.f).CompareTo($p.l - $p.f); if ($c -eq 0) { $c = Cmp $p.n $q.n }; $c })
    for ($i = 0; $i -lt [Math]::Min(3, $am.Count); $i++) { Say "  app_memory: $($am[$i].n) $(Rnd $am[$i].f 0) -> $(Rnd $am[$i].l 0) MB" }
  }
}
$Notes = @(Hs $nt | % {
  $e = Ep (G $_ 'dateCreated'); $on = G $_ 'ownerName'; if (Nul $on) { $on = G $_ 'ownerUri' }
  if (Nn $e) { @{ e = $e; u = (SG $_ 'ownerUri'); n = (S $on); x = (One (G $_ 'excerpt')) } }
})
Sec 'Backup'
if (Nul $bk) { Nc 'backup' } else {
  Kv 'backup_state' (G $bk 'backupStateString')
  Say ('backup_error: ' + (Non (G $bk 'backupError')))
}
if (Nul $nt) { Nc 'notifications' } else {
  $b = @(Srt @($Notes | ? { $_.u -ceq 'homey:manager:backup' }) { param($p, $q) $p.e.CompareTo($q.e) })
  $old = $null; foreach ($x in $Notes) { if ($null -eq $old -or $x.e -lt $old) { $old = $x.e } }
  Say ("backup_notices: $($b.Count)" + $(if (Nn $old) { ' since ' + (Dt $old) }))
  foreach ($x in $b) {
    $k = 'other'; if ($x.x -match 'problem|fail|error') { $k = 'failed' } elseif ($x.x -match 'success|complete|created') { $k = 'succeeded' }
    Say ('  ' + (Dt $x.e) + " ${k}: " + (Cut $x.x))
  }
}
Sec 'Apps'
if (Nul $apps) { Nc 'apps' } else {
  $A = @(Hs $apps)
  Say "apps: $($A.Count) ($(@($A | ? { (SG $_ 'state') -ceq 'running' }).Count) running)"
  foreach ($x in @(Pick { $true } $A)) {
    $p = $x.d; $is = @(); $st = G $p 'state'; $up = G $p 'updateAvailable'; $o = G $p 'origin'
    $c = G $p 'crashedCount'; if ((Num $c) -gt 0) { $is += "crashed $(S $c) times" }
    if (-not (T (G $p 'enabled'))) { $is += 'disabled' }
    elseif ((S $st) -cne 'running') { $is += 'not running (' + $(if (T $st) { S $st } else { 'unknown' }) + ')' }
    if ($up -is [bool]) { if ($up) { $is += 'update available' } }
    elseif (Nn $up) { if ($up -is $DT) { $up = G $up 'version' }; $is += 'update ' + (Txt $up) }
    if ($null -ne $o -and (S $o) -cne 'appstore') { $is += "origin $(S $o)" }
    foreach ($y in $is) { Say "  $($x.n) $(SG $p 'version'): $y" }
  }
}
$DL = @(Hs $devs); $ZName = $DT::new()
foreach ($z in @(Hs $zones)) { $id = G $z 'id'; if (Nn $id) { $ZName[(S $id)] = G $z 'name' } }
function Cap($d, [string]$c) { $v = G (G $d 'capabilitiesObj') $c; if ($v -is $DT) { return $v }; $null }
function Kl($d) { ' [' + (SG $d 'class') + ']' }
function Newest($d) {
  $m = Ep (G $d 'lastSeenAt'); $co = G $d 'capabilitiesObj'; if (-not ($co -is $DT)) { $co = $null }
  foreach ($c in @(Hs $co)) { $t = Ep (G $c 'lastUpdated'); if ($null -ne $t -and ($null -eq $m -or $t -gt $m)) { $m = $t } }
  $m
}
function IsLow($d) {
  $v = G (Cap $d 'measure_battery') 'value'
  ((IsNum $v) -or ($v -is [string])) -and ((S $v) -cmatch '^-?\d+(\.\d+)?$') -and ((Num $v) -le 20)
}
function Safety($d) { foreach ($c in 'water', 'smoke', 'co', 'heat') { if ($null -ne (Cap $d "alarm_$c")) { "alarm_$c" } } }
Sec 'Devices'
if (Nul $devs) { Nc 'devices' } else {
  Say "devices: $($DL.Count)"
  foreach ($x in @(Pick { $v = G $_ 'available'; (Nn $v) -and -not (T $v) } $DL)) {
    $z = SG $x.d 'zone'; if ($ZName.ContainsKey($z) -and $null -ne $ZName[$z]) { $z = S $ZName[$z] }
    $um = G $x.d 'unavailableMessage'
    Say ("  unavailable: $($x.n)" + (Kl $x.d) + " $z" + $(if (Nn $um) { ": $(S $um)" }))
  }
  foreach ($x in @(Pick { (SG $_ 'warningMessage') -ne '' } $DL)) { Say ("  warning: $($x.n)" + (Kl $x.d) + ': ' + (SG $x.d 'warningMessage')) }
  foreach ($x in @(Pick { $null -ne (G (G $_ 'firmwareUpdate') 'availableVersion') } $DL)) {
    $f = G $x.d 'firmwareUpdate'; $cv = G $f 'currentVersion'; if (Nul $cv) { $cv = 'unknown' }
    Say ("  firmware: $($x.n): $(S $cv) -> " + (SG $f 'availableVersion') + $(if (T (G $f 'requiresWake')) { ', needs wake' }))
  }
  foreach ($x in @(Pick { (SG $_ 'class') -cmatch '^(sensor|thermostat)$' } $DL)) {
    $t = Newest $x.d; $l = "  stale: $($x.n)" + (Kl $x.d)
    if (Nul $t) { Say "$l last never" }
    elseif ($NowE - $t -gt 3 * 86400) { Say ("$l last " + (Dt $t) + ' (' + [Math]::Truncate(($NowE - $t) / 86400) + ' days)') }
  }
}
Sec 'Batteries'
if (Nul $devs) { Nc 'devices' } else {
  foreach ($x in @(Pick { IsLow $_ } $DL)) {
    $ab = Cap $x.d 'alarm_battery'
    Say ("  low: $($x.n) " + (SG (Cap $x.d 'measure_battery') 'value') + '%' + $(if (T (G $ab 'value')) { ', alarm' }))
  }
  foreach ($x in @(Pick { (-not (IsLow $_)) -and (T (G (Cap $_ 'alarm_battery') 'value')) } $DL)) { Say "  alarm: $($x.n) alarm_battery on" }
  foreach ($x in @(Pick { ($null -eq (Cap $_ 'measure_battery')) -and ($null -eq (Cap $_ 'alarm_battery')) -and (@(Safety $_).Count -gt 0) } $DL)) {
    Say ("  no_battery_report: $($x.n) [" + (@(Safety $x.d) -join ', ') + ']')
  }
}
Sec 'Flows'
function Fcount($v) { $l = @(Hs $v); "$($l.Count) ($(@($l | ? { T (G $_ 'enabled') }).Count) enabled)" }
if ($null -ne $fl -and $null -ne $af) { Say ('flows: ' + (Fcount $fl) + ', advanced: ' + (Fcount $af)) }
if (Nul $fl) { Nc 'flows' }; if (Nul $af) { Nc 'advanced_flows' }
$all = @(Hs $fl) + @(Hs $af)
foreach ($x in @(Pick { T (G $_ 'broken') } $all)) { Say "  broken: $($x.n)" }
foreach ($x in @(Pick { -not (T (G $_ 'enabled')) } $all)) { Say "  disabled: $($x.n)" }
Sec 'Radio'
if (Nul $zb) { Nc 'zigbee' } else {
  $c = @(Hs (G $zb 'nodes') | ? { (SG $_ 'type') -cne 'coordinator' }).Count
  Say ('zigbee: ready=' + (Yn (G $zb 'zigbee_ready')) + ' error=' + (Non (G $zb 'zigbee_error')) + " nodes=$c")
}
# Z-Wave: two counts only (the state holds network keys)
$zs = G $zw 'zw_state'; $zwn = G $zs 'nodes'
if (-not ($zwn -is $AR)) { Nc 'zwave' } else {
  $me = SG $zs 'nodeId'; $x = G $zs 'noAckNodes'; $na = 0; if ($x -is $AR) { $na = $x.Count }
  Say ("zwave: nodes=$(@($zwn | ? { (S $_) -cne $me }).Count) no_ack=$na")
}
Sec 'Notifications (14 days)'
if (Nul $nt) { Nc 'notifications' } else {
  $wn = @($Notes | ? { $_.e -ge $NowE - 14 * 86400 }); $c = $DT::new()
  foreach ($x in $wn) { if ($c.ContainsKey($x.n)) { $c[$x.n] += 1 } else { $c[$x.n] = 1 } }
  foreach ($k in @(Srt @($c.Keys) { param($p, $q) Cmp $p $q })) { Say "  ${k}: $($c[$k])" }
  # presence and security notices can name people: counted above, never matched or quoted
  $kw = 'backup|offline|disconnect|connection lost|lost connection|unreachable|failed|error|crash|sync.*disabled|battery'
  $m = @($wn | ? { ($_.u -cnotmatch '^homey:manager:(presence|security|backup)$') -and ($_.x -match $kw) })
  foreach ($x in @(Srt $m { param($p, $q) $p.e.CompareTo($q.e) })) { Say ('  match ' + (Dt $x.e) + " $($x.n): " + (Cut $x.x)) }
}
Sec 'Tidiness'
if (Nul $devs) { Nc 'devices' } elseif (Nul $zones) { Nc 'zones' } else {
  $zo = $DT::new(); $used = $DT::new()
  foreach ($z in @(Hs $zones)) { $id = G $z 'id'; if (Nn $id) { $zo[(S $id)] = $z } }
  foreach ($x in $DL) { $used[(SG $x 'zone')] = 1 }
  foreach ($z in $zo.Values) { $x = G $z 'parent'; if (Nn $x) { $used[(S $x)] = 1 } }
  foreach ($x in @(Pick { $k = SG $_ 'zone'; $zo.ContainsKey($k) -and ($null -eq (G $zo[$k] 'parent')) } $DL)) { Say "  no_zone: $($x.n)" }
  foreach ($x in @(Pick { ($null -ne (G $_ 'parent')) -and -not $used.ContainsKey((SG $_ 'id')) } @($zo.Values))) { Say "  empty_zone: $($x.n)" }
  foreach ($x in @(Pick { (SG $_ 'name') -match '^\s|\s$|  ' } $DL)) { Say "  name_spaces: `"$($x.n)`"" }
}
} catch { Fail 'error: the collector failed while rendering the report' 1 }
$Std.Flush()
exit 0
