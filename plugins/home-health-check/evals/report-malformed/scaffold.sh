#!/bin/bash
set -e
. "$(cd "$(dirname "$0")" && pwd)/../_fixtures/lib.sh"
put inventory.md inventory.md
put broken-yaml.md "findings/2026-01-04T1000-pi-health-check-b827eb000000.md"
put pi-latest.md "findings/${TODAY}T${HHMM}-pi-health-check-b827eb000000.md"
put future-format.md "findings/${TODAY}T${HHMM}-router-health-check-306893000000.md"
put odd-severity.md "findings/${TODAY}T${HHMM}-windows-health-check-bcfce7000000.md"
put report-january.md reports/2026-01-05-home-report.md
