# Builds the Agensi ZIPs from the skills in plugins/home-health-check/skills:
#   <OutDir>\home-health-check-pack.zip   all skills plus agensi/README.md (one skill pack)
#   <OutDir>\<skill>.zip                  one ZIP per skill
# Entry names use '/' (Compress-Archive in PowerShell 5.1 writes '\', which breaks on macOS and Linux).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File agensi/package.ps1 -OutDir <folder outside the repo>
param([Parameter(Mandatory = $true)][string]$OutDir)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skillsDir = Join-Path $root 'plugins\home-health-check\skills'
$out = [IO.Path]::GetFullPath($OutDir).TrimEnd('\')
if ($out -eq $root -or $out.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutDir must be outside the repo: $out"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\check-skills.ps1')
if ($LASTEXITCODE -ne 0) { throw 'tools/check-skills.ps1 failed, fix that first' }
New-Item -ItemType Directory -Force $out | Out-Null

function Get-SkillEntries($skill, $prefix) {
    $dir = $skill.FullName
    Get-ChildItem $dir -Recurse -File | ForEach-Object {
        @{ Source = $_.FullName; Entry = $prefix + $skill.Name + '/' + $_.FullName.Substring($dir.Length + 1).Replace('\', '/') }
    }
}

function New-Zip($zipPath, $items) {
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($i in $items) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $i.Source, $i.Entry, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose() }
    $largest = ($items | ForEach-Object { (Get-Item $_.Source).Length } | Measure-Object -Maximum).Maximum
    "{0}  files: {1}  largest file: {2} bytes" -f (Split-Path $zipPath -Leaf), @($items).Count, $largest
}

$skills = Get-ChildItem $skillsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }

$packItems = @(@{ Source = (Join-Path $root 'agensi\README.md'); Entry = 'home-health-check-pack/README.md' })
foreach ($s in $skills) { $packItems += Get-SkillEntries $s 'home-health-check-pack/' }
New-Zip (Join-Path $out 'home-health-check-pack.zip') $packItems

foreach ($s in $skills) { New-Zip (Join-Path $out "$($s.Name).zip") @(Get-SkillEntries $s '') }
