# Find the devices on the local network from a Windows PC. No admin needed.
# Only talks to the local subnet (plus one optional download of a public MAC vendor list).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File discover.ps1 [-Ports] [-Oui] [-Json]
#   -Ports  also check a few well-known TCP ports per device to guess what it is
#   -Oui    look up MAC vendors in Wireshark's public vendor list (downloaded once to ~/.home-health-check/manuf.txt)
#   -Json   print JSON instead of a table
param([switch]$Ports, [switch]$Oui, [switch]$Json)

$ErrorActionPreference = 'SilentlyContinue'

# --- local network ----------------------------------------------------------
$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1
$ifIndex = $route.ifIndex
$gw = $route.NextHop
$ip4 = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 | Select-Object -First 1
$prefix = [math]::Max($ip4.PrefixLength, 22)          # never sweep more than 1024 addresses
$ipBytes = ([Net.IPAddress]$ip4.IPAddress).GetAddressBytes(); [Array]::Reverse($ipBytes)
$ipNum = [BitConverter]::ToUInt32($ipBytes, 0)
$mask = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $prefix))
$net = $ipNum -band $mask
$count = [math]::Pow(2, 32 - $prefix) - 2

function NumToIp([uint32]$n) { $b = [BitConverter]::GetBytes($n); [Array]::Reverse($b); ([Net.IPAddress]$b).ToString() }

# --- ping sweep so the ARP table fills up ----------------------------------
$tasks = for ($i = 1; $i -le $count; $i++) {
    (New-Object System.Net.NetworkInformation.Ping).SendPingAsync((NumToIp ($net + $i)), 600)
}
try { [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$tasks) } catch { }
Start-Sleep -Milliseconds 500

$neighbors = Get-NetNeighbor -InterfaceIndex $ifIndex -AddressFamily IPv4 |
    Where-Object { $_.State -in 'Reachable', 'Stale', 'Delay', 'Probe', 'Permanent' -and $_.LinkLayerAddress -and
                   $_.LinkLayerAddress -notmatch '^(00-00-00-00-00-00|FF-FF-FF-FF-FF-FF|01-00-5E|33-33)' }

$devices = @{}
foreach ($n in $neighbors) {
    $devices[$n.IPAddress] = [ordered]@{ ip = $n.IPAddress; mac = $n.LinkLayerAddress.Replace('-', ':').ToLower(); vendor = ''; random_mac = $false; name = ''; upnp = ''; ports = '' }
}
# this PC itself is not in its own ARP table
$selfMac = (Get-NetAdapter -InterfaceIndex $ifIndex).MacAddress
$devices[$ip4.IPAddress] = [ordered]@{ ip = $ip4.IPAddress; mac = $selfMac.Replace('-', ':').ToLower(); vendor = ''; random_mac = $false; name = "$env:COMPUTERNAME (this PC)"; upnp = ''; ports = '' }

# --- MAC vendor -------------------------------------------------------------
$ouiMap = @{}
if ($Oui) {
    $dir = Join-Path $env:USERPROFILE '.home-health-check'
    $file = Join-Path $dir 'manuf.txt'
    if (-not (Test-Path $file) -or (Get-Item $file).LastWriteTime -lt (Get-Date).AddDays(-90)) {
        New-Item -ItemType Directory -Force $dir | Out-Null
        try { Invoke-WebRequest 'https://www.wireshark.org/download/automated/data/manuf' -OutFile $file -UseBasicParsing -TimeoutSec 60 } catch { }
    }
    # lines look like "B8:27:EB<tab>RaspberryPiF<tab>Raspberry Pi Foundation"; only whole 24-bit prefixes are used
    foreach ($line in (Get-Content $file -Encoding UTF8)) {
        if ($line -match '^([0-9A-F]{2}):([0-9A-F]{2}):([0-9A-F]{2})\s+\S+\s+(.+?)\s*$') { $ouiMap["$($Matches[1])$($Matches[2])$($Matches[3])"] = $Matches[4] }
    }
}
foreach ($d in $devices.Values) {
    $hex = $d.mac.Replace(':', '').ToUpper()
    if ($hex.Length -ge 6) {
        $d.random_mac = '26AE'.Contains($hex.Substring(1, 1))   # locally administered = private/random address
        if ($ouiMap.ContainsKey($hex.Substring(0, 6))) { $d.vendor = $ouiMap[$hex.Substring(0, 6)] }
    }
}

# --- names from DNS (works when the DNS server knows the DHCP names) ----------
foreach ($d in $devices.Values) {
    if (-not $d.name) {
        $ptr = Resolve-DnsName -Name $d.ip -Type PTR -DnsOnly -QuickTimeout | Where-Object NameHost | Select-Object -First 1
        if ($ptr) { $d.name = $ptr.NameHost }
    }
}

