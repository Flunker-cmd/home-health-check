# Read-only probe of the home router / mesh from a Windows PC on the LAN.
# No admin needed. Touches only the local network, plus pings and a 3-hop traceroute to public DNS servers.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File probe.ps1 [-Sweep]
#   -Sweep  ping every address in the local /24 first so the ARP table lists all devices
param([switch]$Sweep)

$ErrorActionPreference = 'SilentlyContinue'
function Section($name) { Write-Output ""; Write-Output "## $name" }

function Ping-Stats($target, $count = 20) {
    $p = New-Object System.Net.NetworkInformation.Ping
    $times = @(); $lost = 0
    for ($i = 0; $i -lt $count; $i++) {
        try { $r = $p.Send($target, 1000) } catch { $r = $null }
        if ($r -and $r.Status -eq 'Success') { $times += $r.RoundtripTime } else { $lost++ }
    }
    if ($times.Count -gt 0) {
        $s = $times | Measure-Object -Minimum -Maximum -Average
        "{0,-16} loss {1,3}%  min {2} ms  avg {3:N1} ms  max {4} ms" -f $target, [int](100 * $lost / $count), $s.Minimum, $s.Average, $s.Maximum
    } else {
        "{0,-16} loss 100%" -f $target
    }
}

function Test-Port($ip, $port) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($ip, $port, $null, $null)
        $ok = $ar.AsyncWaitHandle.WaitOne(800) -and $c.Connected
        return $ok
    } finally { $c.Close() }
}

# ---------------------------------------------------------------------------
Section "Gateway and DHCP"
$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1
$gw = $route.NextHop
$ifIndex = $route.ifIndex
$cfg = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.InterfaceIndex -eq $ifIndex }
$adapter = Get-NetAdapter -InterfaceIndex $ifIndex
$ip4 = (Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 | Select-Object -First 1)
"adapter:        $($adapter.Name) ($($adapter.InterfaceDescription)), link $($adapter.LinkSpeed)"
"this PC:        $($ip4.IPAddress)/$($ip4.PrefixLength)"
"gateway:        $gw"
"DHCP enabled:   $($cfg.DHCPEnabled)"
"DHCP server:    $($cfg.DHCPServer)"
"DNS servers:    $($cfg.DNSServerSearchOrder -join ', ')"
if ($cfg.DHCPLeaseObtained -and $cfg.DHCPLeaseExpires) {
    $lease = ($cfg.DHCPLeaseExpires - $cfg.DHCPLeaseObtained).TotalHours
    "DHCP lease:     {0:N1} h" -f $lease
}

# ---------------------------------------------------------------------------
Section "Latency and packet loss (20 pings each)"
foreach ($t in @($gw) + ($cfg.DNSServerSearchOrder | Where-Object { $_ -ne $gw }) + @('1.1.1.1', '9.9.9.9', '8.8.8.8')) {
    if ($t) { Ping-Stats $t }
}

# ---------------------------------------------------------------------------
Section "Open TCP ports on the gateway"
$ports = 21, 22, 23, 53, 80, 443, 445, 5000, 7547, 8080, 8443, 20001, 49152
$open = foreach ($port in $ports) { if (Test-Port $gw $port) { $port } }
"open:   $($open -join ', ')"
"tested: $($ports -join ', ')"

# ---------------------------------------------------------------------------
Section "UPnP devices (SSDP)"
$udp = New-Object System.Net.Sockets.UdpClient
$udp.Client.ReceiveTimeout = 1000
$msg = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 2`r`nST: upnp:rootdevice`r`n`r`n"
$bytes = [Text.Encoding]::ASCII.GetBytes($msg)
[void]$udp.Send($bytes, $bytes.Length, '239.255.255.250', 1900)
$locations = @{}
$deadline = (Get-Date).AddSeconds(4)
while ((Get-Date) -lt $deadline) {
    try {
        $ep = New-Object System.Net.IPEndPoint([Net.IPAddress]::Any, 0)
        $resp = [Text.Encoding]::ASCII.GetString($udp.Receive([ref]$ep))
        if ($resp -match '(?im)^LOCATION:\s*(\S+)') { $locations[$Matches[1]] = $ep.Address.ToString() }
    } catch { }
}
$udp.Close()

$controlUrls = @()
foreach ($loc in $locations.Keys) {
    try { [xml]$x = (Invoke-WebRequest -Uri $loc -UseBasicParsing -TimeoutSec 4).Content } catch { continue }
    $d = $x.root.device
    "{0,-15} {1} | {2} {3} {4} | {5}" -f $locations[$loc], $d.friendlyName, $d.manufacturer, $d.modelName, $d.modelNumber, $loc
    if ($locations[$loc] -eq $gw) {
        $base = ([Uri]$loc).GetLeftPart([UriPartial]::Authority)
        foreach ($svc in $x.GetElementsByTagName('service')) {
            if ($svc.serviceType -match 'WAN(IP|PPP)Connection') {
                $controlUrls += [pscustomobject]@{ Url = $base + $svc.controlURL; Type = $svc.serviceType }
            }
        }
    }
}
if ($locations.Count -eq 0) { "no UPnP devices answered (UPnP may be off)" }

