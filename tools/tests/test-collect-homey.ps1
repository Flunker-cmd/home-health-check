# Tests for homey-health-check/scripts/collect.ps1. Dot-sourced by tools/test-ps.ps1.
# The collector runs as a child powershell process, like a user would run it. Twin of test-collect-homey.sh.
$HomeyPs = Join-Path $HhcRoot 'plugins\home-health-check\skills\homey-health-check\scripts\collect.ps1'
$HomeyNow = '2026-10-28T12:00Z'

# Invoke-Homey <arg>...: runs the collector, returns Out, Err (UTF-8 text) and Code
function Invoke-Homey {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $q = @($args | ForEach-Object { if ("$_" -match '\s') { '"' + $_ + '"' } else { "$_" } })
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $HomeyPs + '" ' + ($q -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $psi.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $p = [Diagnostics.Process]::Start($psi)
    $err = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ Out = $out.Replace("`r", ''); Err = $err.Result.Replace("`r", ''); Code = $p.ExitCode }
}

# Copy-Homey <name>: a copy of the fixture folder in $HhcTmp, returned as its path
function Copy-Homey([string]$Name) {
    $d = Join-Path $HhcTmp $Name
    Copy-Item -LiteralPath (Get-Fixture 'homey') -Destination $d -Recurse
    $d
}
$Utf8 = New-Object Text.UTF8Encoding($false)

# --- the whole report, byte for byte ---
$r = Invoke-Homey -Homey 192.168.1.50 -FromDir (Get-Fixture 'homey') -Now $HomeyNow
$expected = [IO.File]::ReadAllText((Get-Fixture 'homey/expected.txt'), $Utf8).Replace("`r", '')
Assert-Eq 'collect.ps1 on fixtures matches expected.txt' $expected ($r.Out + $r.Err)
Assert-Eq 'collect.ps1 on fixtures exits 0' '0' "$($r.Code)"

# --- privacy ---
$all = $r.Out + $r.Err
Assert-Eq 'no canary in output' 'no' $(if ($all -match 'CANARY') { 'yes' } else { 'no' })
Assert-Eq 'presence notice not quoted' 'no' $(if ($all -match '(?m)^  match .*Presence') { 'yes' } else { 'no' })
Assert-Eq 'no person named by presence or security notices' 'no' $(if ($all -match 'Person') { 'yes' } else { 'no' })
Assert-Eq 'notices written by flows not quoted' 'no' $(if ($all -match '(?m)^  match .*(Flow|Notifications):') { 'yes' } else { 'no' })

# --- a key without permission for one area (here: no zwave.json) ---
$d = Copy-Homey 'nozwave'
Remove-Item -LiteralPath (Join-Path $d 'zwave.json')
$r = Invoke-Homey -Homey 192.168.1.50 -FromDir $d -Now $HomeyNow
Assert-Match 'missing zwave.json prints not checked' '(?m)^not checked: zwave: not available$' $r.Out
Assert-Match 'missing zwave.json still prints the Flows section' '## Flows' $r.Out
Assert-Eq 'missing zwave.json exits 0' '0' "$($r.Code)"

# --- an older Homey Pro ---
$d = Copy-Homey 'untested'
$f = Join-Path $d 'system.json'
[IO.File]::WriteAllText($f, [IO.File]::ReadAllText($f, $Utf8).Replace('Homey Pro (Early 2023)', 'Homey Pro (2019)'), $Utf8)
$r = Invoke-Homey -Homey 192.168.1.50 -FromDir $d -Now $HomeyNow
Assert-Match 'untested model' '(?m)^model_tested: no$' $r.Out
Remove-Item -LiteralPath (Join-Path $d 'zwave.json')
$r = Invoke-Homey -Homey 192.168.1.50 -FromDir $d -Now $HomeyNow
Assert-Match 'untested model keeps the real reason' '(?m)^not checked: zwave: not available \(untested model\)$' $r.Out

# --- wrongly shaped responses (homey-wrong-shape/ overlays the fixtures; collect.sh must print the same) ---
$d = Copy-Homey 'wrongshape'
Copy-Item -Path (Join-Path (Get-Fixture 'homey-wrong-shape') '*.json') -Destination $d
$r = Invoke-Homey -Homey 192.168.1.50 -FromDir $d -Now $HomeyNow
$expected = [IO.File]::ReadAllText((Get-Fixture 'homey-wrong-shape/expected.txt'), $Utf8).Replace("`r", '')
Assert-Eq 'wrongly shaped responses match homey-wrong-shape/expected.txt' $expected ($r.Out + $r.Err)
Assert-Eq 'wrongly shaped responses exit 0' '0' "$($r.Code)"

