# Copies plugins/home-health-check/shared/findings-format.md, byte for byte, into
# references/findings-format.md of every skill folder. Run after editing the contract.
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pluginDir = Join-Path $root 'plugins\home-health-check'
$src = Join-Path $pluginDir 'shared\findings-format.md'
if (-not (Test-Path $src)) { throw "contract source missing: $src" }

Get-ChildItem (Join-Path $pluginDir 'skills') -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } |
    ForEach-Object {
        $dir = Join-Path $_.FullName 'references'
        New-Item -ItemType Directory -Force $dir | Out-Null
        Copy-Item $src (Join-Path $dir 'findings-format.md') -Force
        "wrote skills/$($_.Name)/references/findings-format.md"
    }
