# Read-only health snapshot of a Homey Pro through its local Web API (plain HTTP on the LAN, GET only). No admin needed.
# This file reads the options and the key and fetches the API responses; render.ps1 (same folder) turns them into the report.
# The key (first line of -KeyFile) goes only into the Authorization header: never an argument, never printed.
# Output and exit codes equal collect.sh, the reference for every rule.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File collect.ps1 -Homey <ip or name> -KeyFile <path>
# Exit codes: 0 report printed, 1 the report could not be rendered, 2 bad options (or render.ps1 missing), 3 Homey not reachable.
# There is no param block: the options are parsed by hand so an unknown option or a missing value prints the usage
# and exits 2 like collect.sh (PowerShell's own parameter binder would exit 1 with its own message).
$ErrorActionPreference = 'Stop'
$Utf8 = New-Object Text.UTF8Encoding($false)
$StdOut = New-Object IO.StreamWriter([Console]::OpenStandardOutput(), $Utf8)
$StdOut.NewLine = "`n"
function Fail([string]$message, [int]$code) {
  $StdOut.Flush()
  [Console]::Error.Write("$message`n")
  exit $code
}
function Usage {
  @('Usage: powershell -NoProfile -ExecutionPolicy Bypass -File collect.ps1 -Homey <ip or name> -KeyFile <path>',
    '  -Homey <ip or name>     the Homey on the LAN (host:port also works)',
    '  -KeyFile <path>         text file whose first line is a read-only Homey API key',
    '  -FromDir <dir>          offline: read saved API responses, for testing',
    '  -Now <ISO 8601 UTC>     offline: the clock to use, for testing (e.g. 2026-10-28T12:00Z)',
    '  files read by -FromDir: system.json devices.json flows.json advancedflows.json apps.json',
    '    zones.json zigbee.json zwave.json updates.json notifications.json backup-state.json',
    '    memory-24h.json memory-7d.json memory-31d.json undervoltage-31d.json') -join "`n"
}

$render = Join-Path $PSScriptRoot 'render.ps1'
if (-not (Test-Path -LiteralPath $render -PathType Leaf)) { Fail 'error: render.ps1 must be in the same folder as collect.ps1' 2 }
. $render

$Homey = ''; $KeyFile = ''; $FromDir = ''; $Now = ''
for ($i = 0; $i -lt $args.Count; $i += 2) {
  $opt = [string]$args[$i]
  if ($opt -match '^-(h|help|\?)$') { $StdOut.WriteLine((Usage)); $StdOut.Flush(); exit 0 }
  if ($opt -notmatch '^-(Homey|KeyFile|FromDir|Now)$' -or $i + 1 -ge $args.Count) { Fail (Usage) 2 }
  Set-Variable -Name $Matches[1] -Value ([string]$args[$i + 1])
}
if ($Homey -eq '' -or ($KeyFile -eq '' -and $FromDir -eq '')) { Fail (Usage) 2 }
if ($FromDir -ne '') {
  $FromDir = [IO.Path]::GetFullPath($FromDir)
} else {
  $key = $null
  try {
    $reader = New-Object IO.StreamReader($KeyFile, $Utf8, $true)
    $key = $reader.ReadLine()
    $reader.Close()
  } catch { Fail 'error: cannot read the key file' 2 }
  if ($null -eq $key -or $key.Trim() -eq '') { Fail 'error: the key file is empty' 2 }
  $Auth = 'Bearer ' + $key.Trim()
  Remove-Variable key
}

Add-Type -AssemblyName System.Web.Extensions
$Json = New-Object Web.Script.Serialization.JavaScriptSerializer
$Json.MaxJsonLength = [int]::MaxValue
$Why = [Collections.Generic.Dictionary[string, object]]::new()
$Responses = @{}
$Calls = 0

