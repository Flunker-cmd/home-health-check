# Checks the skills in this repo against the rules in the design (docs/superpowers/specs).
# Prints one line per violation: FAIL <rule-id> <repo-relative-path>: <message>
# Exit code 0 when everything passes, 1 otherwise. Windows PowerShell 5.1, no parameters.
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pluginDir = Join-Path $root 'plugins\home-health-check'
$skillsDir = Join-Path $pluginDir 'skills'
$contractSrc = Join-Path $pluginDir 'shared\findings-format.md'
$script:fails = 0
$script:checks = 0

function Rel($path) { $path.Substring($root.Length).TrimStart('\', '/').Replace('\', '/') }
function Fail($rule, $path, $msg) { $script:fails++; "FAIL $rule $(Rel $path): $msg" }
function Checked { $script:checks++ }

function Get-Skills {
    Get-ChildItem $skillsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }
}

function Get-RepoFiles($filter) {
    Get-ChildItem $root -Recurse -File -Filter $filter |
        Where-Object { $_.FullName -notmatch '\\(\.git|\.superpowers)\\' }
}

function Test-ContractCopy {
    if (-not (Test-Path $contractSrc)) { Fail 'contract-copy' $contractSrc 'contract source is missing'; return }
    $srcHash = (Get-FileHash $contractSrc).Hash
    foreach ($s in Get-Skills) {
        Checked
        $copy = Join-Path $s.FullName 'references\findings-format.md'
        if (-not (Test-Path $copy)) { Fail 'contract-copy' $copy 'missing, run tools/sync-contract.ps1'; continue }
        if ((Get-FileHash $copy).Hash -ne $srcHash) { Fail 'contract-copy' $copy 'differs from shared/findings-format.md, run tools/sync-contract.ps1' }
    }
}

function Test-ScriptSize {
    foreach ($s in Get-Skills) {
        $dir = Join-Path $s.FullName 'scripts'
        if (-not (Test-Path $dir)) { continue }
        foreach ($f in Get-ChildItem $dir -Recurse -File) {
            Checked
            if ($f.Length -ge 20480) { Fail 'script-size' $f.FullName "$($f.Length) bytes, must be under 20480" }
        }
    }
}

function Test-Ps1Ascii {
    foreach ($f in Get-RepoFiles '*.ps1') {
        Checked
        $bad = [IO.File]::ReadAllBytes($f.FullName) | Where-Object { $_ -gt 127 } | Select-Object -First 1
        if ($null -ne $bad) { Fail 'ps1-ascii' $f.FullName 'contains non-ASCII bytes' }
    }
}

function Test-ShLf {
    foreach ($f in Get-RepoFiles '*.sh') {
        Checked
        if ([IO.File]::ReadAllBytes($f.FullName) -contains 13) { Fail 'sh-lf' $f.FullName 'contains CR (CRLF line endings)' }
    }
}

function Test-IpAllowed($ip) {
    $o = $ip.Split('.') | ForEach-Object { [int]$_ }
    if ($o | Where-Object { $_ -gt 255 }) { return $true }                  # not an address (version string)
    if ($ip -in @('1.1.1.1', '9.9.9.9', '8.8.8.8', '0.0.0.0', '255.255.255.255')) { return $true }
    if ($o[0] -eq 10 -or $o[0] -eq 127) { return $true }
    if ($o[0] -eq 192 -and $o[1] -eq 168) { return $true }
    if ($o[0] -eq 172 -and $o[1] -ge 16 -and $o[1] -le 31) { return $true }
    if ($o[0] -eq 100 -and $o[1] -ge 64 -and $o[1] -le 127) { return $true }  # CGNAT 100.64.0.0/10
    if ($o[0] -eq 169 -and $o[1] -eq 254) { return $true }
    if ($o[0] -ge 224 -and $o[0] -le 239) { return $true }                  # multicast (mDNS, SSDP)
    return $false
}

function Test-Privacy {
    $files = @()
    foreach ($ext in '*.md', '*.ps1', '*.sh') {
        $files += Get-ChildItem $pluginDir -Recurse -File -Filter $ext
    }
    $agensi = Join-Path $root 'agensi'
    if (Test-Path $agensi) { $files += Get-ChildItem $agensi -Recurse -File }
    foreach ($name in 'README.md', 'CLAUDE.md') {
        $p = Join-Path $root $name
        if (Test-Path $p) { $files += Get-Item $p }
    }
    foreach ($f in $files) {
        Checked
        $text = [IO.File]::ReadAllText($f.FullName)
        foreach ($m in [regex]::Matches($text, '(?i)\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b')) {
            if ($m.Value -notmatch '00:00:00$') { Fail 'privacy' $f.FullName "MAC address $($m.Value) (use a placeholder ending in 00:00:00)" }
        }
        if ($text -match '[A-Za-z]:\\Users\\') { Fail 'privacy' $f.FullName 'contains a Windows user path' }
        if ($text -match '[A-Za-z]:\\dev\\') { Fail 'privacy' $f.FullName 'contains a local D:\dev style path' }
        foreach ($m in [regex]::Matches($text, '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b')) {
            if (-not (Test-IpAllowed $m.Value)) { Fail 'privacy' $f.FullName "public-looking IP address $($m.Value)" }
        }
    }
}

function Get-Frontmatter($skillMd) {
    $lines = Get-Content $skillMd
    $fm = @{}
    if ($lines.Count -lt 2 -or $lines[0].Trim() -ne '---') { return $fm }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { break }
        if ($lines[$i] -match '^([A-Za-z_]+):\s*(.*)$') { $fm[$Matches[1]] = $Matches[2].Trim() }
    }
    return $fm
}

