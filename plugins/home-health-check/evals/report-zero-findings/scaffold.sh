#!/bin/bash
set -e
. "$(cd "$(dirname "$0")" && pwd)/../_fixtures/lib.sh"
put inventory.md inventory.md
mkdir -p home-data/findings
