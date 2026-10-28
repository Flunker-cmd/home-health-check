# Render functions for collect.ps1: parsed Homey API responses + the clock -> report lines (see collect.sh for the rules).
# Dot-sourced by collect.ps1. Defines functions only: no HTTP, no key, no files. Windows PowerShell 5.1, ASCII.
$Inv = [Globalization.CultureInfo]::InvariantCulture
$Dict = [Collections.Generic.Dictionary[string, object]]
$Epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
function Say([string]$line) { $line }
# JSON read as perl reads it in collect.sh ($obj.name is $null when missing)
function IsNumber($v) { $v -is [ValueType] -and $v -isnot [bool] }
function Number($v) {
  if (IsNumber $v) { return [double]::Parse($v.ToString($Inv), $Inv) }
  if ($v -is [bool]) { return [double][int]$v }
  if ($v -is [string] -and $v -match '^\s*(-?\d+(\.\d+)?)') { return [double]::Parse($Matches[1], $Inv) }
  return [double]0
}
function Text($v) {
  if ($null -eq $v) { return '' }
  if ($v -is [string]) { return $v }
  if ($v -is [bool]) { if ($v) { return '1' } else { return '0' } }
  if ($v -is [int] -or $v -is [long]) { return $v.ToString($Inv) }
  if (IsNumber $v) { return (Number $v).ToString('G15', $Inv).Replace('E', 'e') }
  return ''
}
function IsTrue($v) {
  if ($null -eq $v) { return $false }
  if ($v -is [bool]) { return $v }
  if ($v -is [string]) { return ($v -ne '' -and $v -ne '0') }
  if (IsNumber $v) { return ((Number $v) -ne 0) }
  return $true
}
# Objects: the members that are objects, by sorted key
function Objects($v) {
  $items = @()
  if ($v -is $Dict) {
    $keys = [string[]]@($v.Keys)
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    $items = @(foreach ($k in $keys) { ,$v[$k] })
  } elseif ($v -is [object[]]) { $items = $v }
  foreach ($item in $items) { if ($item -is $Dict) { $item } }
}
function Message($v) {
  if ($v -is $Dict) { if ($null -ne $v.message) { return Text $v.message }; return 'unknown' }
  if ($v -is [object[]] -or $v -is [bool]) { return 'unknown' }
  return Text $v
}
function ValueOrNone($v) { if ($null -eq $v) { return 'none' }; return Message $v }
# ISO 8601 UTC or epoch ms -> epoch seconds
function ToEpoch($v) {
  if ($v -isnot [string] -and -not (IsNumber $v)) { return $null }
  $s = Text $v
  if ($s -cmatch '^\d+(\.\d+)?$') { return [double]::Parse($s, $Inv) / 1000 }
  if ($s -cnotmatch '^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d)(?::(\d\d)(\.\d+)?)?Z$') { return $null }
  $p = @(1..6 | ForEach-Object { [int]$Matches[$_] })
  try { return ([DateTime]::new($p[0], $p[1], $p[2], $p[3], $p[4], $p[5], [DateTimeKind]::Utc) - $Epoch).TotalSeconds }
  catch { return $null }
}
function FormatDate($seconds) { $Epoch.AddSeconds([Math]::Truncate([double]$seconds)).ToString("yyyy'-'MM'-'dd'T'HH':'mm'Z'", $Inv) }
# half away from zero; perl prints -0
function Round($x, [int]$decimals) {
  $scale = [Math]::Pow(10, $decimals)
  $text = ([Math]::Floor([Math]::Abs($x) * $scale + 0.5) / $scale).ToString('F' + $decimals, $Inv)
  if ($x -lt 0) { return '-' + $text }
  return $text
}
function Mean($values) {
  $sum = 0.0
  foreach ($v in $values) { $sum += $v }
  return $sum / $values.Count
}
function YesNo($v) { if (IsTrue $v) { return 'yes' }; return 'no' }
function OneLine($v) { [regex]::Replace([regex]::Replace((Text $v), '\s+', ' '), '^ | $', '') }
function Excerpt([string]$t) { if ($t.Length -gt 120) { return $t.Substring(0, 120) }; return $t }
function CompareNames([string]$a1, [string]$a2) {
  $c = [string]::CompareOrdinal($a1.ToUpperInvariant(), $a2.ToUpperInvariant())
  if ($c -eq 0) { $c = [string]::CompareOrdinal($a1, $a2) }
  return $c
}
# a stable sort, like perl's
function SortStable($items, [scriptblock]$comparison) {
  $script:SortComparison = $comparison
  $list = [Collections.Generic.List[object]]::new()
  foreach ($item in $items) { $list.Add(@{ index = $list.Count; item = $item }) }
  $list.Sort([Comparison[object]] {
    param($p, $q)
    $c = [int](& $script:SortComparison $p.item $q.item)
    if ($c -eq 0) { $c = $p.index.CompareTo($q.index) }
    return $c
  })
  foreach ($entry in $list) { ,$entry.item }
}
# @{ name; obj } of the objects that pass the test, sorted by name
function SelectByName([scriptblock]$selTest, $selItems) {
  $selected = @(foreach ($selObj in $selItems) {
    if ($selObj -is $Dict -and ($selObj | ForEach-Object $selTest)) { @{ name = (Text $selObj.name); obj = $selObj } }
  })
  SortStable $selected { param($p, $q) CompareNames $p.name $q.name }
}
function Points($series) {
  if ($series -isnot $Dict) { return }
  foreach ($p in @(Objects $series['values'])) { @{ t = (ToEpoch $p.t); v = $p.v } }
}
# means of the first and the last 7 days
function WeekMeans($series) {
  $pts = @(Points $series | Where-Object { $null -ne $_.t })
  if ($pts.Count -eq 0) { return }
  $first = @($pts | Where-Object { $null -ne $_.v -and $_.t -lt $pts[0].t + 7 * 86400 } | ForEach-Object { Number $_.v })
  $last = @($pts | Where-Object { $null -ne $_.v -and $_.t -gt $pts[-1].t - 7 * 86400 } | ForEach-Object { Number $_.v })
  if ($first.Count -and $last.Count) { Mean $first; Mean $last }
}
function Section([string]$name) { Say "## $name" }
function NotChecked([string]$label, [string]$area) {
  if ($area -eq '') { $area = $label }
  $reason = 'not available'
  if (-not $Tested) { $reason = 'untested model' } elseif ($Why.ContainsKey($area)) { $reason = $Why[$area] }
  Say "not checked: ${label}: $reason"
}
function Fact([string]$key, $value) {
  $t = Text $value
  if ($t -ne '') { Say "${key}: $t" } else { NotChecked $key }
}
function Capability($device, [string]$name) {
  $caps = $device.capabilitiesObj
  if ($caps -is $Dict -and $caps[$name] -is $Dict) { return $caps[$name] }
  return $null
}
function ClassTag($device) { ' [' + (Text $device.class) + ']' }
function LastSeen($device) {
  $newest = ToEpoch $device.lastSeenAt
  $caps = $device.capabilitiesObj
  if ($caps -isnot $Dict) { $caps = $null }
  foreach ($c in @(Objects $caps)) {
    $t = ToEpoch $c.lastUpdated
    if ($null -ne $t -and ($null -eq $newest -or $t -gt $newest)) { $newest = $t }
  }
  return $newest
}
function IsLowBattery($device) {
  $v = (Capability $device 'measure_battery').value
  ((IsNumber $v) -or $v -is [string]) -and ((Text $v) -cmatch '^-?\d+(\.\d+)?$') -and ((Number $v) -le 20)
}
function SafetyAlarms($device) {
  foreach ($c in 'water', 'smoke', 'co', 'heat') { if ($null -ne (Capability $device "alarm_$c")) { "alarm_$c" } }
}
function FlowCount($list) {
  $all = @(Objects $list)
  "$($all.Count) ($(@($all | Where-Object { IsTrue $_.enabled }).Count) enabled)"
}
# Write-Report <responses by area> <reasons by area> <now, epoch seconds>: the report lines, in collect.sh's order.
# A response is $null when it could not be read; $Why holds the reason for its area.
function Write-Report($Responses, $Why, $NowEpoch) {
  $sys = $Responses['system']; $updates = $Responses['firmware_update']; $undervoltage = $Responses['undervoltage_31d_max']
  $backup = $Responses['backup']; $notes = $Responses['notifications']; $apps = $Responses['apps']
  $devices = $Responses['devices']; $zones = $Responses['zones']; $flows = $Responses['flows']
  $advanced = $Responses['advanced_flows']; $zigbee = $Responses['zigbee']; $zwave = $Responses['zwave']
  $memory = @{ '24h' = $Responses['memory_24h']; '7d' = $Responses['memory_7d']; '31d' = $Responses['memory_31d'] }
  $Tested = ($null -eq $sys) -or ((Text $sys.homeyModelName) -cmatch '\(Early 2023\)')
  Section 'Homey'
  if ($sys -isnot $Dict) { NotChecked 'system' } else {
    Fact 'model' $sys.homeyModelName
    Say ('model_tested: ' + (YesNo $Tested))
    Fact 'firmware' $sys.homeyVersion
    if ($null -eq $updates) { NotChecked 'firmware_update' } else {
      $u = @(Objects $updates)
      $t = 'none'
      if ($u.Count) { $t = (Message $u[0].version) + ' (' + (Message $u[0].channel) + ')' }
      Say "firmware_update: $t"
    }
    $boot = ToEpoch $sys.bootDate
    Fact 'booted' $(if ($null -ne $boot) { FormatDate $boot })
    Fact 'uptime_days' $(if ($null -ne $sys.uptime) { Round ((Number $sys.uptime) / 86400) 1 })
    $t = Text $sys.rebootReason
    if ($t -eq '') { $t = 'unknown' }
    Say "reboot_reason: $t"
    $total = $sys.totalmem; $free = $sys.freemem
    Fact 'memory' $(if ($null -ne $total -and $null -ne $free) {
      (Round (((Number $total) - (Number $free)) / 1048576) 0) + ' MB used of ' + (Round ((Number $total) / 1048576) 0) + ' MB' })
    $load = $sys.loadavg
    Fact 'loadavg' $(if ($load -is [object[]]) { @($load | ForEach-Object { Round (Number $_) 2 }) -join ' ' })
    $p = @($sys.videoCoreUnderVoltageCurrently, $sys.videoCoreUndervoltageOccured, $sys.videoCoreThrottleOccured | Where-Object { $null -ne $_ })
    Fact 'power' $(if ($p.Count -eq 3) { "undervoltage_now=$(YesNo $p[0]) undervoltage_seen=$(YesNo $p[1]) throttled_seen=$(YesNo $p[2])" })
    $if = $null
    if (IsTrue $sys.ethernetConnected) { $if = 'ethernet' } elseif (IsTrue $sys.wifiConnected) { $if = 'wifi' }
    Fact 'network' $if
    if ($if -eq 'wifi') {
      $strength = $sys.wifiStrength; $freq = $sys.wifiFrequency
      Fact 'wifi_signal' $(if ($null -ne $strength -and $null -ne $freq) { "$(Text $strength)%, $(Text $freq) MHz" })
    }
    Fact 'mac' (Text $sys["$($if)Mac"]).ToLowerInvariant()
    Fact 'address' $sys["$($if)Address"]
  }
  Section 'Stability'
  foreach ($w in ('24h', 60, 'min'), ('7d', 3600, 'h'), ('31d', 3600, 'h')) {
    $series = $memory[$w[0]]
    if ($null -eq $series) { NotChecked "outages_$($w[0])" "memory_$($w[0])"; continue }
    $pts = @(Points $series)
    $n = $pts.Count
    if ($n -gt 0 -and $null -eq $pts[$n - 1].v) { $n-- }
    $runs = @(); $run = $null
    for ($i = 0; $i -lt $n; $i++) {
      if ($null -ne $pts[$i].v) { $run = $null }
      elseif ($null -ne $run) { $run.count++ }
      else { $run = @{ t = $pts[$i].t; count = 1 }; $runs += $run }
    }
    Say ("outages_$($w[0]): " + $(if ($runs.Count) { $runs.Count } else { 'none' }))
    $step = Number $series.step
    foreach ($r in $runs) { Say ('  ' + (FormatDate $r.t) + ' ' + (Round ($r.count * $step / 1000 / $w[1]) 0) + ' ' + $w[2]) }
  }
  $weeks = @(WeekMeans $memory['31d'])
  if ($weeks.Count -eq 2 -and $weeks[0] -gt 0) {
    $pct = Round (($weeks[1] - $weeks[0]) / $weeks[0] * 100) 0
    if (-not $pct.StartsWith('-')) { $pct = '+' + $pct }
    Say "memory_trend_31d: $(Round $weeks[0] 0) MB -> $(Round $weeks[1] 0) MB ($pct%)"
  } else { NotChecked 'memory_trend_31d' 'memory_31d' }
  $uv = @(Points $undervoltage | Where-Object { $null -ne $_.v } | ForEach-Object { Number $_.v })
  if ($uv.Count) {
    $max = $uv[0]
    foreach ($v in $uv) { if ($v -gt $max) { $max = $v } }
    Say "undervoltage_31d_max: $(Round $max 2)"
  } else { NotChecked 'undervoltage_31d_max' }
  $Notices = @(Objects $notes | ForEach-Object {
    $t = ToEpoch $_.dateCreated
    $owner = $_.ownerName
    if ($null -eq $owner) { $owner = $_.ownerUri }
    if ($null -ne $t) { @{ t = $t; uri = (Text $_.ownerUri); owner = (Text $owner); text = (OneLine $_.excerpt) } }
  })
  $byTime = { param($p, $q) $p.t.CompareTo($q.t) }
  Section 'Backup'
  if ($backup -isnot $Dict) { NotChecked 'backup' } else {
    Fact 'backup_state' $backup.backupStateString
    Say ('backup_error: ' + (ValueOrNone $backup.backupError))
  }
  if ($null -eq $notes) { NotChecked 'notifications' } else {
    $list = @(SortStable @($Notices | Where-Object { $_.uri -ceq 'homey:manager:backup' }) $byTime)
    $oldest = $null
    foreach ($x in $Notices) { if ($null -eq $oldest -or $x.t -lt $oldest) { $oldest = $x.t } }
    Say ("backup_notices: $($list.Count)" + $(if ($null -ne $oldest) { ' since ' + (FormatDate $oldest) }))
    foreach ($x in $list) {
      $kind = 'other'
      if ($x.text -match 'problem|fail|error') { $kind = 'failed' } elseif ($x.text -match 'success|complete|created') { $kind = 'succeeded' }
      Say ('  ' + (FormatDate $x.t) + " ${kind}: " + (Excerpt $x.text))
    }
  }
  Section 'Apps'
  if ($null -eq $apps) { NotChecked 'apps' } else {
    $all = @(Objects $apps)
    Say "apps: $($all.Count) ($(@($all | Where-Object { (Text $_.state) -ceq 'running' }).Count) running)"
    foreach ($x in @(SelectByName { $true } $all)) {
      $app = $x.obj; $issues = @(); $update = $app.updateAvailable
      if ((Number $app.crashedCount) -gt 0) { $issues += "crashed $(Text $app.crashedCount) times" }
      if (-not (IsTrue $app.enabled)) { $issues += 'disabled' }
      elseif ((Text $app.state) -cne 'running') { $issues += 'not running (' + $(if (IsTrue $app.state) { Text $app.state } else { 'unknown' }) + ')' }
      if ($update -is [bool]) { if ($update) { $issues += 'update available' } }
      elseif ($null -ne $update) {
        if ($update -is $Dict) { $update = $update.version }
        $issues += 'update ' + (Message $update)
      }
      if ($null -ne $app.origin -and (Text $app.origin) -cne 'appstore') { $issues += "origin $(Text $app.origin)" }
      foreach ($issue in $issues) { Say "  $($x.name) $(Text $app.version): $issue" }
    }
  }
  $DeviceList = @(Objects $devices)
  $ZoneNames = $Dict::new()
  foreach ($z in @(Objects $zones)) { if ($null -ne $z.id) { $ZoneNames[(Text $z.id)] = $z.name } }
  Section 'Devices'
  if ($null -eq $devices) { NotChecked 'devices' } else {
    Say "devices: $($DeviceList.Count)"
    foreach ($x in @(SelectByName { $null -ne $_.available -and -not (IsTrue $_.available) } $DeviceList)) {
      $zone = Text $x.obj.zone
      if ($ZoneNames.ContainsKey($zone) -and $null -ne $ZoneNames[$zone]) { $zone = Text $ZoneNames[$zone] }
      $msg = $x.obj.unavailableMessage
      Say ("  unavailable: $($x.name)" + (ClassTag $x.obj) + " $zone" + $(if ($null -ne $msg) { ": $(Text $msg)" }))
    }
    foreach ($x in @(SelectByName { (Text $_.warningMessage) -ne '' } $DeviceList)) {
      Say ("  warning: $($x.name)" + (ClassTag $x.obj) + ': ' + (Text $x.obj.warningMessage))
    }
    $hasFirmware = { $_.firmwareUpdate -is $Dict -and $null -ne $_.firmwareUpdate.availableVersion }
    foreach ($x in @(SelectByName $hasFirmware $DeviceList)) {
      $fw = $x.obj.firmwareUpdate
      $current = $fw.currentVersion
      if ($null -eq $current) { $current = 'unknown' }
      Say ("  firmware: $($x.name): $(Text $current) -> " + (Text $fw.availableVersion) + $(if (IsTrue $fw.requiresWake) { ', needs wake' }))
    }
    foreach ($x in @(SelectByName { (Text $_.class) -cmatch '^(sensor|thermostat)$' } $DeviceList)) {
      $t = LastSeen $x.obj
      $line = "  stale: $($x.name)" + (ClassTag $x.obj)
      if ($null -eq $t) { Say "$line last never" }
      elseif ($NowEpoch - $t -gt 3 * 86400) { Say ("$line last " + (FormatDate $t) + ' (' + [Math]::Truncate(($NowEpoch - $t) / 86400) + ' days)') }
    }
  }
  Section 'Batteries'
  if ($null -eq $devices) { NotChecked 'devices' } else {
    foreach ($x in @(SelectByName { IsLowBattery $_ } $DeviceList)) {
      $alarm = (Capability $x.obj 'alarm_battery').value
      Say ("  low: $($x.name) " + (Text (Capability $x.obj 'measure_battery').value) + '%' + $(if (IsTrue $alarm) { ', alarm' }))
    }
    foreach ($x in @(SelectByName { -not (IsLowBattery $_) -and (IsTrue (Capability $_ 'alarm_battery').value) } $DeviceList)) {
      Say "  alarm: $($x.name) alarm_battery on"
    }
    $noReport = { $null -eq (Capability $_ 'measure_battery') -and $null -eq (Capability $_ 'alarm_battery') -and @(SafetyAlarms $_).Count -gt 0 }
    foreach ($x in @(SelectByName $noReport $DeviceList)) { Say ("  no_battery_report: $($x.name) [" + (@(SafetyAlarms $x.obj) -join ', ') + ']') }
  }
  Section 'Flows'
  if ($null -ne $flows -and $null -ne $advanced) { Say ('flows: ' + (FlowCount $flows) + ', advanced: ' + (FlowCount $advanced)) }
  if ($null -eq $flows) { NotChecked 'flows' }
  if ($null -eq $advanced) { NotChecked 'advanced_flows' }
  $all = @(Objects $flows) + @(Objects $advanced)
  foreach ($x in @(SelectByName { IsTrue $_.broken } $all)) { Say "  broken: $($x.name)" }
  foreach ($x in @(SelectByName { -not (IsTrue $_.enabled) } $all)) { Say "  disabled: $($x.name)" }
  Section 'Radio'
  if ($zigbee -isnot $Dict) { NotChecked 'zigbee' } else {
    $nodes = @(Objects $zigbee.nodes | Where-Object { (Text $_.type) -cne 'coordinator' }).Count
    Say ('zigbee: ready=' + (YesNo $zigbee.zigbee_ready) + ' error=' + (ValueOrNone $zigbee.zigbee_error) + " nodes=$nodes")
  }
  # Z-Wave: two counts only (the state holds network keys)
  $state = $null
  if ($zwave -is $Dict -and $zwave.zw_state -is $Dict) { $state = $zwave.zw_state }
  if ($state.nodes -isnot [object[]]) { NotChecked 'zwave' } else {
    $controller = Text $state.nodeId
    $noAck = 0
    if ($state.noAckNodes -is [object[]]) { $noAck = $state.noAckNodes.Count }
    Say ("zwave: nodes=$(@($state.nodes | Where-Object { (Text $_) -cne $controller }).Count) no_ack=$noAck")
  }
  Section 'Notifications (14 days)'
  if ($null -eq $notes) { NotChecked 'notifications' } else {
    $recent = @($Notices | Where-Object { $_.t -ge $NowEpoch - 14 * 86400 })
    $counts = $Dict::new()
    foreach ($x in $recent) { if ($counts.ContainsKey($x.owner)) { $counts[$x.owner] += 1 } else { $counts[$x.owner] = 1 } }
    foreach ($owner in @(SortStable @($counts.Keys) { param($p, $q) CompareNames $p $q })) { Say "  ${owner}: $($counts[$owner])" }
    # presence and security notices can name people: never matched or quoted
    $keywords = 'backup|offline|disconnect|connection lost|lost connection|unreachable|failed|error|crash|sync.*disabled|battery'
    $matched = @($recent | Where-Object { $_.uri -cnotmatch '^homey:manager:(presence|security|backup)$' -and $_.text -match $keywords })
    foreach ($x in @(SortStable $matched $byTime)) { Say ('  match ' + (FormatDate $x.t) + " $($x.owner): " + (Excerpt $x.text)) }
  }
  Section 'Tidiness'
  if ($null -eq $devices) { NotChecked 'devices' } elseif ($null -eq $zones) { NotChecked 'zones' } else {
    $zoneById = $Dict::new(); $used = $Dict::new()
    foreach ($z in @(Objects $zones)) { if ($null -ne $z.id) { $zoneById[(Text $z.id)] = $z } }
    foreach ($d in $DeviceList) { $used[(Text $d.zone)] = 1 }
    foreach ($z in $zoneById.Values) { if ($null -ne $z.parent) { $used[(Text $z.parent)] = 1 } }
    $topLevel = { $k = Text $_.zone; $zoneById.ContainsKey($k) -and $null -eq $zoneById[$k].parent }
    foreach ($x in @(SelectByName $topLevel $DeviceList)) { Say "  no_zone: $($x.name)" }
    $empty = { $null -ne $_.parent -and -not $used.ContainsKey((Text $_.id)) }
    foreach ($x in @(SelectByName $empty @($zoneById.Values))) { Say "  empty_zone: $($x.name)" }
    foreach ($x in @(SelectByName { (Text $_.name) -match '^\s|\s$|  ' } $DeviceList)) { Say "  name_spaces: `"$($x.name)`"" }
  }
}
