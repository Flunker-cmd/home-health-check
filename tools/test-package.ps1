# Builds the Agensi ZIPs with agensi/package.ps1 and checks their contents.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-package.ps1 -OutDir <folder outside the repo>
param([Parameter(Mandatory = $true)][string]$OutDir)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skillsDir = Join-Path $root 'plugins\home-health-check\skills'
$package = Join-Path $root 'agensi\package.ps1'
$script:fails = 0
function Fail($msg) { $script:fails++; "FAIL $msg" }

if (-not (Test-Path $package)) { Fail 'agensi/package.ps1 is missing'; "$($script:fails) failures"; exit 1 }
& powershell -NoProfile -ExecutionPolicy Bypass -File $package -OutDir $OutDir | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "package.ps1 exited with $LASTEXITCODE"; "$($script:fails) failures"; exit 1 }

$skills = Get-ChildItem $skillsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } | ForEach-Object { $_.Name }
$zips = @('home-health-check-pack.zip') + ($skills | ForEach-Object { "$_.zip" })

foreach ($z in $zips) {
    $path = Join-Path $OutDir $z
    if (-not (Test-Path $path)) { Fail "$z was not built"; continue }
    $zip = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        $entries = @($zip.Entries | Where-Object { $_.Name -ne '' })
        $names = @($entries | ForEach-Object { $_.FullName })
        if ($names | Where-Object { $_.Contains('\') }) { Fail "$z has entry names with a backslash" }
        if ($entries.Count -gt 200) { Fail "$z has $($entries.Count) files, limit is 200" }
        foreach ($e in $entries) { if ($e.Length -ge 20480) { Fail "$z entry $($e.FullName) is $($e.Length) bytes, limit is 20480" } }
        foreach ($e in $entries) {
            if ($e.Name -notmatch '\.(md|ps1|sh|txt)$') { Fail "$z entry $($e.FullName) has an extension Agensi packaging does not ship" }
        }
        foreach ($bad in 'plugin.json', '.git', 'listings.md', 'package.ps1') {
            if ($names | Where-Object { $_ -match [regex]::Escape($bad) }) { Fail "$z contains $bad" }
        }
        if ($z -eq 'home-health-check-pack.zip') {
            if ($names -notcontains 'home-health-check-pack/README.md') { Fail "$z lacks home-health-check-pack/README.md" }
            $n = @($names | Where-Object { $_ -match '/SKILL\.md$' }).Count
            if ($n -ne $skills.Count) { Fail "$z has $n SKILL.md files, expected $($skills.Count)" }
            foreach ($s in $skills) {
                if ($names -notcontains "home-health-check-pack/$s/SKILL.md") { Fail "$z lacks $s/SKILL.md" }
            }
        } else {
            $s = $z.Substring(0, $z.Length - 4)
            $expected = @("$s/SKILL.md", "$s/references/findings-format.md")
            $scriptsDir = Join-Path $skillsDir "$s\scripts"
            if (Test-Path $scriptsDir) {
                $expected += Get-ChildItem $scriptsDir -Recurse -File | ForEach-Object { "$s/scripts/" + $_.FullName.Substring($scriptsDir.Length + 1).Replace('\', '/') }
            }
            foreach ($x in $expected) { if ($names -notcontains $x) { Fail "$z lacks $x" } }
        }
    } finally { $zip.Dispose() }
}

if ($script:fails -eq 0) { 'OK'; exit 0 }
"$($script:fails) failures"
exit 1