# --- UPnP / SSDP descriptions ----------------------------------------------
$udp = New-Object System.Net.Sockets.UdpClient
$udp.Client.ReceiveTimeout = 1000
$msg = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 2`r`nST: ssdp:all`r`n`r`n"
$bytes = [Text.Encoding]::ASCII.GetBytes($msg)
[void]$udp.Send($bytes, $bytes.Length, '239.255.255.250', 1900)
$locs = @{}
$deadline = (Get-Date).AddSeconds(4)
while ((Get-Date) -lt $deadline) {
    try {
        $ep = New-Object System.Net.IPEndPoint([Net.IPAddress]::Any, 0)
        $resp = [Text.Encoding]::ASCII.GetString($udp.Receive([ref]$ep))
        if ($resp -match '(?im)^LOCATION:\s*(\S+)') { $locs[$ep.Address.ToString()] = $Matches[1] }
    } catch { }
}
$udp.Close()
foreach ($ip in $locs.Keys) {
    try { [xml]$x = (Invoke-WebRequest -Uri $locs[$ip] -UseBasicParsing -TimeoutSec 3).Content } catch { continue }
    $dev = $x.root.device
    $desc = (@($dev.friendlyName, $dev.manufacturer, $dev.modelName, $dev.modelNumber) | Where-Object { $_ }) -join ' | '
    if (-not $devices.ContainsKey($ip)) { $devices[$ip] = [ordered]@{ ip = $ip; mac = ''; vendor = ''; random_mac = $false; name = ''; upnp = ''; ports = '' } }
    $devices[$ip].upnp = $desc
}

# --- well-known ports (opt-in) ----------------------------------------------
if ($Ports) {
    $known = @{ 22 = 'ssh'; 53 = 'dns'; 80 = 'http'; 443 = 'https'; 445 = 'smb'; 554 = 'rtsp'; 631 = 'ipp'; 1400 = 'sonos'
        1883 = 'mqtt'; 3389 = 'rdp'; 5000 = 'nas/upnp'; 5001 = 'nas'; 8008 = 'cast'; 8009 = 'cast'; 8080 = 'http-alt'; 8123 = 'home-assistant'; 9100 = 'printer'; 32400 = 'plex' }
    $portList = $known.Keys | Sort-Object
    $probes = foreach ($d in $devices.Values) {
        foreach ($p in $portList) {
            $c = New-Object System.Net.Sockets.TcpClient
            [pscustomobject]@{ Ip = $d.ip; Port = $p; Client = $c; Ar = $c.BeginConnect($d.ip, $p, $null, $null) }
        }
    }
    Start-Sleep -Milliseconds 1500
    foreach ($pr in $probes) {
        if ($pr.Ar.IsCompleted -and $pr.Client.Connected) {
            $d = $devices[$pr.Ip]
            $d.ports = (@($d.ports, "$($pr.Port)/$($known[$pr.Port])") | Where-Object { $_ }) -join ' '
        }
        $pr.Client.Close()
    }
    # SSDP replies are often dropped by Windows Firewall; ask well-known description URLs directly instead
    $descUrls = @{ 1400 = 'http://{0}:1400/xml/device_description.xml'; 8008 = 'http://{0}:8008/ssdp/device-desc.xml' }
    foreach ($d in $devices.Values) {
        if ($d.upnp) { continue }
        foreach ($p in $descUrls.Keys) {
            if ($d.ports -match "(^| )$p/") {
                try { [xml]$x = (Invoke-WebRequest -Uri ($descUrls[$p] -f $d.ip) -UseBasicParsing -TimeoutSec 3).Content } catch { continue }
                $dev = $x.root.device
                $d.upnp = (@($dev.friendlyName, $dev.manufacturer, $dev.modelName) | Where-Object { $_ }) -join ' | '
            }
        }
    }
}

# --- output -----------------------------------------------------------------
$list = $devices.Values | Sort-Object { [version]$_.ip }
if ($Json) {
    [ordered]@{ scanned = (Get-Date).ToString('s'); subnet = "$(NumToIp $net)/$prefix"; gateway = $gw; devices = @($list) } | ConvertTo-Json -Depth 4
} else {
    "scanned: $((Get-Date).ToString('yyyy-MM-dd HH:mm'))  subnet: $(NumToIp $net)/$prefix  gateway: $gw  devices: $(@($list).Count)"
    if ($locs.Count -eq 0) { "(no SSDP replies - UPnP may be off, or Windows Firewall drops the replies)" }
    if ($Oui -and $ouiMap.Count -eq 0) { "(vendor list could not be downloaded)" }
    $list | ForEach-Object { [pscustomobject]$_ } | Format-Table ip, mac, @{ n = 'rnd'; e = { if ($_.random_mac) { 'yes' } } }, vendor, name, upnp, ports -AutoSize -Wrap | Out-String -Width 220
}
