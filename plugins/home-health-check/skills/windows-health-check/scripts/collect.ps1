# Read-only health snapshot of a Windows 10/11 PC. No admin needed; checks that need admin are marked.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File collect.ps1 [-SkipWinget]
param([switch]$SkipWinget)

$ErrorActionPreference = 'SilentlyContinue'
function Section($name) { Write-Output ""; Write-Output "## $name" }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------------------------------------------------------------------------
Section "System"
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$os = Get-CimInstance Win32_OperatingSystem
"os:        $($os.Caption) $($cv.DisplayVersion), build $($cv.CurrentBuild).$($cv.UBR)"
"installed: $($os.InstallDate)"
"booted:    $($os.LastBootUpTime)"
"admin:     $isAdmin"
$cs = Get-CimInstance Win32_ComputerSystem
$bb = Get-CimInstance Win32_BaseBoard
$bios = Get-CimInstance Win32_BIOS
"computer:  $($cs.Manufacturer) $($cs.Model)"
"board:     $($bb.Manufacturer) $($bb.Product)"
"BIOS:      $($bios.SMBIOSBIOSVersion), released $($bios.ReleaseDate)"
"CPU:       $((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)"
Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
    "RAM:       {0} GB {1}, JEDEC {2} MT/s, running {3} MT/s (XMP/EXPO off if these match on a kit sold as faster)" -f ($_.Capacity / 1GB), $_.PartNumber.Trim(), $_.Speed, $_.ConfiguredClockSpeed
}
Get-CimInstance Win32_VideoController | ForEach-Object { "GPU:       $($_.Name), driver $($_.DriverVersion) ($($_.DriverDate))" }

# ---------------------------------------------------------------------------
Section "Updates"
$pending = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending += 'Windows Update' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending += 'Component Servicing' }
"reboot pending: $(if ($pending) { $pending -join ', ' } else { 'no' })"
"latest updates:"
Get-HotFix | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 5 |
    ForEach-Object { "  {0:yyyy-MM-dd} {1} {2}" -f $_.InstalledOn, $_.HotFixID, $_.Description }
$wu = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
if ($wu.IsContinuousInnovationOptedIn -eq 1) { "get latest updates as soon as available: on" }
$insider = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\Applicability'
if ($insider.BranchName) { "Insider branch: $($insider.BranchName)" }

# ---------------------------------------------------------------------------
Section "Security"
$mp = Get-MpComputerStatus
if ($mp) {
    "Defender: AV {0}, real-time {1}, tamper protection {2}, signatures {3:yyyy-MM-dd}, last quick scan {4:yyyy-MM-dd}" -f $mp.AntivirusEnabled, $mp.RealTimeProtectionEnabled, $mp.IsTamperProtected, $mp.AntivirusSignatureLastUpdated, $mp.QuickScanEndTime
    $pua = (Get-MpPreference).PUAProtection
    "Defender PUA protection: $(switch ($pua) { 1 {'on'} 2 {'audit'} default {'off'} })"
} else {
    "Defender status not readable (third-party antivirus?)"
    Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct | ForEach-Object { "antivirus: $($_.displayName)" }
}
Get-NetFirewallProfile | ForEach-Object { "firewall $($_.Name): $(if ($_.Enabled) {'on'} else {'OFF'})" }
$sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State').UEFISecureBootEnabled
"Secure Boot: $(switch ($sb) { 1 {'on'} 0 {'OFF'} default {'unknown (legacy BIOS?)'} })"
$dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard
if ($dg) {
    "VBS: $(switch ($dg.VirtualizationBasedSecurityStatus) { 2 {'running'} 1 {'enabled, not running'} default {'off'} }), memory integrity (HVCI): $(if ($dg.SecurityServicesRunning -contains 2) {'running'} else {'off'})"
}
$shell = New-Object -ComObject Shell.Application
Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
    $v = $shell.NameSpace("$($_.DriveLetter):").Self.ExtendedProperty('System.Volume.BitLockerProtection')
    "BitLocker $($_.DriveLetter): $(switch ($v) { 1 {'on'} 3 {'encrypting'} 5 {'suspended'} 2 {'off'} 0 {'not available'} default {'unknown'} })"
}
if ($isAdmin) {
    $tpm = Get-Tpm
    "TPM: present $($tpm.TpmPresent), ready $($tpm.TpmReady)"
} else { "TPM: (needs admin)" }
$rdp = (Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections
"Remote Desktop: $(if ($rdp -eq 0) {'ENABLED'} else {'off'})"
"SMB1 client driver: $(if (Get-Service mrxsmb10) {'present'} else {'not installed'})"
"local administrators:"
net localgroup administrators 2>$null | Select-Object -Skip 6 | Where-Object { $_ -and $_ -notmatch 'command completed' } | ForEach-Object { "  $_" }
"shares:"
net share 2>$null | Select-Object -Skip 4 | Where-Object { $_ -and $_ -notmatch 'command completed' } | ForEach-Object { "  $_" }

# ---------------------------------------------------------------------------
Section "Disks"
Get-PhysicalDisk | ForEach-Object {
    "{0}: {1} {2} {3:N0} GB, health {4}, status {5}" -f $_.DeviceId, $_.FriendlyName, $_.MediaType, ($_.Size / 1GB), $_.HealthStatus, $_.OperationalStatus
}
Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
    "{0}: {1:N1} GB free of {2:N1} GB ({3:N0}%)" -f $_.DriveLetter, ($_.SizeRemaining / 1GB), ($_.Size / 1GB), (100 * $_.SizeRemaining / [math]::Max($_.Size, 1))
}
Get-CimInstance Win32_DiskPartition | Where-Object Type -match 'Logical Disk Manager' |
    Select-Object -ExpandProperty DiskIndex -Unique | ForEach-Object { "disk $_ is a dynamic disk (BitLocker can't encrypt it)" }

