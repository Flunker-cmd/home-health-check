#!/bin/bash
# Shared by the case scaffolds: put <fixture> <destination under home-data> [extra sed expression]
set -e
FIX=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TODAY=$(date +%Y-%m-%d)
HHMM=$(date +%H%M)
CLOCK=$(date +%H:%M)
put() {
  mkdir -p "home-data/$(dirname "$2")"
  sed -e "s/@TODAY@/$TODAY/g" -e "s/@CLOCK@/$CLOCK/g" -e "${3:-s/^//}" "$FIX/$1" > "home-data/$2"
}