# --- a devices.json over 3 MB (ConvertFrom-Json in 5.1 gives up near 2 MB) ---
$d = Copy-Homey 'large'
$f = Join-Path $d 'devices.json'
$sb = New-Object Text.StringBuilder
[void]$sb.Append([IO.File]::ReadAllText($f, $Utf8).TrimEnd().TrimEnd('}'))
$filler = 'x' * 10240
for ($i = 0; $i -lt 300; $i++) {
    [void]$sb.Append(",`"pad-$i`": {`"id`": `"pad-$i`", `"name`": `"Pad light $i`", `"class`": `"light`", `"available`": true, `"note`": `"$filler`", `"capabilitiesObj`": {`"onoff`": {`"value`": true, `"lastUpdated`": 1793000000000}}}")
}
[void]$sb.Append('}')
[IO.File]::WriteAllText($f, $sb.ToString(), $Utf8)
Assert-Eq 'large devices.json is over 3 MB' 'yes' $(if ((Get-Item -LiteralPath $f).Length -gt 3MB) { 'yes' } else { 'no' })
$r = Invoke-Homey -Homey 192.168.1.50 -FromDir $d -Now $HomeyNow
Assert-Match 'large devices.json still renders the Devices section' '(?m)^## Devices\ndevices: 311$' $r.Out
Assert-Match 'large devices.json still renders Batteries' '(?m)^  low: Leak sensor 2 15%, alarm$' $r.Out

# --- options ---
$r = Invoke-Homey -Help
Assert-Eq '-Help exits 0 and prints Usage' '0 usage' "$($r.Code) $(if ($r.Out -match 'Usage') { 'usage' })"
$r = Invoke-Homey -Bogus
Assert-Eq '-Bogus exits 2' '2' "$($r.Code)"
$r = Invoke-Homey -FromDir (Get-Fixture 'homey')
Assert-Eq 'missing -Homey exits 2' '2' "$($r.Code)"
$r = Invoke-Homey -Homey 192.168.1.50 -FromDir (Get-Fixture 'homey') -Now bad
Assert-Eq 'bad -Now exits 2' '2' "$($r.Code)"

# --- the key never shows up in an error ---
$k = Join-Path $HhcTmp 'homey-key.txt'
[IO.File]::WriteAllText($k, "CANARY-KEY-FILE`n", $Utf8)
$r = Invoke-Homey -Homey 127.0.0.1:9 -KeyFile $k
Assert-Eq 'an unreachable Homey exits 3' '3' "$($r.Code)"
Assert-Eq 'an unreachable Homey says so' 'error: cannot reach the Homey at 127.0.0.1:9' ($r.Out + $r.Err).Trim()
Assert-Eq 'no key in error output' 'no' $(if (($r.Out + $r.Err) -match 'CANARY') { 'yes' } else { 'no' })

# --- collect.ps1 needs render.ps1 next to it ---
$alone = Join-Path $HhcTmp 'alone'
New-Item -ItemType Directory -Path $alone | Out-Null
Copy-Item -LiteralPath $HomeyPs -Destination $alone
$saved = $HomeyPs
$HomeyPs = Join-Path $alone 'collect.ps1'
$r = Invoke-Homey -Homey 192.168.1.50 -FromDir (Get-Fixture 'homey') -Now $HomeyNow
$HomeyPs = $saved
Assert-Eq 'collect.ps1 without render.ps1 exits 2' '2' "$($r.Code)"
Assert-Eq 'collect.ps1 without render.ps1 says so' 'error: render.ps1 must be in the same folder as collect.ps1' ($r.Out + $r.Err).Trim()

# --- the key never leaves for another host: a redirect is not followed ---
# A fake Homey answers every call with a redirect to a second listener, which logs any request it gets.
$listeners = @(1, 2 | ForEach-Object { $l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $l.Start(); $l })
$otherLog = Join-Path $HhcTmp 'homey-other.log'
$server = [powershell]::Create()
[void]$server.AddScript({
    param($listeners, $log)
    $other = $listeners[1].LocalEndpoint.Port
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    while ([DateTime]::UtcNow -lt $deadline) {
        foreach ($l in $listeners) {
            if (-not $l.Pending()) { continue }
            $c = $l.AcceptTcpClient()
            $s = $c.GetStream()
            $reader = New-Object IO.StreamReader($s)
            $head = ''
            while ($true) { $line = $reader.ReadLine(); if ($null -eq $line -or $line -eq '') { break }; $head += "$line`n" }
            if ($l -eq $listeners[1]) {
                [IO.File]::AppendAllText($log, 'other host got a request' + $(if ($head -match '(?im)^Authorization:') { ' with the key' }) + "`n")
                $answer = "HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
            } else {
                $answer = "HTTP/1.1 302 Found`r`nLocation: http://127.0.0.1:$other/api/manager/system/`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
            }
            $bytes = [Text.Encoding]::ASCII.GetBytes($answer)
            $s.Write($bytes, 0, $bytes.Length)
            $s.Flush()
            $c.Close()
        }
        Start-Sleep -Milliseconds 20
    }
}).AddArgument($listeners).AddArgument($otherLog)
$running = $server.BeginInvoke()
$r = Invoke-Homey -Homey "127.0.0.1:$($listeners[0].LocalEndpoint.Port)" -KeyFile $k
$server.Stop()
foreach ($l in $listeners) { $l.Stop() }
$got = ''
if (Test-Path -LiteralPath $otherLog) { $got = [IO.File]::ReadAllText($otherLog).Trim() }
Assert-Eq 'a redirect is not followed' '' $got
Assert-Eq 'a redirect reads as not available, exit 0' '0 yes' "$($r.Code) $(if ($r.Out -match '(?m)^not checked: system: not available$') { 'yes' })"