# ---------------------------------------------------------------------------
Section "Stability (last 30 days)"
$since = (Get-Date).AddDays(-30)
$crit = @(
    @{ n = 'unexpected shutdowns (Kernel-Power 41)'; f = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since } },
    @{ n = 'dirty shutdowns (EventLog 6008)'; f = @{ LogName = 'System'; ProviderName = 'EventLog'; Id = 6008; StartTime = $since } },
    @{ n = 'blue screens (BugCheck 1001)'; f = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since } },
    @{ n = 'hardware errors (WHEA)'; f = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since } },
    @{ n = 'disk errors (disk 7/11/51/153/154)'; f = @{ LogName = 'System'; ProviderName = 'disk'; StartTime = $since } }
)
foreach ($c in $crit) { "{0}: {1}" -f $c.n, @(Get-WinEvent -FilterHashtable $c.f).Count }
"most frequent System errors:"
Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = $since } |
    Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 10 |
    ForEach-Object { "  {0,4}x {1}" -f $_.Count, $_.Name }
"most frequent Application errors:"
Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Level = 1, 2; StartTime = $since } |
    Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 8 |
    ForEach-Object { "  {0,4}x {1}" -f $_.Count, $_.Name }

# ---------------------------------------------------------------------------
Section "Network"
Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object { "adapter: $($_.Name), $($_.LinkSpeed), $($_.InterfaceDescription)" }
Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses | ForEach-Object { "DNS ($($_.InterfaceAlias)): $($_.ServerAddresses -join ', ')" }
$doh = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name DnsOverHttpsMode
if ($doh) { "Chrome DoH policy: $($doh.DnsOverHttpsMode)" }

# ---------------------------------------------------------------------------
Section "Backup"
$shellFolders = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
"Desktop:   $($shellFolders.Desktop)"
"Documents: $($shellFolders.Personal)"
"Pictures:  $($shellFolders.'My Pictures')"
"(paths under OneDrive = those folders are backed up by OneDrive)"
"OneDrive running: $([bool](Get-Process OneDrive))"
$fh = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\FileHistory'
"File History configured: $([bool]$fh)"
"scheduled tasks that look like backups:"
Get-ScheduledTask | Where-Object { $_.TaskName -match 'backup|restic|veeam|macrium|acronis|duplicati|kopia' -and $_.TaskPath -notmatch '\\Microsoft\\' } |
    ForEach-Object { "  $($_.TaskPath)$($_.TaskName) ($($_.State))" }

# ---------------------------------------------------------------------------
Section "Startup programs"
Get-CimInstance Win32_StartupCommand | Sort-Object Name | ForEach-Object { "  {0}  [{1}]" -f $_.Name, $_.Location }

# ---------------------------------------------------------------------------
Section "Firewall rules pointing at missing programs"
$missing = Get-NetFirewallRule -Enabled True | Get-NetFirewallApplicationFilter |
    Where-Object { $_.Program -and $_.Program -notin 'Any', 'System' -and $_.Program -notmatch '%' -and -not (Test-Path $_.Program) }
"count: $(@($missing).Count)"
$missing | Select-Object -First 10 | ForEach-Object { "  $($_.Program)" }

# ---------------------------------------------------------------------------
if (-not $SkipWinget -and (Get-Command winget)) {
    Section "Available app updates (winget)"
    winget upgrade --accept-source-agreements --disable-interactivity 2>$null |
        Where-Object { $_ -match '\S' -and $_ -notmatch '^[\s\-\\|/]+$' } | Select-Object -Last 40
}
