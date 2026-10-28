#!/bin/bash
set -e
. "$(cd "$(dirname "$0")" && pwd)/../_fixtures/lib.sh"
put inventory.md inventory.md
put pi-latest.md "findings/${TODAY}T${HHMM}-pi-health-check-b827eb000000.md"
put windows-clean.md "findings/${TODAY}T${HHMM}-windows-health-check-bcfce7000000.md"
