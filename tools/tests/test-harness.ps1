# Self-test of tools/test-ps.ps1. Dot-sourced by the harness, so Assert-Eq, Assert-Match and Get-Fixture are defined.

Assert-Eq 'Assert-Eq passes on equal strings' 'abc' 'abc'
Assert-Match 'Assert-Match passes on a match' '^a.c$' 'abc'
Assert-Eq 'Get-Fixture points to an existing file' 'yes' $(if (Test-Path -LiteralPath (Get-Fixture 'homey/system.json') -PathType Leaf) { 'yes' } else { 'no' })
