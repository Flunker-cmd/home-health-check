#!/bin/bash
set -e
. "$(cd "$(dirname "$0")" && pwd)/../_fixtures/lib.sh"
put inventory.md inventory.md
put inventory.md "inventory (1).md"
put pi-latest.md "findings/${TODAY}T${HHMM}-pi-health-check-b827eb000000.md"
put router-january.md "findings/2026-01-05T1000-router-health-check-306893000000.md"
put windows-latest.md "findings/${TODAY}T${HHMM}-windows-health-check-bcfce7000000.md"
put windows-unknown.md "findings/${TODAY}T${HHMM}-windows-health-check-unknown.md"
put macos-private-mac.md "findings/${TODAY}T${HHMM}-macos-health-check-6e1122000000.md"
