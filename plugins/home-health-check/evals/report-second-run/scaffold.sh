#!/bin/bash
set -e
. "$(cd "$(dirname "$0")" && pwd)/../_fixtures/lib.sh"
put inventory-second-run.md inventory.md
for d in 01 02 03 04; do put pi-january.md "findings/2026-01-${d}T1000-pi-health-check-b827eb000000.md" "s/2026-01-05/2026-01-${d}/"; done
put pi-january.md "findings/2026-01-05T1000-pi-health-check-b827eb000000.md"
put pi-latest.md "findings/${TODAY}T${HHMM}-pi-health-check-b827eb000000.md"
put report-january.md reports/2026-01-05-home-report.md
printf "draft\n" > "home-data/reports/${TODAY}-home-report.md"
put pi-february.md "findings/2026-02-01T1000-pi-health-check-b827eb000000.md"
put router-latest.md "findings/${TODAY}T${HHMM}-router-health-check-306893000000.md"