Section "UPnP port mappings on the gateway"
if ($controlUrls.Count -eq 0) { "no WAN connection service found (UPnP IGD off or not exposed)" }
foreach ($cu in $controlUrls) {
    for ($i = 0; $i -lt 64; $i++) {
        $body = "<?xml version=`"1.0`"?><s:Envelope xmlns:s=`"http://schemas.xmlsoap.org/soap/envelope/`" s:encodingStyle=`"http://schemas.xmlsoap.org/soap/encoding/`"><s:Body><u:GetGenericPortMappingEntry xmlns:u=`"$($cu.Type)`"><NewPortMappingIndex>$i</NewPortMappingIndex></u:GetGenericPortMappingEntry></s:Body></s:Envelope>"
        try {
            $r = Invoke-WebRequest -Uri $cu.Url -Method Post -Body $body -ContentType 'text/xml; charset="utf-8"' `
                -Headers @{ SOAPAction = "`"$($cu.Type)#GetGenericPortMappingEntry`"" } -UseBasicParsing -TimeoutSec 4
        } catch { if ($i -eq 0) { "no mappings" }; break }
        [xml]$m = $r.Content
        $e = $m.Envelope.Body.FirstChild
        "{0} {1} -> {2}:{3}  '{4}'  lease {5}s" -f $e.NewProtocol, $e.NewExternalPort, $e.NewInternalClient, $e.NewInternalPort, $e.NewPortMappingDescription, $e.NewLeaseDuration
    }
}

# ---------------------------------------------------------------------------
Section "First hops to the internet (double NAT / CGNAT check)"
tracert -d -h 3 -w 800 1.1.1.1 | Select-String -Pattern '^\s+\d+' | ForEach-Object { $_.Line.Trim() }
"(a private 2nd hop = double NAT; 100.64.x.x-100.127.x.x = carrier-grade NAT)"

# ---------------------------------------------------------------------------
Section "DNS path"
foreach ($srv in @($gw) + ($cfg.DNSServerSearchOrder | Where-Object { $_ -ne $gw })) {
    $a = (Resolve-DnsName doubleclick.net -Type A -Server $srv -DnsOnly -QuickTimeout | Where-Object IPAddress | Select-Object -First 1).IPAddress
    if (-not $a) { $a = '(no answer)' }
    "doubleclick.net via {0,-15} -> {1}" -f $srv, $a
}
"(0.0.0.0 or no answer = filtered; a real address = not filtered)"

# ---------------------------------------------------------------------------
Section "IPv6"
$bind = Get-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6
"IPv6 enabled on adapter: $($bind.Enabled)"
Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv6 | Where-Object { $_.IPAddress -notlike 'fe80*' } |
    ForEach-Object { "address: $($_.IPAddress)/$($_.PrefixLength) ($($_.PrefixOrigin))" }
Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv6 | ForEach-Object { if ($_.ServerAddresses) { "IPv6 DNS: $($_.ServerAddresses -join ', ')" } }
(Get-NetRoute -AddressFamily IPv6 -DestinationPrefix '::/0' | Select-Object -First 1) | ForEach-Object { "IPv6 default route via $($_.NextHop)" }

# ---------------------------------------------------------------------------
Section "Wi-Fi"
$wlan = netsh wlan show interfaces 2>$null
if ($wlan -match 'State\s*:\s*connected') {
    $wlan | Select-String -Pattern '^\s+(SSID|BSSID|Radio type|Authentication|Cipher|Channel|Signal|Band)\s*:' | ForEach-Object { $_.Line.Trim() }
} else { "this PC is not connected over Wi-Fi" }
"nearby networks:"
$ssid = $null
foreach ($line in (netsh wlan show networks mode=bssid 2>$null)) {
    if ($line -match '^SSID \d+ : (.*)$') { $ssid = $Matches[1]; if (-not $ssid) { $ssid = '(hidden)' } }
    elseif ($line -match '^\s+Authentication\s*:\s*(.*)$') { $auth = $Matches[1] }
    elseif ($line -match '^\s+Encryption\s*:\s*(.*)$') { "  {0,-28} {1} / {2}" -f $ssid, $auth, $Matches[1] }
    elseif ($line -match '^\s+BSSID \d+\s*:\s*(.*)$') { $bssid = $Matches[1] }
    elseif ($line -match '^\s+Signal\s*:\s*(.*)$') { $sig = $Matches[1] }
    elseif ($line -match '^\s+Channel\s*:\s*(.*)$') { "      {0}  signal {1}  channel {2}" -f $bssid, $sig, $Matches[1] }
}

# ---------------------------------------------------------------------------
Section "Devices on the LAN (ARP)"
if ($Sweep -and $ip4.PrefixLength -ge 24) {
    $net = ($ip4.IPAddress -split '\.')[0..2] -join '.'
    $jobs = 1..254 | ForEach-Object { (New-Object System.Net.NetworkInformation.Ping).SendPingAsync("$net.$_", 500) }
    try { [Threading.Tasks.Task]::WaitAll($jobs) } catch { }
}
Get-NetNeighbor -InterfaceIndex $ifIndex -AddressFamily IPv4 |
    Where-Object { $_.State -in 'Reachable', 'Stale', 'Delay', 'Probe', 'Permanent' -and $_.LinkLayerAddress -and $_.LinkLayerAddress -notmatch '^(00-00-00-00-00-00|FF-FF-FF-FF-FF-FF|01-00-5E)' } |
    Sort-Object { [version]$_.IPAddress } |
    ForEach-Object { "{0,-15} {1}" -f $_.IPAddress, $_.LinkLayerAddress }
"(look up the first three MAC bytes for the vendor; random-looking MACs with the 2nd hex digit 2/6/A/E are private phone/tablet addresses)"
