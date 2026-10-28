# Runs the PowerShell tests: powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-ps.ps1 [<test file>...]
# Default: every tools/tests/test-*.ps1. Test files are dot-sourced and use:
# Assert-Eq, Assert-Match, Get-Fixture, $HhcTmp (removed at exit), $HhcRoot.
# Windows PowerShell 5.1, ASCII. Repo-only tool, not shipped in the skills. Twin of tools/test-sh.sh.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$TestFiles)

$HhcRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$HhcTmp = Join-Path ([IO.Path]::GetTempPath()) ('hhc-test.' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $HhcTmp -Force | Out-Null
$script:HhcPass = 0
$script:HhcFail = 0

function Assert-Eq([string]$Name, [string]$Expected, [string]$Actual) {
    if ($Expected -ceq $Actual) { $script:HhcPass++; "ok $Name"; return }
    $script:HhcFail++
    "FAIL $Name"
    "  expected: $Expected"
    "  actual:   $Actual"
}

function Assert-Match([string]$Name, [string]$Pattern, [string]$Actual) {
    if ($Actual -match $Pattern) { $script:HhcPass++; "ok $Name"; return }
    $script:HhcFail++
    "FAIL $Name"
    "  expected to match: $Pattern"
    "  actual:            $Actual"
}

function Get-Fixture([string]$Path) { Join-Path (Join-Path $HhcRoot 'tools\fixtures') $Path }

if (-not $TestFiles -or $TestFiles.Count -eq 0) {
    $TestFiles = @(Get-ChildItem (Join-Path $HhcRoot 'tools\tests') -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object { $_.FullName })
}
try {
    foreach ($t in $TestFiles) {
        "# $t"
        try { . $t }
        catch { $script:HhcFail++; "FAIL $t threw: $($_.Exception.Message)" }
    }
} finally {
    Remove-Item -LiteralPath $HhcTmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:HhcFail -eq 0) { "OK $($script:HhcPass) tests"; exit 0 }
"$($script:HhcFail) failures"
exit 1