# Fetch <area> <API path> [<file under -FromDir>]: stores the decoded JSON in $Responses[<area>],
# or $null with the reason in $Why[<area>]. Nothing from a response or an exception is ever printed.
# A body that is not a JSON object (or, for the list areas, an array) is unreadable too.
$ListAreas = 'firmware_update', 'notifications', 'apps', 'devices', 'zones', 'flows', 'advanced_flows'
function Fetch([string]$area, [string]$path, [string]$file = "$area.json") {
  $body = $null
  $status = 'bad'
  if ($FromDir -ne '') {
    $f = Join-Path $FromDir $file
    if ([IO.File]::Exists($f)) { $body = [IO.File]::ReadAllText($f, $Utf8) } else { $status = 404 }
  } else {
    if ($script:Calls -gt 0) { Start-Sleep -Milliseconds 200 }
    $script:Calls++
    $gotHeaders = $false
    try {
      $request = [Net.WebRequest]::Create("http://$Homey/api/manager/$path")
      # no proxy and no redirects: the key goes to the named host only (a 3xx reads as not available)
      $request.Proxy = $null
      $request.AllowAutoRedirect = $false
      $request.Timeout = 15000
      $request.ReadWriteTimeout = 15000
      $request.Headers.Add('Authorization', $Auth)
      $response = $request.GetResponse()
      $gotHeaders = $true
      $status = [int]$response.StatusCode
      if ($status -lt 300) { $body = (New-Object IO.StreamReader($response.GetResponseStream(), $Utf8)).ReadToEnd() }
      $response.Close()
    } catch {
      $body = $null
      $ex = $_.Exception
      while ($null -ne $ex -and $ex -isnot [Net.WebException]) { $ex = $ex.InnerException }
      if ($null -ne $ex -and $null -ne $ex.Response) { $status = [int]$ex.Response.StatusCode }
      elseif ($script:Calls -eq 1) { Fail "error: cannot reach the Homey at $Homey" 3 }
      elseif ($gotHeaders -or ($null -ne $ex -and $ex.Status -eq 'Timeout')) { $status = 'timeout' }
    }
  }
  $data = $null
  if ($null -ne $body) {
    try { $data = $Json.DeserializeObject($body) } catch { $data = $null }
    if ($data -isnot [Collections.Generic.Dictionary[string, object]] -and -not ($data -is [object[]] -and $ListAreas -contains $area)) { $data = $null }
  }
  if ($null -eq $data) {
    $Why[$area] = 'not available'
    if ("$status" -match '^40[13]$') { $Why[$area] = 'key lacks permission' }
    elseif ("$status" -eq 'timeout') { $Why[$area] = 'timed out' }
  }
  $Responses[$area] = $data
}
function SeriesPath([string]$log, [string]$resolution) { "insights/log/number/$log/entry?resolution=$resolution" }

try {
  $NowEpoch = [Math]::Floor(([DateTime]::UtcNow - [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).TotalSeconds)
  if ($Now -ne '') { $NowEpoch = ToEpoch $Now }
  if ($null -eq $NowEpoch) { Fail 'error: -Now must look like 2026-10-28T12:00Z' 2 }
  Fetch 'system' 'system/'
  Fetch 'firmware_update' 'updates/update/' 'updates.json'
  foreach ($w in ('24h', 'last24Hours'), ('7d', 'last7Days'), ('31d', 'last31Days')) {
    Fetch "memory_$($w[0])" (SeriesPath 'homey:manager:system:memory' $w[1]) "memory-$($w[0]).json"
  }
  Fetch 'undervoltage_31d_max' (SeriesPath 'homey:manager:system:undervoltageratio' 'last31Days') 'undervoltage-31d.json'
  Fetch 'backup' 'backup/state' 'backup-state.json'
  Fetch 'notifications' 'notifications/notification/'
  Fetch 'apps' 'apps/app/'
  Fetch 'devices' 'devices/device/'
  Fetch 'zones' 'zones/zone/'
  Fetch 'flows' 'flow/flow/'
  Fetch 'advanced_flows' 'flow/advancedflow/' 'advancedflows.json'
  Fetch 'zigbee' 'zigbee/state'
  Fetch 'zwave' 'zwave/state'
  Write-Report $Responses $Why $NowEpoch | ForEach-Object { $StdOut.WriteLine([string]$_) }
} catch { Fail 'error: the collector failed while rendering the report' 1 }
$StdOut.Flush()
exit 0