function Test-Frontmatter {
    $required = 'name', 'description', 'summary', 'version', 'tags', 'keywords', 'use_cases', 'docs_url'
    $pluginVersion = (Get-Content -Raw (Join-Path $pluginDir '.claude-plugin\plugin.json') | ConvertFrom-Json).version
    foreach ($s in Get-Skills) {
        $md = Join-Path $s.FullName 'SKILL.md'
        $fm = Get-Frontmatter $md
        Checked
        foreach ($k in $required) {
            if (-not $fm.ContainsKey($k)) { Fail 'frontmatter' $md "missing key '$k'" }
        }
        if ($fm.ContainsKey('name') -and $fm['name'] -ne $s.Name) { Fail 'name-folder' $md "name '$($fm['name'])' does not match folder '$($s.Name)'" }
        if ($fm.ContainsKey('version') -and $fm['version'] -ne $pluginVersion) { Fail 'version-match' $md "version '$($fm['version'])' differs from plugin.json '$pluginVersion'" }
    }
}

function Test-AgentNeutral {
    $patterns = '\bClaude\b', "<this skill's directory>", 'Claude Code session', 'Claude in Chrome', 'get_page_text', 'read_page'
    foreach ($s in Get-Skills) {
        $md = Join-Path $s.FullName 'SKILL.md'
        Checked
        $text = [IO.File]::ReadAllText($md)
        foreach ($p in $patterns) {
            if ($text -match $p) { Fail 'agent-neutral' $md "matches '$p'" }
        }
    }
}

function Test-DataDir {
    foreach ($s in Get-Skills) {
        $md = Join-Path $s.FullName 'SKILL.md'
        Checked
        $text = [IO.File]::ReadAllText($md)
        if ($text.Contains('~/.home-health-check') -or $text.Contains('%USERPROFILE%\.home-health-check')) { Fail 'data-dir' $md 'names the data directory path; say <data dir> instead' }
        if (-not $text.Contains('<data dir>')) { Fail 'data-dir' $md 'does not mention <data dir>' }
        if (-not $text.Contains('references/findings-format.md')) { Fail 'data-dir' $md 'does not point to references/findings-format.md' }
    }
}

function Test-NetworkSection {
    foreach ($s in Get-Skills) {
        $md = Join-Path $s.FullName 'SKILL.md'
        Checked
        if (-not [regex]::IsMatch([IO.File]::ReadAllText($md), '(?m)^## Network and permissions\s*$')) { Fail 'network-section' $md "missing '## Network and permissions' heading" }
    }
}

function Test-FindingsSection {
    foreach ($name in 'pi-health-check', 'router-health-check', 'windows-health-check') {
        $md = Join-Path $skillsDir "$name\SKILL.md"
        Checked
        $text = [IO.File]::ReadAllText($md)
        if (-not [regex]::IsMatch($text, '(?m)^## Save findings\s*$')) { Fail 'findings-section' $md "missing '## Save findings' heading" }
        if (-not $text.Contains('hhc-findings/1')) { Fail 'findings-section' $md "does not mention hhc-findings/1" }
        $m = [regex]::Match($text, '(?ms)^### Standard finding ids\s*$(.*?)(?=^#{1,3} |\z)')
        if (-not $m.Success) { Fail 'findings-section' $md "missing '### Standard finding ids' heading"; continue }
        $rows = @($m.Groups[1].Value -split "`n" | Where-Object { $_ -match '^\|\s*`[a-z0-9-]+`\s*\|' })
        if ($rows.Count -lt 8) { Fail 'findings-section' $md "standard id table has $($rows.Count) rows, needs at least 8" }
    }
}

Test-ContractCopy
Test-DataDir
Test-NetworkSection
Test-FindingsSection
Test-Frontmatter
Test-AgentNeutral
Test-ScriptSize
Test-Ps1Ascii
Test-ShLf
Test-Privacy

if ($script:fails -eq 0) { "OK $($script:checks) checks"; exit 0 }
"$($script:fails) failures"
exit 1
